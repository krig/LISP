CC:=gcc
CFLAGS:=-Wall -Werror -g -std=c99 -isystem /usr/local/include
DEPS = stream.h
OBJ = main.o stream.o
LIBS = -lgc


%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

main: $(OBJ)
	$(CC) -o $@ $^ $(CFLAGS) $(LIBS)

.PHONY: clean

clean:
	rm -f main $(OBJ)
