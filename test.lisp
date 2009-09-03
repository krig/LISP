"hello world"
(car '("hello world" "goodbye world"))
(cdr '("hello world" "goodbye world"))

((lambda (x) (x '(1 2))) 'car)
((lambda (x) (x '(1 2))) 'cdr)
((label ff (lambda (x) (cond
                         ((atom x) x)
                         (t (ff (car x)))))) '((5 2) 3))
