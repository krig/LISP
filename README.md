# komplott

A tribute to:

> Recursive Functions of Symbolic Expressions
> and Their Computation by Machine, Part I

(as found in `paper/recursive.pdf`)

A micro-subset of scheme / the original LISP in a single C file: `komplott.c`

### Features

* Single file implementation.
* Scheme-compliant enough for the test programs to be executable by
  GNU Guile.
* Copying garbage collector based on Cheney's Algorithm.
* Limited tail call optimization (not true TCO; see `tests/true-tco.scm`).
* Near-zero error handling.
* Zero thread safety or security.

*Also includes:*

## `lisp15.scm`

An implementation of the core of LISP 1.5 from 1962

## Instructions

* To build the `komplott` executable, run `make`. The only dependency
  aside from `make` is `gcc`.
  
* To run the LISP 1.5 interpreter and a couple of test cases, run `make lisp15`.

## LISP 1.5

The version presented in the README is slightly tweaked from the one
that can be found in `tests/lisp15.scm` in order to more closely
resemble early LISP rather than scheme: `#t` and `#f` are written as
`t` and `nil`.

``` lisp

(define pairlis (lambda (x y a)
                  (cond ((null? x) a)
                        (t (cons (cons (car x) (car y))
                                 (pairlis (cdr x) (cdr y) a))))))

(define assoc (lambda (x a)
                (cond ((equal? (caar a) x) (car a))
                      (t (assoc x (cdr a))))))

(define atom? (lambda (x)
                (cond
                 ((null? x) t)
                 ((atom? x) t)
                 (t nil))))

(define evcon (lambda (c a)
                (cond
                 ((eval (caar c) a) (eval (cadar c) a))
                 (t (evcon (cdr c) a)))))

(define evlis (lambda (m a)
                (cond
                 ((null? m) nil)
                 (t (cons (eval (car m) a)
                             (evlis (cdr m) a))))))

(define apply (lambda (fun x a)
                (cond
                 ((atom? fun)
                  (cond
                   ((equal? fun (quote CAR)) (caar x))
                   ((equal? fun (quote CDR)) (cdar x))
                   ((equal? fun (quote CONS)) (cons (car x) (cadr x)))
                   ((equal? fun (quote ATOM)) (atom? (car x)))
                   ((equal? fun (quote EQ)) (equal? (car x) (cadr x)))
                   (t (apply (eval fun a) x a))))

                 ((equal? (car fun) (quote LAMBDA))
                  (eval (caddr fun) (pairlis (cadr fun) x a)))

                 ((equal? (car fun) (quote LABEL))
                  (apply
                   (caddr fun)
                   x
                   (cons
                    (cons (cadr fun) (caddr fun))
                    a))))))

(define eval (lambda (e a)
               (cond
                ((atom? e) (cdr (assoc e a)))
                ((atom? (car e))
                 (cond
                  ((equal? (car e) (quote QUOTE)) (cadr e))
                  ((equal? (car e) (quote COND)) (evcon (cdr e) a))
                  (t (apply (car e) (evlis (cdr e) a) a))))
                (t (apply (car e) (evlis (cdr e) a) a)))))

(define evalquote (lambda (fn x) (apply fn x (quote ()))))

```

Here is an example of actual LISP 1.5 code:

``` lisp
((LABEL MAPCAR
        (LAMBDA (FN SEQ)
                (COND
                  ((EQ NIL SEQ) NIL)
                  (T (CONS (FN (CAR SEQ))
                           (MAPCAR FN (CDR SEQ)))))))
 DUP LST)

; where
; DUP -> (LAMBDA (X) (CONS X X))
; LST -> (A B C)
```

> To prevent reading from continuing indefinitely, each packet should end
> with STOP followed by a large number of right parentheses. An unpaired right parenthesis
> will cause a read error and terminate reading.

`STOP )))))))))))))))))`
