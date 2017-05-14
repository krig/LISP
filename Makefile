CC:=gcc
CFLAGS:=-Wall -Werror -g -std=c99 -isystem /usr/local/include
DEPS = stream.h
OBJ = main.o stream.o

ifeq ($(USE_LIBGC), 0)
GCFLAGS = -DUSE_LIBGC=0
LIBS =
else
GCFLAGS = -DUSE_LIBGC=1
LIBS = -lgc
endif


%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS) $(GCFLAGS)

LISP: $(OBJ)
	$(CC) -o $@ $^ $(CFLAGS) $(LIBS) $(GCFLAGS)

.PHONY: clean test

test: LISP
	./LISP test.lisp
	./LISP test2.lisp

clean:
	rm -f LISP $(OBJ)
