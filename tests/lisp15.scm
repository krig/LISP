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
(define atom? (lambda (x) (cond ((null? x) #f) ((pair? x) #f) (#t #t))))
(define else #t)

(define assert (lambda (expr expect)
                 (display (cond ((equal? expr expect) (quote pass:_)) (else (quote fail:_))))
                 (display expr)
                 (newline)))

(define pairlis (lambda (x y a)
                  (cond ((null? x) a)
                        (else (cons (cons (car x) (car y))
                               (pairlis (cdr x) (cdr y) a))))))

(define assoc (lambda (x a)
                (cond ((equal? (caar a) x) (car a))
                      (else (assoc x (cdr a))))))

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

(assert (pairlis (quote (a b c)) (quote (1 2 3)) (quote ())) (quote ((a . 1) (b . 2) (c . 3))))
(assert (assoc (quote x) (quote ((y . 5) (x . 3) (z . 7)))) (quote (x . 3)))
(assert (evlis (quote ()) (quote ())) #f)
(assert (eval (quote Y) (quote ((X . 1) (Y . 2) (Z . 3)))) 2)
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
(assert (evalquote (quote (LAMBDA (X Y) (CONS (CAR X) Y))) (quote ((A B) (C D)))) (quote (A C D)))
