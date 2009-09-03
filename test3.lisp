(setq list2 '(fn (a b) (const 'a (cons 'b nil))))
(setq list3 '(fn (a b c) (cons 'a (list2 'b 'c))))

(macro 'def '(name args +body)
  '(list3 'setq name (list3 'fn args *body)))

(macro 'def '(name args body..)
       '(list 'setq name (list 'label name (list 'fn args *body))))

(macro 'defmacro '(name args body..)
       '(list 'macro 'name 'args (quote-all *body)))

