#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file)

(provide write-legacy-project-record)

(define (write-legacy-project-record legacy-root id name roots trusts)
  (define projects-root (build-path legacy-root "projects"))
  (make-directory* projects-root)
  (call-with-output-file
   (build-path projects-root (string-append id ".rkt"))
   (lambda (output)
     (display "#lang odra/config\n\n(project\n  #:format-version 1" output)
     (display "\n  #:id " output)
     (write id output)
     (display "\n  #:generation 1\n  #:name " output)
     (write name output)
     (display "\n  #:directories\n  (list" output)
     (for ([root (in-list roots)]
           [trust (in-list trusts)]
           [index (in-naturals 1)])
       (display "\n    (project-directory\n      #:id " output)
       (write (format "root-~a" index) output)
       (display "\n      #:path " output)
       (write (path->string root) output)
       (display "\n      #:trust '" output)
       (display trust output)
       (display ")" output))
     (display "))\n" output))
   #:exists 'truncate/replace
   #:permissions #o600))
