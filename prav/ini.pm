package ini;

%server = (							# конфигурация сервера
	port => 3000,
	workers => 3,
	user => 'root',					# пользователь, на которого переключится сервер после запуска
	buf_size => 4*1024*1024,		# размер буфера, для выдачи статики
	host => 'my.cc',
	from => 'noreply@',
	test => 1
);
%DBI = (			# конфигурация базы данных
	DNS => 'dbi:Pg:dbname=my',
	user => 'user1',
	password => '%bLamesh%'	#'siKsta'
);
%session = (
	time_clear => 3600,
	key_length => 20
);
