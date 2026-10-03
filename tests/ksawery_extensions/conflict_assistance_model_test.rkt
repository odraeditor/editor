#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/api.rkt"
         (only-in "../../src/command/ksawery-conflict-assistance.rkt"
                  encode-ksawery-conflict-provider
                  encode-ksawery-conflict-response
                  encode-ksawery-conflict-selection-change))

(define (word encoded index)
  (integer-bytes->integer encoded #f #f (* index 8) (* (add1 index) 8)))

(define (words . values)
  (apply bytes-append
         (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))

(define role-contribution
  (make-ksawery-contribution
   7 'conflict.helper 'provider-role
   #:provider-role 'conflict-assistance
   #:observations '(status sequence conflict process)
   #:authorities '(inspect present submit-external-operation assist-conflict)))
(define operation-contribution
  (make-ksawery-contribution
   9 'conflict.tool 'external-operation
   #:observations '(status sequence conflict process)
   #:authorities '(inspect submit-external-operation)))
(define contributor
  (make-ksawery-contributor
   'personal.conflict-tools "Conflict tools" "modules/conflict-tools.rkt" 5
   (list role-contribution operation-contribution)))
(define provider
  (make-ksawery-conflict-provider
   contributor 7 11 13 'conflict.helper "Conflict helper"
   '(text delete missing-stage)
   '(present-guidance open-editor submit-external-tool)
   #:lifecycle 'active))

(define provider-encoded (encode-ksawery-conflict-provider provider))
(check-equal? (word provider-encoded 0) 1)
(check-equal? (word provider-encoded 1) (bytes-length provider-encoded))
(check-equal? (word provider-encoded 2) 2)
(check-equal? (word provider-encoded 3) 5)
(check-equal? (word provider-encoded 4) 7)
(check-equal? (word provider-encoded 5) 11)
(check-equal? (word provider-encoded 6) 13)
(check-equal? (word provider-encoded 7) #b10010010)
(check-equal? (word provider-encoded 8) #b111)
(check-equal? (word provider-encoded 9) 4)

(define selected
  (make-ksawery-conflict-selection-change
   'select 17 0 19 'repository #:provider provider
   #:repository "/tmp/odra-conflict-assistance"))
(define selected-encoded (encode-ksawery-conflict-selection-change selected))
(check-equal? (word selected-encoded 2) 1)
(check-equal? (word selected-encoded 4) 0)
(check-equal? (word selected-encoded 5) 19)
(check-equal? (word selected-encoded 6) 4)
(check-equal? (word selected-encoded 7) 2)
(check-equal? (word selected-encoded 16) 1)

(define replaced
  (make-ksawery-conflict-selection-change
   'replace 17 19 23 'session #:provider provider #:session 29))
(check-equal? (word (encode-ksawery-conflict-selection-change replaced) 2) 2)
(define disabled
  (make-ksawery-conflict-selection-change
   'disable 17 23 31 'global))
(define disabled-encoded (encode-ksawery-conflict-selection-change disabled))
(check-equal? (word disabled-encoded 2) 3)
(check-equal? (word disabled-encoded 7) 1)
(check-equal? (word disabled-encoded 9) 1)
(check-equal? (word disabled-encoded 16) 0)

(define diagnostic
  (make-ksawery-conflict-diagnostic 'provider-declined "Unsupported conflict"))
(define guidance
  (make-ksawery-conflict-guidance
   37 provider "Compare Base and Current." #:diagnostic diagnostic))
(define guidance-encoded (encode-ksawery-conflict-response guidance))
(check-equal? (word guidance-encoded 2) 37)
(check-equal? (word guidance-encoded 5) 2)
(check-true (positive? (word guidance-encoded 8)))
(check-equal? (word guidance-encoded 11) 21)

(define plan
  (make-ksawery-operation-plan
   contributor 9 41 'conflict.tool "Inspect conflict" 43
   (make-ksawery-operation-git) '("diff" "--cc")
   'repository-mutating '(status sequence conflict process)
   (make-ksawery-operation-verifier 'none)
   #:diagnostic-policy 'suppressed))
(define tool
  (make-ksawery-conflict-tool-proposal 47 provider 'worktree-only plan))
(define tool-encoded (encode-ksawery-conflict-response tool))
(check-equal? (word tool-encoded 5) 4)
(check-equal? (word tool-encoded 6) 2)
(check-true (positive? (word tool-encoded 10)))

(define repository #"/tmp/odra-conflict-assistance")
(define path #"src/example.odin")
(define base-object #"1111111111111111111111111111111111111111")
(define current-object #"2222222222222222222222222222222222222222")
(define base-content #"base")
(define current-content #"current")
(define worktree-content #"worktree")
(define repository-offset 0)
(define path-offset (+ repository-offset (bytes-length repository)))
(define base-object-offset (+ path-offset (bytes-length path)))
(define current-object-offset (+ base-object-offset (bytes-length base-object)))
(define base-content-offset (+ current-object-offset (bytes-length current-object)))
(define current-content-offset (+ base-content-offset (bytes-length base-content)))
(define worktree-content-offset (+ current-content-offset (bytes-length current-content)))
(define payload
  (bytes-append repository path base-object current-object
                base-content current-content worktree-content))
(define observation
  (bytes-append
   (words 1 (+ 160 (* 4 64) (bytes-length payload))
          53 59 61 67 71 73 4 #b10010010 4 (bytes-length payload)
          repository-offset (bytes-length repository)
          path-offset (bytes-length path) 0 0 0 0)
   (words 1 2 #o100644 base-object-offset (bytes-length base-object)
          base-content-offset (bytes-length base-content) 0)
   (words 2 2 #o100644 current-object-offset (bytes-length current-object)
          current-content-offset (bytes-length current-content) 0)
   (words 3 1 0 0 0 0 0 0)
   (words 4 2 #o100644 0 0 worktree-content-offset (bytes-length worktree-content) 0)
   payload))
(define decoded (decode-ksawery-conflict-observation observation))
(check-equal? (ksawery-conflict-target-classes
               (ksawery-conflict-observation-target decoded))
              '(text delete missing-stage))
(check-equal? (map ksawery-conflict-side-kind
                   (ksawery-conflict-observation-sides decoded))
              '(base current applied worktree))
(check-equal? (map ksawery-conflict-side-material
                   (ksawery-conflict-observation-sides decoded))
              '(text text missing text))

(check-exn #rx"contribution does not admit"
           (lambda ()
             (make-ksawery-conflict-provider
              contributor 9 11 13 'conflict.invalid "Invalid"
              '(text) '(present-guidance))))
(check-exn #rx"selection generations are inconsistent"
           (lambda ()
             (make-ksawery-conflict-selection-change
              'replace 17 19 19 'global #:provider provider)))
(check-exn #rx"invalid or oversized public text"
           (lambda ()
             (make-ksawery-conflict-guidance 37 provider "unsafe\u001btext")))
