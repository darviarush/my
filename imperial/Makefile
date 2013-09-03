
CFLAGS = -Wall -O2 -lpcre

#$(pcre-config --libs) $(pcre-config --cflags)

im: imperial.c
		gcc $(CFLAGS) -o $@ $<

clean:
		rm -f im