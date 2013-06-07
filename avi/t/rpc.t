use Test::More tests => 15;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "rpc";


$rpc = rpc->new("php");



