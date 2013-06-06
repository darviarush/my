# Cессия. Доступна для всех потоков

package session;

use threads::shared;

use utils;
use cron;
use ini;
$time_clear = $ini::session{time_clear};
$key_length = $ini::session{key_length};


# каждый час %old уничтожается, а %new - становится %old
# таким образом, сессии, которые не были обновлены остануться в %old и будут затёрты
# $key=>[$time, $user_id]
%new :shared = ();
%old :shared = ();

# количество
sub count { scalar keys %new + scalar keys %old }

# добавляет сессию
sub add {
	my ($val) = @_;
	my $key;
	lock(%new);
	lock(%old);
	do { $key = utils::unic_id($key_length); } while(exists $new{$key} or exists $old{$key});
	$new{$key} = shared_clone($val);
	return $key;
}

# проверяет наличие сессии
sub check {
	my ($key) = @_;
	return 1 if exists $new{$key};
	my $val :shared = $old{$key};
	return unless defined $val;
	$new{$key} = $val;
	delete $old{$key};
	return 1;
}

# удаляет сессию
sub erase { my ($key) = @_; lock(%new); lock(%old); delete $new{$key}; delete $old{$key} }

# удаляет просроченные
sub erase_untime {
	lock(%new);
	lock(%old);
	%old = %new;
	%new = ();
}

cron::add($time_clear, "session::erase_untime");

1;