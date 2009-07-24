package RangeCoder;
use strict;
use warnings;

use RangeCoder::Util;
use List::Util qw/max/;

use constant UCHAR_MAX => 256;
use constant MAX_RANGE => 0x1000000;
use constant MIN_RANGE => 0x10000;
use constant MASK      => 0xffffff;
use constant SHIFT     => 16;

sub new {
    my ($class, $count) = @_;
    my $self = bless { count => $count }, $class;

    ## Smoothing (奥村さんの方式)
    ## 655355 を越えないように
    ## 度数の最大値が 255 になるように調節
    if ((my $m = max(@$count)) >= 256) {
       use integer;
       for my $v (@$count) {
           $v = ($v * 255 + $m - 1) / $m;
       }
    }

    my @cumfreq = (0);
    for (my $i = 0; $i < UCHAR_MAX; $i++) {
        $cumfreq[$i + 1] = $cumfreq[$i] + $self->{count}->[$i];
    }

    if ($cumfreq[-1] >= MIN_RANGE) {
        die sprintf 'assert (total symbol occurence: %d)', $cumfreq[-1];
    }

    $self->{cumfreq} = \@cumfreq;
    $self->{low}     = 0;
    $self->{range}   = MAX_RANGE;
    $self->{buff}    = 0;
    $self->{n_carry} = 0;
    return $self;
}

sub encode {
    my ($self, $in, $out, $size) = @_;

    ## サイズ書き込み
    $out->print(pack('I', $size));

    ## 出現頻度表書き込み
    my $cnt_bin = pack('w*', @{$self->{count}});
    $out->print(pack('I', length $cnt_bin));
    $out->print($cnt_bin);

    while (defined(my $c = &getc($in))) {
        my $tmp;
        {
            use integer;
            $tmp = $self->{range} / $self->{cumfreq}->[-1];
        }

        my $old_low  = $self->{low};
        $self->{low}   = ($old_low + $self->{cumfreq}->[$c] * $tmp) & MASK;
        $self->{range} = $self->{count}->[$c] * $tmp;
        $self->encode_normalize($old_low, $out);
    }
    $self->finish($out);
}

sub encode_normalize {
    my ($self, $old_low, $out) = @_;

    if ($self->{low} < $old_low) {
        ## 桁上がり
        $self->{buff} += 1;
        if ($self->{n_carry} > 0) {
            putc($out, $self->{buff});
            for (my $i = $self->{n_carry} - 1; $i > 0; $i--) {
                putc($out, 0);
            }
            $self->{buff} = 0;
            $self->{n_carry}  = 0;
        }
    }

    while ($self->{range} < MIN_RANGE) {
        ## range が MIN_RANGE (MAX_RANGE の 1/256) 以下になった
        ## → low の上位1バイトを削る, range を引き延ばす
        if ($self->{low} < (0xff << SHIFT)) {
            putc($out, $self->{buff});
            for (my $i = $self->{n_carry}; $i > 0; $i--) {
                putc($out, 0xff);
            }
            $self->{buff} = ($self->{low} >> SHIFT) & 0xff; # low の上位 1 バイトを buff に
            $self->{n_carry}  = 0;
        } else {
            ## 上位1バイトが 0xff だった
            $self->{n_carry} += 1;
        }

        ## low, range を 256 倍 (low は 256 倍のあと 24 bit に収める)
        $self->{low} = ($self->{low} << 8) & MASK;
        $self->{range} <<= 8;
    }
}

sub finish {
    my ($self, $out) = @_;
    putc($out, $self->{buff});
    for (my $i = $self->{n_carry}; $i > 0; $i--) {
        putc($out, 0xff);
    }
    putc($out, ($self->{low} >> 16) & 0xff);
    putc($out, ($self->{low} >> 8)  & 0xff);
    putc($out, $self->{low} & 0xff);
}

sub decode {
    my ($class, $in, $out) = @_;

    ## サイズ読み込み
    $in->read(my $tmp, 8) or die $@;
    my ($size, $cnt_size) = unpack('I2', $tmp);

    ## 頻度表読み込み
    $in->read(my $cnt_bin, $cnt_size) or die $!;
    my @count = unpack('w*', $cnt_bin);

    # 1 byte 読み捨て
    &getc($in);

    my $self = $class->new(\@count);
    $self->{low} = &getc($in);
    $self->{low} = ($self->{low} << 8) + &getc($in);
    $self->{low} = ($self->{low} << 8) + &getc($in);

    ## cumfreq[c]/total <= low/range < cumfreq[c + 1]/total な c を探す
    ## 探し当てたら low と range を更新して同様に繰り返す
    while ($size > 0) {
        my ($tmp, $c);
        {
            use integer;
            $tmp = $self->{range} / $self->{cumfreq}->[-1];
            $c = $self->search_code($self->{low} / $tmp);
        }

        $self->{low}  -= $tmp * $self->{cumfreq}->[$c];
        $self->{range} = $tmp * $self->{count}->[$c];
        $self->decode_normalize($in);

        $out->print(chr $c);
        $size--;
    }
}

sub decode_normalize {
    my ($self, $in) = @_;
    while ($self->{range} < MIN_RANGE) {
        $self->{range} <<= 8;
        $self->{low} = (($self->{low} << 8) + &getc($in)) & MASK;
    }
}

sub search_code {
    my ($self, $v) = @_;
    use integer;

    my $i   = 0;
    my $j   = UCHAR_MAX - 1;
    my $cum = $self->{cumfreq};
    while ($i < $j) {
        my $k = ($i + $j) / 2;
        if ($cum->[$k + 1] <= $v) {
            $i = $k + 1;
        } else {
            $j = $k;
        }
    }
    return $i;
}

1;
