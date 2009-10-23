package RangeCoder::Adaptive;
use strict;
use warnings;

use RangeCoder::Util;

use constant UCHAR_MAX => 256;
use constant MAX_RANGE => 0x7fffffff;
use constant MIN_RANGE => 0x800000;
use constant MASK      => 0x7fffffff;
use constant SHIFT     => 23;

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
    $out->print(pack('I', $size));

    while (defined(my $c = &getc($in))) {
        my $tmp;
        {
            use integer;
            $tmp = $self->{range} / $self->{sum};
        }

        my $old_low  = $self->{low};
        $self->{low}   = ($old_low + $self->cumfreq($c) * $tmp) & MASK;
        $self->{range} = $self->{count}->[$c] * $tmp;
        $self->encode_normalize($old_low, $out);
        $self->update($c); ## 適応型: 頻度表を更新
    }
    $self->finish($out);
}

sub finish {
    my ($self, $out) = @_;
    putc($out, $self->{buff});
    for (my $i = $self->{n_carry}; $i > 0; $i--) {
        putc($out, 0xff);
    }
    putc($out, ($self->{low} >> 23)  & 0xff);
    putc($out, ($self->{low} >> 15)  & 0xff);
    putc($out, ($self->{low} >> 7)    & 0xff);
    putc($out, ($self->{low} & 0x7f) << 1);
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
        if ($self->{low} < (0xff << SHIFT)) {
            putc($out, $self->{buff});
            for (my $i = $self->{n_carry}; $i > 0; $i--) {
                putc($out, 0xff);
            }
            $self->{buff} = ($self->{low} >> SHIFT) & 0xff;
            $self->{n_carry}  = 0;
        } else {
            $self->{n_carry} += 1;
        }

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
    $in->read(my $tmp, 4) or die $@;
    my $size = unpack('I', $tmp);
    &getc($in);

    my $self = $class->new;
    $self->{low} = &getc($in);
    $self->{low} = ($self->{low} << 8) + &getc($in);
    $self->{low} = ($self->{low} << 8) + &getc($in);
    $self->{buff} = &getc($in);
    $self->{low} = ($self->{low} << 7) + ($self->{buff} >> 1);

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
        $self->{low}  = ($self->{low} << 1) + ($self->{buff} & 1);
        $self->{buff} = &getc($in);
        $self->{low}  = (($self->{low} << 7) + ($self->{buff} >> 1)) & MASK;
        $self->{range} <<= 8;
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

1;
