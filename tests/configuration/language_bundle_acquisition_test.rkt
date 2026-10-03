#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/path
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
   (string->bytes/utf-8 (string-append (make-string (- width 1 (string-length digits)) #\0)
                                      digits))
   #"\0"))

(define (tar-file path content)
  (define header (make-bytes 512 0))
  (put-field! header 0 (string->bytes/utf-8 path))
  (put-field! header 100 #"0000644\0")
  (put-field! header 108 #"0000000\0")
  (put-field! header 116 #"0000000\0")
  (put-field! header 124 (octal-field (bytes-length content) 12))
  (put-field! header 136 (octal-field 0 12))
  (put-field! header 148 #"        ")
  (bytes-set! header 156 (char->integer #\0))
  (put-field! header 257 #"ustar\0")
  (put-field! header 263 #"00")
  (define checksum (for/sum ([byte (in-bytes header)]) byte))
  (define checksum-digits (number->string checksum 8))
  (put-field!
   header 148
   (bytes-append
    (string->bytes/utf-8
     (string-append (make-string (- 6 (string-length checksum-digits)) #\0)
                    checksum-digits))
    #"\0 "))
  (define padding (modulo (- 512 (modulo (bytes-length content) 512)) 512))
  (bytes-append header content (make-bytes padding 0)
                (make-bytes 1024 0)))

(define member-bytes #"#lang racket/base\n(provide fixture)\n(define fixture 1)\n")
(define archive-bytes (tar-file "bundle/main.rkt" member-bytes))
(define member
  (odra-bundle-archive-member
   "bundle/main.rkt" (sha256 member-bytes) (bytes-length member-bytes)
   'racket-module #f))
(define request
  (odra-bundle-archive-request
   "install-fixture" '("/mock/archive.tar.zst")
   (sha256 archive-bytes) (bytes-length archive-bytes)
   (list member) 8 4096))

(define (with-root action)
  (define root (make-temporary-file "odra-acquisition-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (raw-archive-open path)
  (values (open-input-file path #:mode 'binary) (lambda (_) #t)))

(test-case "verified archive and members publish into the immutable content store"
  (with-root
   (lambda (root)
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (acquisition-response 200 (hash) (open-input-bytes archive-bytes)))]
            [current-acquisition-archive-open raw-archive-open])
         (acquire-language-bundle root request)))
     (check-true (odra-bundle-acquisition? result))
     (check-equal? (odra-bundle-acquisition-downloaded-bytes result)
                   (bytes-length archive-bytes))
     (check-true (file-exists? (odra-bundle-acquisition-archive-path result)))
     (define handle (car (odra-bundle-acquisition-content result)))
     (check-equal? (file->bytes (odra-bundle-content-handle-path handle))
                   member-bytes)
     (check-false
      (directory-exists?
       (build-path root "language-bundles" "staging" "install-fixture"))))))

(test-case "offline acquisition reuses only verified immutable content"
  (with-root
   (lambda (root)
     (parameterize
         ([current-acquisition-transport-open
           (lambda (_) (acquisition-response 200 (hash) (open-input-bytes archive-bytes)))]
          [current-acquisition-archive-open raw-archive-open])
       (check-true (odra-bundle-acquisition?
                    (acquire-language-bundle root request)))
       (define offline
         (acquire-language-bundle root request #:offline? #t))
       (check-true (odra-bundle-acquisition? offline))
       (check-true (odra-bundle-acquisition-offline? offline))
       (check-equal? (odra-bundle-acquisition-downloaded-bytes offline) 0)
       (check-equal? (odra-bundle-acquisition-reused-digests offline)
                     (list (sha256 member-bytes)))))))

(test-case "cancellation removes private acquisition staging"
  (with-root
   (lambda (root)
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (acquisition-response 200 (hash) (open-input-bytes archive-bytes)))]
            [current-acquisition-archive-open raw-archive-open])
         (acquire-language-bundle root request #:cancelled? (lambda () #t))))
     (check-true (odra-bundle-acquisition-failure? result))
     (check-eq? (odra-bundle-acquisition-failure-code result) 'cancelled)
     (check-false
      (directory-exists?
       (build-path root "language-bundles" "staging" "install-fixture"))))))

(test-case "offline cache miss performs no transport request"
  (with-root
   (lambda (root)
     (define transport-called? #f)
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (set! transport-called? #t)
               (error 'transport "must not run"))]
            [current-acquisition-archive-open raw-archive-open])
         (acquire-language-bundle root request #:offline? #t)))
     (check-false transport-called?)
     (check-eq? (odra-bundle-acquisition-failure-code result) 'offline-miss))))
