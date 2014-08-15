package Sisimai::Data;
use feature ':5.10';
use strict;
use warnings;
use Class::Accessor::Lite;
use Sisimai::Address;
use Sisimai::RFC5322;
use Sisimai::String;
use Sisimai::Reason;
use Sisimai::Group;
use Sisimai::Rhost;
use Sisimai::Time;
use Module::Load;
use Time::Piece;
use Try::Tiny;

my $rwaccessors = [
    'date',             # (Time::Piece) Date: in the original message
    'token',            # (String) Message token/MD5 Hex digest value
    'lhost',            # (String) local host name
    'rhost',            # (String) Remote host name
    'alias',            # (String) The value of alias(RHS)
    'listid',           # (String) List-Id header of each ML
    'reason',           # (String) Bounce reason
    'subject',          # (String) UTF-8 Subject text
    'provider',         # (String) Provider name
    'category',         # (String) Host group name
    'addresser',        # (Sisimai::Address) From: header in the original message
    'recipient',        # (Sisimai::Address) Final-Recipient: or To: in the original message
    'messageid',        # (String) Message-Id: header
    'frequency',        # (Integer) Bounce frequency
    'smtpagent',        # (String) MTA name
    'smtpcommand',      # (String) The last SMTP command
    'description',      # (Ref->Hash) Description
    'destination',      # (String) A domain part of the "recipinet"
    'senderdomain',     # (String) A domain part of the "addresser"
    'feedbacktype',     # (String) Feedback Type
    'diagnosticcode',   # (String) Diagnostic-Code: Header
    'diagnostictype',   # (String) The 1st part of Diagnostic-Code: Header
    'deliverystatus',   # (String) Delivery Status(DSN)
    'timezoneoffset',   # (Integer) Time zone offset(seconds)
];
Class::Accessor::Lite->mk_accessors( @$rwaccessors );

sub new {
    # @Description  Constructor of Sisimai::Data
    # @Param <ref>  (Ref->Hash) Data
    # @Return       (Sisimai::Data) Structured email data
    my $class = shift;
    my $argvs = { @_ };
    my $thing = {};

    EMAIL_ADDRESS: {
        # Create email address object
        my $x0 = Sisimai::Address->parse( [ $argvs->{'addresser'} ] );
        my $y0 = Sisimai::Address->parse( [ $argvs->{'recipient'} ] );

        if( ref $x0 eq 'ARRAY' ) {
            my $v = Sisimai::Address->new( shift @$x0 );

            if( ref $v eq 'Sisimai::Address' ) {
                $thing->{'addresser'} = $v;
                $thing->{'senderdomain'} = $v->host;
            }
        }

        if( ref $y0 eq 'ARRAY' ) {
            my $v = Sisimai::Address->new( shift @$y0 );

            if( ref $v eq 'Sisimai::Address' ) {
                $thing->{'recipient'} = $v;
                $thing->{'destination'} = $v->host;
                $thing->{'alias'} = $argvs->{'alias'};
            }
        }
    }
    return undef if( ! $thing->{'recipient'} && ! $thing->{'addresser'} );

    $thing->{'token'} = Sisimai::String->token( 
                            $thing->{'addresser'}->address,
                            $thing->{'recipient'}->address );

    TIMESTAMP: {
        # Create Time::Piece object
        $thing->{'date'} = localtime Time::Piece->new( $argvs->{'date'} );
        $thing->{'timezoneoffset'} = $argvs->{'timezoneoffset'} // '+0000';
    }

    OTHER_VALUES: {
        my $v = [ 
            'listid', 'subject', 'messageid', 'smtpagent', 'diagnosticcode',
            'diagnostictype', 'deliverystatus', 'reason', 'category', 'provider',
            'lhost', 'rhost', 'smtpcommand', 'description', 'feedbacktype',
        ];
        $thing->{ $_ } = $argvs->{ $_ } // '' for @$v;
        $thing->{'frequency'} = 1;
    }
    return bless( $thing, __PACKAGE__ );
}

