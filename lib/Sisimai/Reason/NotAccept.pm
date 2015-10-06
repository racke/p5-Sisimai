package Sisimai::Reason::NotAccept;
use feature ':5.10';
use strict;
use warnings;

sub text  { 'notaccept' }
sub match {
    my $class = shift;
    my $argvs = shift // return undef;

    # Destination mail server does not accept any message
    my $regex = qr/smtp[ ]protocol[ ]returned[ ]a[ ]permanent[ ]error/xi;

    return 1 if $argvs =~ $regex;
    return 0;
}

sub true {
    # @Description  Remote host does not accept any message
    # @Param <obj>  (Sisimai::Data) Object
    # @Return       (Integer) 1 = Not accept
    #               (Integer) 0 = accept
    # @See          http://www.ietf.org/rfc/rfc2822.txt
    my $class = shift;
    my $argvs = shift // return undef;

    return undef unless ref $argvs eq 'Sisimai::Data';
    my $reasontext = __PACKAGE__->text;

    return 1 if $argvs->reason eq $reasontext;

    my $diagnostic = $argvs->diagnosticcode // '';
    my $v = 0;

    if( $argvs->replycode =~ m/\A(?:521|554|556)\z/ ) {
        # SMTP Reply Code is 554 or 556
        $v = 1;

    } else {
        # Check the value of Diagnosic-Code: header with patterns
        if( $argvs->smtpcommand eq 'MAIL' ) {
            # Matched with a pattern in this class
            $v = 1 if __PACKAGE__->match( $diagnostic );
        }
    }

    return $v;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Reason::NotAccept - Bounce reason is C<notaccept> or not.

=head1 SYNOPSIS

    use Sisimai::Reason::NotAccept;
    print Sisimai::Reason::NotAccept->match('domain does not exist:');   # 1

=head1 DESCRIPTION

Sisimai::Reason::NotAccept checks the bounce reason is C<notaccept> or not.
This class is called only Sisimai::Reason class.

This is the error that a destination mail server does ( or can ) not accept any
email. In many case, the server is high load or under the maintenance.  Sisimai
will set C<notaccept> to the reason of email bounce if the value of Status:
field in a bounce email is C<5.3.2> or the value of SMTP reply code is 556.

=head1 CLASS METHODS

=head2 C<B<text()>>

C<text()> returns string: C<notaccept>.

    print Sisimai::Reason::NotAccept->text;  # notaccept

=head2 C<B<match( I<string> )>>

C<match()> returns 1 if the argument matched with patterns defined in this class.

    print Sisimai::Reason::NotAccept->match('domain does not exist:');   # 1

=head2 C<B<true( I<Sisimai::Data> )>>

C<true()> returns 1 if the bounce reason is C<notaccept>. The argument must be
Sisimai::Data object and this method is called only from Sisimai::Reason class.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2015 azumakuniyuki E<lt>perl.org@azumakuniyuki.orgE<gt>,
All Rights Reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut
