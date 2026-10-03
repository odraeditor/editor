#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "configuration.rkt")

(define valid-candidate
  '#hasheq((generation . 2)
           (provider-generation . 4)
           (workflows . (#hasheq((identity . default)
                                 (states . (#hasheq((name . "TODO")
                                                    (finished? . #f)
                                                    (key . #\t)
                                                    (presentation . todo)
                                                    (log . state))
                                            #hasheq((name . "DONE")
                                                    (finished? . #t)
                                                    (key . #\d)
                                                    (presentation . done)
                                                    (log . time)))))))
           (source-sets . (#hasheq((identity . agenda)
                                   (sources . (#hasheq((identity . notes)
                                                       (kind . directory)
                                                       (resource . "notes")
                                                       (depth . 4)
                                                       (document-limit . 128)))))))
           (captures . (#hasheq((key . #\t)
                                (label . "Task")
                                (entry-type . task)
                                (target . "inbox.org::* Inbox")
                                (template . "* TODO %?")
                                (immediate-finish? . #f))))
           (agendas . (#hasheq((key . #\w)
                               (label . "Week")
                               (query . "task:unfinished")
                               (span . week)
                               (result-limit . 4096))))))

(test-case "planning configuration copies one generation"
  (define label (string-copy "Task"))
  (define capture (hash-set (car (hash-ref valid-candidate 'captures)) 'label label))
  (define candidate (hash-set valid-candidate 'captures (list capture)))
  (define admitted (admit-planning-configuration candidate 1))
  (string-set! label 0 #\M)
  (check-equal? (hash-ref admitted 'generation) 2)
  (check-equal? (hash-ref admitted 'provider-generation) 4)
  (check-equal? (hash-ref (car (hash-ref admitted 'workflows)) 'identity) 'default)
  (check-equal? (hash-ref (car (hash-ref admitted 'captures)) 'label) "Task"))

(test-case "stale and conflicting generations reject wholly"
  (check-false (admit-planning-configuration valid-candidate 2))
  (define duplicate
    (hash-set valid-candidate
              'captures
              (list (car (hash-ref valid-candidate 'captures))
                    (car (hash-ref valid-candidate 'captures)))))
  (check-false (admit-planning-configuration duplicate 1)))

(test-case "source and agenda limits remain bounded"
  (define bad-source
    '#hasheq((identity . root)
             (kind . directory)
             (resource . "/")
             (depth . 65)
             (document-limit . 1024)))
  (define invalid
    (hash-set valid-candidate
              'source-sets
              (list (hasheq 'identity 'bad 'sources (list bad-source)))))
  (check-false (admit-planning-configuration invalid 1))
  (define agenda (car (hash-ref valid-candidate 'agendas)))
  (check-false
   (admit-planning-configuration
    (hash-set valid-candidate 'agendas
              (list (hash-set agenda 'result-limit 65537)))
    1)))
