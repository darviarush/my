package model::table;

use utils;

sub new {
	my ($cls, $model, $table, $column) = @_;
	bless {
		model => $model,
		name => $table,
		column => $column
	}, $cls;
}

# используется, когда база не поддерживает alter column
sub alter_table {
	my ($self, $tmp) = @_;
	$tmp->{name} = "$self->{table}_TMP_6754";
	my %u = utils::set($self->column_names);
	my $col = join ", ", map { model::escape($_) } grep { exists $u{$_} } $tmp->column_names;
	return (
		$self->rename($tmp->{table}),
		$self->create,
		"insert into ".$self->name." ($col) select $col from ".$tmp->name,
		$tmp->drop
	);
}

# возвращает изменённое имя таблицы
sub name { @_ = $_[0]->{name}; goto &model::escape }

# возвращает имена столбцов через запятую
sub column_names { map { $_->{name} } values %{$_[0]->{column}} }

# возвращает sql-код для создания таблицы
sub create {
	my ($self) = @_;
	my @col = map { $_->name." ".$_->sql } sort { $b->{primary_key} <=> $a->{primary_key} or $a->{name} cmp $b->{name} } values %{"$self->{model}::COLUMN"};
	$sql = "create table ".$self->name." (\n".join(",\n", @col)."\n)";
	return $sql;
}

# возвращает sql-код для удаления таблицы
sub drop { "drop table ".$_[0]->name }

# возвращает sql-код для переименования таблицы в базе
sub rename {
	my ($self, $new) = @_;
	"alter table ".$self->name." rename to ".model::escape($new);
}


package model::column;

use widget;
use utils;

sub new {
	my ($cls, $param) = @_;
	my $self = bless {
		model => undef,		# класс таблицы
		key => undef,		# имя переменной класса
		table => undef,		# ссылка на таблицу
		name => undef,		# имя столбца
		validator => [],	# список валидаторов
		widget => undef,	# виджет
		type => undef,		# может быть преобразован из serial и bigserial
		ref_type => undef,	# тип. Будет использоваться для ссылок на этот
		null => undef,		# 1 или undef
		default => undef,
		primary_key => undef,
		option => undef,
		ref => undef,		# после первого прохода - имя таблицы, при втором - указатель на column id этой таблицы
		on_update => 'cascade',
		on_delete => 'cascade',
		%$param
	}, $cls;
	
	unless(defined $self->{name}) {
		$self->{name} = $self->{key};
		$self->{name} .= "_id" if defined $self->{ref};
	}
	
	#$self->{table} = $self->{model} unless defined $self->{table};
	
	$self->{primary_key} = 1 if $self->{key} eq "id";
	$self->handle_type_serial if $self->{type} eq "serial";
	$self->handle_type_bigserial if $self->{type} eq "bigserial";
	
	widget::by_model_type($self);
	
	return $self;
}

sub load {
	my ($cls, $model, $key, $table, @param) = @_;
	
	my $self = { model => $model, key => $key, table => $table };
	my $i = 0;
	for my $param (@param) {
		if(ref \$param eq "GLOB") {
			my $type = $param;
			$type =~ s/^\*(\w+):://;
			my $module = $1;
			if($module eq $model) {	$self->{ref} = $type }
			elsif($module eq "widget") { $self->{widget} = $param }
			elsif($module eq "validator") {	push @{$self->{validator}}, $param }
			else { die "Не распознанный параметр `$param`" }
		}
		elsif(ref $param eq "model::column") { %$self = (%$self, %$param) }
		elsif($i == 0 && !ref $param) { $self->{type} = $param }
		elsif($i == 1 && !ref $param) { $self->{default} = $param }
		else { die "Не распознанный параметр `$param`" }
		$i++;
	}
	
	$self->{null} = 1 if $self->{default} eq "null";
	$self->{null} = undef, $self->{default} = undef if $self->{default} eq "not_null";
	
	$self = model::column->new($self);
	
	return $self;
}

# вызывается при втором проходе по столбцам. При первом - load
sub post {
	my ($self) = @_;
	if(defined $self->{ref}) {
		my $ref = $self->{ref};
		die "Ссылка на таблицу $ref без id из $self->{model}::$self->{key}" unless $self->{ref} = ${"${ref}::id"};
	}
	$self->{type} = $self->{ref}{ref_type} unless defined $self->{type};
}

