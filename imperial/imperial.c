%{

#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <getopt.h>
#include <string.h>

#include <pcre.h>
#include <gc.h>

enum {SPACE = 128, DECIMAL, DOUBLE, WORD, VAR, IF};

%}

I		[0-9]+
D		{I}?"."{I}
E		({I}|{D})e("+"|"-"){I}
WORD	[a-z_][a-z_0-9]+
A		[a-z]
OP		":"|"<"|">"|"="

%%
\n|\r		return '\n';
[:space:]	return SPACE;
{I}			return DECIMAL;
{E}			return DOUBLE;
{OP}		return *yytext;
if			return IF;
{WORD}		return WORD;
{A}			return VAR;
%%

char* PATH_TO_ROOT = ".";
char* PATH_TO_CACHE = ".cache";
char* OUT_FILE = NULL;


void cc_load_cache(char* file) {
	yyin = fopen(file, "rb");
	if(!yyin) {
		fprintf(stderr, "Файл `%s` не открыт: %s\n", file, strerror(errno));
		exit(errno);
	}
}

int cc_load_from_cache(char* file) {
	char* ext = strrchr(file, '.');

	if(ext) *ext = '\0';
	PATH_TO_ROOT
	 = malloc();
	
	struct stat sta;
	if( stat(file, &sta) == 0 ) {
		if(sta.st_mtime > )
	}
}

void actionRun(char* file) {
	// определяем расширение
	char* ext = strrchr(file, '.');
	if (ext) {	// есть расширение
		if(strcmp(ext+1, "ic")==0) { cc_load_cache(file); cc_run(); return; }	// да это же кеш	
	}

	// пробуем извлечь из кеша
	if(cc_load_from_cache(file)) {
		cc_run();
		return;
	}
	
	yyin = fopen(file, "rb");
	if(!yyin) {
		fprintf(stderr, "Файл `%s` не открыт: %s\n", file, strerror(errno));
		exit(errno);
	}
	
	printf("compile %s\n", file);
	
	printf("compiled in %g sec\n", file);
	
	fclose(yyin);
}

int yywrap() { return 1; }

void actionHelp() {
	printf("This is Imperial programming language\n\n"
	"\n"
	);
}

void actionVersion() {
	printf("Imperial 1.0\n");
}

//extern char *optarg;
//extern int optind, opterr, optopt;

static const char *optString = "ovh";

// optional_argument
static const struct option longOpts[] = {
	{ "out-file", required_argument, NULL, 'o' },
	{ "version", no_argument, NULL, 'v' },
	{ "help", no_argument, NULL, 'h' },
	{ NULL, no_argument, NULL, 0 }
};


int main(int ac, char** av) {
	int opt, longIndex = 0;
	opterr = 0;	// не выводить ошибку
	while((opt = getopt_long( ac, av, optString, longOpts, &longIndex )) != -1) switch(opt) {
		case '?':
			printf("Не распознанная опция `%c`\n", optopt);
			return 0;
		case 'o':
			OUT_FILE = optarg;
			break;
		case 'h':
			actionHelp();
			return 0;
		case 'v':
			actionVersion();
			return 0;
	}
	
	if (optind < ac) {
		while (optind < ac)	actionRun(av[optind++]);
		printf("\n");
	} else {
		fprintf(stderr, "usage: %s [options] <file> [<file>]...\n", av[0]);
		return 1;
	}

	return 0;
}

