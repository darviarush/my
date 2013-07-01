use Test::More tests => 17;

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

$rpc->{objects}{0} = $obj3;
$stub3 = $rpc->stub(0);

$data_x = [1, 3.0, $obj1, 4, "1", $utils::boolean::true];
$data = {"f"=> [0, $stub3, [$data_x], 33.1, {"data_x" => $data_x, "obj2" => $obj2}, "pp", 33], "g"=> "Привет!"};

$rpc->pack($data);

$_ = $file;
s/[\x0-\x1f]/ /g;

print "$_\n";

is(%{$rpc->{objects}}+0, 3);

$a = $rpc->unpack;

is_deeply($a, $data);

$dx2 = $a->{"f"}->[2][0];
is($dx2, $a->{"f"}->[4]->{"data_x"});
is($dx2->[2], $obj1);
is($a->{"f"}->[4]->{"obj2"}, $obj2);
is(ref $dx2->[6], "utils::boolean");



=pod

$rpc = rpc->new("perl");

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

=cut