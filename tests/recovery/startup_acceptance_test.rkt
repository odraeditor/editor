#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/system
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for recovery acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define enter (bytes 13))
(define exit-editor (bytes 24 3))
(define discard #"d")
(define cancel (bytes 7))
(define review (bytes-append (bytes 27 120) #"recover-unsaved-work" enter))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (start-editor path environment)
  (define command
    (string-append
     "stty rows 18 cols 100; exec "
     (shell-quote odra-path)
     (if path (string-append " " (shell-quote (path->string path))) "")))
  (parameterize ([current-environment-variables environment])
    (subprocess #f #f #f script-path "-qfec" command "/dev/null")))

(define (collect-output process output input error-output output-result error-result)
  (subprocess-wait process)
  (define output-bytes (channel-get output-result))
  (define error-bytes (channel-get error-result))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (values (subprocess-status process) output-bytes error-bytes))

(define (wait-for-current-checkpoint current-directory [count 1])
  (let loop ([attempt 0])
    (cond
      [(and (directory-exists? current-directory)
            (= count (length (directory-list current-directory))))
       #t]
      [(>= attempt 100) #f]
      [else
       (sleep 0.1)
       (loop (add1 attempt))])))

;; Every phase waits for a newly observed frame, so earlier list output cannot satisfy a cancellation assertion.
(define (exercise-editor path environment marker exercise #:exit-prefix [exit-prefix #""])
  (define-values (process output input error-output) (start-editor path environment))
  (define transcript (open-output-bytes))
  (define (await! expected)
    (define phase (open-output-bytes))
    (wait-for-terminal-readiness!
     'recovery-scope process output input error-output phase #:content-marker expected)
    (define observed (get-output-bytes phase))
    (write-bytes observed transcript)
    observed)
  (define (send! keys)
    (write-bytes keys input)
    (flush-output input))
  (dynamic-wind
   void
   (lambda ()
     (exercise (await! marker) send! await!)
     (define output-result (make-channel))
     (define error-result (make-channel))
     (thread (lambda ()
               (copy-port output transcript)
               (channel-put output-result (get-output-bytes transcript))))
     (thread (lambda () (channel-put error-result (port->bytes error-output))))
     (send! (bytes-append exit-prefix exit-editor discard))
     (check-not-false (sync/timeout 10 process) "editor did not exit after the recovery exercise")
     (define-values (status captured errors)
       (collect-output process output input error-output output-result error-result))
     (check-equal? status 0)
     (check-equal? errors #"")
     captured)
   (lambda ()
     (when (eq? (subprocess-status process) 'running)
       (subprocess-kill process #t)
       (subprocess-wait process))
     (for ([port (in-list (list output error-output))])
       (unless (port-closed? port) (close-input-port port)))
     (unless (port-closed? input) (close-output-port input)))))

(define (checkpoint-snapshot directory)
  (for/hash ([path (in-list (directory-list directory))])
    (values path (file->bytes (build-path directory path)))))

(define temporary-directory
  (make-temporary-file "odra-recovery-acceptance-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define configuration-home (build-path temporary-directory "configuration"))
   (define state-home (build-path temporary-directory "state"))
   (define cache-home (build-path temporary-directory "cache"))
   (define data-home (build-path temporary-directory "data"))
   (for ([directory (in-list (list configuration-home state-home cache-home data-home))])
     (make-directory* directory))
   (define environment (environment-variables-copy (current-environment-variables)))
   (environment-variables-set! environment #"XDG_CONFIG_HOME"
                               (path->bytes configuration-home))
   (environment-variables-set! environment #"XDG_STATE_HOME"
                               (path->bytes state-home))
   (environment-variables-set! environment #"XDG_CACHE_HOME"
                               (path->bytes cache-home))
   (environment-variables-set! environment #"XDG_DATA_HOME"
                               (path->bytes data-home))
   (define project-a (build-path temporary-directory "project-a"))
   (define project-b (build-path temporary-directory "project-b"))
   (define project-c (build-path temporary-directory "project-c"))
   (for ([directory (in-list (list project-a project-b project-c))])
     (make-directory* directory))
   (define source-path (build-path project-a "source-a.txt"))
   (define other-path (build-path project-c "other.txt"))
   (define sibling-path (build-path project-a "sibling.txt"))
   (define source-b (build-path project-b "source-b.txt"))
   (call-with-output-file source-path
     (lambda (output) (display "base\n" output)))
   (for ([path (in-list (list other-path sibling-path source-b))])
     (call-with-output-file path (lambda (output) (display "other-base\n" output))))

   (define-values (first-process first-output first-input first-error)
     (start-editor source-path environment))
   (define first-capture (open-output-bytes))
   (wait-for-terminal-readiness!
    'recovery-checkpoint first-process first-output first-input first-error
    first-capture
    #:content-marker #"source-a.txt")
   (define first-output-result (make-channel))
   (define first-error-result (make-channel))
   (thread
    (lambda ()
      (copy-port first-output first-capture)
      (channel-put first-output-result (get-output-bytes first-capture))))
   (thread (lambda () (channel-put first-error-result (port->bytes first-error))))
   (write-bytes #"draft-" first-input)
   (flush-output first-input)
   (define current-record-directory
     (build-path state-home "odra" "recovery" "v1" "current"))
   (check-true (wait-for-current-checkpoint current-record-directory)
               "modified buffer did not publish a recovery checkpoint")
   (subprocess-kill first-process #t)
   (collect-output first-process first-output first-input first-error
                   first-output-result first-error-result)
   (check-equal? (file->bytes source-path) #"base\n")

   ;; A retained candidate must not interrupt another project, another explicit file, or an untargeted launch.
   (define original-checkpoint (checkpoint-snapshot current-record-directory))
   (for ([scenario (in-list
                   (list (list "unrelated file" other-path #"other.txt" #t)
                         (list "other file in the same directory" sibling-path #"sibling.txt" #t)
                         (list "unrelated directory" project-c #"other.txt" #f)
                         (list "no launch target" #f #"Create a new buffer" #f)))])
     (test-case (car scenario)
       (exercise-editor
        (cadr scenario) environment (caddr scenario)
        (lambda (initial send! await!)
          (check-false (contains? initial #"Restore ("))
          (check-true (contains? initial #"recover-unsaved-work"))
          (when (cadddr scenario)
            (send! review)
            (define global-frame (await! #"Restore ("))
            (check-true (contains? global-frame #"source-a.txt"))
            (send! cancel)
            (define returned (await! (caddr scenario)))
            (check-false (contains? returned #"Restore ("))))
        #:exit-prefix (if (equal? (cadr scenario) project-c) cancel #""))
       (check-equal? (checkpoint-snapshot current-record-directory) original-checkpoint)
       (check-equal? (file->bytes source-path) #"base\n")))

   ;; A directory-selected candidate can be deferred without replacing the requested directory view.
   (test-case "matching directory cancellation"
     (exercise-editor
      project-a environment #"Restore ("
      (lambda (initial send! await!)
        (check-true (contains? initial #"source-a.txt"))
        (send! cancel)
        (check-false (contains? (await! #"sibling.txt") #"Restore (")))
      #:exit-prefix cancel)
     (check-equal? (checkpoint-snapshot current-record-directory) original-checkpoint))

   ;; Source compatibility alone must not make restore-matching import another project's draft.
   (test-case "automatic restore excludes unrelated work"
     (define personal-root (build-path configuration-home "odra"))
     (define init-path (build-path personal-root "init.rkt"))
     (make-directory* personal-root)
     (dynamic-wind
      (lambda ()
        (call-with-output-file init-path
          (lambda (output)
            (display
             (string-append
              "#lang racket/base\n"
              "(require odra/recovery)\n"
              "(provide odra-recovery-policy)\n"
              "(define odra-recovery-policy (recovery-policy #:startup 'restore-matching))\n")
             output))))
      (lambda ()
        (exercise-editor
         other-path environment #"other.txt"
         (lambda (initial send! await!)
           (check-false (contains? initial #"Restore ("))
           (check-false (contains? initial #"draft-base"))
           (send! review)
           (check-true (contains? (await! #"Restore (") #"source-a.txt"))
           (send! cancel)
           (await! #"other.txt")))
        (check-equal? (checkpoint-snapshot current-record-directory) original-checkpoint)
        (check-equal? (file->bytes source-path) #"base\n"))
      (lambda () (when (file-exists? init-path) (delete-file init-path)))))

   ;; Publish a second candidate, then discard only that file while the first remains globally recoverable.
   (define-values (third-process third-output third-input third-error)
     (start-editor source-b environment))
   (define third-capture (open-output-bytes))
   (wait-for-terminal-readiness!
    'recovery-second-checkpoint third-process third-output third-input third-error
    third-capture #:content-marker #"source-b.txt")
   (define third-output-result (make-channel))
   (define third-error-result (make-channel))
   (thread (lambda ()
             (copy-port third-output third-capture)
             (channel-put third-output-result (get-output-bytes third-capture))))
   (thread (lambda () (channel-put third-error-result (port->bytes third-error))))
   (write-bytes #"draft-b-" third-input)
   (flush-output third-input)
   (check-true (wait-for-current-checkpoint current-record-directory 2))
   (subprocess-kill third-process #t)
   (collect-output third-process third-output third-input third-error
                   third-output-result third-error-result)
   (test-case "discard stays within the selected candidate"
     (exercise-editor
      source-b environment #"Restore ("
      (lambda (initial send! await!)
        (check-false (contains? initial #"source-a.txt"))
        ;; Restorable candidates expose Restore, Inspect, Compare, then Discard.
        (send! (bytes-append (bytes 14 14 14) enter))
        (check-false (contains? (await! #"other-base") #"Restore ("))))
     (check-equal? (checkpoint-snapshot current-record-directory) original-checkpoint)
     (check-equal? (file->bytes source-b) #"other-base\n"))

   (define-values (second-process second-output second-input second-error)
     (parameterize ([current-directory project-a])
       (start-editor (string->path "source-a.txt") environment)))
   (define restart-capture (open-output-bytes))
   (wait-for-terminal-readiness!
    'recovery-restart second-process second-output second-input second-error
    restart-capture
    #:content-marker #"Restore")
   (define second-output-result (make-channel))
   (define second-error-result (make-channel))
   (thread
    (lambda ()
      (copy-port second-output restart-capture)
      (channel-put second-output-result (get-output-bytes restart-capture))))
   (thread (lambda () (channel-put second-error-result (port->bytes second-error))))
   (write-bytes (bytes-append enter exit-editor discard) second-input)
   (flush-output second-input)
   (define-values (status output error-output)
     (collect-output second-process second-output second-input second-error
                     second-output-result second-error-result))
   (check-equal? status 0)
   (check-equal? error-output #"")
   (check-true (contains? output #"draft-base"))
   (check-equal? (file->bytes source-path) #"base\n")
   (check-equal? (directory-list current-record-directory) '()))
 (lambda ()
   (when (directory-exists? temporary-directory)
     (delete-directory/files temporary-directory))))
