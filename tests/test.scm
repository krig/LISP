(define cadr (lambda (c) (car (cdr c))))
(define cdar (lambda (c) (cdr (car c))))
(define caar (lambda (c) (car (car c))))
(define cddr (lambda (c) (cdr (cdr c))))
(define caadr (lambda (c) (car (car (cdr c)))))
(define cadar (lambda (c) (car (cdr (car c)))))
(define caaar (lambda (c) (car (car (car c)))))
(define caddr (lambda (c) (car (cdr (cdr c)))))
(define cdadr (lambda (c) (cdr (car (cdr c)))))
(define cddar (lambda (c) (cdr (cdr (car c)))))
(define cdaar (lambda (c) (cdr (car (car c)))))
(define cdddr (lambda (c) (cdr (cdr (cdr c)))))

(define not (lambda (x) (cond ((null? x) #t) (#t #f))))

(define atom? (lambda (x)
  (cond ((null? x) #f)
        ((pair? x) #f)
        (#t #t))))

(define else #t)

(define displayln (lambda (x) (display x) (newline)))

(define assert (lambda (expr expect)
                 (cond ((equal? expr expect)
                        ((lambda () (display (quote pass:_)) (displayln expr))))
                       (else
                        ((lambda () (display (quote fail:_)) (displayln expr)))))))

(define sq (lambda (x) (* x x)))
(assert (sq 3) 9)

(define length (lambda (l) (cond ((null? l) 0) (else (+ 1 (length (cdr l)))))))
(assert (length (quote (1 2 3))) 3)


(displayln (quote fac_15))

(define fac (lambda (n)
              (cond ((equal? n 0) 1)
                    (else (* n (fac (- n 1)))))))

(fac 15)
(assert (fac 15) (quote 1307674368000))


(displayln (quote two-in-a-row?))

(define member? (lambda (a lat)
                  (cond
                   ((null? lat) #f)
                   ((equal? a (car lat)) #t)
                   ((member? a (cdr lat)) #t)
                   (else #f))))

(define is-first? (lambda (a lat)
                    (cond
                     ((null? lat) #f)
                     (else (equal? (car lat) a)))))

(define two-in-a-row? (lambda (lat)
                        (cond
                         ((null? lat) #f)
                         ((is-first? (car lat) (cdr lat)) #t)
                         ((two-in-a-row? (cdr lat)) #t)
                         (else #f))))

(assert (two-in-a-row? (quote (Italian sardines spaghetti parsley))) #f)
(assert (two-in-a-row? (quote (Italian sardines sardines spaghetti parsley))) #t)
(assert (two-in-a-row? (quote (Italian sardines more sardines spaghetti))) #f)


(displayln (quote sum-of-prefixes))

(define sum-of-prefixes-helper
  (lambda (sonssf tup)
    (cond
     ((null? tup) (quote ()))
     (else (cons (+ sonssf (car tup))
                 (sum-of-prefixes-helper
                  (+ sonssf (car tup))
                  (cdr tup)))))))

(define sum-of-prefixes (lambda (tup) (sum-of-prefixes-helper 0 tup)))

(assert (sum-of-prefixes (quote (1 1 1))) (quote (1 2 3)))
(assert (sum-of-prefixes (quote (1 1 1 1 1))) (quote (1 2 3 4 5)))
(assert (sum-of-prefixes (quote (2 1 9 17 0))) (quote (2 3 12 29 29)))


(displayln (quote lisp-in-lisp))

(define pairlis (lambda (x y a)
                  (cond ((null? x) a)
                        (else (cons (cons (car x) (car y))
                               (pairlis (cdr x) (cdr y) a))))))

(define assoc (lambda (x a)
                (cond ((equal? (caar a) x) (car a))
                      (else (assoc x (cdr a))))))

(assert (pairlis (quote (a b c)) (quote (1 2 3)) (quote ())) (quote ((a . 1) (b . 2) (c . 3))))
(assert (assoc (quote x) (quote ((y . 5) (x . 3) (z . 7)))) (quote (x . 3)))

(define atom2 (lambda (x)
                (cond
                 ((null? x) #t)
                 ((atom? x) #t)
                 (else #f))))

(define evcon (lambda (c a)
                (cond
                 ((eval (caar c) a) (eval (cadar c) a))
                 (else (evcon (cdr c) a)))))

(define evlis (lambda (m a)
                (cond
                 ((null? m) #f)
                 (else (cons (eval (car m) a)
                             (evlis (cdr m) a))))))

(assert (evlis (quote ()) (quote ())) #f)

(define apply (lambda (fun x a)
                (cond
                 ((atom2 fun)
                  (cond
                   ((equal? fun (quote CAR)) (caar x))
                   ((equal? fun (quote CDR)) (cdar x))
                   ((equal? fun (quote CONS)) (cons (car x) (cadr x)))
                   ((equal? fun (quote ATOM)) (atom2 (car x)))
                   ((equal? fun (quote EQ)) (equal? (car x) (cadr x)))
                   (else (apply (eval fun a) x a))))

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
                ((atom2 e) (cdr (assoc e a)))
                ((atom2 (car e))
                 (cond
                  ((equal? (car e) (quote QUOTE)) (cadr e))
                  ((equal? (car e) (quote COND)) (evcon (cdr e) a))
                  (else (apply (car e) (evlis (cdr e) a) a))))
                (else (apply (car e) (evlis (cdr e) a) a)))))

(define evalquote (lambda (fn x) (apply fn x (quote ()))))

(assert (eval (quote Y) (quote ((X . 1) (Y . 2) (Z . 3)))) 2)

(assert (eval (quote ((LAMBDA (X) (CAR X)) Z)) (quote ((NIL) (T . #t) (Z . (A B C))))) (quote A))

(assert (eval
         (quote ((LABEL MAPCAR
                        (LAMBDA (FN SEQ)
                                (COND
                                 ((EQ NIL SEQ) NIL)
                                 (T (CONS (FN (CAR SEQ))
                                          (MAPCAR FN (CDR SEQ)))))))
                 DUP
                 LST))
         (quote ((NIL . ())
                 (T . #t)
                 (DUP . (LAMBDA (X) (CONS X X)))
                 (LST . (A B C)))))
        (quote ((A . A) (B . B) (C . C))))