sub make {
    # @Description  Another constructor of Sisimai::Data
    # @Param <ref>  (Hash) Data and orders
    # @Return       (Ref->Array) List of Sisimai::Data
    my $class = shift;
    my $argvs = { @_ };

    return undef unless exists $argvs->{'data'};
    return undef unless ref $argvs->{'data'} eq 'Sisimai::Message';

    my $messageobj = $argvs->{'data'};
    my $rfc822data = $messageobj->rfc822;
    my $fieldorder = { 'recipient' => [], 'addresser' => [] };
    my $objectlist = [];

    return undef unless $messageobj->ds;
    return undef unless $messageobj->rfc822;

    ORDER_OF_HEADERS: {
        # Decide the order of email headers: user specified or system default.
        if( exists $argvs->{'order'} && ref $argvs->{'order'} eq 'HASH' ) {
            # If the order of headers for searching is specified, use the order
            # for detecting an email address.
            for my $e ( 'recipient', 'addresser' ) {
                # The order should be "Array Reference".
                next unless $argvs->{'order'}->{ $e };
                next unless ref $argvs->{'order'}->{ $e } eq 'ARRAY';
                next unless scalar @{ $argvs->{'order'}->{ $e } } eq 'ARRAY';
                push @{ $fieldorder->{ $e } }, @{ $argvs->{'order'}->{ $e } };
            }
        }

        for my $e ( 'recipient', 'addresser' ) {
            # If the order is empty, use default order.
            if( not scalar @{ $fieldorder->{ $e } } ) {
                # Load default order of each accessor.
                Module::Load::load 'Sisimai::MTA';
                $fieldorder->{ $e } = Sisimai::MTA->RFC822HEADERS( $e );
            }
        }
    }

    LOOP_DELIVERY_STATUS: for my $e ( @{ $messageobj->ds } ) {
        # Create parameters for new() constructor.
        my $o = undef;  # Sisimai::Data Object
        my $r = undef;  # Reason text
        my $p = {
            'lhost'          => $e->{'lhost'}        // '',
            'rhost'          => $e->{'rhost'}        // '',
            'alias'          => $e->{'alias'}        // '',
            'reason'         => $e->{'reason'}       // '',
            'smtpagent'      => $e->{'agent'}        // '',
            'recipient'      => $e->{'recipient'}    // '',
            'smtpcommand'    => $e->{'command'}      // '',
            'feedbacktype'   => $e->{'feedbacktype'} // '',
            'diagnosticcode' => $e->{'diagnosis'}    // '',
            'diagnostictype' => $e->{'spec'}         // '',
            'deliverystatus' => $e->{'status'}       // '',
        };
        next if $p->{'deliverystatus'} =~ m/\A2[.]/;

        EMAIL_ADDRESS: {
            # Detect email address from message/rfc822 part
            for my $f ( @{ $fieldorder->{'addresser'} } ) {
                # Check each header in message/rfc822 part
                my $h = lc $f;
                next unless exists $rfc822data->{ $h };
                next unless length $rfc822data->{ $h };
                next unless Sisimai::RFC5322->is_emailaddress( $rfc822data->{ $h } );
                $p->{'addresser'} = $rfc822data->{ $h };
                last;
            }

            # Fallback: Get the sender address from the header of the bounced
            # email if the address is not set at loop above.
            $p->{'addresser'} ||= $messageobj->{'header'}->{'to'}; 

            if( length $p->{'recipient'} == 0 ) {
                # Detect "recipient" address if it is not set yet
                for my $f ( @{ $fieldorder->{'recipient'} } ) {
                    # Check each header in message/rfc822 part
                    my $h = lc $f;
                    next unless exists $rfc822data->{ $h };
                    next unless length $rfc822data->{ $h };
                    next unless Sisimai::RFC5322->is_emailaddress( $rfc822data->{ $h } );
                    $p->{'recipient'} = $rfc822data->{ $h };
                    last;
                }
            }

        } # End of EMAIL_ADDRESS
        next unless $p->{'addresser'};
        next unless $p->{'recipient'};

        TIMESTAMP: {
            # Convert from a time stamp or a date string to a machine time.
            my $v = $e->{'date'};

            unless( $v ) {
                # Date information did not exist in message/delivery-status part,...
                for my $f ( @{ Sisimai::MTA->RFC822HEADERS('date') } ) {
                    # Get the value of Date header or other date related header.
                    next unless $rfc822data->{ $f };
                    $v = $rfc822data->{ $f };
                    last;
                }
            }

            my $datestring = Sisimai::Time->parse( $v );
            my $zoneoffset = 0;

            if( $datestring =~ m/\A(.+)\s+([-+]\d{4})\z/ ) {
                # Wed, 26 Feb 2014 06:05:48 -0500
                $datestring = $1;
                $zoneoffset = Sisimai::Time->tz2second($2);
                $p->{'timezoneoffset'} = $2;
            }

            try {
                # Convert from the date string to an object then calculate time
                # zone offset.
                my $t = Time::Piece->strptime( $datestring, '%a, %d %b %Y %T' );
                $p->{'date'} = ( $t->epoch - $zoneoffset ) // undef; 

            } catch {
                # Failed to parse the date string...
                warn $_;
            };
        }
        next unless $p->{'date'};

        OTHER_TEXT_HEADERS: {
            $p->{'listid'}    = $rfc822data->{'list-id'}    // '';
            $p->{'subject'}   = $rfc822data->{'subject'}    // '';
            $p->{'messageid'} = $rfc822data->{'message-id'} // '';
        }

        CLASSIFICATION: {
            # Set host group and provider name
            my $v = Sisimai::Group->find( 'email' => $p->{'recipient'} ) // {};
            $p->{'provider'} = $v->{'provider'} // '';
            $p->{'category'} = $v->{'category'} // '';
        }

        $o = __PACKAGE__->new( %$p );
        next unless defined $o;

        if( $o->reason eq '' || $o->reason =~ m/\A(?:onhold|undefined)\z/ ) {
            # Decide the reason of email bounce
            if( Sisimai::Rhost->match( $o->rhost ) ) {
                # Remote host dependent error
                $r = Sisimai::Rhost->get( $o );
            }

            $r ||= Sisimai::Reason->get( $o );
            $o->reason( $r );
        }
        push @$objectlist, $o;

    } # End of for(LOOP_DELIVERY_STATUS)

    return $objectlist;
}

