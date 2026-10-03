#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/file
         racket/list
         racket/port
         racket/string
         racket/system
         "vendor/canonical-json.rkt")

(provide source-observation environment-observation input-observation
         pressure-observation resource-observation)

;; Probe failures are absent observations. Never retain raw stderr or paths.
(define (probe executable . arguments)
  (define binary (find-executable-path executable))
  (define deadline (find-executable-path "timeout"))
  (and binary deadline
       (let ()
         (define discard (open-output-file "/dev/null" #:exists 'append))
         (define-values (process output input _errors)
           (apply subprocess #f #f discard deadline "--foreground" "--kill-after=1s" "5s"
                  binary arguments))
         (close-output-port discard)
         (close-output-port input)
         (define data (read-bytes 16384 output))
         (define bounded? (eof-object? (peek-byte output)))
         (unless bounded? (subprocess-kill process #t))
         (close-input-port output)
         (subprocess-wait process)
         (and bounded? (zero? (subprocess-status process))
              (if (eof-object? data) ""
                  (string-trim (bytes->string/utf-8 data #\?)))))))

(define (source-observation repository-root expected-commit ref)
  (define commit (probe "git" "-C" repository-root "rev-parse" "HEAD"))
  (define tree (probe "git" "-C" repository-root "rev-parse" "HEAD^{tree}"))
  (define changes (probe "git" "-C" repository-root "status" "--porcelain" "--untracked-files=no"))
  (unless (and commit tree (equal? commit expected-commit) (equal? changes "")
               (regexp-match? #px"^[0-9a-f]{40,64}$" tree)
               (regexp-match? #px"^[A-Za-z0-9._/-]{1,160}$" ref))
    (raise-user-error 'native-evidence "source identity is not the expected clean checkout"))
  (hasheq 'repository "odra/odra" 'commit commit 'tree tree 'ref ref 'dirty #f))

(define (safe-version value)
  (and value (<= (string-length value) 160)
       (regexp-match? #px"^[A-Za-z0-9 .:;_+()\\[\\]-]+$" value)
       value))

(define (environment-observation)
  (define tools
    (for/hasheq ([entry '(("odin" "version") ("racket" "--version") ("make" "--version")
                          ("cc" "--version") ("git" "--version"))]
                 #:do [(define raw (apply probe entry))
                       (define first (and raw (pair? (string-split raw "\n"))
                                          (car (string-split raw "\n"))))
                       (define binary (find-executable-path (car entry)))
                       (define prefix (and binary (path->string binary)))
                       (define normalized
                         (if (and first prefix (string-prefix? first (string-append prefix " ")))
                             (string-append (car entry) (substring first (string-length prefix)))
                             first))
                       (define version (safe-version normalized))]
                 #:when version)
      (values (string->symbol (car entry)) version)))
  (define architecture (safe-version (probe "uname" "-m")))
  (define base (hasheq 'platform "linux" 'kernel_family "linux"))
  (define with-architecture (if architecture (hash-set base 'architecture architecture) base))
  (if (positive? (hash-count tools)) (hash-set with-architecture 'toolchains tools) with-architecture))

(define input-files
  '("release/public-source-policy.json" "release/public-source-closure.json"
    "release/linux-x86_64/build-environment.json"
    ".build/modules/product-modules.manifest" ".build/hosting/libodra_racket_runtime.a"
    ".build/syntax-vendor/libtree-sitter-odin.a"
    ".build/terminal-vendor/install/lib/libghostty-vt.a"))

(define (input-observation root)
  (hasheq
   'files
   (for/hasheq ([relative input-files]
                #:do [(define path (build-path root relative))]
                #:when (and (file-exists? path) (not (link-exists? path))))
     (values (string->symbol relative) (file-sha256 path)))
   'build_overrides_digest
   (jsexpr-sha256
    (for/hasheq ([name '("ODIN" "RACKET" "RACO" "CC" "ODIN_THREADS" "ODIN_FLAGS"
                         "CFLAGS" "LDFLAGS" "MAKEFLAGS" "SOURCE_DATE_EPOCH"
                         "ODRA_NIGHTLY_TIMEOUT")]
                 #:when (getenv name))
      (define value (getenv name))
      (unless (<= (string-length value) 4096)
        (raise-user-error 'native-evidence "build override exceeds its byte bound"))
      (values (string->symbol name) value)))))

;; Pressure totals are cumulative microseconds; keep only normalized numeric samples.
(define (pressure-observation [root "/proc/pressure"])
  (for*/hasheq ([kind '("cpu" "memory" "io")]
                #:do [(define path (build-path root kind))]
                #:when (file-exists? path)
                [line (in-list (file->lines path))]
                #:do [(define match (regexp-match #px"^(some|full) .*total=([0-9]+)$" line))]
                #:when match)
    (values (string->symbol (format "~a_~a_us" kind (cadr match)))
            (string->number (caddr match)))))

(define (resource-observation time-path before [after (pressure-observation)])
  (define time
    (and (file-exists? time-path)
         (<= (file-size time-path) 1024)
         (for/first ([line (reverse (file->lines time-path))]
                     #:when (regexp-match? #px"^[0-9.]+ [0-9.]+ [0-9]+$" line))
           (map string->number (string-split line)))))
  (define observed
    (if time
        (hasheq 'cpu_user_ms (inexact->exact (round (* 1000 (car time))))
                'cpu_system_ms (inexact->exact (round (* 1000 (cadr time))))
                'peak_rss_bytes (* 1024 (caddr time)))
        (hasheq)))
  (define pressure
    (for/hasheq ([(key initial) (in-hash before)]
                 #:when (and (hash-has-key? after key) (>= (hash-ref after key) initial)))
      (values key (- (hash-ref after key) initial))))
  (if (positive? (hash-count pressure)) (hash-set observed 'pressure pressure) observed))
