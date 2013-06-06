package pages;

use utils;
use mail;

# инициализирует страницы
sub init {
	local (*d);
	utils::walk("page", sub {
		my ($path) = @_;
		return unless $path =~ s/\.pl$//;	# удаляем расширение и пропускаем только *.pl
		my $body = utils::read("$path.pl");
		my $html = "$path.html";
		$html = -e $html && template::new($html);

		$path =~ s!/!::!g;
		$eval = "package $path; use validator; sub run { ".(defined $html? "my \$x = do { $body }; $html": $body)." }";
		eval $eval;
		die "$path: ". ($@ // $!) if $@ // $!;
	});
}

# выполняет страницу
sub start {
	my ($path) = @_;
	if($path eq "/") { $path = "pages::index::"; } else { $path =~ s!/!::!g; $path = "pages${path}::"; }
	#my $action = *{${$path}{$request::PROTO}}{CODE} // *{${$path}{"run"}}{CODE};
	my $action = *{${$path}{"run"}}{CODE};
	eval {
		@request::BODY = $action->();
		@request::BODY = &{"${_}::run"} for @{"${path}layout"};
	};
	$request::RESPONSE = "HTTP/1.1 500 Internal Server Error\n", $request::OUTHEAD{"Content-Type"} = "text/plain; charset=utf-8", @request::BODY = $@ // $! if $@ // $!;
	utils::clear_mem($path); # очищаем память
}

package template;
# формирует темплейт
#
# $x и ${x} - заменяет на значение, обрабатывается escapeHTML
# $%x и $%{x} - заменяет на значение, не обрабатывается
# <include page> - подключает страницу
# <input name=y> - вставляет value=..., но если value уже есть - то ничего не делает
# <select name=u></select> - добавляет опции, если u формата [[value, text, selected]...] или [[group, [value, text]...]...]. Необязательный selected
# <textarea name=u></textarea> - вставляется значение между тегов
# <script>...</script> - обрабатывается компиллятором coffee
# <script type=...>...</script> - не обрабатывается
# <for i=a>...</for> - цикл
# <if a>...</if> - условие
# <if a>...<else>...</if> - условие с "иначе"
# <if a>...<elseif b>...<else>...</if>
sub new {
	my ($path) = @_;
	local ($_, $', $`, $&, $1, $2, $3);
	my $tmp = $path;
	$tmp =~ s!^!tmp/!;
	$tmp =~ s!\.\w+$!.pl!;
	my $mday = -M $tmp;
	return utils::read($tmp) if defined $mday and -M $path > $mday;

	$_ = utils::read($path);

	@ST = ();

	s{
		(?<R><!--.*?-->)|								# отбрасываем комментарии
		(?<S>[\'\\])|									# экранируем символы
		\$(?<E>%?)(?:\{(?<V>[\w\.]+)\}|(?<V>[\w\.]+))|					# обрабатываем переменные
		(?<I><input\b[^<>]*?\bname=\\?['"]?)(?<I2>[\w\.]+)(?<I3>[^<>]*)>|		# input
		(?<sel><select\b[^<>]+\bname=\\?["']?(?<sel2>[\w+\.])[^<>]*>.*?)</select>|	# select
		(?<T><textarea\b[^<>]+\bname=\\?["']?(?<T2>\w+)[^<>]*>)</textarea>|		# textarea
		<include\s+(?<L>[\w/:]+)(?<Le>\.html)?\s*>|							# include
		<for\s+(?<F>\w+)=(?<Fv>[\w\.]+)\s*>|						# for start
		(?<Fe></for>)|									# for end
		<if\s+(?<if>[\w\.]+)\s*>|							# if
		<elseif\s+(?<elseif>[\w\.]+)\s*>|						# elseif
		(?<else><else>)|								# else
		(?<endif></if>)|								# end if
		(?<layout><layout\s*/?>)						# layout
	}{
		defined $+{R}? "":							# отбрасываем комментарии
		defined $+{S}? "\\$+{S}":						# экранируем символы
		defined $+{V}? var($+{E}, $+{V}):					# обрабатываем переменные
		defined $+{I}? input($+{I}, $+{I2}, $+{I3}):				# input
		defined $+{sel}? $+{sel}.template::select($+{sel2})."</select>":	# select
		defined $+{T}? textarea($+{T}, $+{T2}):					# textarea
		defined $+{Le}? include_html($+{L}):					# include html
		defined $+{L}? qq{', *{"pages$+{L}::run"}->(), '}:			# include
		defined $+{F}? for_start($+{F}, $+{Fv}):			# for start
		defined $+{Fe}? for_end():							# for end
		defined $+{if}? if_start($+{if}):					# if
		defined $+{elseif}? elseif($+{elseif}):				# elseif
		defined $+{else}? if_else():						# else
		defined $+{endif}? if_end():						# end if
		defined $+{layout}? q{', @request::BODY, '}:		# layout
		$&;
	}gxesmi;

	$_ = "('$_')";

	s/(, |\()''(, |\))/ $1 eq "(" && $2 eq ")"? "''": $1 eq "("? "(": $2 eq ")"? ")": ", "/ge;	# удаляем пустые элементы

	utils::mkpath($tmp);
	utils::write($tmp, $_);
	return $_;
}

# вставляет html
sub include_html {
	my ($path) = @_;
	local ($+, $`, $', $&);
	my $html = utils::read("page/$path");
	$html =~ s/[\'\\]/\\$&/g;
	return $html;
}

# генерирует код для вставки в темплэйт
sub val {
	my @x = split /\./, $_[0];
	"\$x->".join("", map { "{'$_'}" } @x);
}

# генерирует option
sub select {
	my ($x) = val(@_);
	return "', map({'<option value=\"'.utils::escapeHTML(\$_->[0]).'\"'.(\$_->[2]? ' selected': '').'>'.utils::escapeHTML(\$_->[1])} \@{$x}), '";
}

# подставляет value в input
sub input {
	my ($x, $y, $z) = @_;
	$z =~ /\bvalue=/ || $y =~ /\bvalue=/? "$x$y$z>": "$x$y$z".' value="\', utils::escapeHTML('.val($y).'), \'">';
}

# textarea
sub textarea {
	$_[0].'\', utils::escapeHTML('.val($_[1]).'), \'</textarea>'
}

# переменные с $ и $%
sub var {
	'\', '.($_[0]? val($_[1]): "utils::escapeHTML(".val($_[1]).")").', \''
}

# for
sub for_start {
	my ($i, $a) = @_;
	push @ST, ["FOR", $a];
	'\', map({ $x->{\''.$i.'\'} = $_; (\''
}

sub for_end {
	my ($type, $a) = @{pop @ST};
	die "template:$path: </for> без <for>" if $type ne "FOR";
	'\') } @{'.val($a).'}), \''
}

# if
sub if_start {
	my ($a) = @_;
	push @ST, ["IF"];
	'\', ('.val($a).'? \''
}

sub elseif {
	my ($a) = @_;
	my ($type, $was_else) = @{$ST[$#ST]};
	die "template:$path: <elseif> без <if>" if $type ne "IF";
	die "template:$path: <elseif> после <else>" if $was_else;
	'\': '.val($a).'? \''
}

sub if_else {
	my ($type, $was_else) = @{$ST[$#ST]};
	die "template:$path: <else> без <if>" if $type ne "IF";
	die "template:$path: <else> после <else>" if $was_else;
	$ST[$#ST]->[1] = 1;
	"': '"
}

sub if_end {
	my ($type, $was_else) = @{$ST[$#ST]};
	die "template:$path: </if> без <if>" if $type ne "IF";
	($was_else? "": "': '")."'), '";
}

# вызывается компиллятор coffee
sub coffee {
	my ($x) = @_;
	utils::write("tmp/x.coffee", $1);
	`coffee -c tmp/x.coffee`;
	die "нет компиллятора coffee" if $?;
	"<script>\n".utils::read("tmp/x.js")."</script>";
}

1;