sub damn {
    # @Description  Convert from object to hash reference
    # @Param        <None>
    # @Return       (Ref->Hash) Data in Hash reference
    my $self = shift;
    my $data = undef;

    try {
        my $v = {};
        my $stringdata = [ qw|
            token lhost rhost listid alias reason subject provider category 
            messageid smtpagent smtpcommand description destination 
            senderdomain deliverystatus timezoneoffset feedbacktype|
        ];
        
        for my $e ( @$stringdata ) {
            # Copy string data
            $v->{ $e } = $self->$e // '';
        }
        $v->{'description'} = $self->diagnosticcode // '';
        $v->{'frequency'}   = $self->frequency // 0;
        $v->{'addresser'}   = $self->addresser->address;
        $v->{'recipient'}   = $self->recipient->address;
        $v->{'date'}        = $self->date->epoch;
        $data = $v;

    } catch {
        warn $_;
    };

    return $data;
}

sub dump {
    # @Description  Data dumper
    # @Param <str>  (String) Data format: json, csv
    # @Return       (String) Dumped data
    my $self = shift;
    my $argv = shift || 'json';

    return undef unless $argv =~ m/\A(?:json|csv)\z/;

    my $referclass = '';
    my $dumpeddata = '';

    try {
        $referclass = sprintf( "Sisimai::Data::%s", uc $argv );
        Module::Load::load $referclass;
        $dumpeddata = $referclass->dump( $self );

    } catch {
        warn $_;
    };

    return $dumpeddata;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Data - Parsed data object

=head1 SYNOPSIS

    use Sisimai::Data;
    my $data = Sisimai::Data->make( 'data' => <Sisimai::Message> object );
    for my $e ( @$data ) {
        print $e->reason;               # userunknown, mailboxfull, and so on.
        print $e->recipient->address;   # (Sisimai::Address) envelope recipient address
        print $e->bonced->ymd           # (Time::Piece) Date of bounce
    }

=head1 DESCRIPTION

Sisimai::Data generate parsed data from Sisimai::Message object.

=head1 CLASS METHODS

=head2 C<B<make( I<Hash> )>>

C<make> generate parsed data and returns an array reference which are 
including Sisimai::Data objects.

    my $mail = Sisimai::Mail->new('/var/mail/root');
    while( my $r = $mail->read ) {
        my $mesg = Sisimai::Message->new( 'data' => $r );
        my $data = Sisimai::Data->make( 'data' => $mesg );
        for my $e ( @$data ) {
            print $e->reason;               # userunknown, mailboxfull, and so on.
            print $e->recipient->address;   # (Sisimai::Address) envelope recipient address
            print $e->bonced->ymd           # (Time::Piece) Date of bounce
        }
    }

=head1 INSTANCE METHODS

=head2 C<B<damn()>>

C<damn> convert the object to a hash reference.

    my $hash = $self->damn;
    print $hash->{'recipient'}; # user@example.jp
    print $hash->{'date'};      # 1393940000

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014 azumakuniyuki E<lt>perl.org@azumakuniyuki.orgE<gt>,
All Rights Reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut
