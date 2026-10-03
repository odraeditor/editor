#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/path
         racket/port
         racket/string
         rackunit
         "../../src/language_bundle/acquisition.rkt"
         (submod "../../src/language_bundle/acquisition.rkt" test-support))

(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (put-field! target offset value)
  (bytes-copy! target offset value))

(define (octal-field value width)
  (define digits (number->string value 8))
  (bytes-append
   (string->bytes/utf-8
    (string-append (make-string (- width 1 (string-length digits)) #\0) digits))
   #"\0"))

(define (tar-file path content [type #\0])
  (define header (make-bytes 512 0))
  (put-field! header 0 (string->bytes/utf-8 path))
  (put-field! header 100 #"0000644\0")
  (put-field! header 108 #"0000000\0")
  (put-field! header 116 #"0000000\0")
  (put-field! header 124 (octal-field (bytes-length content) 12))
  (put-field! header 136 (octal-field 0 12))
  (put-field! header 148 #"        ")
  (bytes-set! header 156 (char->integer type))
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
  (bytes-append header content (make-bytes padding 0) (make-bytes 1024 0)))

(define content #"verified fixture bytes")
(define expected-member
  (odra-bundle-archive-member
   "bundle/data.bin" (sha256 content) (bytes-length content) 'data #f))
(define valid-archive (tar-file "bundle/data.bin" content))

(define (request-for id archive [archive-digest (sha256 archive)])
  (odra-bundle-archive-request
   id '("https://first.example/archive.tar.zst")
   archive-digest (bytes-length archive) (list expected-member) 8 4096))

(define (raw-open path)
  (values (open-input-file path #:mode 'binary) (lambda (_) #t)))

(define (with-root action)
  (define root (make-temporary-file "odra-acquisition-failure-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (stage-exists? root id)
  (directory-exists? (build-path root "language-bundles" "staging" id)))

(define (mock-success archive)
  (acquisition-response 200 (hash) (open-input-bytes archive)))

(test-case "redirects are followed only within the explicit ceiling"
  (with-root
   (lambda (root)
     (define calls '())
     (define request (request-for "redirect-fixture" valid-archive))
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (location)
               (set! calls (cons location calls))
               (if (string=? location "https://first.example/archive.tar.zst")
                   (acquisition-response
                    302 (hash "location" "https://second.example/archive.tar.zst")
                    (open-input-bytes #""))
                   (mock-success valid-archive)))]
            [current-acquisition-archive-open raw-open])
         (acquire-language-bundle root request #:redirect-limit 1)))
     (check-true (odra-bundle-acquisition? result))
     (check-equal? (reverse calls)
                   '("https://first.example/archive.tar.zst"
                     "https://second.example/archive.tar.zst"))))
  (with-root
   (lambda (root)
     (define request (request-for "redirect-limit" valid-archive))
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (acquisition-response
                302 (hash "location" "https://second.example/archive.tar.zst")
                (open-input-bytes #"")))]
            [current-acquisition-archive-open raw-open])
         (acquire-language-bundle root request #:redirect-limit 0)))
     (check-eq? (odra-bundle-acquisition-failure-code result) 'limit)
     (check-false (stage-exists? root "redirect-limit")))))

(test-case "retryable transport status stops at the configured ceiling"
  (with-root
   (lambda (root)
     (define attempts 0)
     (define request (request-for "retry-success" valid-archive))
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (set! attempts (add1 attempts))
               (if (< attempts 3)
                   (acquisition-response 503 (hash) (open-input-bytes #""))
                   (mock-success valid-archive)))]
            [current-acquisition-archive-open raw-open])
         (acquire-language-bundle root request #:retry-limit 2)))
     (check-true (odra-bundle-acquisition? result))
     (check-equal? attempts 3)))
  (with-root
   (lambda (root)
     (define attempts 0)
     (define request (request-for "retry-limit" valid-archive))
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (set! attempts (add1 attempts))
               (acquisition-response 503 (hash) (open-input-bytes #"")))]
            [current-acquisition-archive-open raw-open])
         (acquire-language-bundle root request #:retry-limit 2)))
     (check-equal? attempts 3)
     (check-eq? (odra-bundle-acquisition-failure-code result) 'http-status))))

(test-case "connection deadline cancels a blocked transport owner"
  (with-root
   (lambda (root)
     (define request (request-for "timeout-fixture" valid-archive))
     (define result
       (parameterize
           ([current-acquisition-transport-open (lambda (_) (sync never-evt))]
            [current-acquisition-archive-open raw-open])
         (acquire-language-bundle
          root request #:deadline-milliseconds 10 #:retry-limit 0)))
     (check-eq? (odra-bundle-acquisition-failure-code result) 'timeout)
     (check-false (stage-exists? root "timeout-fixture")))))

(test-case "digest mismatch cannot enter the immutable store"
  (with-root
   (lambda (root)
     (define request
       (request-for "digest-fixture" valid-archive (make-string 64 #\f)))
     (define result
       (parameterize
           ([current-acquisition-transport-open (lambda (_) (mock-success valid-archive))]
            [current-acquisition-archive-open raw-open])
         (acquire-language-bundle root request #:retry-limit 0)))
     (check-eq? (odra-bundle-acquisition-failure-code result) 'digest)
     (check-false
      (file-exists?
       (language-bundle-content-path root (make-string 64 #\f)))))))

(test-case "archive traversal, hard links, and devices reject before publication"
  (for ([case
         (in-list
          (list (cons 'archive-path (tar-file "../escape" content))
                (cons 'archive-type (tar-file "bundle/data.bin" content #\1))
                (cons 'archive-type (tar-file "bundle/data.bin" content #\2))
                (cons 'archive-type (tar-file "bundle/data.bin" content #\3))))])
    (with-root
     (lambda (root)
       (define id (format "archive-~a" (car case)))
       (define archive (cdr case))
       (define request (request-for id archive))
       (define result
         (parameterize
             ([current-acquisition-transport-open (lambda (_) (mock-success archive))]
              [current-acquisition-archive-open raw-open])
           (acquire-language-bundle root request #:retry-limit 0)))
       (check-eq? (odra-bundle-acquisition-failure-code result) (car case))
       (check-false (stage-exists? root id))))))

(test-case "decompression failure discards every extracted stage"
  (with-root
   (lambda (root)
     (define request (request-for "decompression-fixture" valid-archive))
     (define result
       (parameterize
           ([current-acquisition-transport-open (lambda (_) (mock-success valid-archive))]
            [current-acquisition-archive-open
             (lambda (path)
               (values (open-input-file path #:mode 'binary) (lambda (_) #f)))])
         (acquire-language-bundle root request #:retry-limit 0)))
     (check-eq? (odra-bundle-acquisition-failure-code result) 'decompression)
     (check-false (stage-exists? root "decompression-fixture")))))

(test-case "allocation failure is contained and leaves no acquisition stage"
  (with-root
   (lambda (root)
     (define request (request-for "allocation-fixture" valid-archive))
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (raise
                (exn:fail:out-of-memory
                 "simulated allocation failure" (current-continuation-marks))))]
            [current-acquisition-archive-open raw-open])
         (acquire-language-bundle root request #:retry-limit 0)))
     (check-eq? (odra-bundle-acquisition-failure-code result) 'transport)
     (check-false (stage-exists? root "allocation-fixture")))))

(define (zstd-compress bytes)
  (define-values (process output input error-output)
    (subprocess #f #f #f "/usr/bin/zstd" "-q" "-c"))
  (write-bytes bytes input)
  (close-output-port input)
  (define compressed (port->bytes output))
  (close-input-port output)
  (port->bytes error-output)
  (close-input-port error-output)
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (error 'zstd-compress "fixture compression failed"))
  compressed)

(test-case "default local transport and zstd decoder acquire a real archive"
  (with-root
   (lambda (root)
     (define compressed (zstd-compress valid-archive))
     (define source-path (build-path root "fixture.tar.zst"))
     (call-with-output-file source-path
       (lambda (output) (write-bytes compressed output))
       #:exists 'error #:mode 'binary #:permissions #o600)
     (define request
       (odra-bundle-archive-request
        "real-zstd" (list (path->string source-path))
        (sha256 compressed) (bytes-length compressed)
        (list expected-member) 8 4096))
     (define result (acquire-language-bundle root request #:retry-limit 0))
     (check-true (odra-bundle-acquisition? result) (format "~s" result))
     (check-equal?
      (file->bytes
       (odra-bundle-content-handle-path
        (car (odra-bundle-acquisition-content result))))
      content))))
