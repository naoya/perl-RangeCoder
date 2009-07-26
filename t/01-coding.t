use strict;
use warnings;

use IO::String;
use UNIVERSAL::require;
use Test::More qw/no_plan/;

my @static_classses  = qw/RangeCoder RangeCoder::Wide/;
my @adaptive_classes = qw/RangeCoder::Adaptive RangeCoder::Adaptive::BIT RangeCoder::Adaptive::FiniteContext/;

my $text =<<EOT;
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse congue pretium orci et pretium. Fusce sem lacus, adipiscing a commodo eget, interdum pretium urna. Sed dapibus enim eu nunc porta eget aliquam augue porta. Etiam et tempor ante. Suspendisse sagittis elementum odio sed dapibus. Nullam scelerisque gravida diam, eget hendrerit nibh sagittis posuere. Donec ac purus risus. Vestibulum interdum dolor ut dui egestas nec laoreet dui porta. Etiam leo augue, venenatis sit amet aliquam id, rutrum eget nunc. Nullam eget neque velit, convallis bibendum sapien. Sed dignissim volutpat sollicitudin.

Proin vestibulum, massa eget vehicula suscipit, tellus odio mattis nisl, vel tristique nibh erat vel justo. Duis vitae nunc mattis purus bibendum tempor. In eu dui et lacus porta viverra pretium et ipsum. Nunc porttitor sagittis dolor faucibus laoreet. Morbi quam dolor, mattis ut pharetra nec, convallis ut urna. Aenean sagittis, metus venenatis convallis euismod, urna tellus rhoncus est, non ornare dui diam in neque. Aliquam leo quam, ullamcorper eu rutrum id, convallis nec nibh. Vivamus condimentum lorem ac tellus interdum viverra. Nam quis eros urna, eget tincidunt turpis. In hac habitasse platea dictumst. Suspendisse malesuada ante et nibh luctus accumsan et ac nibh. Nullam nec odio ac eros malesuada posuere. Quisque eget erat augue, eu euismod dui. Phasellus consectetur venenatis dignissim. Vestibulum hendrerit vehicula aliquet. Nullam tempus nulla in neque ultricies vitae dapibus orci ullamcorper. Suspendisse faucibus orci non nisi ultricies nec scelerisque lorem hendrerit. Donec eleifend dignissim eros eget cursus.

Nullam tincidunt nibh non libero blandit faucibus. Sed at purus lorem. Morbi ut dictum arcu. Morbi congue interdum sagittis. Vivamus lacinia rhoncus magna, sit amet auctor lorem vulputate sit amet. Aliquam tempus rutrum nulla at ullamcorper. Maecenas sed est sapien. Donec a ante et nulla tempus condimentum. Vivamus imperdiet tincidunt sodales. Nunc volutpat dictum tempor. Etiam mattis, mi sit amet feugiat vulputate, ante lorem tempor nibh, ut condimentum elit felis sit amet dui. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Nullam eu dui nisi. Vestibulum porttitor risus diam. Etiam vitae pretium nisi. Fusce at urna eget dui aliquam euismod.

Nulla mollis, urna iaculis euismod sodales, urna dolor facilisis erat, at placerat ante nisi nec leo. Aenean in lectus eget tortor sodales convallis. Nam sagittis augue vitae ipsum facilisis vitae sagittis est viverra. Quisque semper dictum ligula, vitae luctus libero lacinia in. Etiam eu laoreet sapien. Mauris euismod, leo vel ultricies rutrum, arcu purus blandit magna, vel eleifend lectus ipsum non nunc. Ut eros quam, volutpat vitae imperdiet auctor, cursus ac ligula. Aenean nec purus sed dolor fringilla vestibulum. Cras sed quam at tortor tincidunt auctor. Sed sagittis hendrerit arcu, ut vehicula lectus ultrices vel. Nam ac nisi eu ligula placerat rhoncus vitae quis lectus. Donec ut purus quis nisi interdum ornare euismod sed massa. Quisque porttitor hendrerit ligula sodales placerat. Cras ut massa ut nibh volutpat accumsan.

Nulla quis metus vel lorem dignissim lobortis. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Curabitur ut augue lectus. Nam tortor urna, rutrum ut porttitor ut, interdum vitae lacus. Morbi vitae orci a nibh dictum sagittis eu eget elit. Curabitur euismod scelerisque mauris id aliquet. Cras eu tellus vitae enim euismod dapibus. Aenean condimentum mollis dolor, eget egestas libero malesuada id. Praesent placerat fermentum tellus at fringilla. Integer convallis sapien at neque tincidunt iaculis. Aenean ultricies auctor enim, a eleifend dui porttitor nec. Aliquam tempor condimentum lacus nec varius. Vestibulum consequat, nibh a ultrices mattis, orci nibh vehicula ligula, eu semper lorem nibh nec tellus. Cras metus ante, sodales nec semper non, ultricies in nulla. Sed tempus lorem eget velit malesuada rutrum eu id erat. Suspendisse elit enim, mollis a hendrerit quis, mattis sit amet metus.
EOT

my @count;
for (my $i = 0; $i < 0x100; $i++) {
    $count[$i] = 0;
}
for my $c (unpack('C*', $text)) {
    $count[$c]++;
}

sub test_compression {
    my ($is_adaptive, @classes) = @_;
    for my $class (@classes) {
        $class->use or die $@;

        my $in   = IO::String->new($text);
        my $out  = IO::String->new;
        my $test = IO::String->new;

        my $rc = $is_adaptive ? $class->new : $class->new(\@count);
        $rc->encode($in, $out, length $text);

        $out->seek(0, 0);
        $class->decode($out, $test);

        {
            local $/;
            $out->seek(0, 0);
            ok length scalar <$out> > 0;

            $out->seek(0, 0);
            ok length scalar <$out> < length $text;

            $test->seek(0, 0);
            is scalar <$test>, $text;
        }

        $in->close;
        $out->close;
        $test->close;
    }
}

test_compression(0, @static_classses);
test_compression(1, @adaptive_classes);
