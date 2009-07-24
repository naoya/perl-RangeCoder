package RangeCoder::Adaptive::BIT;
use strict;
use warnings;

use RangeCoder::Util;
use Algorithm::BIT;

use constant UCHAR_MAX => 256;
use constant MAX_RANGE => 0x1000000;
use constant MIN_RANGE => 0x10000;
use constant MASK      => 0xffffff;
use constant SHIFT     => 16;

use Algorithm::BIT;

sub new {
    my ($class) = @_;
    my $self = bless {}, $class;
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

    my $table = create_table(UCHAR_MAX);
    while (defined(my $c = &getc($in))) {
        my $tmp;
        {
            use integer;
            $tmp = $self->{range} / $table->sum;
        }

        my $old_low  = $self->{low};
        $self->{low}   = ($old_low + $table->cumul($c) * $tmp) & MASK;
        $self->{range} = $table->freq($c) * $tmp;

        $self->encode_normalize($old_low, $out);
        $self->update($c, $table);
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
            $self->{n_carry} = 0;
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
    putc($out, ($self->{low} >> 16) & 0xff);
    putc($out, ($self->{low} >> 8)  & 0xff);
    putc($out, $self->{low} & 0xff);
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

    my $table = create_table(UCHAR_MAX);
    while ($size > 0) {
        my ($tmp, $c, $num);
        {
            use integer;
            $tmp = $self->{range} / $table->sum;
            ($c, $num) = $table->search_index($self->{low} / $tmp);
        }

        $self->{low}  -= $tmp * $num;
        $self->{range} = $tmp * $table->freq($c);

        $self->decode_normalize($in);
        $self->update($c, $table);

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

1;
