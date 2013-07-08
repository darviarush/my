

prog(perl, F, perl(I, '-e', 'require rpc; rpc->new')) :- format(atom(I), "-I'~w'", F).
prog(php, F, php('-r', A)) :- format(atom(I), 'require_once \"~w/rpc.php\"; new rpc();', F).
prog(python, F, python('-c', A)) :- format(atom(I), 'import sys; sys.path.append(\'~w\'); from rpc import RPC; RPC()', F).
prog(ruby, F, ruby(I, '-e', 'require \'rpc.rb\'; RPC.new')) :- format(atom(I), "-I'%s'", F).
prog(swi, F, pl('-s', I, '-g', go, '-t', halt)) :- format(atom(I), '~w/rpc.pro', F).

% rpc(Role, R, W, Prog, Objects, Nums, Warn).

% конструктор. Создаёт соединение
rpc(R, W, rpc(test, R, W, -1, t, [], 0)).
rpc(Prog, Self):-
	prog(Prog, ProgPath), pipe(ChR, W), pipe(R, ChW), fork(Pid), 
		(Pid = child, dup(ChR, 4), dup(ChW, 5), format(ProgPath, File, Path), exec(Path); Self = rpc(major, R, W, Prog, t, [])).
	


% закрывает соединение
rpc_close(Self):- rpc_ok(Self, _), rpc(major, R, W, _, _, _, _) = Self, close(R), close(W).

% создаёт сервис
rpc_minor(R) :- open('/dev/fd/4', read, R, [type(binary)]), open('/dev/fd/5', write, W, [type(binary)]), Self = rpc(minor, R, W, 1, t, []), rpc_ret(Self, Self2, R), (Self2=rpc(minor, _, _, _, _, _, Warn), Warn=1, print('MINOR ENDED'(R)); true).


% превращает в бинарный формат и сразу отправляет. Объекты складирует в Objects - rpc(Role, R, W, Prog, Objects, Nums, Warn).

rpc_pack(rpc(Role,R,W,P,O,N,Warn), Data, rpc(Role,R,W,P,O1,N,Warn)):- rpc_pk(W,O,Data,Warn,O1), (Warn = 1, print(), nl; true).
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
				print $pipe "s", pack("l", length $key), $key;
			}
			
			if(my $val_hash = ref $val eq "HASH" or ref $val eq "ARRAY") {
				print($pipe "h", pack "l", $n), next if defined($n = $is{$val});
				my $num = keys %is;
				$is{$val} = $num;
				print $pipe $val_hash? ("H", pack "l", 0+keys(%$val)): ("A", pack "l", 0+@$val);
				push @st, $arr;
				$arr = $val;
				$hash = $val_hash;
			}
			elsif(ref $val eq "utils::boolean") { print $pipe $val? "T": "F" }
			elsif(ref $val eq "rpc::stub") {
				my $stub = tied %$val;
				print $pipe "S", pack "l", $stub->{num};
			}
			elsif(ref $val) {
				my $objects = $self->{objects};
				my $num = keys %$objects;
				$objects->{$num} = $val;
				warn "$self->{role} add($num) =".Dumper($objects) if $self->{warn} >= 2;
				print $pipe "B", pack "l", $num;
			}
			elsif(!defined $val) { print $pipe "U" }
			elsif(($svref = svref_2object \$val) && (($svref = $svref->FLAGS) & B::SVp_IOK)) {	# integer
				print $pipe $val == 1? "1": $val == 0? "0": ("i", pack "l", $val);
			}
			elsif($svref & B::SVp_POK) {		# string
				_utf8_off($val) if is_utf8($val);
				print $pipe "s", pack("l", length $val), $val;
			}
			elsif($svref & B::SVp_NOK) {		# double
				print $pipe "n", pack "d", $val;
			}
			else {	die "Значение неизвестного типа ".Devel::Peek::Dump($val)." val=`$val`" }
		}
	}
	
	return $self;
}

# считывает указанное количество байт
sub read {
	my ($self, $n) = @_;
	read $self->{r}, my $buf, $n or die "Оборван поток ввода. $!";
	return $buf;
}

# считывает и распаковывает
sub readf {
	my ($self, $fmt) = @_;
	unpack $fmt, $self->read($fmt eq "d"? 8: 4);
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

			$_ = $self->read(1);
			
			if($_ eq "h") {	$val = $is[$self->readf("l")] }
			elsif($_ eq "H") { $replace_arr = 1; $val = {} }
			elsif($_ eq "A") { $replace_arr = 0; $val = []; }
			elsif($_ eq "S") { $val = $objects->{$self->readf("l")} }
			elsif($_ eq "B") { $val = $self->stub($self->readf("l")) }
			elsif($_ eq "T") { $val = $utils::boolean::true }
			elsif($_ eq "F") { $val = $utils::boolean::false }
			elsif($_ eq "U") { $val = undef }
			elsif($_ eq "1") { $val = 1 }
			elsif($_ eq "0") { $val = 0 }
			elsif($_ eq "i") { $val = $self->readf("l") }
			elsif($_ eq "n") { $val = $self->readf("d") }
			elsif($_ eq "s") { $val = $self->read($self->readf("l")) }
			else { die "Неизвестный формат в командном потоке: `$_`" }
			
			if($hash) {
				if($len % 2) { $key = $val }
				else { $arr->{$key} = $val }
			}
			else { push @$arr, $val }
			
			if(defined $replace_arr) {
				push @st, [$arr, $hash, $key, $len];
				push @is, $arr = $val;
				($hash, $len) = ($replace_arr, ($replace_arr+1) * $self->readf("l"));
				$replace_arr = undef;
			}
			
		}
	}
	
	return $ret->[0];
}

# отправляет команду и получает ответ
sub reply {
	my $self = shift;
	warn "$self->{role} -> ".utils::array_dump(\@_) if $self->{warn};
	$self->pack(\@_)->pack($self->{nums});
	$self->{nums} = [];
	$self->ret
}

# отправляет ответ
sub ok {
	my ($self, $ret, $cmd) = @_;
	$cmd //= "ok";
	warn "$self->{role} -> $cmd ".utils::array_dump($ret) if $self->{warn};
	$self->pack([$cmd, $ret])->pack($self->{nums});
	$self->{nums} = [];
	return $self;
}

# создаёт экземпляр класса
sub new_instance {
	my $self = shift;
	my $class = shift;
	$self->reply("new", $class, \@_, wantarray);
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
		$self->{warn} && warn("$self->{role} closed: ".utils::array_dump([caller(1)])), 
		return unless defined $ret and ref $ret;	# закрыт канал
	
		my $nums = $self->unpack;
		
		warn "$self->{role} <- ".utils::array_dump($ret)." ".utils::array_dump($nums)."\n" if $self->{warn};
		
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
			elsif($cmd eq "apply" or $cmd eq "new" and do {splice $ret, 1, 0, "new"; 1}) {
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