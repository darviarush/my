#include <stdio.h>
#include <unistd.h>
#include <getopt.h>
#include <string.h>
#include <pcre.h>

pcre* [];

void initRegex() {
	pcre_compile(const char *pattern, int options, const char **errptr, int *erroffset, const unsigned char *tableptr);
}


void actionHelp() {
	printf("This is Imperial programming language\n\n"
	"usage: \n"
	);
}

void actionVersion() {
	printf("Imperial 1.0\n");
}

//extern char *optarg;
//extern int optind, opterr, optopt;

static const char *optString = "vh";

static const struct option longOpts[] = {
    { "version", no_argument, NULL, 'v' },
    { "help", no_argument, NULL, 'h' },
    { NULL, no_argument, NULL, 0 }
};


int main(int ac, char** av) {
	int opt, longIndex = 0;
	while((opt = getopt_long( ac, av, optString, longOpts, &longIndex )) != -1) switch(opt) {
		case '?':
			printf("exit\n");
			return 0;
		case 'h':
			actionHelp();
			return 0;
		case 'v':
			actionVersion();
			return 0;
	}
	
	if (optind < ac) {
        while (optind < ac)
            printf("%s ", av[optind++]);
        printf("\n");
    }
	
	return 0;
}

