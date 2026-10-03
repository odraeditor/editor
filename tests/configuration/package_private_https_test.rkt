#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         net/url-connect
         openssl
         racket/file
         racket/port
         racket/string
         rackunit
         "../../src/language_bundle/acquisition.rkt"
         (submod "../../src/language_bundle/acquisition.rkt" test-support)
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/endpoint-transport.rkt"
         "../../src/package_catalog/state-records.rkt")

(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (read-request input)
  (define request-line (read-line input 'any))
  (define headers
    (let loop ([result (hash)])
      (define line (read-line input 'any))
      (cond
        [(or (eof-object? line) (string=? line "")) result]
        [else
         (define matched (regexp-match #px"^([^:]+):[ ]*(.*)$" line))
         (loop
          (if matched
              (hash-set result (string-downcase (cadr matched)) (caddr matched))
              result))])))
  (values (and (string? request-line)
               (let ([matched (regexp-match #px"^[A-Z]+ ([^ ]+) HTTP/" request-line)])
                 (and matched (cadr matched))))
          headers))

(define (write-response output status headers body)
  (fprintf output "HTTP/1.1 ~a\r\n" status)
  (for ([(name value) (in-hash headers)])
    (fprintf output "~a: ~a\r\n" name value))
  (fprintf output "Content-Length: ~a\r\nConnection: close\r\n\r\n"
           (bytes-length body))
  (write-bytes body output)
  (flush-output output))

(define (with-local-https handler action)
  (define owner (make-custodian))
  (define listener
    (parameterize ([current-custodian owner])
      (define context (ssl-make-server-context 'auto))
      (define certificate (collection-file-path "test.pem" "openssl"))
      (ssl-load-certificate-chain! context certificate)
      (ssl-load-private-key! context certificate)
      (ssl-listen 0 8 #t "127.0.0.1" context)))
  (define-values (_host port _remote-host _remote-port)
    (ssl-addresses listener #t))
  (parameterize ([current-custodian owner])
    (thread
     (lambda ()
       (let loop ()
         (define-values (input output) (ssl-accept listener))
         (with-handlers ([exn:fail? void])
           (define-values (path headers) (read-request input))
           (define-values (status response-headers body)
             (handler path headers))
           (write-response output status response-headers body))
         (close-input-port input)
         (close-output-port output)
         (loop)))))
  (dynamic-wind
    void
    (lambda ()
      (parameterize ([current-https-protocol 'auto])
        (action (format "https://127.0.0.1:~a" port))))
    (lambda () (custodian-shutdown-all owner))))

(define (catalog-endpoint uri)
  (define catalog-id (make-string 64 #\a))
  (odra-package-catalog-state-endpoint
   1 1
   (odra-package-catalog-endpoint
    "private" catalog-id uri 'https 'origin 0 #t)
   "catalog.private"))

(define catalog-policy
  (odra-package-catalog-transport-policy 4096 3000 2 0 'direct))

(test-case "local HTTPS catalog fixture receives ephemeral authorization"
  (define secret "Bearer local-catalog-secret")
  (with-local-https
   (lambda (path headers)
     (if (and (string=? path "/catalog.rktd")
              (string=? (hash-ref headers "authorization" "") secret))
         (values "200 OK" (hash "Content-Type" "application/octet-stream")
                 #"catalog")
         (values "401 Unauthorized" (hash) #"denied")))
   (lambda (origin)
     (define result
       (fetch-package-catalog-endpoint
        (catalog-endpoint (string-append origin "/catalog.rktd"))
        catalog-policy
        (lambda (_) (hash "authorization" secret))))
     (check-true (odra-package-catalog-fetch-result? result))
     (check-equal? (odra-package-catalog-fetch-result-bytes result) #"catalog")
     (check-false (regexp-match? (regexp (regexp-quote secret))
                                 (format "~s" result))))))

(test-case "local HTTPS catalog authentication rejection is redacted"
  (define secret "Bearer rejected-catalog-secret")
  (with-local-https
   (lambda (_path _headers)
     (values "401 Unauthorized" (hash) #"denied"))
   (lambda (origin)
     (define result
       (fetch-package-catalog-endpoint
        (catalog-endpoint (string-append origin "/catalog.rktd"))
        catalog-policy
        (lambda (_) (hash "authorization" secret))))
     (check-eq? (odra-package-catalog-fetch-failure-code result) 'http-status)
     (check-false (regexp-match? (regexp (regexp-quote secret))
                                 (format "~s" result))))))

(define (put-field! target offset value)
  (bytes-copy! target offset value))

(define (octal-field value width)
  (define digits (number->string value 8))
  (bytes-append
   (string->bytes/utf-8
    (string-append (make-string (- width 1 (string-length digits)) #\0) digits))
   #"\0"))

(define (tar-member path content)
  (define header (make-bytes 512 0))
  (put-field! header 0 (string->bytes/utf-8 path))
  (put-field! header 100 #"0000600\0")
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

(define artifact-bytes #"private artifact")
(define archive-bytes
  (bytes-append (tar-member "bundle/data.bin" artifact-bytes)
                (make-bytes 1024 0)))

(define (raw-archive-open path)
  (values (open-input-file path #:mode 'binary) (lambda (_) #t)))

(test-case "local HTTPS artifact fixture receives ephemeral authorization"
  (define secret "Bearer local-artifact-secret")
  (with-local-https
   (lambda (path headers)
     (if (and (string=? path "/archive.tar.zst")
              (string=? (hash-ref headers "authorization" "") secret))
         (values "200 OK" (hash "Content-Type" "application/octet-stream")
                 archive-bytes)
         (values "401 Unauthorized" (hash) #"denied")))
   (lambda (origin)
     (define root (make-temporary-file "package-private-https-~a" 'directory))
     (file-or-directory-permissions root #o700)
     (dynamic-wind
       void
       (lambda ()
         (define request
           (odra-bundle-archive-request
            "private-artifact"
            (list (string-append origin "/archive.tar.zst"))
            (sha256 archive-bytes) (bytes-length archive-bytes)
            (list
             (odra-bundle-archive-member
              "bundle/data.bin" (sha256 artifact-bytes)
              (bytes-length artifact-bytes) 'data #f))
            1 (bytes-length artifact-bytes)))
         (define result
           (parameterize ([current-acquisition-archive-open raw-archive-open])
             (acquire-language-bundle
              root request
              #:storage-directory "packages"
              #:request-headers
              (lambda (_) (hash "authorization" secret)))))
         (check-true (odra-bundle-acquisition? result))
         (check-equal?
          (file->bytes
           (odra-bundle-content-handle-path
            (car (odra-bundle-acquisition-content result))))
          artifact-bytes)
         (check-false (regexp-match? (regexp (regexp-quote secret))
                                     (format "~s" result))))
       (lambda () (delete-directory/files root))))))
