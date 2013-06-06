# заглушка
package rpc;

use utils;

%prog = ();



# конструктор. Создаёт соединение, если его нет
sub new {
	my ($cls, $prog) = @_;
	
	open my($pipe), $prog{$prog} // $prog or die "Ошибка создания канала. $!";
	binmode $pipe;
	
	bless {pipe => $pipe, prog => $prog, objects => []}, $cls;
}

# квотирует для передачи
sub json_quote {
	my ($self, $val) = @_;
	if(ref $val eq "rpc::stub") {
		$val = { "\x0stub\x0" => 1, num => $val->{num} };
	} elsif(ref $val) {
		my $objects = $self->{objects};
		push @$objects, $val;
		$val = { "\x0bless\x0" => ref $val, num => $#$objects };
	}
	
	utils::json_quote($val);
}

# превращает в json и сразу отправляет. Объекты складирует в $self->{objects}
sub pack {
	my ($self, $data) = @_;

	my $pipe = $self->{pipe};
	my $sk = 1;
	
	walk_data($data, sub {
		my ($ref, $key) = @_;
		if($sk == 1) {$sk = 0} else { print $pipe "," }
		print $pipe $self->json_quote($key), ":" if defined $key;
		print $pipe $self->json_quote($$ref);
	}, sub {
		my ($ref, $key, $class) = @_;
		print $pipe "," if $sk;
		$sk = 1;
		print $pipe $self->json_quote($key), ":";
		print $pipe $class == 0? "[": "{";
	}, sub {
		my ($ref, $key, $class) = @_;
		print $pipe $class == 0? "]": "}";
	});
	
	print $pipe "\n";
}

# вызывает функцию
sub call {
	my ($self, $name, @args) = @_;
	local ($,, $\) = ();
	print $self->{pipe} $name, "\n";
	$self->pack(\@args);
	$self->ret(@_);
}

# вызывает метод
sub apply {
	my ($self, $class, $name, @args) = @_;
	local ($,, $\) = ();
	print $self->{pipe} "$class $name\n";
	$self->pack(\@args);
	$self->ret(@_);
}

# выполняет код
sub eval {
	my ($self, $eval) = @_;
	print $self->{pipe} "eval\n", pack("L", length $eval), $eval;
	$self->ret(@_);
}

# получает и возвращает данные и устанавливает ссылочные параметры
sub ret {
	my ($self) = @_;
	my $pipe = $self->{pipe};
	my $ret = <$pipe>;
	
	while($ret ne "ok\n") {	# клиент послал запрос
		chop $ret;
		my ($cmd, $arg1, $arg2) = split / /, $ret;
		if($cmd eq "stub") {
			my $args = from_json(scalar <$pipe>);
			$self->{objects}->[$arg1]->$arg2(@$args);
			
		}
		elsif($cmd eq "apply") {
			
		}
		elsif($cmd eq "call") {
			
		}
		elsif($cmd eq "eval") {
			
		}
		else {
			die "Неизвестная команда `$cmd`";
		}
	}

	$ret = <$pipe>;
	$ret = from_json($ret);
	utils::walk_data(sub {	# восстанавливаем заглушки
		my ($ref, $key) = @_;
		my $scalar = $$ref;
		return if ref $scalar ne "HASH";
		$$ref = $self->{objects}->[$scalar->{num}] if exists $scalar->{"\x0bless\x0"};
		$$ref = $self->stub($scalar->{num}) if exists $scalar->{"\x0stub\x0"};
	});
	my $return = $ret->{0};
	delete $ret->{0};
	while(my ($key, $val) = each %$ret) {
		$_[$key] = $val;
	}
	return $return;
}

# создаёт заглушку, для удалённого объекта
sub stub {
	my ($self, $num) = @_;
	bless {rpc => $self, num => $num}, "rpc::stub";
}


# заглушка
package rpc::stub;

sub AUTOLOAD {
	my ($self, @param) = @_;
	local ($&, $`, $');
	$AUTOLOAD =~ /\w+$/;
	my $name = $&;

	my $rpc = $self->{rpc};
	my $pipe = $rpc->{pipe};
	my $num = $self->{num};
	
	print $pipe "stub $num $name\n";
	$rpc->pack(\@param);
	$rpc->ret(@_);
}
