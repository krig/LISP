(define displayln (lambda (x) (display x) (newline)))

(define assert (lambda (expr expect)
                 (cond ((equal? expr expect)
                        ((lambda () (display (quote pass:_)) (displayln expr))))
                       (else
                        ((lambda () (display (quote fail:_)) (displayln expr)))))))

(define length (lambda (l) (cond ((null? l) 0) (else (+ 1 (length (cdr l)))))))
(assert (length (quote (1 2 3))) 3)

(displayln (quote fac_15))

(define fac (lambda (n)
              (cond ((equal? n 0) 1)
                    (else (* n (fac (- n 1)))))))

(fac 15)
(assert (fac 15) (quote 1307674368000))

