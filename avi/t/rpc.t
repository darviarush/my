use Test::More tests => 29;

use Carp 'verbose';
$SIG{ __DIE__ } = *Carp::confess;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "rpc";
use_ok "utils";

$rpc = rpc->new("perl");


$a = $rpc->unpack('{"f":["x",1]}');
is_deeply($a, {"f"=>["x",1]});

@A = $rpc->eval('reverse(@$args)', 1,[2,4],{"f"=>"p"},3);
is_deeply(\@A, [3,{"f"=>"p"},[2,4],1]);

@A = $rpc->call('reverse', 1,[2,4],{"f"=>"p"},3);
is_deeply(\@A, [3,{"f"=>"p"},[2,4],1]);

eval { $rpc->eval("die 'test exception'") };
like($@, qr/test exception/);


$rpc->eval("require Cwd; use Data::Dumper");

$pwd = $rpc->call("Cwd::getcwd");
ok($pwd);

$dump = $rpc->call("Dumper", [1]);
is($dump, "\$VAR1 = [\n          1\n        ];\n");

$rpc->eval("use CGI;");

$cgi = $rpc->apply("CGI", "new");
$h1 = $cgi->h1('hello world');
is($h1, '<h1>hello world</h1>');


$header = $cgi->header;
is($header, "Content-Type: text/html; charset=ISO-8859-1\r\n\r\n");

$header = $cgi->header(-type=>'image/gif', -expires=>'+3d');
like($header, qr/Content-Type: image\/gif/);


delete ${"main::"}{"cgi"};

$test1 = $rpc->eval("'test1'");
is($test1, "test1");

@ret = $rpc->eval("\$args->[0]->call('reverse', 1,2,\@\$args)", $rpc, 4);
is_deeply(\@ret, [4,$rpc,2,1]);

$rpc->eval("test");



$bless = $rpc->eval("\$args->[0]->{bless}", $rpc);
is($bless, $rpc->{bless});

#$rpc->warn(1);

$myobj = bless {}, "myclass";
$ret = $rpc->eval("\$args->[0]->{x10} = 10", $myobj);
is($ret, 10);
is($myobj->{'x10'}, 10);

$ret = $rpc->eval("\$args->[0]->{x10}", $myobj);
is($ret, 10);


$rpc->close;




$rpc = rpc->new('php');

@ret = $rpc->eval("return array_reverse(\$args);", 1,[2,4],{"f"=>"p"},3);
is_deeply(\@ret, [3,{"f"=>"p"},[2,4],1]);

@ret = $rpc->call("array_reverse", [1,[2,4],{"f"=>"p"},3]);
is_deeply(\@ret, [3,{"f"=>"p"},[2,4],1]);

eval { $rpc->eval("throw new Exception('test exception');") };
like($@, qr/test exception/);

sub myclass::ex { $_[1]+$_[2]+$_[0]->{x10} }
$myobj = bless {}, "myclass";

$ret = $rpc->eval("return \$args[0]->x10 = 10;", $myobj);
is($ret, 10);
is($myobj->{'x10'}, 10);

$ret = $rpc->eval("return \$args[0]->x10;", $myobj);
is($ret, 10);

$ret = $rpc->eval("return \$args[0]->ex(\$args[1], \$args[2]);", $myobj, 20, 30);
is_deeply($ret, [60]);

($ret) = $rpc->eval("return \$args[0]->ex(\$args[1], \$args[2]);", $myobj, 20, 30);
is($ret, 60);


$stub = $rpc->eval('class A { public $c; function ex($a, $b=0) { return $a+$b+$this->c; } } return new A();');
isa_ok($stub, "rpc::stub");

$stub->{'c'} = 30;
is($stub->{'c'}, 30);

$ret = $stub->ex(10);
is($ret, 40);

$ret = $stub->ex(10, 20);
is($ret, 60);


$rpc->close;



$rpc = rpc->new('python');
#$rpc->warn(1);


@ret = $rpc->eval("reversed(args)", 1,[2,4],{"f"=>"p"},3);
is_deeply(\@ret, [3,{"f"=>"p"},[2,4],1]);

@ret = $rpc->call("reversed", [1,[2,4],{"f"=>"p"},3]);
is_deeply(\@ret, [3,{"f"=>"p"},[2,4],1]);

eval { $rpc->eval("raise Exception('test exception')") };
like($@, qr/test exception/);

$myobj = bless {}, "myclass";

$ret = $rpc->eval("args[0].x10 = 10", $myobj);
is($ret, 10);
is($myobj->{'x10'}, 10);

$ret = $rpc->eval("args[0].x10", $myobj);
is($ret, 10);

$ret = $rpc->eval("args[0].ex(args[1], args[2])", $myobj, 20, 30);
is_deeply($ret, [60]);

($ret) = $rpc->eval("args[0].ex(args[1], args[2])", $myobj, 20, 30);
is($ret, 60);

$stub = $rpc->eval("
class A: 
	def ex($a, $b=0):
		return $a+$b+$this->c
return A()
");
isa_ok($stub, "rpc::stub");

$stub->{'c'} = 30;
is($stub->{'c'}, 30);

$ret = $stub->ex(10);
is($ret, 40);

$ret = $stub->ex(10, 20);
is($ret, 60);


$rpc->close;
