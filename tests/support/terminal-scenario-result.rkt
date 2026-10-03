#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(provide
 (struct-out terminal-scenario-result)
 (struct-out terminal-scenario-failure)
 classify-terminal-scenario)

(struct terminal-scenario-result
  (completed? process-status output errors restored? cleanup)
  #:transparent)

(struct terminal-scenario-failure (code cleanup process-status) #:transparent)

(define (classify-terminal-scenario result)
  (cond
    [(not (terminal-scenario-result-completed? result))
     (terminal-scenario-failure
      'completion-timeout
      (terminal-scenario-result-cleanup result)
      (terminal-scenario-result-process-status result))]
    [(not (zero? (terminal-scenario-result-process-status result)))
     (terminal-scenario-failure
      'process-failure
      (terminal-scenario-result-cleanup result)
      (terminal-scenario-result-process-status result))]
    [(not (bytes=? (terminal-scenario-result-errors result) #""))
     (terminal-scenario-failure
      'unexpected-stderr
      (terminal-scenario-result-cleanup result)
      (terminal-scenario-result-process-status result))]
    [(not (terminal-scenario-result-restored? result))
     (terminal-scenario-failure
      'terminal-restoration-missing
      (terminal-scenario-result-cleanup result)
      (terminal-scenario-result-process-status result))]
    [else #f]))

(module+ test
  (require rackunit)

  (test-case "timeout retains one primary cause despite cleanup artifacts"
    (define failure
      (classify-terminal-scenario
       (terminal-scenario-result
        #f 137 #"partial output" #"Session terminated, killing shell..."
        #f 'forced-process-termination)))
    (check-eq? (terminal-scenario-failure-code failure) 'completion-timeout)
    (check-eq? (terminal-scenario-failure-cleanup failure)
               'forced-process-termination)
    (check-equal? (terminal-scenario-failure-process-status failure) 137))

  (test-case "completed scenarios retain exact primary failure precedence"
    (check-eq?
     (terminal-scenario-failure-code
      (classify-terminal-scenario
       (terminal-scenario-result #t 9 #"" #"diagnostic" #f 'none)))
     'process-failure)
    (check-eq?
     (terminal-scenario-failure-code
      (classify-terminal-scenario
       (terminal-scenario-result #t 0 #"" #"diagnostic" #f 'none)))
     'unexpected-stderr)
    (check-eq?
     (terminal-scenario-failure-code
      (classify-terminal-scenario
       (terminal-scenario-result #t 0 #"" #"" #f 'none)))
     'terminal-restoration-missing))

  (test-case "successful completion has no failure"
    (check-false
     (classify-terminal-scenario
      (terminal-scenario-result #t 0 #"complete" #"" #t 'none)))))
