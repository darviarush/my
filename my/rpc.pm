# заглушка
package rpc;

use IPC::Open2;
use Data::Dumper;

use utils;


%prog = (
"perl" => "perl -Mrpc -e 'rpc->client'",
"php" => "php -r 'require_once \"rpc.php\"; rpc->client()'",
"python" => "",
"ruby" => ""
);



# конструктор. Создаёт соединение
sub new {
	my ($cls, $prog) = @_;
	
	open2 my($reader), my($writer), $prog{$prog} // $prog or die "Ошибка создания канала. $!";
	binmode $reader;
	binmode $writer;
	
	bless {r => $reader, w => $writer, prog => $prog, objects => [], bless => "\0bless\0", stub => "\0stub\0", role => "SERVER"}, $cls;
}

# закрывает соединение
sub close {
	my ($self) = @_;
	local ($,, $\) = ();
	my $w = $self->{w};
	print $w "ok\nnull\n";
	close $w, $self->{r};
}

# создаёт клиента
sub client {
	my ($cls) = @_;
	open my $r, "<&STDIN" or die "NOT DUP STDIN: $!";
	open my $w, ">&STDOUT" or die "NOT DUP STDOUT: $!";
	my $self = bless {r => $r, w => $w, objects => [], bless => "\0stub\0", stub => "\0bless\0", role => "CLIENT"}, $cls;
	select $r; $| = 1;
	select $w; $| = 1;
	open STDIN, "/dev/null";
	open STDOUT, "< /dev/null";
	$self->ret;
}

# квотирует для передачи
sub json_quote {
	my ($self, $val) = @_;
	if(ref $val eq "rpc::stub") {
		$val = "{".utils::json_quote($self->{stub}).":$val->{num}}";
	} elsif(ref $val) {
		my $objects = $self->{objects};
		push @$objects, $val;
		$val = "{".utils::json_quote($self->{bless}).":$#$objects}";
	}
	else { $val = utils::json_quote($val) }
	return $val;
}

# превращает в json и сразу отправляет. Объекты складирует в $self->{objects}
sub pack {
	my ($self, $data, $cmd) = @_;
	local ($,, $\) = ();
	my $pipe = $self->{w};
	my ($so, $flag) = (0, 1);
	
	print $pipe $cmd if defined $cmd;
	
	utils::walk_data($data, sub {
		my ($ref, $key) = @_;
		print $pipe "," if $flag and $so;
		$flag = 1;
		print $pipe utils::json_quote($key), ":" if defined $key;
		print $pipe $self->json_quote($$ref);
	}, sub {
		my ($ref, $key, $class) = @_;
		print $pipe "," if $so++ and $flag;
		print $pipe utils::json_quote($key), ":" if defined $key;
		print $pipe $class == 0? "[": "{";
		$flag = 0;
	}, sub {
		my ($ref, $key, $class) = @_;
		print $pipe $class == 0? "]": "}";
		$so--;
		$flag = 1;
	});
	
	print $pipe "\n";
}

# распаковывает
sub unpack {
	my ($self, $data) = @_;

	$data = utils::from_json($data);
	my $objects = $self->{objects};
	my $bless = $self->{bless};
	my $stub = $self->{stub};
	
	utils::walk_data($data, sub {}, sub {
		my ($ref, $key, $hash) = @_;
		return unless $hash;
		
		my $num;
		my $val = $$ref;
		
		if(defined($num = $val->{$stub})) {
			$$ref = $self->stub($num);
		}
		elsif(defined($num = $val->{$bless})) {
			$$ref = $objects->[$num];
		}		
	});
	
	return $data;
}

# вызывает функцию
sub call {
	my ($self, $name, @args) = @_;
	$self->pack(\@args, "call $name ".(wantarray?1:0)."\n");
	$self->ret(@_);
}

# вызывает метод
sub apply {
	my ($self, $class, $name, @args) = @_;
	$self->pack(\@args, "apply $class $name ".(wantarray?1:0)."\n");
	$self->ret(@_);
}

# выполняет код
sub eval {
	my ($self, $eval, @args) = @_;
	local ($,, $\) = ();
	my $pipe = $self->{w};
	$self->pack(\@args, "eval ".(wantarray?1:0)."\n");
	print $pipe pack("L", length $eval), $eval;
	$self->ret(@_);
}

# получает и возвращает данные и устанавливает ссылочные параметры
sub ret {
	my ($self) = @_;
	local ($,, $\) = ();
	my $pipe = $self->{r};
	my (@ret, $args);
	
	for(;;) {	# клиент послал запрос
		my $ret = <$pipe>;
		my $arg = scalar <$pipe>;
		$args = $self->unpack($arg);
		#chop $arg;
		#chop $ret;
		
		last if $ret eq "ok\n";
	
		chop $ret;
		
		my ($cmd, $arg1, $arg2, $arg3) = split / /, $ret;
		if($cmd eq "stub") {
			if($arg3) { @ret = $self->{objects}->[$arg1]->$arg2(@$args); $self->pack(\@ret, "ok\n") }
			else { $self->pack(scalar $self->{objects}->[$arg1]->$arg2(@$args), "ok\n") }
		}
		elsif($cmd eq "apply") {
			if($arg3) { @ret = $arg1->$arg2(@$args); $self->pack(\@ret, "ok\n") }
			else { $self->pack(scalar $arg1->$arg2(@$args), "ok\n") }
		}
		elsif($cmd eq "call") {
			if($arg2) { @ret = &$arg1(@$args); $self->pack(\@ret, "ok\n") }
			else { $self->pack(scalar &$arg1(@$args), "ok\n") }
		}
		elsif($cmd eq "eval") {
			my $buf;
			die "Разрыв соединения" if read($pipe, $buf, 4) != 4;
			my $len = unpack("L", $buf);
			die "Разрыв соединения" if read($pipe, $buf, $len) != $len;
			if($arg1) { @ret = eval $buf }
			else { @ret = scalar eval $buf }
			die $@ // $! if $@ // $!;
			$self->pack($arg1? \@ret: $ret[0], "ok\n");
		}
		else {
			die "Неизвестная команда `$cmd`";
		}
	}

	return wantarray && ref $args eq "ARRAY"? @$args: $args;
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
	my $pipe = $rpc->{w};
	my $num = $self->{num};
	
	print $pipe "stub $num $name ".(wantarray?1:0)."\n";
	$rpc->pack(\@param);
	$rpc->ret(@_);
}
