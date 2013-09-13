
CFLAGS = -Wall -O2 -lpcre -lgc

#$(pcre-config --libs) $(pcre-config --cflags)

im: imperial.c
		flex -o o/imperial.lex.c -i $<
		gcc $(CFLAGS) -o $@ o/imperial.lex.c

ex: im
		./im examples/manual.im

clean:
		rm -f im o/*
