use Test::More tests => 18;

use Carp 'verbose';
$SIG{ __DIE__ } = *Carp::confess;

use Data::Dumper;

require_ok('model');

$\ = "\n";

model->connect->init->sync;

isa_ok($model::dbh, "DBI::db");

$model::dbh->do("BEGIN");
$SIG{__DIE__} = sub { $model::dbh->do("ROLLBACK"); };

$language_id = language->insert(id=>"BK", name=>"x1");
is($language_id, "BK");

$name_id = name->insert();
ok($name_id);

$namen_id = namen->insert(language=>[id=>"IX", name=>"x3"], name=>[], iname=>"Ок2");
ok($namen_id);

$namen_id = namen->insert(language_id=>$language_id, name_id=>$name_id, iname=>"Ок");
ok($namen_id);

$sql = namen->filter(id=>$namen_id)->domain(qw/language_id name_id iname/);
$namen_id = namen->insert($sql);
ok($namen_id, 'namen_id last');

$row = language->domain(id, name)->insert([['PK', 'r1'], ['BB', 'r2']]);
is_deeply($row, ['PK', 'BB']);

$rows = $sql->all;
is_deeply($rows, [['BK', $rows->[0][1], "Ок"]]);

# тестируем model::from_join
$ref = {"<>" => [["", "city"]]};
$res = model::from_join([qw/name namen_ref language name/], $ref);
is($res, "C.name");

is_deeply($ref, {
	'#' => "D",
	'<>' => [['inner join name A on city.name_id=A.id
inner join namen B on A.id=B.name_id
inner join language C on B.language_id=C.id
', 'city']],
	'city::name' => ['name', 'A'],
	'city::name::namen_ref' => ['namen', 'B'],
	'city::name::namen_ref::language' => ['language', 'C']
});

# Подготавливаем выборку из 2-х
$city_id = city->insert(name_id=>$name_id);

$city = city->filter(name::namen_ref::language::name => 'x1');
ok($city->can("id"));

$city_id = $city->id->row;
ok($city_id);
is(ref $city_id, "");

$col = $city->domain()->name->namen_ref->language->id->col;
is_deeply($col, ['BK']);

$q = city->filter(name::namen_ref::language::name => 'x1')->domain("name::namen_ref::language::*", "name::namen_ref::*", "name::*", "*");
$all = $q->all;
is(scalar @$all, 2);
is(scalar @{$all->[0]}, 9);
is(scalar @{$all->[1]}, 9);

$f = model::functor();

$sql = model::functor2sql( $f->str() == str.$f );
is($sql, "str = 'str'");

$ids = namen->filter($f->lower(namen->iname) == $f->lower('Ок'.$f x 1))->name->id;
print STDERR $ids->sql;
is_deeply($ids->col, ['BK']);





$model::dbh->do("ROLLBACK");
model->close;