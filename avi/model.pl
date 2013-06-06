
# языки
package language;
$id = "char(2)";
$name = "text";

# связь с namen
package name;

# названия на разных языках
package namen;
$id = bigserial;
$name = *name;
$language = *language;
$iname = "text";

# города, в которых можно что-то приобрести
package city;
$name = *name;

# станции метро
package metro;
$city = *city;
$name = *name;

# пользователи
package usr;
$city = *city;
$metro = *metro;
@phone = qw(bigint 0);
@register = qw(date current_date); # когда добавлен - тип, значение по умолчанию
@news = qw(boolean true);			# присылать новости
@reminder = qw(boolean true);		# присылать уведомления
#$hash = "char(128)";		# пароль захешированный
$passwd = "varchar(255)";	# пароль
$email = "varchar(255)";	# почта
$name = "varchar(255)";		# фио
@addall = ("text", "''");	# выводится во всех товарах

$INDEX = ["email", "passwd"];
@UNIQUE = qw(email passwd);

# каталоги категорий
package catalog;
$name = *name;


# категории товаров
package category;
$catalog = *catalog;
$name = *name;

# товары
package product;
$usr = *usr;
$category = *category;
$cost = "int";
$name = "varchar(255)";
$description = "text";

# фотографии
package img;

# у товара может быть несколько фотографий
package img_proguct;
$id = undef;
$img = *img;
$product = *product;

# расписание пользователя
package timetable;
$usr = *usr;
$point = "smallint"; # день недели 7, час 24, минуты 60: день*24*60+час*60+минута
$place = "varchar(65535)";

# назначенные встречи
package meeting;
$id = undef;
$product = *product;
$timetable = *timetable;


# сообщения к товарам
package msg;
$product = *product;
$usr = *usr;
$msg = "text";

# закладки на товары
package bookmark;
$id = undef;
$product = *product;
$usr = *usr;
