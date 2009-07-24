package RangeCoder::Util;
use strict;
use warnings;
use Exporter::Lite;

our @EXPORT    = qw/getc putc/;
our @EXPORT_OK = @EXPORT;

sub putc {
    my ($out, $ord) = @_;
    $out->write(pack('C', $ord), 1);
}

sub getc {
    my $in = shift;
    if (defined (my $packed = $in->getc)) {
        return unpack('C', $packed);
    }
    return;
}

1;
