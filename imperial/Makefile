
CFLAGS = -Wall -O2 -lpcre

#$(pcre-config --libs) $(pcre-config --cflags)

im: imperial.c
		flex -o imperial.lex.c -i $<
		gcc $(CFLAGS) -o $@ imperial.lex.c

ex: im
		./im examples/algoritm.im

clean:
		rm -f im *.lex.c