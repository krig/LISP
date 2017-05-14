# a humble LISP

[![Build Status](https://travis-ci.org/krig/LISP.svg?branch=master)](https://travis-ci.org/krig/LISP)

My attempt to implement an interpreter for the original LISP.

## DEPENDENCIES

* A C99-compatible compiler
* libgc (boehm gc)

## PRIMITIVES

```
x = atom
(x . y) = s-expression
(atom x) -> t IF x is an atom
(atom (x . x)) -> nil

(eq x y) -> t if x and y are both atomic and refer to the same symbol
    (eq x x) => t
    (eq x y) => nil
    (eq x (x . y)) => undefined

(car x) -> defined only if x is not atomic
     (car (e1 . e2)) => e1
     (car (x . a)) => x
     (car ((x . a) . y)) => (x . a)

(cdr x) ->
     (cdr (e1 . e2)) => e2

(cons x y) -> for any x y
      (cons x x) -> (x . x)
      (cons e1 e2) -> (e1 . e2)

(cond (e1 s1) (e2 s2) (e3 s3)) ->
      returns the first sN for which eN evaluates to t

(ff x) ->
    (cond
      ((atom x) x)
      (t (ff (car x))))

(defun (subst x y z)
    "the result of substituting the sexpr x for all
occurrences of the atomic symbol y in the sexpr z"
  (cond
    ((atom z) (cond
                ((eq z y) x)
                (t z)))
    (t (cons (subst x y (car z))
             (subst x y (cdr z))))))

(defun (and x y)
    (cond
      (x y)
      (t nil)))

(defun (or x y)
    (cond
      (x t)
      (t y)))

(defun (not x)
    (cond
      (x nil)
      (t t)))

(defun (weirdo p q)
    (cond
      (p q)
      (t t)))

(defun (equal x y)
    (or (and (atom x) (atom y) (eq x y))
     (and (not (atom x)) (not (atom y))
          (equal (car x) (car y))
          (equal (cdr x) (cdr y)))))

(defun (null x)
    (and (atom x) (eq x nil)))

(defun (cadr x)
    (car (cdr x)))

(defun (caddr x)
    (car (cdr (cdr x))))

;; etc.

(defun (list a b c)
    (cons a (cons b (cons c nil))))

(defun (append x y)
    (cond
      ((null x) y)
      (t (cons (car x)
               (append (cdr x) y)))))

(defun (apply f args)
    (eval (cons f (appq args)) nil))

(defun (appq m)
    (cond
      ((null m) nil)
      (t (cons (list 'quote (car m))
               (appq (cdr m))))))

(defun (eval e a)
    (cond
      ((atom e) (assoc e a))
      ((atom (car e))
       (cond
         ((eq (car e) 'quote) 
```
