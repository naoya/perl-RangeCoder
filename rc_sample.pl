#!/usr/bin/env perl
use strict;
use warnings;
use FindBin::libs;

use Path::Class qw/file/;
use IO::String;
use Benchmark::Timer;

use RangeCoder;

my $path = shift or die "usage: %0 <file>";
my $file = file($path);
my $t    = Benchmark::Timer->new;
my $in   = $file->openr;
my $out  = IO::String->new;
my $size = $file->stat->size;

encode_file($in, $out, $size, $t);

$out->seek(0, 0);
my $bin;
while ($out->read(my $buff, 1024)) {
    $bin .= $buff;
}
$out->seek(0, 0);

decode_file($out, \*STDOUT, $t);

warn sprintf "%d bytes => %d bytes", $size, length($bin);
warn scalar $t->reports;

sub encode_file {
    my ($in, $out, $size, $t) = @_;

    my @count;
    for (my $i = 0; $i < 0x100; $i++) {
        $count[$i]= 0;
    }
    while (defined (my $s = $in->getc)) {
        $count[ord $s]++;
    }

    $in->seek(0, 0);

    $t->start('encoding');
    my $rc = RangeCoder->new(\@count);
    $rc->encode($in, $out, $size);
    $t->stop('encoding');
}

sub decode_file {
    my ($in, $out, $t) = @_;
    $t->start('decoding');
    RangeCoder->decode($in, $out);
    $t->stop('decoding');
}
