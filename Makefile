CC=gcc
CFLAGS=-Wall -Werror -g -std=c99
DEPS = stream.h
OBJ = main.o stream.o

glib_cflags = `pkg-config --cflags glib-2.0`
glib_libs = `pkg-config --libs glib-2.0`

%.o: %.c $(DEPS)
	$(CC) $(glib_cflags) -c -o $@ $< $(CFLAGS)

main: $(OBJ)
	$(CC) -o $@ $^ $(glib_cflags) $(CFLAGS) $(glib_libs)

.PHONY: clean

clean:
	rm -f main $(OBJ)
