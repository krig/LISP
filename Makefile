CC=gcc
CFLAGS=-Wall -g

main: main.o stream.o

clean:
	rm -f main *.o
