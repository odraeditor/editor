#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base)

(provide
 (contract-out
  [command-inspection-request
   (-> exact-nonnegative-integer? exact-nonnegative-integer?
       exact-nonnegative-integer? list?)]
  [command-transform
   (-> exact-nonnegative-integer? exact-nonnegative-integer?
       exact-nonnegative-integer? exact-nonnegative-integer?
       exact-nonnegative-integer? bytes? list?)]
  [command-uppercase-current-line
   (-> exact-positive-integer? exact-positive-integer?
       exact-nonnegative-integer? exact-nonnegative-integer?
       exact-nonnegative-integer? bytes? list?)]
  [uppercase-current-line (-> bytes? bytes?)]))

;; command-inspection-request asks Odin for the proof command's bounded source range.
(define (command-inspection-request capability buffer-id revision)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 0
                           (string->bytes/utf-8 (exn-message failure))))])
    (unless (and (positive? capability) (positive? buffer-id))
      (error 'command-inspection-request "invalid command capability"))
    (set! retained-capability capability)
    (void revision)
    (list #t 6 10 #"")))

;; The proof retains only the opaque scalar wrapper; Odin still owns explicit release.
(define retained-capability #f)

;; uppercase-current-line transforms one valid UTF-8 copy and owns no editor state.
(define (uppercase-current-line source)
  (string->bytes/utf-8 (string-upcase (bytes->string/utf-8 source))))

;; command-uppercase-current-line echoes checked production turn identity.
(define (command-uppercase-current-line
         capability buffer-id revision start end source)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 0 0 0 0 #""
                           (string->bytes/utf-8 (exn-message failure))))])
    (unless (= (- end start) (bytes-length source))
      (error 'uppercase-current-line "inspection length mismatch"))
    (list #t capability buffer-id revision start end
          (uppercase-current-line source) #"")))

;; command-transform computes a replacement request from an Odin-owned byte copy.
(define (command-transform capability buffer-id revision start end source)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 0 0 0 0 #""
                           (string->bytes/utf-8 (exn-message failure))))])
    (unless (= (- end start) (bytes-length source))
      (error 'command-transform "inspection length mismatch"))
    (list #t capability buffer-id revision start end
          (uppercase-current-line source) #"")))

(module+ test
  (require rackunit)

  (check-equal? (command-inspection-request 1 9 0) '(#t 6 10 #""))
  (check-equal? (command-transform 1 9 0 6 10 #"odra")
                '(#t 1 9 0 6 10 #"ODRA" #""))
  (check-equal? (uppercase-current-line #"") #"")
  (check-equal? (uppercase-current-line #"hello odra") #"HELLO ODRA")
  (check-equal? (uppercase-current-line (string->bytes/utf-8 "straße λódź"))
                (string->bytes/utf-8 "STRASSE ΛÓDŹ"))
  (check-exn exn:fail:contract?
             (lambda () (uppercase-current-line #"\377")))
  (check-equal? (command-uppercase-current-line 1 9 0 0 4 #"odra")
                '(#t 1 9 0 0 4 #"ODRA" #"")))
