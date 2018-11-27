.PHONY: all test clean

all: komplott

komplott: komplott.c
	$(CC) -g -Og -Wall -Werror -std=c11 -o $@ komplott.c
	wc -l $^ tests/lisp15.scm

test: komplott tests/test.scm
	time -p ./komplott tests/test.scm
	./komplott tests/lisp15.scm
	./komplott tests/exp.scm

clean:
	rm -f ./komplott
