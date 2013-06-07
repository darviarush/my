use Test::More tests => 2;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "utils";

$x = utils::to_json({"x"=>{"p"=>[20, 30, []], "m"=>{"t"=>"y"}}, 1=>22, "y"=>{"p"=>{"f"=>12, "y"=>10}}});
is($x, '{"x":{"m":{"t":"y"},"p":[20,30,[]]},1:22,"y":{"p":{"f":12,"y":10}}}');