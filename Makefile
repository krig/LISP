CC=gcc
CFLAGS=-Wall -Werror -g -std=c99
DEPS = stream.h
OBJ = main.o stream.o

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

main: $(OBJ)
	$(CC) -o $@ $^ $(CFLAGS)

.PHONY: clean

clean:
	rm -f main $(OBJ)
