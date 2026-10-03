#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         "../../src/command/language-bundles.rkt"
         "../../src/hosting/language-bundle-bridge.rkt")

(define (with-root action)
  (define root (make-temporary-file "odra-language-bundle-~a" 'directory))
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (write-module root content)
  (define path (build-path root "bundle.rkt"))
  (call-with-output-file path
    (lambda (output) (display content output))
    #:exists 'truncate/replace)
  path)

(define valid-module
  (string-append
   "#lang racket/base\n"
   "(require odra/language-bundles)\n"
   "(provide odra-language-bundle)\n"
   "(define odra-language-bundle\n"
   "  (language-support-bundle\n"
   "   #:id 'org.example.language #:display-name \"Example Language\"\n"
   "   #:version \"1.0.0\" #:api-min \"1.0.0\" #:api-max \"2.0.0\"\n"
   "   #:description \"Example bundle.\" #:publisher 'org.example\n"
   "   #:source 'catalog.example #:targets '((linux x86-64))))\n"))

(test-case "bundle module exports one prepared immutable value"
  (with-root
   (lambda (root)
     (define result (load-language-bundle-module (write-module root valid-module) 0 1))
     (check-eq? (language-bundle-load-result-state result) 'prepared)
     (check-equal? (language-bundle-load-result-generation result) 1)
     (check-true (language-bundle-value? (language-bundle-load-result-bundle result)))
     (check-true (immutable? (language-bundle-load-result-bytes result)))
     (check-false (language-bundle-load-result-rejection result)))))

(test-case "stale load rejects before evaluating the module"
  (define result (load-language-bundle-module "/missing/bundle.rkt" 4 4))
  (check-eq? (language-bundle-load-result-state result) 'rejected)
  (check-eq? (language-bundle-load-rejection-code
              (language-bundle-load-result-rejection result))
             'stale-generation))

(test-case "module exceptions and malformed exports remain contained"
  (with-root
   (lambda (root)
     (for ([content
            (in-list
             (list
              "#lang racket/base\n(error 'bundle \"fixture failure\")\n"
              "#lang racket/base\n(provide odra-language-bundle)\n(define odra-language-bundle 'invalid)\n"))])
       (define result
         (load-language-bundle-module (write-module root content) 0 1))
       (check-eq? (language-bundle-load-result-state result) 'rejected)
       (check-eq? (language-bundle-load-rejection-code
                   (language-bundle-load-result-rejection result))
                  'exception)
       (check-false (language-bundle-load-result-bundle result))
       (check-false (language-bundle-load-result-bytes result))))))

(test-case "encoded bundle boundary rejects excessive authoring output"
  (define target '((linux x86-64)))
  (define long-path (string-append "data/" (make-string 4050 #\x)))
  (define artifacts
    (for/list ([index (in-range 600)])
      (language-bundle-artifact
       #:id (string->symbol (format "artifact-~a" index))
       #:kind 'data #:path long-path #:sha256 (make-string 64 #\a)
       #:size 1 #:targets target)))
  (define excessive
    (language-support-bundle
     #:id 'org.example.excessive #:display-name "Excessive"
     #:version "1.0.0" #:api-min "1.0.0" #:api-max "2.0.0"
     #:description "Boundary fixture." #:publisher 'org.example
     #:source 'catalog.example #:targets target #:artifacts artifacts))
  (check-exn exn:fail? (lambda () (language-bundle-encode excessive))))
