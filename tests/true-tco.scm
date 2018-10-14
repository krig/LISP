(define a (lambda (x) (b x)))
(define b (lambda (x) (a x)))
(a #t)
