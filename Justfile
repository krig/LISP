debug:
  odin build komplott.odin -file -debug -vet -strict-style

test: debug
  ./komplott tests/test.scm
