use Test::More tests => 29;

use Carp 'verbose';
$SIG{ __DIE__ } = *Carp::confess;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "rpc";
use_ok "utils";


$rpc = rpc->new('swi');
$rpc->warn(1);

@ret = $rpc->eval("args.reverse", 1,[2,4],{"f"=>"p"},3);
is_deeply(\@ret, [3,{"f"=>"p"},[2,4],1]);

($ret) = $rpc->call("format", "%+i %#X %#10i", 1, 22, -3);
is($ret, "+1 0x");

eval { $rpc->eval("raise Exception, 'test exception'") };
like($@, qr/test exception/);

$myobj = bless {}, "myclass";

$ret = $rpc->eval("args[0]['x10'] = 10", $myobj);
is($ret, 10);
is($myobj->{'x10'}, 10);

$ret = $rpc->eval("args[0]['x10']", $myobj);
is($ret, 10);

$ret = $rpc->eval("args[0].ex(*args[1..2])", $myobj, 20, 30);
is_deeply($ret, [60]);

($ret) = $rpc->eval("args[0].ex(*args[1..2])", $myobj, 20, 30);
is($ret, 60);


$stub = $rpc->eval('class A; def ex a, b=0; return a+b+@c; end; end; A.new');
isa_ok($stub, "rpc::stub");

$stub->{'c'} = 30;
is($stub->{'c'}, 30);

$ret = $stub->ex(10);
is($ret, 40);

$ret = $stub->ex(10, 20);
is($ret, 60);


$rpc->close;
