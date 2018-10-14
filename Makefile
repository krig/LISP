SRC = komplott.c

.PHONY: all test lisp15 clean opt

all: komplott

komplott: $(SRC)
	$(CC) -g -Og -Wall -Werror -std=c11 -o $@ $(SRC)
	wc -l $^ tests/lisp15.scm

komplott.opt: $(SRC)
	$(CC) -O2 -Wall -Werror -std=c11 -o $@ $(SRC)

opt: komplott.opt

lisp15: komplott lisp15.scm
	./komplott lisp15.scm

test: komplott tests/test.scm
	time -p ./komplott tests/test.scm
	./komplott tests/lisp15.scm
	./komplott tests/exp.scm

clean:
	rm -f ./komplott ./komplott.opt
