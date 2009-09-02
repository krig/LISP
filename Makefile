glib_cflags = `pkg-config --cflags glib-2.0`
glib_libs = `pkg-config --libs glib-2.0`

CC=gcc
CFLAGS=-Wall -Werror -g -std=c99 $(glib_cflags)
DEPS = stream.h
OBJ = main.o stream.o
LIBS = -lgc $(glib_libs)


%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

main: $(OBJ)
	$(CC) -o $@ $^ $(CFLAGS) $(LIBS)

.PHONY: clean

clean:
	rm -f main $(OBJ)
