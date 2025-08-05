.PHONY: all test clean loc

all: komplott komplodin loc

loc:
	wc -l komplott.c komplodin.odin tests/lisp15.scm

komplott: komplott.c
	$(CC) -g -Og -Wall -Werror -std=c11 -o $@ komplott.c

komplodin: komplodin.odin
	odin build komplodin.odin -file -debug -vet -strict-style -vet-unused

test: komplott komplodin tests/test.scm tests/exp.scm tests/lisp15.scm
	@time -p ./komplott tests/test.scm
	./komplott tests/lisp15.scm
	./komplott tests/exp.scm
	@time -p ./komplodin tests/test.scm
	./komplodin tests/lisp15.scm
	./komplodin tests/exp.scm

clean:
	rm -f ./komplott ./komplodin
