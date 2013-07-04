use Test::More tests => 25;

use Carp 'verbose';
$SIG{ __DIE__ } = *Carp::confess;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "rpc";
use_ok "utils";

open $w, ">", \$file or die $!;
open $r, "<", \$file or die $!;

$rpc = rpc->new(-1, $r, $w);

$obj1 = bless {}, "test_class1";
$obj2 = bless {}, "test_class2";
$obj3 = bless {}, "test_class_for_stub";

$rpc->{objects}->{0} = $obj3;
$stub3 = $rpc->stub(0);

$data_x = [1, 3.0, $obj1, 4, "1", $utils::boolean::true];
$data = {"f"=> [0, $stub3, [$data_x], 33.1, {"data_x" => $data_x, "obj2" => $obj2}, "pp", 33], "g"=> "Привет!"};

$rpc->pack($data);

#$_ = $file;
#s/[\x0-\x1f]/ /g;
#print "$_\n";

is(3, 0+keys %{$rpc->{objects}});

$unpack = $rpc->unpack;

$dx2 = $unpack->{"f"}->[2]->[0];

is($dx2, $unpack->{"f"}->[4]->{"data_x"});
is(ref($dx2->[2]), "rpc::stub");
is(ref($unpack->{"f"}->[4]->{"obj2"}), "rpc::stub");
is(ref($dx2->[5]), "utils::boolean");
is($unpack->{"f"}->[1], $obj3);
is($dx2->[0], 1);
is($unpack->{"f"}->[0], 0, "end");



$rpc = rpc->new("perl");
#$rpc->warn(1);
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

$cgi = $rpc->new_instance("CGI");
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



$role = $rpc->eval("\$args->[0]->{role}", $rpc);
is($role, $rpc->{role});

#$rpc->warn(1);

$myobj = bless {}, "myclass";
$ret = $rpc->eval("\$args->[0]->{x10} = 10", $myobj);
is($ret, 10);
is($myobj->{'x10'}, 10);

$ret = $rpc->eval("\$args->[0]->{x10}", $myobj);
is($ret, 10);


$rpc->close;
