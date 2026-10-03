#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/cmdline
         racket/file
         racket/list
         racket/match
         racket/path
         racket/string
         (prefix-in bundle: "../src/command/language-bundles.rkt")
         "../src/hosting/language-bundle-bridge.rkt")

(provide
 (struct-out bundle-author-diagnostic)
 (struct-out language-bundle-validation)
 (struct-out language-bundle-archive)
 validate-language-bundle
 conform-language-bundle
 build-language-bundle-archive)

(struct bundle-author-diagnostic (severity code message) #:transparent)
(struct language-bundle-validation (state bundle bytes diagnostics) #:transparent)
(struct language-bundle-archive (path digest size members) #:transparent)

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (parse-version value)
  (match (regexp-match #px"^([0-9]+)\\.([0-9]+)\\.([0-9]+)" value)
    [(list _ major minor patch)
     (list (string->number major) (string->number minor) (string->number patch))]
    [_ #f]))

(define (version<=? left right)
  (define parsed-left (parse-version left))
  (define parsed-right (parse-version right))
  (and parsed-left parsed-right
       (or (equal? parsed-left parsed-right)
           (let loop ([left parsed-left] [right parsed-right])
             (cond
               [(null? left) #t]
               [(< (car left) (car right)) #t]
               [(> (car left) (car right)) #f]
               [else (loop (cdr left) (cdr right))])))))

(define (error-diagnostic code message)
  (bundle-author-diagnostic 'error code message))

(define (artifact-diagnostics value root platform architecture)
  (append-map
   (lambda (artifact)
     (define path
       (simplify-path
        (build-path root (bundle:odra-language-bundle-artifact-path artifact))))
     (define target (list platform architecture))
     (append
      (if (member target (bundle:odra-language-bundle-artifact-targets artifact) equal?)
          '()
          (list
           (error-diagnostic
            'artifact-target
            (format "Artifact ~a does not support ~a/~a."
                    (bundle:odra-language-bundle-artifact-id artifact)
                    platform architecture))))
      (cond
        [(not (file-exists? path))
         (list
          (error-diagnostic
           'artifact-missing
           (format "Artifact ~a is missing at ~a."
                   (bundle:odra-language-bundle-artifact-id artifact) path)))]
        [(not (= (file-size path)
                 (bundle:odra-language-bundle-artifact-size artifact)))
         (list
          (error-diagnostic
           'artifact-size
           (format "Artifact ~a size differs from its declaration."
                   (bundle:odra-language-bundle-artifact-id artifact))))]
        [(not (string=? (sha256-file path)
                        (bundle:odra-language-bundle-artifact-sha256 artifact)))
         (list
          (error-diagnostic
           'artifact-digest
           (format "Artifact ~a digest differs from its declaration."
                   (bundle:odra-language-bundle-artifact-id artifact))))]
        [else '()])))
   (bundle:odra-language-support-bundle-artifacts value)))

(define (compatibility-diagnostics value platform architecture api-version)
  (define target (list platform architecture))
  (append
   (if (member target (bundle:odra-language-support-bundle-targets value) equal?)
       '()
       (list
        (error-diagnostic
         'unsupported-target
         (format "Bundle does not support ~a/~a." platform architecture))))
   (if (and (version<=? (bundle:odra-language-support-bundle-api-min value)
                        api-version)
            (version<=? api-version
                        (bundle:odra-language-support-bundle-api-max value)))
       '()
       (list
        (error-diagnostic
         'incompatible-api
         (format "Odra API ~a is outside the declared range ~a through ~a."
                 api-version
                 (bundle:odra-language-support-bundle-api-min value)
                 (bundle:odra-language-support-bundle-api-max value)))))))

(define (validate-language-bundle module-path
                                  #:root [root (path-only (path->complete-path module-path))]
                                  #:platform [platform 'linux]
                                  #:architecture [architecture 'x86-64]
                                  #:api-version [api-version "1.0.0"])
  (define loaded (load-language-bundle-module module-path 0 1))
  (cond
    [(not (eq? (language-bundle-load-result-state loaded) 'prepared))
     (define rejection (language-bundle-load-result-rejection loaded))
     (language-bundle-validation
      'invalid #f #f
      (list
       (error-diagnostic
        (language-bundle-load-rejection-code rejection)
        (language-bundle-load-rejection-detail rejection))))]
    [else
     (define value (language-bundle-load-result-bundle loaded))
     (define diagnostics
       (append
        (compatibility-diagnostics value platform architecture api-version)
        (artifact-diagnostics value root platform architecture)))
     (language-bundle-validation
      (if (ormap (lambda (entry)
                   (eq? (bundle-author-diagnostic-severity entry) 'error))
                 diagnostics)
          'invalid
          'valid)
      value
      (language-bundle-load-result-bytes loaded)
      diagnostics)]))

(define (conformance-diagnostics value)
  (define checks
    (list
     (list 'language
           (pair? (bundle:odra-language-support-bundle-languages value))
           "Bundle must declare at least one language.")
     (list 'syntax-provider
           (pair? (bundle:odra-language-support-bundle-syntax-providers value))
           "Bundle must declare at least one syntax provider.")
     (list 'service
           (pair? (bundle:odra-language-support-bundle-services value))
           "Bundle must declare at least one language service.")
     (list 'command
           (pair? (bundle:odra-language-support-bundle-commands value))
           "Bundle must declare at least one semantic command.")
     (list 'direct-keymap
           (for/or ([keymap (in-list (bundle:odra-language-support-bundle-keymaps value))])
             (member 'direct (bundle:odra-language-keymap-states keymap)))
           "Bundle must declare a Direct language-context keymap.")
     (list 'modal-keymap
           (for/or ([keymap (in-list (bundle:odra-language-support-bundle-keymaps value))])
             (for/or ([state (in-list (bundle:odra-language-keymap-states keymap))])
               (regexp-match? #px"^modal" (symbol->string state))))
           "Bundle must declare a Modal language-context keymap.")))
  (for/list ([check (in-list checks)] #:unless (cadr check))
    (error-diagnostic (car check) (caddr check))))

(define (conform-language-bundle module-path
                                 #:root [root (path-only (path->complete-path module-path))]
                                 #:platform [platform 'linux]
                                 #:architecture [architecture 'x86-64]
                                 #:api-version [api-version "1.0.0"])
  (define validated
    (validate-language-bundle
     module-path #:root root #:platform platform #:architecture architecture
     #:api-version api-version))
  (cond
    [(not (eq? (language-bundle-validation-state validated) 'valid)) validated]
    [else
     (define diagnostics
       (conformance-diagnostics (language-bundle-validation-bundle validated)))
     (struct-copy
      language-bundle-validation validated
      [state (if (null? diagnostics) 'conformant 'invalid)]
      [diagnostics diagnostics])]))

(define (put-field! target offset value)
  (bytes-copy! target offset value))

(define (octal-field value width)
  (define digits (number->string value 8))
  (bytes-append
   (string->bytes/utf-8
    (string-append (make-string (- width 1 (string-length digits)) #\0) digits))
   #"\0"))

(define (tar-member path content executable?)
  (define header (make-bytes 512 0))
  (put-field! header 0 (string->bytes/utf-8 path))
  (put-field! header 100 (if executable? #"0000755\0" #"0000644\0"))
  (put-field! header 108 #"0000000\0")
  (put-field! header 116 #"0000000\0")
  (put-field! header 124 (octal-field (bytes-length content) 12))
  (put-field! header 136 (octal-field 0 12))
  (put-field! header 148 #"        ")
  (bytes-set! header 156 (char->integer #\0))
  (put-field! header 257 #"ustar\0")
  (put-field! header 263 #"00")
  (define checksum (for/sum ([byte (in-bytes header)]) byte))
  (define digits (number->string checksum 8))
  (put-field!
   header 148
   (bytes-append
    (string->bytes/utf-8
     (string-append (make-string (- 6 (string-length digits)) #\0) digits))
    #"\0 "))
  (define padding (modulo (- 512 (modulo (bytes-length content) 512)) 512))
  (bytes-append header content (make-bytes padding 0)))

(define (build-language-bundle-archive module-path output-path
                                       #:root [root (path-only (path->complete-path module-path))]
                                       #:platform [platform 'linux]
                                       #:architecture [architecture 'x86-64]
                                       #:api-version [api-version "1.0.0"])
  (define conformance
    (conform-language-bundle
     module-path #:root root #:platform platform #:architecture architecture
     #:api-version api-version))
  (unless (eq? (language-bundle-validation-state conformance) 'conformant)
    (raise-arguments-error
     'build-language-bundle-archive
     "bundle must pass conformance before archive creation"
     "diagnostics" (language-bundle-validation-diagnostics conformance)))
  (define artifacts
    (sort
     (bundle:odra-language-support-bundle-artifacts
      (language-bundle-validation-bundle conformance))
     string<? #:key bundle:odra-language-bundle-artifact-path))
  (define archive
    (bytes-append
     (apply
      bytes-append
      (for/list ([artifact (in-list artifacts)])
        (define relative (bundle:odra-language-bundle-artifact-path artifact))
        (tar-member
         relative
         (file->bytes (build-path root relative))
         (eq? (bundle:odra-language-bundle-artifact-kind artifact) 'executable))))
     (make-bytes 1024 0)))
  (make-parent-directory* output-path)
  (call-with-output-file output-path
    (lambda (output) (write-bytes archive output))
    #:exists 'truncate/replace #:mode 'binary)
  (language-bundle-archive
   (path->complete-path output-path) (sha256-file output-path)
   (bytes-length archive) (length artifacts)))

(define (print-validation result)
  (for ([diagnostic (in-list (language-bundle-validation-diagnostics result))])
    (printf "~a ~a: ~a\n"
            (bundle-author-diagnostic-severity diagnostic)
            (bundle-author-diagnostic-code diagnostic)
            (bundle-author-diagnostic-message diagnostic)))
  (when (null? (language-bundle-validation-diagnostics result))
    (define value (language-bundle-validation-bundle result))
    (printf "~a ~a@~a\n"
            (language-bundle-validation-state result)
            (bundle:odra-language-support-bundle-id value)
            (bundle:odra-language-support-bundle-version value))))

(module+ main
  (define arguments (current-command-line-arguments))
  (when (< (vector-length arguments) 2)
    (eprintf "usage: language-bundle-author.rkt validate|conform MODULE\n")
    (eprintf "       language-bundle-author.rkt archive MODULE OUTPUT\n")
    (exit 64))
  (define command (vector-ref arguments 0))
  (define module-path (vector-ref arguments 1))
  (case (string->symbol command)
    [(validate)
     (define result (validate-language-bundle module-path))
     (print-validation result)
     (unless (eq? (language-bundle-validation-state result) 'valid) (exit 1))]
    [(conform)
     (define result (conform-language-bundle module-path))
     (print-validation result)
     (unless (eq? (language-bundle-validation-state result) 'conformant) (exit 1))]
    [(archive)
     (when (< (vector-length arguments) 3)
       (eprintf "archive requires an output path\n")
       (exit 64))
     (define result
       (build-language-bundle-archive module-path (vector-ref arguments 2)))
     (printf "archive ~a sha256=~a bytes=~a members=~a\n"
             (language-bundle-archive-path result)
             (language-bundle-archive-digest result)
             (language-bundle-archive-size result)
             (language-bundle-archive-members result))]
    [else
     (eprintf "unknown command: ~a\n" command)
     (exit 64)]))
