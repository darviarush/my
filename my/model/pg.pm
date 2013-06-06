
# запускается после коннекта
sub handle_connect {
	$dbh->do("SET NAMES 'utf8'");
}

# возвращает информацию об индексах
sub get_info_index {
	my $sql = "SELECT c.relname
FROM pg_catalog.pg_class AS c 
    LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'i' AND (c.relname like '%_idx' or c.relname like '%_unq') AND n.nspname NOT IN ('pg_catalog', 'pg_toast')
";
	return $dbh->selectcol_arrayref($sql);
}

# возвращает информацию о таблицах
sub get_info {
	my $sql = "select table_name, column_name, data_type, column_default, is_nullable, character_maximum_length 
		from information_schema.columns
		where table_schema='public'";
	my $rows = $dbh->selectall_arrayref($sql);
	my $info1;
	
	for my $info (@$rows) {	# создаём info
		my ($table_name, $column_name, $data_type, $column_default, $is_nullable, $character_maximum_length) = @$info;
		
		$data_type = "serial", $column_default = undef if $column_default eq "nextval('${table}_id_seq'::regclass)" and $data_type eq "integer";
		$data_type .= "($character_maximum_length)" if $character_maximum_length;
		
		$column_default =~ s/::text$//;
		$column_default =~ s/^\('now'::text\)::date$/current_date/;
		
		$info1->{$table_name}->{$column_name} = model::column->new({
			table => undef,		# имя таблицы
			name => undef,		# имя столбца
			type => $data_type,		# может быть преобразован из serial и bigserial
			null => $is_nullable eq "YES"? 1: undef,
			default => $column_default,
			primary_key => undef,
			option => undef,
			ref => undef,
		});
	}
	return $info1;
}


package model::column;

sub handle_type_serial {
	my ($self) = @_;
	$self->{ref_type} = "int";
}

sub handle_type_bigserial {
	my ($self) = @_;
	$self->{ref_type} = "bigint";
}

# корректирует тип
sub correct_type {
	my ($self) = @_;
	local ($_) = $self->{type};
	s/^(int|int4)\b/integer/;	
	s/^char\b/character/;
	s/^varchar\b/character varying/;
	return $_;
}
