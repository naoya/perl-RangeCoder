package RangeCoder::Adaptive::FiniteContext::Table;
use strict;
use warnings;

use Algorithm::BIT;
use constant UCHAR_MAX => 256;

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->{sum} = 0;
    my $bit = Algorithm::BIT->new(UCHAR_MAX);
    for (my $i = 0; $i < UCHAR_MAX; $i++) {
        $bit->update($i, 1);
    }
    $self->{table} = $bit;

    return $self;
}

sub cumul {
    my ($self, $c) = @_;
    return $self->{table}->cumul($c);
}

sub freq {
    my ($self, $c) = @_;
    return $self->{table}->freq($c);
}

sub update {
    my ($self, $c, $v) = @_;
    $self->{table}->update($c, $v);
}

sub sum {
    return $_[0]->cumul(UCHAR_MAX);
}

sub search_index {
    my ($self, $v) = @_;
    return $self->{table}->search_index($v);
}

1;
