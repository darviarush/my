
%prog = (
"perl" => "perl -I'%s' -e 'require rpc; rpc->new'",
"php" => "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
"python" => "python -c 'import sys; sys.path.append(\"%s\"); from rpc import RPC; RPC()'",
"ruby" => "ruby -I'%s' -e 'require \"rpc.rb\"; RPC.new'"
);


# конструктор. Создаёт соединение
sub new {
	my ($cls, $prog) = @_;
	
	goto &minor unless defined $prog;
	
	return bless {r=>$_[2], w=>$_[3], prog => -1, objects => {}, nums => [], role => "TEST"}, $cls if $prog == -1;
	
	#open2 my($reader), my($writer), $prog{$prog} // $prog or die "Ошибка создания канала. $!";
	my ($reader, $ch_writer, $ch_reader, $writer);
	
	pipe $ch_reader, $writer or die "not create pipe. $!";
	pipe $reader, $ch_writer or die "not create pipe. $!";;
	
	binmode $reader; binmode $writer; binmode $ch_reader; binmode $ch_writer;

	my $stdout = select $in; $| = 1;
	select $writer; $| = 1;
	select $ch_writer; $| = 1;
	select $stdout;
	
	my $pid = fork;
	
	die "fork. $!" if $pid < 0;
	
	unless($pid) {
		$prog = $prog{$prog};
		$prog = sprintf $prog, $INC{'rpc.pm'} =~ /\/rpc.pm$/ && $` if defined $prog;
		my $ch4 = fileno $ch_reader;
		my $ch5 = fileno $ch_writer;
		POSIX::dup2($ch4, 4) if $ch4 != 4;
		POSIX::dup2($ch5, 5) if $ch5 != 5;
		exec $prog or die "Ошибка создания подчинённого. $!";
	}
		
	bless {r => $reader, w => $writer, prog => $prog, objects => {}, nums => [], warn=>0, role => "MAJOR"}, $cls;
}

# закрывает соединение
sub close {
	my ($self) = @_;
	local ($,, $\) = ();
	$self->ok;
	close $self->{w} or die "Не закрыт поток записи";
	close $self->{r} or die "Не закрыт поток чтения";
}

# создаёт клиента
sub minor {
	my ($cls) = @_;

	open my $r, "<&=4" or die "NOT ASSIGN IN: $!";
	open my $w, ">&=5" or die "NOT ASSIGN OUT: $!";
	
	binmode $r; binmode $w;
	my $stdout = select $w; $| = 1;
	select $stdout;

	
	my $self = bless {r => $r, w => $w, objects => {}, nums => [], warn=>0, role => "MINOR"}, $cls;
	my @ret = $self->ret;
	warn "MINOR ENDED @ret" if $self->{warn};
	return @ret;
}



# превращает в бинарный формат и сразу отправляет
sub pack {
	my ($self, $data) = @_;
	local ($_, $,, $\) = ();
	my %is = ();
	my ($svref, $n);
	my $pipe = $self->{w};
	
	my @st = [$data];
	
	while(@st) {
		my $arr = pop @st;
		my $hash = ref $arr eq "HASH";

		while(my($key, $val) = $hash? each %$arr: each @$arr) {
			
			if($hash) {
				_utf8_off($key) if is_utf8($key);
				print $pipe "s", pack("L", length $key), $key;
			}
			
			if(ref $val eq "HASH") {
				print($pipe "h", pack "L", $n), next if defined($n = $is{$val});
				my $num = keys %is;
				$is{$val} = $num;
				print $pipe "H", pack "L", 0+keys(%$val);
				push @st, $arr;
				$arr = $val;
				$hash = 1;
			}
			elsif(ref $val eq "ARRAY") {
				print($pipe "h", pack "L", $n), next if defined($n = $is{$val});
				my $num = keys %is;
				$is{$val} = $num;
				print $pipe "A", pack "L", 0+@$val;
				push @st, $arr;
				$arr = $val;
				$hash = 0;
			}
			elsif(ref $val eq "utils::boolean") {
				print $pipe $val? "T": "F";
			}
			elsif(ref $val eq "rpc::stub") {
				my $stub = tied %$val;
				print $pipe "S", pack "L", $stub->{num};
			}
			elsif(ref $val) {
				my $objects = $self->{objects};
				my $num = keys %$objects;
				$objects->{$num} = $val;
				warn "$self->{role} add($num) =".Dumper($objects) if $self->{warn} >= 2;
				print $pipe "B", pack "l", $num;
			}
			elsif(!defined $val) {
				print $pipe "U";	# undef
			}
			elsif(($svref = svref_2object \$val) && (($svref = $svref->FLAGS) & B::SVp_IOK)) {	# integer
				print $pipe $val == 1? "1": $val == 0? "0": ("i", pack "l", $val);
			}
			elsif($svref & B::SVp_POK) {		# string
				_utf8_off($val) if is_utf8($val);
				print $pipe "s", pack("L", length $val), $val;
			}
			elsif($svref & B::SVp_NOK) {		# double
				print $pipe "n", pack "d", $val;
			}
			else {	die "Значение неизвестного типа ".Devel::Peek::Dump($val)." val=`$val`" }
		}
	}
	
	return $self;
}

# считывает структуру из потока ввода
sub unpack {
	my ($self) = @_;
	my $pipe = $self->{r};
	
	local ($_, $/) = ();
	
	my $objects = $self->{objects};
	my (@is, $len, $arr, $hash, $key, $val, $replace_arr);
	my $ret = [];
	my @st = [$ret, 0, 0, 1];

	while(@st) {
		($arr, $hash, $key, $len) = @{pop @st};

		while($len--) {

			read $pipe, $_, 1 or die "Оборван поток ввода. $!";
			
			if($_ eq "h") {
				die "Не 4 байта считано. $!" if 4 != read $pipe, $_, 4;
				my $num = unpack "L", $_;
				$val = $is[$num];
			}
			elsif($_ eq "H") { $replace_arr = 1; $val = {} }
			elsif($_ eq "A") { $replace_arr = 0; $val = []; }
			elsif($_ eq "S") {
				die "Не 4 байта считано. $!" if 4 != read $pipe, $_, 4;
				$val = $objects->{unpack "L", $_};
			}
			elsif($_ eq "B") {
				die "Не 4 байта считано. $!" if 4 != read $pipe, $_, 4;
				$val = $self->stub(unpack "L", $_);
			}
			elsif($_ eq "T") { $val = $utils::boolean::true }
			elsif($_ eq "F") { $val = $utils::boolean::false }
			elsif($_ eq "U") { $val = undef }
			elsif($_ eq "1") { $val = 1 }
			elsif($_ eq "0") { $val = 0 }
			elsif($_ eq "i") {
				die "Не 4 байта считано. $!" if 4 != read $pipe, $_, 4;
				$val = unpack "l", $_;
			}
			elsif($_ eq "n") {		# double
				die "Не 8 байт считано. $!" if 8 != read $pipe, $_, 8;
				$val = unpack "d", $_;
			}
			elsif($_ eq "s") {		# string
				die "Не 4 байта считано. $!" if 4 != read $pipe, $_, 4;
				my $n = unpack "L", $_;
				die "Не $n байт считано. $!" if $n != read $pipe, $val, $n;
			}
			
			if($hash) {
				if($len % 2) { $key = $val }
				else { $arr->{$key} = $val }
			}
			else { push @$arr, $val }
			
			if(defined $replace_arr) {
				push @st, [$arr, $hash, $key, $len];
				push @is, $arr = $val;
				die "Не 4 байта считано. $!" if 4 != read $pipe, $_, 4;
				($hash, $len) = ($replace_arr, ($replace_arr+1) * unpack "L", $_);
				$replace_arr = undef;
			}
			
		}
	}
	
	return $ret->[0];
}

# отправляет команду и получает ответ
sub reply {
	my $self = shift;
	warn "$self->{role} -> ".Dumper(\@_) if $self->{warn};
	$self->pack(\@_)->pack($self->{nums})->ret
}

# отправляет ответ
sub ok {
	my ($self, $ret, $cmd) = @_;
	warn "$self->{role} -> ".Dumper([$cmd // "ok", $ret]) if $self->{warn};
	$self->pack([$cmd // "ok", $ret])->pack($self->{nums});
}

# создаёт экземпляр класса
sub create {
	my $self = shift;
	my $class = shift;
	$self->reply("create", $class, \@_, wantarray);
}

# вызывает функцию $rpc->call($name, @args)
sub call {
	my $self = shift;
	my $name = shift;
	$self->reply("call", $name, \@_, wantarray);
}

# вызывает метод
sub apply {
	my $self = shift;
	my $class = shift;
	my $name = shift;
	$self->reply("apply", $class, $name, \@_, wantarray);
}

# выполняет код
sub eval {
	my $self = shift;
	my $eval = shift;
	$self->reply("eval", $eval, \@_, wantarray);
}

# устанавливает warn на миноре
sub warn {
	my ($self, $val) = @_;
	$self->{warn} = $val+=0;
	$self->reply("warn", $val);
}

# удаляет ссылки на объекты из objects
sub erase {
	my ($self, $nums) = @_;
	local $_;
	my $objects = $self->{objects};
	delete $objects->{$_} for @$nums;
}

# получает и возвращает данные и устанавливает ссылочные параметры
sub ret {
	my ($self) = @_;
	local ($,, $\) = ();

	my (@ret, $ret);
	
	for(;;) {	# клиент послал запрос
		$ret = $self->unpack;
		$self->{warn} && warn("$self->{role} closed: ".Dumper([caller(1)])), 
		return unless defined $ret and ref $ret;	# закрыт канал
	
		my $nums = $self->unpack;
		
		warn "$self->{role} <- ".Dumper($ret)."\n" if $self->{warn};
		
		my $cmd = shift @$ret;
		
		$self->erase($nums), last if $cmd eq "ok";
		$self->erase($nums), die $ret->[0] if $cmd eq "error";
		
		eval {

			if($cmd eq "stub") {
				my ($num, $name, $args, $wantarray) = @$ret;
				if($wantarray) { @ret = $self->{objects}->{$num}->$name(@$args); $self->ok(\@ret) }
				else { $self->ok(scalar $self->{objects}->{$num}->$name(@$args)) }
			}
			elsif($cmd eq "get") {
				my ($num, $key) = @$ret;
				$self->ok($self->{objects}->{$num}->{$key});
			}
			elsif($cmd eq "set") {
				my ($num, $key, $val) = @$ret;
				$self->{objects}->{$num}->{$key} = $val;
				$self->ok(1);
			}
			elsif($cmd eq "warn") {
				$self->{warn} = $ret->[0];
				$self->ok(1);
			}
			elsif($cmd eq "apply" or $cmd eq "create" and do {splice $ret, 1, 0, "new"; 1}) {
				my ($class, $name, $args, $wantarray) = @$ret;
				if($wantarray) { @ret = $class->$name(@$args); $self->ok(\@ret) }
				else { $self->ok(scalar $class->$name(@$args)) }
			}
			elsif($cmd eq "call") {
				my ($name, $args, $wantarray) = @$ret;
				if($wantarray) { @ret = eval $name.'(@$args)'; die $@ // $! if $@ // $!; $self->ok(\@ret) }
				else { @ret = scalar eval $name.'(@$args)'; die $@ // $! if $@ // $!; $self->ok($ret[0]) }
			}
			elsif($cmd eq "eval") {
				my ($eval, $args, $wantarray) = @$ret;
				if($wantarray) { @ret = eval $eval; die $@ // $! if $@ // $!; $self->ok(\@ret) }
				else { @ret = scalar eval $eval; die $@ // $! if $@ // $!; $self->ok($ret[0]) }
			}
			else {
				die "$self->{role} Неизвестная команда `$cmd` `$ret` `$arg`";
			}
		};
		$self->ok($@ // $!, "error") if $@ // $!;
		$self->erase($nums); 
	}

	my $args = $ret->[0];
	return wantarray && ref $args eq "ARRAY"? @$args: $args;
}

# создаёт заглушку, для удалённого объекта
sub stub {
	my ($self, $num) = @_;
	my %x;
	tie %x, "rpc::prestub", $self, $num; 
	bless \%x, "rpc::stub";
}


# заглушка
package rpc::stub;

sub AUTOLOAD {
	my $self = shift;
	local ($&, $`, $');
	$AUTOLOAD =~ /\w+$/;
	my $name = $&;
	$self = tied %$self;
	$self->{rpc}->reply("stub", $self->{num}, $name, \@_, wantarray);
}

sub DESTROY {
	my ($self) = @_;
	$self = tied %$self;
	push @{$self->{rpc}->{erase}}, $self->{num};
}

package rpc::prestub;

use Data::Dumper;

sub TIEHASH { my ($cls, $rpc, $num) = @_; bless {rpc => $rpc, num => $num}, $cls }
sub FETCH { my ($self, $key) = @_; $self->{rpc}->reply("get", $self->{num}, $key) }
sub STORE { my ($self, $key, $val) = @_; $self->{rpc}->reply("set", $self->{num}, $key, $val) }

sub DELETE { my ($self, $key) = @_; warn "NOT IMPLEMENTED method DELETE"; undef }
sub CLEAR { my ($self) = @_; warn "NOT IMPLEMENTED method CLEAR"; undef }
sub EXISTS { my ($self, $key) = @_; warn "NOT IMPLEMENTED method EXISTS"; undef }
sub SCALAR { my ($self) = @_; warn "NOT IMPLEMENTED method SCALAR"; 0 }

sub FIRSTKEY { my ($self) = @_; warn "NOT IMPLEMENTED method FIRSTKEY"; undef }
sub NEXTKEY { my ($self, $lastkey) = @_; warn "NOT IMPLEMENTED method NEXTKEY"; undef }
#sub DESTROY { my ($self) = @_; warn "NOT IMPLEMENTED method DESTROY"; undef }
sub UNTIE { my ($self) = @_; warn "NOT IMPLEMENTED method UNTIE"; undef }
