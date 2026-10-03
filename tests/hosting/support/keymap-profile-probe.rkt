#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/command/keymaps.rkt"
         "../../../src/hosting/keymap-profile-bridge.rkt"
         (submod "../../../src/hosting/keymap-profile-bridge.rkt" test-support))

(provide runtime-keymap-profile-batch-probe)

(define (runtime-keymap-profile-batch-probe scenario registry-generation)
  (cond
    [(= scenario 0) (runtime-keymap-profile-batch registry-generation)]
    [(= scenario 2) (list #t registry-generation #"bad" #"")]
    [(= scenario 3)
     (list #t registry-generation (make-bytes (add1 maximum-copy-bytes)) #"")]
    [else
     (with-handlers ([exn?
                      (lambda (failure)
                        (list #f 0 #"" (string->bytes/utf-8 (exn-message failure))))])
       (when (= scenario 1)
         (error 'runtime-keymap-profile-batch-probe "requested profile failure"))
       (when (= scenario 4) (collect-garbage))
       (define batch
         (profile-catalog-batch
          registry-generation
          (if (= scenario 5) 3 schema-version)
          (if (= scenario 9)
              (synthetic-profile-catalog registry-generation)
              (interaction-profile-catalog-candidate registry-generation))))
       (define selected
         (case scenario
           [(6) (batch-with-u64 batch 16 (add1 registry-generation))]
           [(7) (batch-with-u64 batch 40 999)]
           [(8) (subbytes batch 0 (sub1 (bytes-length batch)))]
           [else batch]))
       (list #t registry-generation selected #""))]))

(module+ test
  (require rackunit)
  (check-false (car (runtime-keymap-profile-batch-probe 1 17)))
  (check-equal?
   (caddr (runtime-keymap-profile-batch-probe 2 17))
   #"bad"))
