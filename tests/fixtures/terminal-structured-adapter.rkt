#lang racket/base

(require racket/match)

(file-stream-buffer-mode (current-output-port) 'none)

(define (emit-frame value)
  (write-byte #x1e)
  (display value)
  (write-byte #x1f)
  (newline)
  (flush-output))

(displayln "human:ready")
(emit-frame "ODRA/1 response 0 ready")
(emit-frame "ODRA/1 malformed")

(for ([line (in-lines)])
  (match (regexp-match #px"^request ([0-9]+) (.*)$" line)
    [(list _ identity payload)
     (displayln (string-append "human:request:" payload))
     (emit-frame (string-append "ODRA/1 response " identity " " payload))]
    [_
     (cond
       [(string=? line "quit")
        (displayln "human:closed")
        (emit-frame "ODRA/1 response 0 closed")
        (exit 0)]
       [else
        (displayln "human:invalid-request")
        (emit-frame "ODRA/1 error 0 invalid-request")])]))
