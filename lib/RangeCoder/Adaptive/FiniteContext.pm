package RangeCoder::Adaptive::FiniteContext;
use strict;
use warnings;

use RangeCoder::Util;
use Algorithm::BIT;

use constant UCHAR_MAX => 256;
use constant MAX_RANGE => 0x7fffffff;
use constant MIN_RANGE => 0x800000;
use constant MASK      => 0x7fffffff;
use constant SHIFT     => 23;

sub new {
    my $self = bless {}, shift;
    $self->{low}     = 0;
    $self->{range}   = MAX_RANGE;
    $self->{buff}    = 0;
    $self->{n_carry} = 0;
    return $self;
}

sub create_table {
    my $max = shift;
    my $t = Algorithm::BIT->new($max);
    for (my $i = 0; $i < $max; $i++) {
        $t->update($i, 1);
    }
    return $t;
}

sub encode {
    my ($self, $in, $out, $size) = @_;
    $out->print(pack('I', $size));

    my @freq;
    my $c00 = 0;
    my $c0  = 0;

    while (defined(my $c = &getc($in))) {
        if (!$freq[$c00][$c0]) {
            $freq[$c00][$c0] = create_table(UCHAR_MAX);
        }

        my $tmp;
        {
            use integer;
            $tmp = $self->{range} / $freq[$c00][$c0]->sum;
        }

        my $old_low  = $self->{low};
        $self->{low}   = ($old_low + $freq[$c00][$c0]->cumul($c) * $tmp) & MASK;
        $self->{range} = $freq[$c00][$c0]->freq($c) * $tmp;

        $self->encode_normalize($old_low, $out);
        $self->update($c, $freq[$c00][$c0]);

        ## 文脈更新
        $c00 = $c0;
        $c0  = $c;
    }
    $self->finish($out);
}

sub encode_normalize {
    my ($self, $old_low, $out) = @_;

    if ($self->{low} < $old_low) {
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
    my ($self, $c, $table) = @_;
    $table->update($c, 1);
    if ($table->sum >= MIN_RANGE) {
        for (my $i = 0; $i < UCHAR_MAX; $i++) {
            my $n = $table->freq($i) >> 1;
            if ($n > 0) {
                $table->update($i, -$n);
            }
        }
    }
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

    my @freq;
    my $c00 = 0;
    my $c0  = 0;

    while ($size > 0) {
        if (!$freq[$c00][$c0]) {
            $freq[$c00][$c0] = create_table(UCHAR_MAX);
        }

        my ($tmp, $c, $num);
        {
            use integer;
            $tmp = $self->{range} / $freq[$c00][$c0]->sum;
            ($c, $num) = $freq[$c00][$c0]->search_index($self->{low} / $tmp);
        }

        $self->{low}  -= $tmp * $num;
        $self->{range} = $tmp * $freq[$c00][$c0]->freq($c);

        $self->decode_normalize($in);
        $self->update($c, $freq[$c00][$c0]);

        $out->print(chr $c);
        $size--;

        $c00 = $c0;
        $c0  = $c;
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

1;