# создаёт sql-код для столбца
sub sql {
	my ($self) = @_;
	my ($type, $default, $key) = ($self->{type}, $self->{default}, $self->{key});

	my $null = $self->{null};
	my $ref;
	if($self->{ref}) {
		my $ref_tab = $self->{ref}->{table}->name;
		$ref = " references $ref_tab(id) on update $self->{on_update} on delete $self->{on_delete}";
	}

	my $null = $self->{null}? "": " not null";
	$null = " primary key" if $self->{primary_key};
	
	$default = " default $default" if defined $default;
	my $option = $self->{option};
	$option = " $option" if $option;
	$sql = "$type$null$option$ref$default";
	return $sql;
}

# для вставки в код sql
sub table { @_ = $_[0]->{table}->{name}; goto &model::escape }
sub name { @_ = $_[0]->{name}; goto &model::escape }

sub correct_type { $_[0]->{type} }	# корректирует тип для сравнения с полученным из базы (некоторые базы имеют синонимы)


sub alter_add {
	my ($self) = @_;
	return "alter table ".$self->table." add column ".$self->name." ".$self->sql;
}

sub alter_type {
	my ($self) = @_;
	return "alter table ".$self->table." alter ".$self->name." type $self->{type}";
}

sub alter_default {
	my ($self) = @_;
	my $default = $self->{default};
	return "alter table ".$self->table." alter ".$self->name.(defined $default? " set default $default": " drop default");
}

sub alter_null {
	my ($self) = @_;
	return "alter table ".$self->table." alter ".$self->name.($self->{null}? " set not null": " drop not null");
}

sub alter_drop {
	my ($self) = @_;
	return "alter table ".$self->table." drop column ".$self->name;
}

sub alter_modify {
	my ($self) = @_;
	return "alter table ".$self->table." modify column ".$self->name." ".$self->sql;
}

sub alter_rename {
	my ($self) = @_;
	return "alter table ".$self->table." change column ".$self->name." ".$self->name." ".$self->sql;
}



package model;

use DBI;

use utils;
use ini;
use Data::Dumper;

# создаёт подключение к серверу БД
sub connect {
	my $ini = $_[1] // \%ini::DBI;

	die "Неверный DNS в ini::DBI::DNS" unless DBI->parse_dsn($ini->{DNS});
	
	$dbh = DBI->connect($ini->{DNS}, $ini->{user} // "", $ini->{password} // "",
		{RaiseError => 1, PrintError => 0, PrintWarn => 0, %{$ini->{options}}});
		
	$base = {%$ini, dbh => $dbh};
		
	model::reset($base);
	handle_connect();
	return model;
}

# завершает соединение
sub close {
	$dbh->disconnect;
	return model;
}

# переключается с базы на базу
sub reset {
	my ($base) = @_;
	die "Не указан драйвер базы данных в base::DNS" unless $base->{DNS} =~ /^dbi:(\w+)/;
	my $drv = lc $1;
	do "model";
	die $@ // $! if $@ // $!;
	do "model/$drv.pm";
	die $@ // $! if $@ // $!;
}

#%nocolumn = utils::set("ISA", "INDEX", "UNIQUE", "TABLE", "RENAME", "FILE");	# какие переменные пакета нельзя считать столбцами

# создаёт в указанном пакете метод столбца
sub create_domain_method {
	my ($model, $key, $ref) = @_;
	my $ret = $ref? "bless \$self, $ref": '$self';
	eval << "END";
sub ${model}::$key {
	my (\$self) = \@_;
	\$self->obj;
	if(\@_>1) {
		delete \$self->{dom};
		push \@{\$self->{set}}, '$key', \$_[1];
		return \$self;
	}
	\$self->{dom}->[0] .= \$self->{dom}->[0] ne ''? '::$key': $key;
	return $ret;
}
END
	die $@ if $@;

	eval << "END";
sub ${model}::rowset::$key {
	my (\$self, \$val) = \@_;
	if(\@_ > 1) {
		\$self->{set}->{'$key'} = \$val;
		return \$self;
	}
	return \$self->{set}->{'$key'};
}
END
	die $@ if $@;
}

