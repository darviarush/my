#ifndef __STRINGC__H__
#define __STRINGC__H__

#include <gc.h>
#include <type.h>

typedef struct ilet {
	uint32 flags;
	char any[];
} ilet;


typedef struct string {
	
	uint32 length; 
	char* data;
} string;

string* string_new(char* s);	// копирует строку в 
string* string_c(const char* );	// строка

#endif
