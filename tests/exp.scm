(define exp (lambda (base pow)
              (cond ((equal? pow 0) 1)
                    (#t (* base (exp base (- pow 1)))))))

(define displayln (lambda (x)
                    (display x)
                    (newline)))

(define main (lambda ()
               (displayln (exp 2 16))))

(main)
