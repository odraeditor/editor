#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "../../src/command/catalog.rkt")

(define procedure-entered? #f)

(define (personal-definition name
                             #:description [description "Personal command"]
                             #:source [source "modules/text-commands.rkt"])
  (make-command-definition
   name
   'personal
   'ordinary
   'prohibited
   '(buffer view text-mutation)
   description
   (lambda (_context)
     (set! procedure-entered? #t)
     (void))
   #:requirements '(active-buffer)
   #:provider "personal"
   #:source source))

  (test-case "definitions compose after factory catalog"
  (define candidate
    (compose-personal-command-catalog
     2
     (list (personal-definition "uppercase-selection"))))
  (define definitions (odra-command-catalog-definitions candidate))
  (check-equal? (odra-command-catalog-generation candidate) 2)
  (check-equal? (length definitions) 8)
  (check-equal? (odra-command-definition-name (last definitions))
                "uppercase-selection")
  (check-false procedure-entered?))

(test-case "personal admission preserves logical provenance"
  (define definition (personal-definition "normalize-title"))
  (define source (odra-command-definition-provenance definition))
  (check-equal? (odra-command-source-provider source) "personal")
  (check-equal? (odra-command-source-source source)
                "modules/text-commands.rkt")
  (check-equal? (odra-command-source-location source) ""))

  (test-case "duplicate identities reject candidate"
  (define duplicate (personal-definition "duplicate-command"))
  (check-exn
   #rx"unique"
   (lambda ()
     (compose-personal-command-catalog 2 (list duplicate duplicate)))))

  (test-case "factory collisions reject candidate"
  (check-exn
   #rx"unique"
   (lambda ()
     (compose-personal-command-catalog
      2
      (list (personal-definition "uppercase-current-line"))))))

  (test-case "non-personal definitions reject admission"
  (define definition
    (make-command-definition
     "wrong-provider"
     'transaction
     'ordinary
     'prohibited
     '(buffer)
     "Wrong provider"
     void))
  (check-exn
   #rx"expected personal command definitions"
   (lambda () (compose-personal-command-catalog 2 (list definition)))))

(test-case "improper command sets reject before composition"
  (check-exn
   #rx"personal command list"
   (lambda ()
     (compose-personal-command-catalog
      2
      (cons (personal-definition "improper-command") 'tail)))))

(test-case "personal command count is bounded independently"
  (define admitted
    (for/list ([index (in-range maximum-personal-commands)])
      (personal-definition (format "personal-command-~a" index))))
  (check-equal?
   (length
    (odra-command-catalog-definitions
     (compose-personal-command-catalog 2 admitted)))
   (+ 7 maximum-personal-commands))
  (check-exn
   #rx"exceeds the admitted bound"
   (lambda ()
     (compose-personal-command-catalog
      2
      (cons (personal-definition "one-too-many") admitted)))))

(test-case "definition metadata remains bounded"
  (check-exn
   #rx"invalid bounded command definition"
   (lambda ()
     (personal-definition
      "oversized-description"
      #:description (make-string 257 #\x)))))
