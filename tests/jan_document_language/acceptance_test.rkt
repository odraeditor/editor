#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/port
         racket/system
         rackunit)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Jan acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (run-scenario name suffix source actions)
  (define document-path
    (make-temporary-file (string-append "odra-jan-" name "-~a" suffix)))
  (define home-path (make-temporary-file "odra-jan-home-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file
      document-path
      #:exists 'truncate/replace
      (lambda (output) (write-bytes source output)))
     (define command
       (string-append
        "stty rows 22 cols 132; exec env -u NO_COLOR TERM=xterm-256color "
        "COLORTERM=truecolor HOME="
        (shell-quote (path->string home-path))
        " XDG_CONFIG_HOME="
        (shell-quote (path->string home-path))
        " "
        (shell-quote odra-path)
        " "
        (shell-quote (path->string document-path))))
     (define-values (process output input error-output)
       (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
     (define transcript-box (box #""))
     (define reader
       (thread (lambda () (set-box! transcript-box (port->bytes output)))))
     (define input-open? #t)
     (define (send bytes [pause 0.3])
       (when input-open?
         (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
           (write-bytes bytes input)
           (flush-output input)))
       (sleep pause))
     (sleep 1.0)
     (actions send document-path)
     (define exited? (sync/timeout 12 process))
     (unless exited? (subprocess-kill process #t))
     (subprocess-wait process)
     (thread-wait reader)
     (define transcript (unbox transcript-box))
     (define errors (port->bytes error-output))
     (close-output-port input)
     (close-input-port output)
     (close-input-port error-output)
     (define diagnostic-start (max 0 (- (bytes-length transcript) 4096)))
     (check-not-false exited? name)
     (check-equal?
      (subprocess-status process)
      0
      (string-append
       name
       "\n"
       (bytes->string/utf-8 (subbytes transcript diagnostic-start) #\?)))
     (check-equal? errors #"" name)
     (check-true (contains? transcript #"\33[?25h\33[?2026l") name)
     (values transcript (file->bytes document-path)))
   (lambda ()
     (when (file-exists? document-path) (delete-file document-path))
     (when (directory-exists? home-path) (delete-directory/files home-path)))))

(define document-source
  (bytes-append
   #"#+TiTlE: Fidelity\r\n"
   (string->bytes/utf-8 "* TODO λ heading\r\n")
   #"  Indented body with [[https://example.test][link]].\r\n"
   #"#+unknown_form: retained exactly\r\n"
   #"#+begin_src odin\r\n"
   #"main :: proc() {}\r\n"))

;; The running editor exposes every Stage 1 command, refreshes after an edit,
;; reports bounded future-stage state, and saves the original bytes unchanged.
(define-values (org-output org-saved)
  (run-scenario
   "workflow"
   ".org"
   document-source
   (lambda (send _path)
     (send #"\33xjan-inspect-syntax\r" 0.5)
     (send #"\33xjan-lint\r" 0.5)
     (send #"\33xjan-language-status\r" 0.7)
     (send #"q" 1.0)
     (send #"Z" 0.4)
     (send #"\33xjan-lint-refresh\r" 0.5)
     (send #"\33xjan-inspect-syntax\r" 0.5)
     (send (bytes 31) 0.4)
     (send (bytes 24 19) 0.4)
     (send (bytes 24 3) 0))))

(check-equal? org-saved document-source)
(check-true (contains? org-output #"Z#+TiTlE: Fidelity"))
(check-true (contains? org-output #"Jan syntax: path="))
(check-true (contains? org-output #"Jan lint: diagnostics="))
(check-true (contains? org-output #"jan-lint-refresh"))
(check-true (contains? org-output #"\33[38;2;"))
(check-true (contains? org-output #"Language: jan"))
(check-true (contains? org-output #"Provider: factory-jan-tree-sitter"))
(check-true
 (contains? org-output #"Baseline: jan-org-9.8.10-v1 syntax=Org Syntax v2 future-stage-capabilities=0"))
(check-true (contains? org-output #"Jan limits: source="))
(check-true (contains? org-output #"revision=1"))

;; The identical `.jan` source selects the same provider and keeps the same
;; bytes, including CRLF, Unicode, casing, indentation, and unknown forms.
(define-values (jan-output jan-saved)
  (run-scenario
   "suffix-parity"
   ".jan"
   document-source
   (lambda (send _path)
     (send #"\33xjan-language-status\r" 0.7)
     (send #"q" 1.0)
     (send (bytes 24 19) 0.4)
     (send (bytes 24 3) 0))))

(check-equal? jan-saved document-source)
(check-true (contains? jan-output #"Language: jan"))
(check-true (contains? jan-output #"Provider: factory-jan-tree-sitter"))
(check-true (contains? jan-output #"Parser: lifecycle=Ready status=Current"))
