
# в sqlite нет 
$model::CHANGE_COLUMN_LEVEL_TABLE = 1;

# запускается после коннекта
sub handle_connect {
	$dbh->do('PRAGMA encoding = "UTF-8"');
}

sub handle_drop_tables { map { "drop table ".escape($_) } @_ }

# возвращает информацию об индексах
sub get_info_index {
	my $sql = "SELECT name FROM sqlite_master WHERE type='index'";
	return [grep { !/^sqlite_autoindex_.+_\d+$/ } @{$dbh->selectcol_arrayref($sql)}];
}

# возвращает информацию о таблицах
sub get_info {
	# tbl_name, rootpage,
	my $info1;
	my $sql = "SELECT name, sql FROM sqlite_master WHERE type='table'";
	my $tables = $dbh->selectall_arrayref($sql);
	for my $row (@$tables) {
		my ($table, $create_table) = @$row;
		next if $table eq "sqlite_sequence";
		$sql = "PRAGMA table_info($table)";
		my $rows = $dbh->selectall_arrayref($sql);
		for my $row (@$rows) {
			my ($number, $column_name, $type, $is_null, $default, $primary_key) = @$row;

			$info1->{$table}->{$column_name} = model::column->new({
				table => $table,		# имя таблицы
				name => $column_name,		# имя столбца
				type => $type,		# может быть преобразован из serial и bigserial
				null => $is_null || $primary_key? 1: undef,
				default => $default,
				primary_key => $primary_key? 1: undef,
				option => undef,
				ref => undef,
			});
		}
	}
	return $info1;
}


package model::column;

$primary_key = "primary key";

sub handle_type_serial {
	my ($self) = @_;
	$self->{type} = "integer";
	$self->{ref_type} = "integer";
	$self->{option} = "AUTOINCREMENT";
}

sub handle_type_bigserial {
	my ($self) = @_;
	$self->{type} = "int8";
	$self->{ref_type} = "int8";
	$self->{option} = "AUTOINCREMENT";
}


1;