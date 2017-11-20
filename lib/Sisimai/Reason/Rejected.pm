package Sisimai::Reason::Rejected;
use feature ':5.10';
use strict;
use warnings;

sub text  { 'rejected' }
sub description { "Email rejected due to a sender's email address (envelope from)" }
sub match {
    # Try to match that the given text and regular expressions
    # @param    [String] argv1  String to be matched with regular expressions
    # @return   [Integer]       0: Did not match
    #                           1: Matched
    # @since v4.0.0
    my $class = shift;
    my $argv1 = shift // return undef;
    my $isnot = qr/recipient[ ]address[ ]rejected/xi;
    my $regex = qr{(?>
         [<][>][ ]invalid[ ]sender
        |address[ ]rejected
        |Administrative[ ]prohibition
        |batv[ ](?:
             failed[ ]to[ ]verify   # SoniWall
            |validation[ ]failure   # SoniWall
            )
        |backscatter[ ]protection[ ]detected[ ]an[ ]invalid[ ]or[ ]expired[ ]email[ ]address    # MDaemon
        |bogus[ ]mail[ ]from        # IMail - block empty sender
        |Connections[ ]not[ ]accepted[ ]from[ ]servers[ ]without[ ]a[ ]valid[ ]sender[ ]domain
        |denied[ ]\[bouncedeny\]    # McAfee
        |does[ ]not[ ]exist[ ]E2110
        |domain[ ]of[ ]sender[ ]address[ ].+[ ]does[ ]not[ ]exist
        |Emetteur[ ]invalide.+[A-Z]{3}.+(?:403|405|415)
        |empty[ ]envelope[ ]senders[ ]not[ ]allowed
        |error:[ ]no[ ]third-party[ ]dsns               # SpamWall - block empty sender
        |From:[ ]Domain[ ]is[ ]invalid[.][ ]Please[ ]provide[ ]a[ ]valid[ ]From:
        |fully[ ]qualified[ ]email[ ]address[ ]required # McAfee
        |invalid[ ]domain,[ ]see[ ][<]url:.+[>]
        |Mail[ ]from[ ]not[ ]owned[ ]by[ ]user.+[A-Z]{3}.+421
        |Message[ ]rejected:[ ]Email[ ]address[ ]is[ ]not[ ]verified
        |mx[ ]records[ ]for[ ].+[ ]violate[ ]section[ ].+
        |Null[ ]Sender[ ]is[ ]not[ ]allowed
        |recipient[ ]not[ ]accepted[.][ ][(]batv:[ ]no[ ]tag
        |returned[ ]mail[ ]not[ ]accepted[ ]here
        |rfc[ ]1035[ ]violation:[ ]recursive[ ]cname[ ]records[ ]for
        |rule[ ]imposed[ ]mailbox[ ]access[ ]for        # MailMarshal
        |sender[ ](?:
             verify[ ]failed        # Exim callout
            |not[ ]pre[-]approved
            |rejected
            |domain[ ]is[ ]empty
            )
        |syntax[ ]error:[ ]empty[ ]email[ ]address
        |the[ ]message[ ]has[ ]been[ ]rejected[ ]by[ ]batv[ ]defense
        |transaction[ ]failed[ ]unsigned[ ]dsn[ ]for
        |Unroutable[ ]sender[ ]address
        |you[ ]are[ ]sending[ ]to[/]from[ ]an[ ]address[ ]that[ ]has[ ]been[ ]blacklisted
        )
    }xi;

    return 0 if $argv1 =~ $isnot;
    return 1 if $argv1 =~ $regex;
    return 0;
}

sub true {
    # Rejected by the envelope sender address or not
    # @param    [Sisimai::Data] argvs   Object to be detected the reason
    # @return   [Integer]               1: is rejected
    #                                   0: is not rejected by the sender
    # @since v4.0.0
    # @see http://www.ietf.org/rfc/rfc2822.txt
    my $class = shift;
    my $argvs = shift // return undef;

    return undef unless ref $argvs eq 'Sisimai::Data';
    require Sisimai::SMTP::Status;

    my $statuscode = $argvs->deliverystatus // '';
    my $reasontext = __PACKAGE__->text;
    my $tempreason = Sisimai::SMTP::Status->name($statuscode) || 'undefined';

    return 1 if $argvs->reason eq $reasontext;

    my $diagnostic = $argvs->diagnosticcode // '';
    my $v = 0;

    if( $tempreason eq $reasontext ) {
        # Delivery status code points C<rejected>.
        $v = 1;
    } else {
        # Check the value of Diagnosic-Code: header with patterns
        if( $argvs->smtpcommand eq 'MAIL' ) {
            # The session was rejected at 'MAIL FROM' command
            $v = 1 if __PACKAGE__->match($diagnostic);

        } elsif( $argvs->smtpcommand eq 'DATA' ) {
            # The session was rejected at 'DATA' command
            if( $tempreason ne 'userunknown' ) {
                # Except "userunknown"
                $v = 1 if __PACKAGE__->match($diagnostic);
            }
        } else {
            if( $tempreason eq 'undefined' || $tempreason eq 'onhold' ) {
                # Try to match with message patterns when the temporary reason
                # is "onhold" or "undefined"
                $v = 1 if __PACKAGE__->match($diagnostic);
            }
        }
    }

    return $v;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Reason::Rejected - Bounce reason is C<rejected> or not.

=head1 SYNOPSIS

    use Sisimai::Reason::Rejected;
    print Sisimai::Reason::Rejected->match('550 Address rejected');   # 1

=head1 DESCRIPTION

Sisimai::Reason::Rejected checks the bounce reason is C<rejected> or not. This
class is called only Sisimai::Reason class.

This is the error that a connection to destination server was rejected by a 
sender's email address (envelope from). Sisimai set C<rejected> to the reason
of email bounce if the value of Status: field in a bounce email is C<5.1.8> or
the connection has been rejected due to the argument of SMTP MAIL command.

    <kijitora@example.org>:
    Connected to 192.0.2.225 but sender was rejected.
    Remote host said: 550 5.7.1 <root@nijo.example.jp>... Access denied

=head1 CLASS METHODS

=head2 C<B<text()>>

C<text()> returns string: C<rejected>.

    print Sisimai::Reason::Rejected->text;  # rejected

=head2 C<B<match(I<string>)>>

C<match()> returns 1 if the argument matched with patterns defined in this class.

    print Sisimai::Reason::Rejected->match('550 Address rejected');   # 1

=head2 C<B<true(I<Sisimai::Data>)>>

C<true()> returns 1 if the bounce reason is C<rejected>. The argument must be
Sisimai::Data object and this method is called only from Sisimai::Reason class.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2017 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut
