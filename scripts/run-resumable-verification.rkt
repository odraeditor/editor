#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/file
         racket/list
         racket/match
         racket/path
         racket/string
         racket/system)

(define state-version 1)

(define (fresh-state)
  (hasheq 'version state-version
          'status 'in-progress
          'passed '()
          'failed #f))

(define (valid-state? value)
  (and (hash? value)
       (equal? (hash-ref value 'version #f) state-version)
       (memq (hash-ref value 'status #f) '(in-progress complete))
       (let ([passed (hash-ref value 'passed #f)])
         (and (list? passed) (andmap string? passed)))
       (let ([failed (hash-ref value 'failed #f)])
         (or (not failed) (string? failed)))))

(define (read-state path)
  (with-handlers ([exn:fail? (lambda (_) (fresh-state))])
    (if (file-exists? path)
        (let ([value (call-with-input-file path read)])
          (if (valid-state? value) value (fresh-state)))
        (fresh-state))))

(define (write-state path value)
  (define parent (path-only path))
  (when parent (make-directory* parent))
  (call-with-output-file path
    (lambda (output)
      (write value output)
      (newline output))
    #:exists 'truncate/replace))

(define (prepare-state path)
  (define current (read-state path))
  (define prepared
    (if (eq? (hash-ref current 'status) 'complete)
        (fresh-state)
        current))
  (write-state path prepared)
  prepared)

(define (complete-state path)
  (define current (read-state path))
  (define completed
    (hash-set* current
               'status 'complete
               'failed #f))
  (write-state path completed)
  completed)

(define (reset-state path)
  (when (file-exists? path) (delete-file path)))

(define (step-passed? state name)
  (and (member name (hash-ref state 'passed)) #t))

(define (make-dry-run? [flags (getenv "MAKEFLAGS")])
  (and flags
       (and (for/or ([token (in-list (string-split flags))])
              (or (member token '("--dry-run" "--just-print" "--recon"))
                  (regexp-match? #px"^-?[A-Za-z]*n[A-Za-z]*$" token)))
            #t)))

(define (record-step-pass path state name)
  (define passed (hash-ref state 'passed))
  (define updated
    (hash-set* state
               'status 'in-progress
               'passed (if (member name passed) passed (append passed (list name)))
               'failed #f))
  (write-state path updated)
  updated)

(define (record-step-failure path state name)
  (define updated
    (hash-set* state
               'status 'in-progress
               'failed name))
  (write-state path updated)
  updated)

(define (run-command arguments)
  (unless (pair? arguments)
    (raise-user-error 'verify-resume "a command is required after --"))
  (define executable (find-executable-path (car arguments)))
  (unless executable
    (raise-user-error 'verify-resume "command is unavailable: ~a" (car arguments)))
  (apply system* executable (cdr arguments)))

(define (run-step path name command)
  (define state (read-state path))
  (cond
    [(make-dry-run?)
     (printf "verify-resume: dry-run ~a\n" name)
     #t]
    [(step-passed? state name)
     (printf "verify-resume: skip ~a\n" name)
     #t]
    [else
     (printf "verify-resume: run ~a\n" name)
     (flush-output)
     (define passed? (run-command command))
     (if passed?
         (begin
           (record-step-pass path state name)
           (printf "verify-resume: pass ~a\n" name)
           #t)
         (begin
           (record-step-failure path state name)
           (eprintf "verify-resume: fail ~a\n" name)
           #f))]))

(module+ main
  (define state-path #f)
  (define action #f)
  (define step-name #f)
  (define command '())
  (command-line
   #:program "run-resumable-verification.rkt"
   #:once-each
   [("--state") path "State file under the build directory"
                  (set! state-path (string->path path))]
   [("--prepare") "Prepare a new run or continue an incomplete one"
                    (set! action 'prepare)]
   [("--complete") "Mark the current run complete"
                     (set! action 'complete)]
   [("--reset") "Discard resumable verification state"
                  (set! action 'reset)]
   [("--step") name "Run or skip one named verification step"
                   (set! action 'step)
                   (set! step-name name)]
   #:args remaining
   (set! command (if (and (pair? remaining) (string=? (car remaining) "--"))
                     (cdr remaining)
                     remaining)))
  (unless state-path
    (raise-user-error 'verify-resume "--state is required"))
  (case action
    [(prepare)
     (define state (prepare-state state-path))
     (printf "verify-resume: ready with ~a passed step(s)\n"
             (length (hash-ref state 'passed)))]
    [(complete)
     (define state (complete-state state-path))
     (printf "verify-resume: complete with ~a passed step(s)\n"
             (length (hash-ref state 'passed)))]
    [(reset)
     (reset-state state-path)
     (printf "verify-resume: reset\n")]
    [(step)
     (unless step-name
       (raise-user-error 'verify-resume "--step requires a name"))
     (unless (run-step state-path step-name command) (exit 1))]
    [else
     (raise-user-error 'verify-resume
                       "one of --prepare, --complete, --reset, or --step is required")]))

(module+ test
  (require rackunit)

  (define (call-with-temporary-state procedure)
    (define temporary-directory
      (make-temporary-file "odra-verify-resume-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (procedure (build-path temporary-directory "state.rktd")))
      (lambda () (delete-directory/files temporary-directory))))

  (test-case "incomplete run preserves step outcomes"
    (call-with-temporary-state
     (lambda (state-path)
       (define initial (prepare-state state-path))
       (check-equal? (hash-ref initial 'passed) '())
       (define first-pass (record-step-pass state-path initial "first"))
       (check-true (step-passed? first-pass "first"))
       (define failed (record-step-failure state-path first-pass "second"))
       (check-equal? (hash-ref failed 'failed) "second")
       (define resumed (prepare-state state-path))
       (check-true (step-passed? resumed "first"))
       (check-false (step-passed? resumed "second"))
       (define second-pass (record-step-pass state-path resumed "second"))
       (check-false (hash-ref second-pass 'failed)))))

  (test-case "completed and invalid state start clean"
    (call-with-temporary-state
     (lambda (state-path)
       (define initial (prepare-state state-path))
       (complete-state state-path)
       (define restarted (prepare-state state-path))
       (check-equal? (hash-ref restarted 'passed) '())
       (call-with-output-file state-path
         (lambda (output) (display "not valid state" output))
         #:exists 'truncate/replace)
       (check-equal? (hash-ref (read-state state-path) 'passed) '())
       (reset-state state-path)
       (check-false (file-exists? state-path)))))

  (test-case "step execution skips success and retries failure"
    (call-with-temporary-state
     (lambda (state-path)
       (define racket-executable
         (path->string (find-executable-path "racket")))
       (check-true
        (run-step state-path
                  "success"
                  (list racket-executable "-e" "(void)")))
       (check-true
        (run-step state-path
                  "success"
                  (list racket-executable "-e" "(exit 9)")))
       (check-false
        (run-step state-path
                  "retry"
                  (list racket-executable "-e" "(exit 7)")))
       (check-true
        (run-step state-path
                  "retry"
                  (list racket-executable "-e" "(void)"))))))

  (test-case "Make dry runs never execute or record a step"
    (check-true (make-dry-run? "n"))
    (check-true (make-dry-run? "-kn"))
    (check-true (make-dry-run? "--dry-run"))
    (check-false (make-dry-run? "j12 --jobserver-auth=3,4"))
    (call-with-temporary-state
     (lambda (state-path)
       (parameterize ([current-environment-variables
                       (environment-variables-copy
                        (current-environment-variables))])
         (putenv "MAKEFLAGS" "n")
         (check-true
          (run-step state-path "dry-run" (list "command-must-not-exist")))
         (check-false (step-passed? (read-state state-path) "dry-run")))))))