# инициализирует (подключает) модель
sub init {
	my ($cls, @paths) = @_;
	local ($_, $`, $', $&, $1);
	
	@paths = @{$ini::DBI{model}} unless @paths;
	
	my (@col, $col);
	push @path, @paths;
	for my $path (@paths) {
		my $file = utils::read($path) or die "не могу открыть файл модели `$path`. $!";
		require $path;

		while($file =~ /^package\s+(\w+)/gm) {
			my $model = $1;
			push @model, $model;					# собираем названия
			@{"${model}::rowset::ISA"} = "model::rowset" unless @{"${model}::rowset::ISA"};		# наследуем rowset
			@{"${model}::ISA"} = "model::orm" unless @{"${model}::ISA"};		# наследуем orm
			${"${model}::FILE"} = $path;			# пометка - из какого файла модель
			${"${model}::id"} = "serial" unless exists ${"${model}::"}{"id"};
			
			my $table_name = ${"${model}::TABLE"};
			$table_name = $model unless defined $table_name;
			
			$table = ${"${model}::TABLE"} = model::table->new($model, $table_name);
			
			#$TABLE2MODEL{$table} = $model;				# отображение таблиц в модели
			
			while(my($key, $val) = each %{"${model}::"}) {	# формируем методы столбцов и заменяем значения на model::column
				next if $key =~ /^[A-Z_0-9]+$/;	# отбрасываем служебные столбцы
				my (@param) = (${"${model}::$key"} or (), @{"${model}::$key"});
				@{"${model}::$key"} = ();
				my $type = $param[0];
				next if not defined $type;	# пропускаем столбцы помеченные, как не существующие
				
				${"${model}::$key"} = ${"${model}::COLUMN"}{$key} = $col = model::column->load($model, $key, $table, @param);
				push @col, $col;
				
				# ссылка?
				if(ref \$type eq "GLOB") {
					$type =~ s/^.*:://;
					my $key_ref = $type eq $key? "${model}_ref": "${model}__${key}_ref";
					create_domain_method($type, $key_ref, $model);
					create_domain_method($model, $key, $type);
					$key .= "_id";
				}
				create_domain_method($model, $key);
			}
			
			$table->{column} = \%{"${model}::COLUMN"};
		}
	}

	$_->post(), ${"$_->{model}::COLUMN_BY_NAME"}{$_->{name}} = $_ for @col;
	
	return model;
}

# Константы для синхронизации
$CHANGE_COLUMN_LEVEL_TABLE = 0;
$CHANGE_COLUMN_LEVEL_COLUMN = 0;
$RETURNING = 1;						# позволяет добавлять RETURNING в INSET, UPDATE и DELETE


# возвращает sql-код для удаления таблиц
sub handle_drop_tables { "drop table ".join(", ", map { escape($_) } @_)." cascade" }

# синхронизирует модель
sub sync {
	model->sync_sql;
	$model::dbh->do($_) for @change;
	return model;
}

# выдаёт sql-код в @model::change для синхронизации
sub sync_sql {
	my $sql;
	my ($info) = get_info();
	my %table2model;
	my %indexes = map { ($_, 1) } @{get_info_index()};	# индексы в базе
	my %is_indexes = ();								# индексы в модели
	
	MODEL: for my $model (@model) {							# синхронизируем модели в пакетах
		my $table = ${"${model}::TABLE"};
		my $tab = $table->{name};
		if(my $column = $info->{$tab}) {				# таблица существует в БД
			$table2model{$tab} = $model;
			
			my @change_local = ();
			
			while(my ($key, $col) = each %{"${model}::COLUMN"}) {	# пробег по столбцам
				my $name = $col->{name};
				
				my $db_column = $column->{$name};
				
				unless($db_column) {		# нет столбца - создаём
					push @change_local, $col->alter_add;
					next;
				}
				
				my $change;
				if($col->correct_type ne $db_column->{type}) {				# type
					push(@change, $table->alter_table(model::table->new(undef, $tab, $column))), next MODEL if $CHANGE_COLUMN_LEVEL_TABLE;
					push(@change, $col->alter_modify), next if $CHANGE_COLUMN_LEVEL_COLUMN;
					push @change, $col->alter_type;
				}
				
				if($col->{default} ne $db_column->{default}) {		# default
					push(@change, $table->alter_table(model::table->new(undef, $tab, $column))), next MODEL if $CHANGE_COLUMN_LEVEL_TABLE;
					push(@change, $col->alter_modify), next if $CHANGE_COLUMN_LEVEL_COLUMN;
					push @change, $col->alter_default;
				}
				
				if($col->{null} ne $db_column->{null}) {
					push(@change, $table->alter_table(model::table->new(undef, $tab, $column))), next MODEL if $CHANGE_COLUMN_LEVEL_TABLE;
					push(@change, $col->alter_modify), next if $CHANGE_COLUMN_LEVEL_COLUMN;
					push @change, $col->alter_null;
				}
				
			}
			
			push @change, @change_local;
			
		} else {	# таблица не существует в БД - создаём
			push @change, $table->create($model);
		}
		
		# добавляем индексы
		for my $ind ("INDEX", "UNIQUE") {
			for my $index (${"${model}::$ind"} or (), @{"${model}::$ind"}) {
				my @col = ref $index? @$index: $index;
				my $name = join "_", map { my $i=$_; $i=~s/\W+/_/g; $i } @col;
				my ($unique, $postfix);
				if($ind eq "UNIQUE") {
					$unique = "unique ";
					$postfix = "unq";
				} else {
					$unique = "";
					$postfix = "idx";
				}
				
				$name = "${tab}_${name}_$postfix";
				$is_indexes{$name} = 1;
				next if exists $indexes{$name};
				my $col = join ", ", map { my $i=$_; s/^\w+$/"$&"/; $i } @col;
				$sql = "create ${unique}index $name on ".$table->name." ($col)";
				push @change, $sql;
			}
		}
	}
	
	# таблицы не существующие в модели, но они есть в БД
	my @delete;
	for(keys %$info) {
		push(@delete, $_), delete $info->{$_} unless exists $table2model{$_};
	}

	push @change, handle_drop_tables(@delete) if @delete;
	
	# удаляем индексы не существующие в модели
	#%indexes = map { ($_, 1) } @{get_info_index()};
	
	for my $index (keys %indexes)  {
		next if exists $is_indexes{$index};
		push @change, "drop index $index";
	}
	
	# удаляем столбцы не существующие в модели
	#my ($info) = get_info();
	
	while(my ($tab, $column) = each %$info) {
		my $model = $table2model{$tab};
		my $COLUMN = \%{"${model}::COLUMN_BY_NAME"};
		
		while(my ($name, $col) = each %$column) {
			next if exists $COLUMN->{$name}; # если столбик существует в модели - ничего не делаем
			push @change, $col->alter_drop;
		}
	}
	
	return model;
}

# формирует запрос
sub select {
	my ($self, $ref) = @_;
	$self->obj;
	my $table = ${ref($self)."::TABLE"}->{name};
	push @{$ref->{"<>"}}, ["", $table];
	#push @{$ref->{"<->"}}, $self;
	my $set = join ", ", map {escape($_->[0])." = ".quote($_->[1], $ref)} build_alias($self->{set});
	my $values = model::values($self, $ref);
	my $from = "from $table";
	my $where = model::where($self, $ref);
	my $group = join ", ", map { quote($_, $ref) } @{$self->{group}}; $group = "group by $group" if $group;
	my $having = model::where($self, $ref, 1);
	my $order = join ", ", map { quote($_, $ref) } @{$self->{order}}; $order = "order by $order" if $order;
	my $offset = $self->{offset}? "offset $self->{offset}": "";
	my $limit = $self->{limit}? "limit $self->{limit}": "";
	my $join = pop @{$ref->{"<>"}};
	#pop @{$ref->{"<->"}};
	return ($values, $set, $from, $join->[0], $where, $group, $having, $order, $offset, $limit);
}

# создаёт join-ы
sub from_join {
	my ($join, $ref) = @_;
	
	my $r = $ref->{"<>"}; # <> - from
	$r = $r->[$#$r];
	my $main_tab = $r->[1];
	
	return "$main_tab.$join->[0]" if @$join <= 1;	# должно быть несколько, чтобы сформировать join-ы
	
	# инициализируем счётчик, если он пуст
	$ref->{"#"} = "A" unless defined $ref->{"#"};
	
	# находим в $ref начальную часть пути
	my ($cash, $i);
	for($i = $#$join; $i>0; $i--) {
		$i++, last if $cash = $ref->{join "::", $main_tab, @{$join}[0..$i]};
	}

	# заполняем кэш в начальное состояние, если ничего не найдено
	$cash = [$main_tab, $main_tab] unless $cash;
	
	# создаём join-ны для ненайденной части
	my $U = $cash->[1];
	for(; $i < $#$join; $i++) {
		my $key = $join->[$i];
		my $model;
		my $j;
		$U = $ref->{"#"}++;								# # - счётчик U
		if($key =~ /_ref$/) {	# обратная ссылка
			local ($`, $', $1);
			$key =~ /(?:__(\w+))?_ref$/;
			my ($tab, $fld) = ($`, $1 // ($i==0? $main_tab: $join->[$i-1]));
			get_ref($tab, $fld);	# проверка, что такое поле есть
			$model = $tab;
			$key = $fld;
			$j = "inner join ".escape($model)." $U on $cash->[1].id=$U.${key}_id\n";
		} else {				# прямая ссылка
			$model = get_ref($cash->[0], $key);
			$j = "inner join ".escape($model)." $U on $cash->[1].${key}_id=$U.id\n";
		}
		$r->[0] .= $j;
		$ref->{join "::", $main_tab, @{$join}[0..$i]} = $cash = [$model, $U];
	}
	
	return "$U.$join->[$#$join]";	# возвращает таблицу из которой берётся столбец (для select, where, having)
}

# эскейпит, и заодно создаёт join-ны
sub escape_dom {
	my ($val, $ref) = @_;
	$val = [split "::", $val];
	from_join($val, $ref);
}

# формирует where
%OP = qw(eq = ne <> lt < le <= gt > ge >= in in like like ilike ilike between between);
sub where {
	my ($self, $ref, $having) = @_;
	local $_;
	my $sql = "";
	my @filter;
	my $op;
	my ($filter, $i) = ($self->{$having? "having": "filter"}, 0);

	for(;;) {		# для скобок [] -> ()

		for(; $i<@$filter; $i+=2) {
			my $a = $filter->[$i];
			my $b = $filter->[$i+1];
			if($a eq "OR") {
				$sql .= " OR ";
				$i--;
				next;
			}

			if(ref $a eq "ARRAY") {	# скобки
				push @filter, [$filter, $i];
				$filter = $a;
				$i = 0;
				$sql .= "(";
				next;
			}

			if(ref $a eq "model::functor") {
				$a = functor2sql($a, $ref);
				$op = "=";
			}
			else {
				my @join = split /::/, $a;	# join-ы
				$op = $OP{$join[$#join]};	# операторы
				if($op) { pop(@join); } else { $op = '=' }

				# формируем join-ны
				$a = from_join(\@join, $ref);
			}
			
			# аргументы функции или in
			if(ref $b eq "ARRAY") {
				$b = join ", ", map { quote($_, $ref) } @$b;
			} else {
				$b = quote($b, $ref);
			}

			$op = $op eq "="? "is": "is not" if not defined $b;

			$sql .= "$a $op $b";
			last unless $i+2<@$filter;
			$sql .= " AND ";
		}

		($filter, $i) = @{pop @filter};
		last unless defined $filter;
		$sql .= ")";
	}
	return $sql? ($having? "having": "where")." $sql": "";
}

# формирует values
sub values {
	my ($self, $ref) = @_;
	local $_;
	my $dom = $self->{dom};
	my $as = $self->{as};
	return "" unless @$dom | @$as;
	my $x = join ", ", map({ escape_dom($_, $ref) } @$dom), map {quote($_->[0], $ref)." as ".escape($_->[1])} build_alias($as);
	return $x;
}

# формирует as и set
sub build_alias {
	my ($as) = @_;
	my ($i, $val);
	map { if($i++ % 2 == 0) { $val = $_; () } else { [$val, $_] } } @$as;
}

# возвращает имена столбцов
sub names {
	my ($self, $ref) = @_;
	local $_;
	my $i = 0;
	join ", ", (map { my @A = split "::", $_; escape($A[$#A]) } @{$self->{dom}},
		map { $i++ % 2==0? escape_dom($_, $ref): () } @{$self->{as}});
}

# оборачивает в '' значение, или вызывает select
sub quote {
	my ($val, $ref) = @_;
	ref $val eq "SCALAR"? escape_dom($$val, $ref):
	ref $val eq "ARRAY"? "(".join(", ", map { quote($_, $ref) } @$val).")":
	ref $val && $val->isa("model::orm")? (%$val == 2 && @{$val->{dom}}==1? escape_dom($val->{dom}->[0], $ref): "(".$val->sql.")"):
	ref $val && $val->isa("model::functor")? functor2sql($val, $ref):
	$val=~/^-?\d+(?:\.\d+)?\z/? $val:
	$dbh->quote($val);
}

# оборачивает в "" название таблицы или столбца, если нужно
%ESCAPE = utils::set(qw/select update insert set from where and or not user/);
sub escape {
	my ($val) = @_;
	return $val if $val =~ /^[a-z_]\w*\z/i and not exists $ESCAPE{lc $val};
	local ($`, $', $&);
	$val =~ s/[\\"]/\\$&/g;
	return "\"$val\"";
}

# разыменовывает ссылку на таблицу (класс)
sub get_ref {
	my ($self, $key) = @_;
	my $model = ref($self) || $self;
	my $ref = ${"${tab}::$key"};
	die "Поле $tab.$key не является ссылкой `$ref`" unless $ref->{model};
	$ref = $ref->{model};
	return wantarray? ($ref, escape("${ref}_id")): $ref;
}

# если ссылка - добавляет _id
sub if_ref {
	my ($self, $key) = @_;
	my $ref = ${(ref($self) || $self)."::$key"};
	return escape($ref.(ref \$ref eq "GLOB"? "_id": ""));
}

# проверяет - является ли объект наследником model::orm (запросом)
sub is_orm {
	ref($_[0]) !~ /^(?:ARRAY|GLOB|HASH|CODE|SCALAR|)\z/ and $_[0]->isa("model::orm")
}

# вызывает соответствующую функцию dbh для запросов update, insert с returning и без
sub do {
	my ($self, $sql) = @_;
	my $size = @{$self->{dom}} + @{$self->{as}} / 2;
	my $many_set = ref $self->{set}->[0] eq "ARRAY";
	
	print STDERR $sql;
	
	unless($RETURNING) {
		my $count = $dbh->do($sql);
		return $count unless $size;
		
		my $model = ref $self;
		$model->obj;
		$model->{dom} = $self->{dom};
		$model->{as} = $self->{as};
		$sql = $model->sql;
		$sql .= " where rowid=last_insert_rowid()";
		print STDERR $sql;
	}
	else { return $dbh->do($sql) unless $size }
	
	return $dbh->selectall_arrayref($sql) if $size > 1 and $many_set;
	return $dbh->selectcol_arrayref($sql) if $size == 1 and $many_set;
	return $dbh->selectrow_array($sql);
}

#	if(ref $val eq "ARRAY") {
#		my $ref;
#		($ref, $key) = model::get_ref($self, $key);
#		$val = $ref->insert(@{$val});
#	}

package model::orm;

# превращает класс в объект
sub obj {
	my ($cls) = @_;
	$_[0] = bless {}, $cls unless ref $cls;
	$_[0]
}

# регистрирует столбцы в select
sub dom {
	my ($self, @param) = @_;
	$self->obj->{dom} = [@param];
	return $self;
}

# регистрирует столбцы с алиасами (as)
sub as {
	my ($self, @param) = @_;
	$self->obj->{as} = [@param];
	return $self;
}

# множество значений
sub set {
	my ($self, @param) = @_;
	$self->obj->{set} = {@param};
	return $self;
}

# возвращает значение из set
sub get {
	my ($self, $param) = @_;
	return $self->{set}{$param};
}

# where
sub filter {
	my ($self, @param) = @_;
	$self->obj->{filter} = [@param];
	return $self;
}

# группировка
sub group {
	my ($self, @param) = @_;
	$self->obj->{group} = [@param];
	return $self;
}

# having
sub having {
	my ($self, @param) = @_;
	$self->obj->{having} = [@param];
	return $self;
}

# сортировка - desc ставиться при "\"
sub order {
	my ($self, @param) = @_;
	$self->obj->{order} = [@param];
	return $self;
}

# offset
sub offset {
	my ($self, $offset) = @_;
	$self->obj->{offset} = $offset;
}

# limit
sub limit {
	my ($self, $limit) = @_;
	$self->obj->{limit} = $limit;
}

# объединяет запросы через union all. Если перед запросом стоит 0 - то через union
sub union {
	my ($self, @union) = @_;
	push @{$self->{union}}, @union;
	return $self;
}

# возвращает sth
sub sth {
	my ($self, $view) = @_;
	my $sql = !defined $view? $self->sql: $self->$view;
	return $model::dbh->prepare($sql);
}

# возвращает rowset для этой модели. Если 
sub rowset {
	my ($self) = @_;
	$self->obj;
	${ref($self)."::rowset"}->new(@_);
}

# возвращает 1-ю строку или первое значение, устанавливает limit 1, даже если лимит уже установлен
#	$self->$view - для usql, isql и esql
sub row {
	my ($self, $view) = @_;
	$self->{limit} = 1;
	my $sql = !defined $view? $self->sql: $self->$view;
	return $model::dbh->selectrow_array($sql);
}

# возвращает первый столбец
sub col {
	my ($self, $view) = @_;
	my $sql = !defined $view? $self->sql: $self->$view;
	my $rows = $model::dbh->selectcol_arrayref($sql);
	return $rows;
}

# возвращает все строки
sub all {
	my ($self, $view, $slice) = @_;
	my $sql = !defined $view? $self->sql: $self->$view;
	my $rows = $model::dbh->selectall_arrayref($sql, $slice);
	return $rows;
}

# insert - значения в виде матрицы или запрос, или таблица
sub insert {
	my ($self, @param) = @_;
	$self->obj;
	push @{$self->{set}}, @param;
	return model::do($self, $self->isql);
}

# update - поле-значение, значением может быть запрос
sub update {
	my ($self, @param) = @_;
	$self->obj;
	push @{$self->{set}}, @param;
	return model::do($self, $self->usql);
}

# delete - удаляет строки
sub erase {
	my ($self) = @_;
	$self->obj;
	return model::do($self, $self->esql);
}

# insert или update, если есть
sub store {
	my ($self, @param) = @_;
	$self->obj;
	push @{$self->{set}}, @param;
	

	my $set = $self->{set};
	
	
	
	
	return model::do($self, $self->esql);
}

# возвращает запрос select
sub sql {
	my ($self, $ref) = @_;
	my @any = model::select(@_);
	$any[0] = "*" if $any[0] eq "";
	my $sql = join " ", "select", grep {$_ ne ""} @any;
	my $union = " union all ";
	$sql = join "", $sql, map { $_ eq "0"? do { $union = " union "; () }: do { my $s = $union.$_->sql($ref); $union = " union all "; $s } } @{$self->{union}};
	return $sql;
}

# возвращает запрос insert
sub isql {
	my ($self) = @_;
	my $sql;
	my $set = $self->{set};
	my $table = ${ref($self)."::TABLE"}->name;
	
	if(!@$set) { $sql = "insert into $table default values" }
	elsif(ref($set->[0]) eq "ARRAY") {	# множественный инсёрт (...), (...) ...	tab->insert([[cols], [values1], [values2], ...])
		my $cols = shift @$set;
		my $val = join ",\n", map { "(".join(", ", map { model::quote($_) } @$_).")" } @$set;
		$sql = "insert into $table (".join(", ", map { model::escape($_) } @$cols).") values $val";
		unshift @$set, $cols;
	}
	elsif(@$set == 1 and model::is_orm($set->[0])) {
		my $q = $set->[0];
		my $values = model::names($q);
		$sql = "insert into $table ($values) ".$q->sql;
	}
	else {	
		my ($col, $let);
		for(my $i=0; $i<@$set; $i+=2) {			
			$col .= model::escape($set->[$i]);
			$let .= model::quote($set->[$i+1]);
			last if $i+2 >= @$set;
			$col .= ", ";
			$let .= ", ";
		}
	
		$sql = "insert into $table ($col) values ($let)";
	}	
	
	my $values = model::values($self);
	$sql .= " returning $values" if $model::RETURNING and $values ne "";
	return $sql;
}

# возвращает запрос update
sub usql {
	my ($values, $set, @any) = model::select(@_);
	push @any, "returning $values" if $model::RETURNING and $values ne "";
	my $sql = join " ", "update", ${ref($self)."::TABLE"}->name, "set", $set, grep {$_ ne ""} @any;
	return $sql;
}

# возвращает запрос delete
sub esql {
	my ($values, @any) = model::select(@_);
	push @any, "returning $values" if $model::RETURNING and $values ne "";
	my $sql = join " ", "delete", grep {$_ ne ""} @any;
	return $sql;
}

# управляет join-ами полей. Можно установить right, left или outer join
# sub join {}

package model::rowset;

# создаёт экземпляр, вызывается с указанием класса
#	dom - содержит домены для наборов - {dom1=>0, dom2=>1...}
#	col - домены последовательно []
#	rowset - [[val1, val2...], [val21, val22...]...]
#	pos - позиция текущией строки в наборе
#	safe - если установлен, то будет сохранять все запрошенные из базы данные в rowset
#	

sub new {
	my ($cls, $model, $safe) = @_;
	bless {
		model => $model,
		safe => $safe,
		col => [],
		dom => {},
		rowset => [$set],
		pos => 0,
		sth => undef,
		error => undef
	}, $cls;
}

# переходит или считывает следующий
#	Если закончено считывание выдаёт undef и остаётся на последнем
#	Если просто перешёл - 2
#	Если считал - 1
sub next {
	my ($self) = @_;
	my $rowset = $self->{rowset};
	$self->{pos}++, return 2 if $#$rowset != $self->{pos};
	
	my $sth = $self->{sth};
	return unless $sth;
	
	my $set = $sth->fetch_hashref;
	$sth->finish, $self->{sth} = undef, return unless $set;
	@$rowset = () unless $self->{safe};
	push @$rowset, $self->{set} = $set;
	$self->{pos} = $#$rowset;
	return 1;
}

# устанавливает данные из ассоциативного массива, причём только те, которые есть в таблице
#	Без параметров устанавливает параметры из request
#	Параметры:
#		name => val
#		name => [val1...], ...
#		{name => val}
#		[{name => val, ...}, ...]
#		[[name, ...], [val ...], ...]
#
#		в cols[]
sub set {
	my ($self, @param) = @_;
	
	$self->{pos} = 0;
	
	@param = %$request::param unless @param;
	
	if(ref $param[0] eq "HASH") {
		$self->{set} = $param[0];
		$self->{rowset} = [$param[0]];
	}
	elsif(ref $param eq "ARRAY") {
		
	}
	else {
		
	}
	return $self;
}

# валидирует роусеты
#	оставляет сообщения об ошибке в $self->{error}{$field} = [...]
#	сообщения касающиеся таблицы в $self->{error}{0}
sub validate {
	my ($self) = @_;
	
	my $rowset = $self->{rowset};
	for my $set (@$rowset) {
		while(my ($k, $v) = each %$set) {
			for my $validator (@{${ref($self->{model})."::$k"}->{validator}}) {
				$validator->($v);
				push @{$self->{error}{$k}}, $@ if $@;
			}
		}
	}
	
	return 1;
}

# сохраняет данные из роусетов. Если есть id, то происходит update, если нет - insert, иначе - происходит insert
sub store {
	my ($self) = @_;
	$self->obj;

	my %arg = @{$self->{set}};
	unless(exists $arg{"id"}) {
		$self->{dom} = "id";
		$arg{id} = $self->insert;
	}
	push @{$self->{where}}, "id", $arg{id};
	delete $arg{id};
	$self->{set} = %arg;
	return $self->update;
}

# загружает ровсеты по id
#	без параметров - всю таблицу
sub load {
	my ($self, @id) = @_;
	$self->clear;
	@{$self->{rowset}} = $self->{set} = $model::dbh->selectrow_hashref($self->sql), return $self if @id == 1;
	$self->{where} = ["id", @id == 1? $id: \@id];
	$self->{rowset} = $model::dbh->prepare($self->sql);
	return $self;
}

# очищает набор
sub clear {
	my ($self) = @_;
	my $sth = $self->{sth};
	$self->{sth} = undef, $sth->finish if $sth;
	my $set = $self->{set} = {};
	$self->{rowset} = [$set];
	$self->{error} = undef;
	return $self;
}

# устанавливает из реквеста, валидирует и сохраняет. Если были ошибки - возвращает undef
sub save {
	my ($self) = @_;
	$self->store, return 1 if $self->set->validate;
}


# возвращает rowset с указанными записями
sub get {
	my ($self, @idx) = @_;
	
	return ;
}

# используется для всктавки в sql произвольного текста
package model::raw;

# конструктор
sub new {
	my ($cls, $val) = @_;
	bless \$val, $cls;
}

package model::functor;

# возвращает функтор
sub model::functor {
	#print STDERR "echo -------------->model::functor--";
	bless [map { ref $_ eq "model::functor"? @$_: $_ } @_], model::functor;
}


BEGIN {
	$nigma = sub {
		my ($operator, $self, $operand, $swap) = @_;

		print STDERR "nigma $operator ->".@$self." swap=$swap";
		
		if(ref $operand eq "model::functor") {
			if($swap) {	push @$self, $operator, @$operand } else { unshift @$self, @$operand, $operator }
		else {
			if($swap) {	push @$self, $operator, $operand } else { unshift @$self, $operand, $operator }
		}
		
		return $self;
	}
}

use overload (
	"." => sub { my ($self, $x) = @_; my $op = model::functor(); $op->{const} = $x; $op },
	"x" => sub { unshift @_, "||"; goto &$nigma; },
	"+" => sub { unshift @_, "+"; goto &$nigma; },
	"-" => sub { unshift @_, "-"; goto &$nigma; },
	"neg" => sub { unshift @_, "neg"; goto &$nigma; },
	"*" => sub { unshift @_, "*"; goto &$nigma; },
	"/" => sub { unshift @_, "/"; goto &$nigma; },
	"|" => sub { unshift @_, "or"; goto &$nigma; },
	"&" => sub { unshift @_, "and"; goto &$nigma; },
	"!" => sub { unshift @_, "not"; goto &$nigma; },
	".." => sub { unshift @_, "in"; goto &$nigma; },
	"==" => sub { unshift @_, "="; goto &$nigma; },
	"!=" => sub { unshift @_, "<>"; goto &$nigma; },
	"<" => sub { unshift @_, "<"; goto &$nigma; },
	">" => sub { unshift @_, ">"; goto &$nigma; },
	"<=" => sub { unshift @_, "<="; goto &$nigma; },
	">=" => sub { unshift @_, ">="; goto &$nigma; },
	'""' => sub { "mx=`$_[1]`  model::functor(".@{$_[0]}.")" },
);

# для вставки функций в sql
sub AUTOLOAD {
	print STDERR "echo $AUTOLOAD\n";
	local ($&, $`, $');
	$AUTOLOAD =~ /[^:]+$/;
	return model::functor(model::raw->new("$&("), @_, model::raw->new(")"));
}

sub DESTROY {}

1;