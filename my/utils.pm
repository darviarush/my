package utils::boolean;

# Эмулирует булевый класс для json

$true = utils::boolean->new(1);
$false = utils::boolean->new(0);

use overload 'bool' => sub { ${$_[0]} };

use overload '""'   => sub { ${$_[0]} ? 'true' : 'false' };
use overload 'eq'   => sub { my($s, $t) = @_; "$s" eq (ref $t eq ref $s ? "$t": $t)? $true: $false };
use overload 'ne'   => sub { my($s, $t)=@_; !($s eq $t) };

use overload '0+'   => sub { ${$_[0]} };
use overload '=='   => sub { my($s,$t)=@_; $$s == (ref $t eq ref $s ? $$t: $t)? $true: $false };
use overload '!='   => sub { my($s,$t)=@_; !($s == $t) };
use overload '!'	=> sub { ${$_[0]} ? $false: $true };

sub new {
	my ( $class, $value ) = @_;
	bless \(my $state = $value), $class;
}

package utils;

use Data::Dumper;

# дампер JSON
sub to_json {
	my @s;
	walk_data($_[0], sub {
		my ($ref, $key) = @_;
		push @s, (defined($key)? json_quote($key).":".json_quote($$ref): json_quote($$ref)), ",";
	}, sub {
		my ($ref, $key, $class) = @_;
		push @s, json_quote($key).":" if defined $key;
		push @s, $class == 0? "[": "{";
	}, sub {
		my ($ref, $key, $class) = @_;
		pop @s if $s[$#s] eq ",";
		push @s, ($class == 0? "]": "}"), ",";
	});
	pop @s if $s[$#s] eq ",";
	return join("", @s);
}

# оборачивает в кавычки json
sub json_quote {
	my ($x) = @_;
	return "$x" if $x eq "utils::boolean";
	return "null" unless defined $x;
	return $x if $x eq 0+$x;

	$x = "$x";
	$x =~ s/[\\\"\x0-\x19]/my $k = $&; $k =~ tr{\n\r\t\f\b\\\"}{nrtfb\\\"}? "\\$k": sprintf("\\u%04x", ord $k)/ge;
	return "\"$x\"";
}

# старый дампер JSON
sub to_json_old {
	my ($x) = @_;
	local ($_, $`, $', $&);
	return do { my @x; while(my($a, $b) = each %$x) { push @x, to_json($a).":".to_json($b) } "{".join(",", @x)."}" } if ref $x eq "HASH";
	return "[".join(",", map { to_json($_) } @$x)."]" if ref $x eq "ARRAY";
	if(ref $x eq "SCALAR") {
		return "true" if $$x eq "1";
		return "false" if $$x eq "0";
	}
	return "null" if not defined $x;
	return $x if $x eq 0+$x;
	my $k;
	$x = "$x";
	$x =~ s/[\\\"\x0-\x19]/$k = $&; $k =~ tr{\n\r\t\f\b\\\"}{nrtfb\\\"}? "\\$k": sprintf("\\u%04x", ord $k)/ge;
	return "\"$x\"";
}

# парсер JSON
sub from_json {
	local ($_, $`, $', $1, $2, $&);
	($_) = @_;

	my (@x, @s, $pos);

	my $pop_hash = sub {
		$@ = "Нет элементов ключ-значение JSON", return if @x < 2;
		pop @s;
		$@ = "Нет хеша JSON", return if ref $s[$#s] ne "HASH";
		my $b = pop @x;
		my $a = pop @x;
		$s[$#s]->{$a} = $b;
		return 1;
	};

	my $pop_array = sub {
		$@ = "Нет массива JSON", return if ref $s[$#s] ne "ARRAY";
		$@ = "Нет элементa значения JSON", return unless @x;
		push @{$s[$#s]}, pop @x;
		return 1;
	};

	my $pop = sub {
		return &$pop_hash unless ref $s[$#s];		# двоеточие
		&$pop_array;
	};

	for(;;) {
		/\G\s*/g; $pos = pos;

		push(@x, {}), next if /\G\{\s*\}/g; pos = $pos;
		push(@x, []), next if /\G\[\s*\]/g; pos = $pos;

		push(@s, {}), next if /\G\{/g; pos = $pos;
		push(@s, []), next if /\G\[/g; pos = $pos;
		push(@s, ":"), next if /\G:/g; pos = $pos;
		do { return unless &$pop }, next if /\G,/g; pos = $pos;
		do { return unless &$pop_hash;  push @x, pop @s; }, next if /\G}/g; pos = $pos;
		do { return unless &$pop_array; push @x, pop @s; }, next if /\G]/g; pos = $pos;

		push(@x, $utils::boolean::true), next if /\Gtrue\b/g; pos = $pos;
		push(@x, $utils::boolean::false), next if /\Gfalse\b/g; pos = $pos;
		push(@x, undef), next if /\Gnull\b/g; pos = $pos;
		push(@x, 0+$&), next if /\G-?\d+(\.\d+)?([Ee][+-]?\d+)?/g; pos = $pos;
		do {		# преобразуем строку
			my $x = $1;
			$x =~ s{\\([nrtfb\\/\"])}{ my $y=$1; $y =~ tr{nrtfb}{\n\r\t\f\b}; $y }ge;
			$x =~ s/\\u([0-9A-Fa-f]{4})/my $x = chr hex $1;
				utf8::encode($x) if utf8::is_utf8($x);
				$x
			/ge;
			push @x, $x;
		}, next if /\G\" ( ( \\\\ | \\\" | [^\"\n\r] )* ) \"/gx; pos = $pos;

		last if /\G$/;

		$@ = "Не конец JSON `".substr($_, pos, length $_)."`";
		return;
	}

	$@ = "Осталось ".@x." элементов JSON", return if @x != 1;
	$@ = "Остались операторы JSON", return if @s;
	return $x[0];

}

# заходит во все хеши и массивы и запускает функцию на конце для скаляра. Второй параметр - ссылка на скаляр - ф-я может модифицировать
# аналог array_walk_recursive в php, но с большими возможностями
sub walk_data {
	my ($scalar, $fn, $fn_begin, $fn_end) = @_;
	my ($k, $v);
	my @scalar = (\$_[0]);

	while(@scalar) {
		my $ref = pop @scalar;
		
		$fn_end->(@$ref), next if ref $ref eq "ARRAY";
		
		my $key = undef;
		($key, $ref) = %$ref if ref $ref eq "HASH";
		
		my $scalar = $$ref;
		my $class = ref $scalar;

		if($class eq "ARRAY") {
			$fn_begin->($ref, $key, 0) if $fn_begin;
			next if ref $$ref ne "ARRAY";
			push @scalar, [$ref, $key, 0] if $fn_end;
			push @scalar, reverse \(@$scalar);
		}
		elsif($class eq "HASH") {
			$fn_begin->($ref, $key, 1) if $fn_begin;
			next if ref $$ref ne "HASH";
			push @scalar, [$ref, $key, 1] if $fn_end;
			push @scalar, {$_=>\($scalar->{$_})} for keys %$scalar;
		}
		else {
			$fn->($ref, $key);
		}
	}
}

# создаёт множество
sub set { map { $_=>1 } @_ }

# разбирает построчный файл. Возвращает массив. Начальные и конечные пробельные символы удаляются
sub parse_vector {
	my ($path) = @_;

	return () unless -e $path;

	local ($_, $', $`, $1);

	open my($f), $path or die "not open vector file `$path`. $!\n";
	my @lines = grep {$_} map {s/^\s*(.*?)\s*$/$1/; $_} <$f>;
	close $f;
	return @lines;
}

# печатает построчный файл
sub print_vector {
	my $path = shift;
	open my($f), ">", $path or die "not create vector file `$path`. $!\n";
	local ($\, $_) = "\n";
	print $f $_ for @_;
	close $f;
}

# перезаписывает построчный массив
sub replace_vector {
	my ($path, $sub) = @_;
	my @args = parse_vector($path);
	print_vector($path, &$sub(@args));
}

# разбирает ini-файл и возвращает хэш
sub parse_ini {
	my ($path) = @_;

	return {} unless -e $path;

	local ($_, $1, $2, $3, $4, $', $`);

	open my($f), $path or die "not open ini file `$path`. $!\n";

	my $result = {};
	my $entry = $result;

	my $canon = sub {
		return unless ref $entry eq "ARRAY";
		my $arr = $entry;
		$entry = $entry->[$#$entry];
		push @$arr, ($entry = {}) unless ref $entry eq "HASH";
	};

	my $can = sub {
		my ($key, $val) = @_;
		my $v = $entry->{$key};
		if(ref $v eq "ARRAY") { push @$v, $val } else { $entry->{$key} = [$v, $val] }
	};

	while(<$f>) {
		# удаляем начальные и конечные пробельные символы
		s/^\s*(.*?)\s*$/$1/;

		# пропускаем пустые строки и комментарии
		next if $_ eq "" or /^[;#]/;

		# строка с "="
		/^(.*?)\s*=\s*/ && do {
			my ($key, $val) = ($1, $');
			$val = undef if $val eq "";
			$entry->{$key} = $val, next unless exists $entry->{$key};
			&$can($key, $val);
			next;
		};

		# новая глава
		/^\[(.*?)\]$/ && do {
			$entry = $result;
			my @x = split '::', $1;
			my $key = pop @x;
			$entry = $entry->{$_} // ($entry->{$_} = {}), &$canon for @x;
			if(exists $entry->{$key}) { my $val = {}; &$can($key, $val); $entry = $val; }
			else { $entry = ($entry->{$key} = {}); }
		};
		next;

		# ошибка в ini
		close $f;
		die "$.. Error parsing ini-file `$path`\n";
	}

	close $f;

	return $result;
}

sub dump_ini {
	my ($ini) = @_;
	return "" unless keys %$ini;
	my @tree = (''=>$ini);
	my $dump = "";
	my $tek = '';
	while(@tree) {
		my ($path, $tree) = splice @tree, -2;
		$dump .= "\n[$path]\n", next unless keys %$tree;
		$dump .= "\n[$path]\n", $tek = $path if $tek ne $path;
		while(my($a, $b) = each %$tree) {
			unless(ref $b) {
				$dump .= "$a = $b\n";
				next;
			}
			my $apath = $path? "${path}::$a": $a;
			push @tree, $apath, $b;
		}
	}
	$dump =~ s/^\s+//; # убрать первую строку
	return $dump;
}

sub print_ini {
	($path, $ini) = @_;
	open my($f), ">", $path or die "not create ini-file `$path`. $!\n";
	print $f dump_ini($ini);
	close $f;
}


# создаёт уникальный идентификатор
my @abc = ('A'..'Z', 'a'..'z', '0'..'9', '/', '$', '.');

sub unic_id {
	my $size = shift // 16;
	my $unic_id = "";

	for(my $i=0; $i<$size; $i++) {
		my $j = int rand scalar @abc;
		$unic_id .= $abc[$j];
	}

	return $unic_id;
}


# создаёт соль заданной длины
sub gen_salt {
	my $size = shift // 16;
	my $salt = "";

	for(my $i=0; $i<$size; $i++) { $salt .= chr(rand 256); }

	return $salt;
}

# распаковывает данные переданные в виде параметров url
sub param {
	my ($data, $sep) = @_;
	local ($_, $`, $');
	require URI::Escape;
	my $param = {};
	for ($data? split($sep // "&", $data): ()) {
		tr/+/ /;
		/$/ unless /=/;
		my $key = URI::Escape::uri_unescape($`);
		my $val = $param->{$key};
		my $newval = URI::Escape::uri_unescape($');
		if(defined $val) {
			if(ref $val) { push @$val, $newval } else { $param->{$key} = [$val, $newval]}
		} else {
			$param->{$key} = $newval;
		}
	}
	return $param;
}

# возвращает путь к файлу
sub dirname ($) { $_[0] =~ m!/[^/]*$! and $`; }

# возвращает имя файла
sub basename ($) { $_[0] =~ m![^/]*$! and $&; }

# делает директорию приложения текущей
sub cdapp { chdir basename($0); }

# читает pid управляющего процесса
sub read_pid {
	my $home = home();
	open my($f), "<", "$home/script/PID";
	my $pid;
	join("", <$f>) =~ /\bpid (\d+)/i and $pid = $1;
	close $f;
	return unless $pid and kill 0, $pid;
	return $pid;
}

# возвращает абсолютный путь к директории script
sub pwd { my $home = `pwd`; chomp $home; $home .= "/script"; return $home; }

# модифицирует crontab
sub save_boot {
	my ($save) = @_;
	my $home = pwd();
	my @list = ("\@reboot $home/bis start -n",
		"*/1 * * * * $home/bis start -n",
		"*/1 * * * * /usr/bin/lockf -t 60 $home/SLK $home/bis session_delex");
	my $list = $save? join("\n", @list)."\n": "";
	open my($f), "|crontab -" or die "$@$!\n";
	print $f $list;
	close $f;
}

sub killall {
	my ($sig, $name) = @_;
	local ($1, $`, $', $_);
	kill $sig, map { /(\d+)/ && $1 } grep { /$name/ } split "\n", `ps -A -o pid,command`;
}

sub confirm {
	my $yes = "";
	local $\ = "";
	do { print("$_[0] (yes/no) "); } while ($yes = <STDIN>) !~ /^yes|no$/;
	return $yes =~ /yes/;
}

# Dumper не должен возвращать \x{...}
$Data::Dumper::Useqq = 1;

{ no warnings 'redefine';
	sub Data::Dumper::qquote {
		my $s = shift;
		$s =~ s/\'/\\\'/g;
		return "'$s'";
	}
}

# возвращает дамп ссылки
sub Dump { substr(Dumper($_[0]), 8, -2) }

# записывает тест в файл
sub write_test {
	my ($action, $data, $body, $sess) = @_;

	my $json = from_json($body);

	my $auth = $sess? "_auth": "";

	open my($f), '+<', home()."/t/api$auth.t";
	my $file = join("", <$f>);
	$file =~ s/use Test::More tests => (\d+);/$_=$&; s!\d+!$&+3!e; $_/e;
	seek $f, 0, 0;
	print $f $file;
	print $f qq{

\$t->post_form_ok("/api/$action", ${\Dump($data)})
	->json_key_is("head::error", $json->{head}->{error})
	->json_key_is("body", ${\Dump($json->{body})});

};
	close $f;
}

# читает весь файл
sub read {
	my ($path) = @_;
	return "" unless -e $path;
	open my($f), $path or die("Utils::read: Не могу открыть $path: $!\n");
	read $f, my($body), -s $f;
	close $f;
	return $body;
}

# создаёт директории в пути, если их нет
sub mkpath {
	my ($path) = @_;
	local ($`, $');
	mkdir $` while $path =~ m!/!g;
}

# записывает весь файл
sub write {
	my $path = shift;
	open my($f), ">", $path or die("Utils::write: Не могу создать $path: $!\n");
	local $_;
	local $\ = "";
	print $f $_ for @_;
	close $f;
}

# запись файла с вопросом при перезаписи
sub writeno {
	my ($path) = @_;
	if(-e $path) {
		return unless confirm("Перезаписать $path ?");
	}
	goto &write;
}

# дописывает в конец файла
sub endwrite {
	my $path = shift;
	open my($f), ">>", $path or die("Utils::endwrite: Не могу открыть $path: $!\n");
	local $_;
	local $\ = "";
	print $f $_ for @_;
	close $f;
}


# перезаписывает весь файл
sub replace {
	my ($path, $block) = @_;
	my $file = Utils::read($path);
	&$block($file);
	Utils::write($path, $file);
}

# копирует файл
sub cp {
	my ($from, $to) = @_;
	utils::write($to, utils::read($from));
}

# stderr и stdout записывает так же и в файл
sub tee {
	my ($path, $nodel) = @_;

	# удаляем файл
	unlink $path unless $nodel;

	require File::Tee;

	# перенаправляем вывод тестов
	File::Tee::tee(STDERR, ">>$path");
	File::Tee::tee(STDOUT, ">>$path");

	select STDERR; $| = 1;  # make unbuffered
	select STDOUT; $| = 1;  # make unbuffered
}

# формирует параметры
sub form_param {
	my ($param) = @_;
	require URI::Escape;
	my $uri_escape = sub { my ($x) = @_; utf8::encode($x) if utf8::is_utf8($x); URI::Escape::uri_escape($x) };
	join "&", map {
		my $p = $param->{$_};
		my $s = &$uri_escape($_)."=";
		if(ref $p eq "ARRAY") { $s = join "&", map {$s.&$uri_escape($_)} @$p }
		else { $s .= &$uri_escape($p) }
	} keys %$param;
}

# отправляет запрос http-пост
sub post {
	require LWP::UserAgent;
	my ($url, $param) = @_;
	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);
	my $response = $ua->post($url, Content => form_param($param));
	my ($service) = caller 1;
	die(error505($service, $response->status_line)) unless $response->is_success;
	$response->content;
}

# для вставки в строки javascript
sub escapejs {
	my ($x) = @_;
	local ($&, $`, $');
	$x =~ s/[\\\"\']/\\$&/g;
	$x =~ s/\n/\\n/g;
	$x =~ s/\r/\\r/g;
	return $x;
}

# возвращает строку javascript
sub stringjs { '"'.escapejs($_[0]).'"' }

# для вставки в HTML
sub escapeHTML {
	local ($_, $&, $`, $');
	$_ = $_[0];
	s/&/&amp;/g;
	s/</&lt;/g;
	s/>/&gt;/g;
	s/\"/&quot;/g;
	s/\'/&#39;/g;
	return $_;
}

# понятно
sub camelcase {
	my $s = ucfirst $_[0];
	$s =~ s/_([a-z])/uc $1/ge;
	$s
}

# понятно
sub decamelcase {
	my $s = lcfirst $_[0];
	$s =~ s/[A-Z]/"_".lc $&/ge;
	$s
}

# переводит натуральное число в заданную систему счисления
sub to_radix {
	my ($n, $radix) = @_;
	my ($x, $y) = "";
	for(;;) {
		$y = $n % $radix;
		$x = ($y < 10? $y:  chr($y + ($y<36? ord("A") - 10: $y<62? ord("a")-36 : 128-62))).$x;
		last unless $n = int $n / $radix;
	}
	return $x;
}

# парсит число в указанной системе счисления
sub from_radix {
	my ($s, $radix) = @_;
	my $x = 0;
	for my $ch (split "", $s) {
		$a = ord $ch;
		$x = $x*$radix + $a - ($a <= ord("9")? ord("0"): $a <= ord("Z")? ord('A')-10: $a <= ord('z')? ord('a')-36: 128-62);
	}
	return $x;
}

# заходит во все поддиректории и запускает функцию на конце для файла, а если их две - для файла и папки
#	Если $fn или $fn_dir возвращает -1, то функция завершает работу
#	Если $fn_dir возвращает -2, то walk в данную папку не входит
sub walk {
	my ($fn, $fn_dir) = pop @_;
	$fn_dir = pop @_ if ref $_[$#_] eq "CODE";
	my @dir = ();
	for my $path (@_) {
		if(-d $path) { my $ret = ($fn_dir and $fn_dir->($path)); return if $ret == -1; push @dir, $path if $ret != -2; }
		else { return if $fn->($path) == -1; }
	}
	local (*d);
	while(@dir) {
		my $dir = pop @dir;
		opendir d, $dir or die "не могу открыть $dir. $!";
		while(my $file = readdir d) {
			next if $file eq "." or $file eq "..";
			$path = "$dir/$file";
			if(-d $path) { my $ret = ($fn_dir and $fn_dir->($path)); return if $ret == -1; push @dir, $path if $ret != -2; }
			else { return if $fn->($path) == -1; }
		}
		closedir d;
	}
}

# это объект?
sub blessed {
	ref($_[0]) !~ /^(?:ARRAY|GLOB|HASH|CODE|SCALAR|)\z/
}

# isa для объекта
sub isa {
	my ($a, $b) = @_;
	blessed($a) && $a->isa($b)
}

# can для объекта
sub can {
	my ($a, $b) = @_;
	blessed($a) && $a->can($b)
}

# очищает память пакета
sub clear_mem {
	@$b = (), %$b = (), $$b = undef while ($a, $b) = each %{"$_[0]::"}
}

1;