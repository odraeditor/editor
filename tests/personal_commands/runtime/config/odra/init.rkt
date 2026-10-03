#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require odra/commands)

(define (uppercase-current-line context)
  (define line (command-context-current-line context))
  (command-context-replace!
   context line (string-upcase (command-context-read context line))))

(define (reject-command _context)
  (command-reject 'user "Personal command rejected the request."))

(define (partial-reject-command context)
  (define line (command-context-current-line context))
  (command-context-replace! context line "MUST NOT COMMIT")
  (command-reject 'user "Discard the staged edit."))

(define (wrong-effect-command context)
  (define line (command-context-current-line context))
  (command-context-replace! context line "MUST NOT COMMIT"))

(define (report-command-context context)
  (define region (command-context-active-region context))
  (command-context-message!
   context
   (format "~a|~a|~a|~a"
           (or (command-context-document-path context) "")
           (text-position-offset (command-context-point context))
           (if region (command-context-read context region) "")
           (or (command-context-candidate-selection context) ""))))

(define (candidate-command _context)
  (make-command-candidate-result
   7
   "Ada"
   (list
    (make-command-candidate
     "ada" "Ada Lovelace" '("mathematician" "computing")
     "/tmp/ada.org" 12 24 1))))

(provide odra-personal-commands)

(define odra-personal-commands
  (list
   (make-command
    'personal-uppercase-current-line
    uppercase-current-line
    #:description "Uppercase the current line."
    #:source "init.rkt"
    #:location "5:1")
   (make-command 'personal-no-op (lambda (_context) (void)))
   (make-command 'personal-candidates candidate-command #:effects '(buffer view))
   (make-command 'personal-reject reject-command)
   (make-command 'personal-exception
                 (lambda (_context) (error 'personal-exception "requested failure")))
   (make-command 'personal-invalid-result (lambda (_context) 42))
   (make-command 'personal-partial-reject partial-reject-command)
   (make-command 'personal-wrong-effect wrong-effect-command
                 #:effects '(buffer view))
   (make-command 'personal-report-context report-command-context
                 #:requirements '(active-buffer active-document active-region)
                 #:effects '(buffer view))))
