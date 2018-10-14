(define atom? (lambda (x) (cond ((null? x) #f) ((pair? x) #f) (#t #t))))
(define cadr (lambda (x) (car (cdr x))))
(define displayln (lambda (x) (display x) (newline)))

(displayln (quote hello-world))
(displayln (car (quote (hello-world goodbye-world))))
(displayln (cadr (quote (hello-world goodbye-world))))
(displayln ((lambda (x) (x (quote (1 2)))) car))
(displayln ((lambda (x) (x (quote (1 2)))) cadr))

(define ff (lambda (x)
             (cond
              ((pair? x) (ff (car x)))
              (#t x))))

(define mapcar (lambda (f l)
                 (cond
                  ((null? l) #f)
                  (#t (cons (f (car l)) (mapcar f (cdr l)))))))

(displayln (mapcar ff (quote ((5 2) 3))))
