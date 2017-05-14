(setq cadr '(fn (x) (car (cdr x))))

"hello world"
(car '("hello world" "goodbye world"))
(cadr '("hello world" "goodbye world"))

((fn (x) (x '(1 2))) 'car)
((fn (x) (x '(1 2))) 'cdr)
((label ff (fn (x) (cond
                     ((atom x) x)
                     (t (ff (car x)))))) '((5 2) 3))
