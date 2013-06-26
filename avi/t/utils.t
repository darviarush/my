use Test::More tests => 4;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "utils";

$x = utils::to_json({"x"=>{"p"=>[20, 30, []], "m"=>{"t"=>"y"}}, 1=>22, "y"=>{"p"=>{"f"=>12, "y"=>10}}});
is($x, '{"x":{"m":{"t":"y"},"p":[20,30,[]]},1:22,"y":{"p":{"f":12,"y":10}}}');

$x = [{x=>f}];

utils::walk_data($x, sub {
	ok(0);
}, sub {
	my ($ref, $key, $hash) = @_;
	$$ref = 1 if $hash;
});
is_deeply($x, [1]);


$x = {f=>1};
utils::walk_data($x, sub {}, sub {
	my ($ref) = @_;
	$$ref = 1;
});

is($x, 1);