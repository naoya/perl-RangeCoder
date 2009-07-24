package RangeCoder::Adaptive;
use strict;
use warnings;

use constant UCHAR_MAX => 256;

use constant MAX_RANGE => 0x1000000;
use constant MIN_RANGE => 0x10000;
use constant MASK      => 0xffffff;
use constant SHIFT     => 16;

use List::Util qw/max/;

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    my @count;
    for (my $i = 0; $i < UCHAR_MAX; $i++) {
        $count[$i] = 1;
    }

    $self->{count}   = \@count;
    $self->{low}     = 0;
    $self->{range}   = MAX_RANGE;
    $self->{buff}    = 0;
    $self->{n_carry} = 0;
    $self->{sum}     = UCHAR_MAX;

    return $self;
}

sub encode {
    my ($self, $in, $out, $size) = @_;

    ## サイズ書き込み
    $out->print(pack('I', $size));

    while (defined(my $c = &getc($in))) {
        # printf STDERR "[%x, %x] - %s -> ", $self->low, $self->range, chr $c;
        my $tmp;
        {
            use integer;
            $tmp = $self->{range} / $self->{sum};
        }

        my $old_low  = $self->{low};
        $self->{low}   = ($old_low + $self->cumfreq($c) * $tmp) & MASK;
        $self->{range} = $self->{count}->[$c] * $tmp;

        # printf STDERR "[%x, %x]\n", $self->low, $self->range;
        $self->encode_normalize($old_low, $out);
        $self->update($c);
    }

    ## finish()
    putc($out, $self->{buff});
    for (my $i = $self->{n_carry}; $i > 0; $i--) {
        putc($out, 0xff);
    }
    # putc($out, ($self->{low} >> 24) & 0xff);
    putc($out, ($self->{low} >> 16) & 0xff);
    putc($out, ($self->{low} >> 8)  & 0xff);
    putc($out, $self->{low} & 0xff);
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

sub update {
    my ($self, $c) = @_;
    $self->{count}->[$c]++;
    $self->{sum}++;

    ## sum が MIN_RANGE 以上になったら各記号の出現頻度を 1/2
    if ($self->{sum} >= MIN_RANGE) {
        my $n = 0;
        for my $v (@{$self->{count}}) {
            $v = ($v >> 1) | 1;
            $n += $v;
        }
        $self->{sum} = $n;
    }
}

sub cumfreq {
    my ($self, $c) = @_;
    my $n     = 0;
    my $count = $self->{count};
    for (my $i = 0; $i < $c; $i++) {
        $n += $count->[$i];
    }
    return $n;
}

sub decode {
    my ($class, $in, $out) = @_;

    ## サイズ読み込み
    $in->read(my $tmp, 4) or die $@;
    my $size = unpack('I', $tmp);

    # 1 byte 読み捨て
    &getc($in);

    my $self = $class->new;
    # 3 bytes (24 bit) read
    $self->{low} = &getc($in);
    $self->{low} = ($self->{low} << 8) + &getc($in);
    $self->{low} = ($self->{low} << 8) + &getc($in);
    # $self->{low} = ($self->{low} << 8) + &getc($in);

    ## cumfreq[c]/total <= low/range < cumfreq[c + 1]/total な c を探す
    ## 探し当てたら low と range を更新して同様に繰り返す
    while ($size > 0) {
        my ($tmp, $c, $num);
        {
            use integer;
            $tmp = $self->{range} / $self->{sum};
            ($c, $num) = $self->search_code($self->{low} / $tmp);
        }

        $self->{low}  -= $tmp * $num;
        $self->{range} = $tmp * $self->{count}->[$c];
        $self->decode_normalize($in);
        $self->update($c);

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

## とりあえず線形探索
sub search_code {
    my ($self, $v) = @_;

    my $n   = 0;
    my $count = $self->{count};

    for (my $c = 0; $c < UCHAR_MAX; $c++) {
        if ($v < $n + $count->[$c]) {
            return ($c, $n);
        }
        $n += $count->[$c];
    }
}

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
