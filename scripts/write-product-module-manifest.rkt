#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/cmdline
         racket/file
         racket/path)

(define output-path #f)
(define identity #f)
(define version #f)
(define role #f)
(define artifact-path #f)
(define entrypoint #f)
(define abi-minimum #f)
(define abi-maximum #f)
(define modules '())

(command-line
 #:program "write-product-module-manifest"
 #:once-each
 [("--output") value "Manifest output path" (set! output-path value)]
 [("--identity") value "Semantic module identity" (set! identity value)]
 [("--version") value "Semantic module version" (set! version value)]
 [("--role") value "Semantic provider role" (set! role value)]
 [("--artifact") value "Module artifact path" (set! artifact-path value)]
 [("--entrypoint") value "Native module entrypoint" (set! entrypoint value)]
 [("--abi-minimum") value "Minimum ABI version" (set! abi-minimum value)]
 [("--abi-maximum") value "Maximum ABI version" (set! abi-maximum value)]
 #:multi
 [("--module") module-identity module-version module-role module-artifact
                 module-entrypoint module-abi-minimum module-abi-maximum
                 "Complete module declaration"
                 (set! modules
                       (append modules
                               (list (list module-identity
                                           module-version
                                           module-role
                                           module-artifact
                                           module-entrypoint
                                           module-abi-minimum
                                           module-abi-maximum))))])

(when (and identity version role artifact-path entrypoint abi-minimum abi-maximum)
  (set! modules
        (append modules
                (list (list identity version role artifact-path entrypoint
                            abi-minimum abi-maximum)))))

(unless (and output-path (pair? modules))
  (raise-user-error 'write-product-module-manifest
                    "an output path and at least one complete module are required"))

(define (module-content declaration)
  (define module-identity (list-ref declaration 0))
  (define module-version (list-ref declaration 1))
  (define module-role (list-ref declaration 2))
  (define artifact
    (simplify-path (path->complete-path (list-ref declaration 3)) #t))
  (define module-entrypoint (list-ref declaration 4))
  (define module-abi-minimum (list-ref declaration 5))
  (define module-abi-maximum (list-ref declaration 6))
  (define digest
    (call-with-input-file artifact
      (lambda (input) (bytes->hex-string (sha256-bytes input)))
      #:mode 'binary))
  (string-append
   "module\n"
   "identity=" module-identity "\n"
   "version=" module-version "\n"
   "role=" module-role "\n"
   "artifact=" (path->string (file-name-from-path artifact)) "\n"
   "digest=" digest "\n"
   "size=" (number->string (file-size artifact)) "\n"
   "entrypoint=" module-entrypoint "\n"
   "abi-minimum=" module-abi-minimum "\n"
   "abi-maximum=" module-abi-maximum "\n"
   "end\n"))

(define content
  (string-append "odra-product-modules 1\n"
                 (apply string-append (map module-content modules))))

(make-parent-directory* output-path)
(call-with-output-file output-path
  (lambda (output) (display content output))
  #:exists 'truncate/replace)
