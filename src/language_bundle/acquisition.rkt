#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         net/url
         racket/contract/base
         racket/file
         racket/list
         racket/match
         racket/path
         racket/port
         racket/string
         "../storage/durable-file.rkt"
         "advisory-response.rkt")

(provide
 (struct-out odra-bundle-archive-member)
 (struct-out odra-bundle-archive-request)
 (struct-out odra-bundle-content-handle)
 (struct-out odra-bundle-acquisition)
 (struct-out odra-bundle-bootstrap-acquisition)
 (struct-out odra-bundle-acquisition-failure)
 (contract-out
  [language-bundle-content-path (-> path-string? string? path?)]
  [acquire-language-bundle
   (->* (path-string? odra-bundle-archive-request?)
        (#:offline? boolean?
         #:storage-directory string?
         #:request-headers procedure?
         #:advisory-evaluator procedure?
         #:cancelled? procedure?
         #:deadline-milliseconds exact-positive-integer?
         #:redirect-limit exact-nonnegative-integer?
         #:retry-limit exact-nonnegative-integer?)
        (or/c odra-bundle-acquisition? odra-bundle-acquisition-failure?))]
  [acquire-language-bundle-bootstrap-member
   (->* (path-string? string? (listof string?) string? exact-positive-integer?
                       string? string?)
        (#:offline? boolean?
         #:storage-directory string?
         #:member-byte-limit exact-positive-integer?
         #:request-headers procedure?
         #:cancelled? procedure?
         #:deadline-milliseconds exact-positive-integer?
         #:redirect-limit exact-nonnegative-integer?
         #:retry-limit exact-nonnegative-integer?)
        (or/c odra-bundle-bootstrap-acquisition?
              odra-bundle-acquisition-failure?))]))

(define maximum-archive-entries 8192)
(define maximum-expanded-bytes (expt 2 30))
(define maximum-location-bytes 4096)
(define maximum-message-bytes 4096)
(define transfer-buffer-bytes (* 64 1024))
(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define admitted-member-kinds
  '(data documentation executable grammar license manifest query racket-module
         runtime-adapter tree-sitter-grammar))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (identity? value)
  (and (string? value)
       (<= 1 (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(define (archive-path? value)
  (and (bounded-text? value maximum-location-bytes)
       (not (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." ".."))))))

(define (location? value)
  (and (bounded-text? value maximum-location-bytes)
       (or (absolute-path? (string->path value))
           (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" value))))

(struct odra-bundle-archive-member (path digest size kind executable?)
  #:transparent
  #:guard
  (lambda (path digest size kind executable? _)
    (unless (and (archive-path? path) (digest? digest)
                 (exact-nonnegative-integer? size)
                 (<= size maximum-expanded-bytes)
                 (memq kind admitted-member-kinds)
                 (boolean? executable?))
      (raise-arguments-error 'odra-bundle-archive-member
                             "invalid immutable archive member"))
    (values (copied path) (copied digest) size kind executable?)))

(struct odra-bundle-archive-request
  (id locations archive-digest archive-size members entry-limit expanded-byte-limit)
  #:transparent
  #:guard
  (lambda (id locations archive-digest archive-size members entry-limit
              expanded-byte-limit _)
    (define member-paths
      (and (list? members) (map odra-bundle-archive-member-path members)))
    (define expanded-size
      (and (list? members)
           (for/sum ([member (in-list members)])
             (odra-bundle-archive-member-size member))))
    (unless (and (identity? id)
                 (list? locations) (pair? locations)
                 (= (length locations) (length (remove-duplicates locations string=?)))
                 (andmap location? locations)
                 (digest? archive-digest)
                 (exact-positive-integer? archive-size)
                 (list? members) (pair? members)
                 (<= (length members) maximum-archive-entries)
                 (andmap odra-bundle-archive-member? members)
                 (= (length member-paths)
                    (length (remove-duplicates member-paths string=?)))
                 (exact-positive-integer? entry-limit)
                 (<= (length members) entry-limit maximum-archive-entries)
                 (exact-positive-integer? expanded-byte-limit)
                 (<= expanded-size expanded-byte-limit maximum-expanded-bytes))
      (raise-arguments-error 'odra-bundle-archive-request
                             "invalid bounded archive acquisition request"))
    (values (copied id) (map copied locations) (copied archive-digest)
            archive-size members entry-limit expanded-byte-limit)))

(struct odra-bundle-content-handle (path digest size kind executable?)
  #:transparent
  #:guard
  (lambda (path digest size kind executable? _)
    (unless (and (path-string? path) (absolute-path? path)
                 (digest? digest) (exact-nonnegative-integer? size)
                 (memq kind admitted-member-kinds) (boolean? executable?))
      (raise-arguments-error 'odra-bundle-content-handle
                             "invalid immutable content handle"))
    (values (copied path) (copied digest) size kind executable?)))

(struct odra-bundle-acquisition
  (request-id archive-path content downloaded-bytes offline? reused-digests)
  #:transparent
  #:guard
  (lambda (request-id archive-path content downloaded-bytes offline? reused-digests _)
    (unless (and (identity? request-id)
                 (path-string? archive-path)
                 (absolute-path? archive-path)
                 (list? content) (pair? content)
                 (andmap odra-bundle-content-handle? content)
                 (exact-nonnegative-integer? downloaded-bytes)
                 (boolean? offline?)
                 (or (not offline?) (zero? downloaded-bytes))
                 (list? reused-digests)
                 (equal? reused-digests
                         (sort (remove-duplicates reused-digests string=?) string<?))
                 (andmap digest? reused-digests))
      (raise-arguments-error 'odra-bundle-acquisition
                             "invalid completed bundle acquisition"))
    (values (copied request-id) (copied archive-path) content downloaded-bytes
            offline? (map copied reused-digests))))

(struct odra-bundle-bootstrap-acquisition
  (request-id archive-path member downloaded-bytes offline? reused-digests)
  #:transparent
  #:guard
  (lambda (request-id archive-path member downloaded-bytes offline? reused-digests _)
    (unless (and (identity? request-id)
                 (path-string? archive-path) (absolute-path? archive-path)
                 (odra-bundle-content-handle? member)
                 (exact-nonnegative-integer? downloaded-bytes)
                 (boolean? offline?)
                 (or (not offline?) (zero? downloaded-bytes))
                 (list? reused-digests)
                 (equal? reused-digests
                         (sort (remove-duplicates reused-digests string=?) string<?))
                 (andmap digest? reused-digests))
      (raise-arguments-error 'odra-bundle-bootstrap-acquisition
                             "invalid bootstrap member acquisition"))
    (values (copied request-id) (copied archive-path) member downloaded-bytes
            offline? (map copied reused-digests))))

(define failure-codes
  '(archive-checksum archive-format archive-member-count archive-member-digest
                     archive-member-size archive-path archive-type cancelled
                     cleanup credential decompression digest http-status limit
                     offline-miss publication redirect security-advisory size
                     timeout transport))

(struct odra-bundle-acquisition-failure (code message location)
  #:transparent
  #:guard
  (lambda (code message location _)
    (unless (and (memq code failure-codes) (string? message) (string? location))
      (raise-arguments-error 'odra-bundle-acquisition-failure
                             "invalid bounded acquisition failure"))
    (define bytes (string->bytes/utf-8 message))
    (values code
            (copied
             (if (<= (bytes-length bytes) maximum-message-bytes)
                 message
                 (bytes->string/utf-8
                  (subbytes bytes 0 maximum-message-bytes) #\uFFFD)))
            (copied location))))

(struct acquisition-response (status headers body) #:transparent)
(struct exn:fail:acquisition exn:fail (code location) #:transparent)

(define (raise-acquisition code message [location ""])
  (raise (exn:fail:acquisition message (current-continuation-marks)
                               code location)))

(define (status-code status)
  (match (regexp-match #px#"^HTTP/[0-9.]+ ([0-9]{3})" status)
    [(list _ code) (string->number (bytes->string/utf-8 code))]
    [_ 0]))

(define (request-header-lines headers)
  (for/list ([(name value) (in-hash headers)])
    (string->bytes/utf-8 (format "~a: ~a" name value))))

(define (default-transport-open location [headers (hash)])
  (cond
    [(regexp-match? #px"^https://" location)
     (define-values (status response-header-lines body)
       (http-sendrecv/url
        (string->url location)
        #:headers (request-header-lines headers)
        #:content-decode '()))
     (acquisition-response
      (status-code status)
      (for/hash ([header (in-list response-header-lines)]
                 #:do [(define matched
                         (regexp-match #px#"^([^:]+):[ ]*(.*)$" header))]
                 #:when matched)
        (values (string-downcase (bytes->string/utf-8 (cadr matched)))
                (bytes->string/utf-8 (caddr matched))))
      body)]
    [else
     (acquisition-response 200 (hash)
                           (open-input-file location #:mode 'binary))]))

(define current-acquisition-transport-open
  (make-parameter default-transport-open))

(define (default-archive-open archive-path)
  (define-values (process output input errors)
    (subprocess #f #f #f "/usr/bin/zstd" "-dc" "--"
                (path->string archive-path)))
  (close-output-port input)
  (values
   output
   (lambda (successful?)
     (unless successful? (subprocess-kill process #t))
     (close-input-port output)
     (subprocess-wait process)
     (define status (subprocess-status process))
     (port->bytes errors)
     (close-input-port errors)
     (or (not successful?) (zero? status)))))

(define current-acquisition-archive-open
  (make-parameter default-archive-open))

(define (language-bundle-content-path root digest)
  (unless (digest? digest)
    (raise-argument-error 'language-bundle-content-path "SHA-256 digest" digest))
  (build-path (path->complete-path root) "language-bundles" "content" "sha256"
              (substring digest 0 2) digest))

(define (acquisition-content-path root storage-directory digest)
  (unless (member storage-directory '("language-bundles" "packages") string=?)
    (raise-argument-error 'acquire-language-bundle
                          "an admitted acquisition storage directory"
                          storage-directory))
  (build-path (path->complete-path root) storage-directory "content" "sha256"
              (substring digest 0 2) digest))

(define (remaining-seconds deadline)
  (max 0.0 (/ (- deadline (current-inexact-monotonic-milliseconds)) 1000.0)))

(define (check-interruption cancelled? deadline location)
  (when (cancelled?)
    (raise-acquisition 'cancelled "bundle acquisition was cancelled" location))
  (when (<= (remaining-seconds deadline) 0)
    (raise-acquisition 'timeout "bundle acquisition deadline expired" location)))

(define (valid-request-headers? value)
  (and (hash? value)
       (<= (hash-count value) 8)
       (for/and ([(name content) (in-hash value)])
         (and (string? name) (string? content)
              (regexp-match? #px"^(?:authorization|x-[a-z0-9-]+)$"
                             (string-downcase name))
              (<= 1 (bytes-length (string->bytes/utf-8 content)) 4096)
              (not (string-contains? content "\r"))
              (not (string-contains? content "\n"))))))

(define (resolved-request-headers location resolver)
  (define resolved
    (with-handlers ([exn:fail? (lambda (_) #f)]) (resolver location)))
  (unless (valid-request-headers? resolved)
    (raise-acquisition 'credential
                       "artifact credential could not be resolved" location))
  (when (and (positive? (hash-count resolved))
             (not (regexp-match? #px"^https://" location)))
    (raise-acquisition 'credential
                       "artifact credentials require HTTPS" location))
  (for/hash ([(name content) (in-hash resolved)])
    (values (string-downcase name) content)))

(define (open-response location headers cancelled? deadline)
  (define result-channel (make-channel))
  (define worker-custodian (make-custodian))
  (parameterize ([current-custodian worker-custodian])
    (thread
     (lambda ()
       (with-handlers ([exn:fail? (lambda (observed)
                                    (channel-put result-channel (cons 'failure observed)))])
         (define opener (current-acquisition-transport-open))
         (define response
           (cond
             [(procedure-arity-includes? opener 2) (opener location headers)]
             [(and (zero? (hash-count headers))
                   (procedure-arity-includes? opener 1))
              (opener location)]
             [else
              (raise-acquisition
               'credential
               "artifact transport cannot accept credential headers"
               location)]))
         (channel-put result-channel (cons 'response response))))))
  (let loop ()
    (check-interruption cancelled? deadline location)
    (define observed
      (sync/timeout (min 0.05 (remaining-seconds deadline)) result-channel))
    (cond
      [(not observed) (loop)]
      [(eq? (car observed) 'failure)
       (custodian-shutdown-all worker-custodian)
       (raise-acquisition 'transport (exn-message (cdr observed)) location)]
      [else (values (cdr observed) worker-custodian)])))

(define (copy-response-to-file response output expected-size cancelled? deadline location)
  (unless (= (acquisition-response-status response) 200)
    (raise-acquisition 'http-status
                       (format "artifact source returned status ~a"
                               (acquisition-response-status response))
                       location))
  (define input (acquisition-response-body response))
  (define buffer (make-bytes transfer-buffer-bytes))
  (let loop ([total 0])
    (check-interruption cancelled? deadline location)
    (define ready
      (sync/timeout (min 0.05 (remaining-seconds deadline)) input))
    (cond
      [(not ready) (loop total)]
      [else
       (define read-count (read-bytes-avail! buffer input))
       (cond
         [(eof-object? read-count)
          (unless (= total expected-size)
            (raise-acquisition 'size "downloaded archive size does not match" location))
          total]
         [else
          (define next-total (+ total read-count))
          (when (> next-total expected-size)
            (raise-acquisition 'limit "download exceeded the declared byte ceiling" location))
          (write-bytes buffer output 0 read-count)
          (loop next-total)])])))

(define (file-digest path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (verified-content-file? path digest size)
  (and (file-exists? path)
       (not (link-exists? path))
       (not (durable-file-check path))
       (= (file-size path) size)
       (string=? (file-digest path) digest)))

(define (ensure-private-acquisition-directory path)
  (when (link-exists? path)
    (raise-acquisition 'publication
                       "bundle acquisition directory cannot be a symbolic link"
                       (path->string path)))
  (unless (directory-exists? path)
    (make-directory path)
    (file-or-directory-permissions path #o700))
  (define mode (hash-ref (file-or-directory-stat path #f) 'mode))
  (unless (zero? (bitwise-and mode #o077))
    (raise-acquisition 'publication
                       "bundle acquisition directory must be owner-only"
                       (path->string path))))

(define (tar-text header start end)
  (define field (subbytes header start end))
  (define nul (or (bytes-index field 0) (bytes-length field)))
  (bytes->string/utf-8 (subbytes field 0 nul)))

(define (bytes-index value byte)
  (for/first ([current (in-bytes value)] [index (in-naturals)]
              #:when (= current byte))
    index))

(define (tar-octal header start end)
  (define text (string-trim (tar-text header start end) #px"[ \u0000]+"))
  (and (regexp-match? #px"^[0-7]+$" text) (string->number text 8)))

(define (tar-checksum-valid? header)
  (define expected (tar-octal header 148 156))
  (and expected
       (= expected
          (for/sum ([byte (in-bytes header)] [index (in-naturals)])
            (if (<= 148 index 155) 32 byte)))))

(define (zero-block? block)
  (for/and ([byte (in-bytes block)]) (zero? byte)))

(define (read-exact input amount code message)
  (define value (read-bytes amount input))
  (unless (and (bytes? value) (= (bytes-length value) amount))
    (raise-acquisition code message))
  value)

(define (tar-member-path header)
  (define name (tar-text header 0 100))
  (define prefix (tar-text header 345 500))
  (if (string=? prefix "") name (string-append prefix "/" name)))

(define (copy-tar-member input output size cancelled? deadline)
  (define buffer (make-bytes transfer-buffer-bytes))
  (let loop ([remaining size])
    (unless (zero? remaining)
      (check-interruption cancelled? deadline "")
      (define amount (min remaining transfer-buffer-bytes))
      (define bytes (read-exact input amount 'archive-format
                                "archive member ended before its declared size"))
      (write-bytes bytes output)
      (loop (- remaining amount)))))

(define (extract-verified-members archive-path stage-root request cancelled? deadline)
  (define members (odra-bundle-archive-request-members request))
  (define-values (input finish) ((current-acquisition-archive-open) archive-path))
  (define successful? #f)
  (dynamic-wind
    void
    (lambda ()
      (define staged
        (let loop ([remaining members] [index 0] [result '()])
          (define header
            (read-exact input 512 'archive-format "archive ended before trailer"))
          (cond
            [(zero-block? header)
             (define second-trailer
               (read-exact input 512 'archive-format "archive trailer is incomplete"))
             (unless (zero-block? second-trailer)
               (raise-acquisition 'archive-format "archive trailer is malformed"))
             (unless (null? remaining)
               (raise-acquisition 'archive-member-count
                                  "archive omits declared members"))
             (reverse result)]
            [(null? remaining)
             (raise-acquisition 'archive-member-count
                                "archive contains undeclared members")]
            [else
             (unless (tar-checksum-valid? header)
               (raise-acquisition 'archive-checksum "invalid TAR header checksum"))
             (define expected (car remaining))
             (define path (tar-member-path header))
             (unless (archive-path? path)
               (raise-acquisition 'archive-path "archive member path escapes its root" path))
             (unless (string=? path (odra-bundle-archive-member-path expected))
               (raise-acquisition 'archive-path
                                  "archive member order or path differs from the manifest" path))
             (define type (bytes-ref header 156))
             (unless (or (= type 0) (= type (char->integer #\0)))
               (raise-acquisition 'archive-type
                                  "archive contains a link, device, or unsupported member" path))
             (define size (tar-octal header 124 136))
             (unless (and size (= size (odra-bundle-archive-member-size expected)))
               (raise-acquisition 'archive-member-size
                                  "archive member size differs from the manifest" path))
             (define staged-path (build-path stage-root (format "member-~a" index)))
             (call-with-output-file staged-path
               (lambda (output)
                 (copy-tar-member input output size cancelled? deadline))
               #:exists 'error #:mode 'binary #:permissions #o600)
             (file-or-directory-permissions staged-path #o600)
             (define padding (modulo (- 512 (modulo size 512)) 512))
             (when (positive? padding)
               (read-exact input padding 'archive-format
                           "archive member padding is incomplete"))
             (unless (string=? (file-digest staged-path)
                               (odra-bundle-archive-member-digest expected))
               (raise-acquisition 'archive-member-digest
                                  "archive member digest differs from the manifest" path))
             (loop (cdr remaining) (add1 index)
                   (cons (cons expected staged-path) result))])))
      (set! successful? #t)
      staged)
    (lambda ()
      (unless (finish successful?)
        (raise-acquisition 'decompression "zstd decompression failed")))))

(define (discard-tar-member input size cancelled? deadline)
  (copy-tar-member input (open-output-nowhere) size cancelled? deadline))

(define (extract-bootstrap-member archive-path stage-root expected-path
                                  expected-digest member-byte-limit
                                  cancelled? deadline)
  (define-values (input finish) ((current-acquisition-archive-open) archive-path))
  (define successful? #f)
  (dynamic-wind
    void
    (lambda ()
      (define result #f)
      (let loop ([index 0] [expanded 0] [paths '()])
        (define header
          (read-exact input 512 'archive-format "archive ended before trailer"))
        (cond
          [(zero-block? header)
           (define second-trailer
             (read-exact input 512 'archive-format "archive trailer is incomplete"))
           (unless (zero-block? second-trailer)
             (raise-acquisition 'archive-format "archive trailer is malformed"))
           (unless result
             (raise-acquisition 'archive-member-count
                                "archive omits the bootstrap member"))]
          [else
           (when (>= index maximum-archive-entries)
             (raise-acquisition 'archive-member-count
                                "archive exceeds the member-count ceiling"))
           (unless (tar-checksum-valid? header)
             (raise-acquisition 'archive-checksum "invalid TAR header checksum"))
           (define path (tar-member-path header))
           (unless (archive-path? path)
             (raise-acquisition 'archive-path
                                "archive member path escapes its root" path))
           (when (member path paths string=?)
             (raise-acquisition 'archive-path
                                "archive contains duplicate member paths" path))
           (define type (bytes-ref header 156))
           (unless (or (= type 0) (= type (char->integer #\0)))
             (raise-acquisition 'archive-type
                                "archive contains a link, device, or unsupported member"
                                path))
           (define size (tar-octal header 124 136))
           (unless size
             (raise-acquisition 'archive-format
                                "archive member size is malformed" path))
           (define next-expanded (+ expanded size))
           (when (> next-expanded maximum-expanded-bytes)
             (raise-acquisition 'limit
                                "archive exceeds the expanded-byte ceiling" path))
           (cond
             [(zero? index)
              (unless (string=? path expected-path)
                (raise-acquisition 'archive-path
                                   "bootstrap member is not first in the archive" path))
              (when (> size member-byte-limit)
                (raise-acquisition 'limit
                                   "bootstrap member exceeds its byte ceiling" path))
              (define staged-path (build-path stage-root "bootstrap-member"))
              (call-with-output-file staged-path
                (lambda (output)
                  (copy-tar-member input output size cancelled? deadline))
                #:exists 'error #:mode 'binary #:permissions #o600)
              (file-or-directory-permissions staged-path #o600)
              (unless (string=? (file-digest staged-path) expected-digest)
                (raise-acquisition 'archive-member-digest
                                   "bootstrap member digest differs from the catalog"
                                   path))
              (set! result (cons staged-path size))]
             [else
              (discard-tar-member input size cancelled? deadline)])
           (define padding (modulo (- 512 (modulo size 512)) 512))
           (when (positive? padding)
             (read-exact input padding 'archive-format
                         "archive member padding is incomplete"))
           (loop (add1 index) next-expanded (cons path paths))]))
      (set! successful? #t)
      result)
    (lambda ()
      (unless (finish successful?)
        (raise-acquisition 'decompression "zstd decompression failed")))))

(define (publish-content-file root storage-directory stage digest size)
  (define target (acquisition-content-path root storage-directory digest))
  (cond
    [(file-exists? target)
     (unless (verified-content-file? target digest size)
       (raise-acquisition 'publication
                          "immutable content path contains different bytes"
                          (path->string target)))
     (delete-file stage)
     (values target #t)]
    [else
     (define result
       (durable-file-publish-existing
        stage target
        #:private-directories
        (list root (build-path root storage-directory)
              (build-path root storage-directory "content")
              (build-path root storage-directory "content" "sha256")
              (path-only target))
        #:validate-stage
        (lambda (candidate) (verified-content-file? candidate digest size))))
     (unless (and (odra-durable-file-publication? result)
                  (eq? (odra-durable-file-publication-publication result)
                       'published-durable))
       (raise-acquisition 'publication "immutable content publication failed"
                          (path->string target)))
     (values target #f)]))

(define retry-statuses '(408 429 500 502 503 504))
(define redirect-statuses '(301 302 307 308))

(define (uri-authority location)
  (define parsed (string->url location))
  (list (string-downcase (url-host parsed)) (or (url-port parsed) 443)))

(define (download-archive stage request request-headers cancelled? deadline
                          redirect-limit retry-limit)
  (define (try-location location redirects retries credential-authority)
    (define headers (resolved-request-headers location request-headers))
    (define request-authority
      (and (positive? (hash-count headers)) (uri-authority location)))
    (define admitted-authority (or credential-authority request-authority))
    (when (and credential-authority
               (not (equal? credential-authority (uri-authority location))))
      (raise-acquisition
       'redirect "credentialed artifact redirect changed HTTPS authority"
       location))
    (define opened
      (with-handlers ([exn:fail:acquisition?
                       (lambda (observed) (cons 'failure observed))])
        (define-values (response owner)
          (open-response location headers cancelled? deadline))
        (list 'response response owner)))
    (cond
      [(eq? (car opened) 'failure)
       (define observed (cdr opened))
       (cond
         [(memq (exn:fail:acquisition-code observed) '(cancelled timeout))
          (raise observed)]
         [(positive? retries)
          (try-location location redirects (sub1 retries) admitted-authority)]
         [else (raise observed)])]
      [else
       (define response (cadr opened))
       (define owner (caddr opened))
       (define status (acquisition-response-status response))
       (cond
         [(= status 200)
          (define copy-failure
            (with-handlers ([exn:fail:acquisition? values])
              (dynamic-wind
                void
                (lambda ()
                  (call-with-output-file stage
                    (lambda (output)
                      (copy-response-to-file
                       response output
                       (odra-bundle-archive-request-archive-size request)
                       cancelled? deadline location))
                    #:exists 'truncate/replace #:mode 'binary #:permissions #o600))
                (lambda () (custodian-shutdown-all owner)))
              #f))
          (cond
            [(not copy-failure)
             (file-or-directory-permissions stage #o600)
             (unless (string=? (file-digest stage)
                               (odra-bundle-archive-request-archive-digest request))
               (raise-acquisition 'digest "downloaded archive digest does not match"
                                  location))
             (odra-bundle-archive-request-archive-size request)]
            [(memq (exn:fail:acquisition-code copy-failure) '(cancelled timeout))
             (raise copy-failure)]
            [(positive? retries)
             (try-location location redirects (sub1 retries)
                           admitted-authority)]
            [else (raise copy-failure)])]
         [(memq status redirect-statuses)
          (define redirected
            (hash-ref (acquisition-response-headers response) "location" #f))
          (custodian-shutdown-all owner)
          (unless (and redirected
                       (regexp-match? #px"^https://" redirected)
                       (location? redirected))
            (raise-acquisition 'http-status
                               "redirect location is absent or unsafe" location))
          (when (zero? redirects)
            (raise-acquisition 'limit "artifact redirect ceiling exceeded" location))
          (when (and admitted-authority
                     (not (equal? admitted-authority
                                  (uri-authority redirected))))
            (raise-acquisition
             'redirect "credentialed artifact redirect changed HTTPS authority"
             location))
          (try-location redirected (sub1 redirects) retries admitted-authority)]
         [(and (memq status retry-statuses) (positive? retries))
          (custodian-shutdown-all owner)
          (try-location location redirects (sub1 retries) admitted-authority)]
         [else
          (custodian-shutdown-all owner)
          (raise-acquisition 'http-status
                             (format "artifact source returned status ~a" status)
                             location)])]))
  (let loop ([locations (odra-bundle-archive-request-locations request)]
             [latest #f])
    (cond
      [(null? locations)
       (if latest (raise latest)
           (raise-acquisition 'transport "no artifact source is available"))]
      [else
       (define location (car locations))
       (with-handlers ([exn:fail:acquisition?
                        (lambda (observed)
                          (if (memq (exn:fail:acquisition-code observed)
                                    '(cancelled timeout))
                              (raise observed)
                              (loop (cdr locations) observed)))])
         (try-location location redirect-limit retry-limit #f))])))

(define (acquire-language-bundle root request
                                 #:offline? [offline? #f]
                                 #:storage-directory
                                 [storage-directory "language-bundles"]
                                 #:request-headers
                                 [request-headers (lambda (_location) (hash))]
                                 #:advisory-evaluator
                                 [advisory-evaluator
                                  (lambda (_phase _package-id _release-id
                                                  _artifact-digests _installed?
                                                  _active?)
                                    (odra-security-advisory-response '() '() '()))]
                                 #:cancelled? [cancelled? (lambda () #f)]
                                 #:deadline-milliseconds [deadline-milliseconds 60000]
                                 #:redirect-limit [redirect-limit 4]
                                 #:retry-limit [retry-limit 2])
  (define complete-root (path->complete-path root))
  (unless (member storage-directory '("language-bundles" "packages") string=?)
    (raise-argument-error 'acquire-language-bundle
                          "an admitted acquisition storage directory"
                          storage-directory))
  (define stage-root
    (build-path complete-root storage-directory "staging"
                (odra-bundle-archive-request-id request)))
  (define archive-target
    (acquisition-content-path
     complete-root storage-directory
     (odra-bundle-archive-request-archive-digest request)))
  (define deadline (+ (current-inexact-monotonic-milliseconds)
                      deadline-milliseconds))
  (define created-stage? #f)
  (with-handlers
      ([exn:fail:acquisition?
        (lambda (observed)
          (with-handlers ([exn:fail? void])
            (when (and created-stage? (directory-exists? stage-root))
              (delete-directory/files stage-root)))
          (odra-bundle-acquisition-failure
           (exn:fail:acquisition-code observed) (exn-message observed)
           (exn:fail:acquisition-location observed)))]
       [exn:fail?
        (lambda (observed)
          (with-handlers ([exn:fail? void])
            (when (and created-stage? (directory-exists? stage-root))
              (delete-directory/files stage-root)))
          (odra-bundle-acquisition-failure 'cleanup (exn-message observed) ""))])
    (define declared-content
      (sort
       (remove-duplicates
        (cons
         (odra-bundle-archive-request-archive-digest request)
         (map odra-bundle-archive-member-digest
              (odra-bundle-archive-request-members request)))
        string=?)
       string<?))
    (define advisory-response
      (advisory-evaluator
       'acquisition (odra-bundle-archive-request-id request) #f
       declared-content #f #f))
    (when (member 'block-acquisition
                  (odra-security-advisory-response-actions advisory-response))
      (raise-acquisition
       'security-advisory
       "local security policy blocks acquisition of this exact content"))
    (when (directory-exists? stage-root)
      (raise-acquisition 'publication "bundle acquisition staging already exists"))
    (unless (directory-exists? complete-root)
      (make-directory* complete-root)
      (file-or-directory-permissions complete-root #o700))
    (for ([directory
           (in-list
            (list complete-root
                  (build-path complete-root storage-directory)
                  (build-path complete-root storage-directory "staging")
                  stage-root))])
      (ensure-private-acquisition-directory directory))
    (set! created-stage? #t)
    (define archive-stage (build-path stage-root "archive.tar.zst"))
    (define archive-cached?
      (verified-content-file?
       archive-target (odra-bundle-archive-request-archive-digest request)
       (odra-bundle-archive-request-archive-size request)))
    (define downloaded-bytes
      (cond
        [archive-cached? 0]
        [offline?
         (raise-acquisition 'offline-miss
                            "verified archive is absent from the offline content store")]
        [else
         (when (> redirect-limit 8)
           (raise-acquisition 'limit "redirect limit exceeds the acquisition maximum"))
         (when (> retry-limit 8)
           (raise-acquisition 'limit "retry limit exceeds the acquisition maximum"))
         (download-archive archive-stage request request-headers cancelled? deadline
                           redirect-limit retry-limit)]))
    (define archive-input (if archive-cached? archive-target archive-stage))
    (define staged-members
      (extract-verified-members archive-input stage-root request cancelled? deadline))
    (define reused '())
    (unless archive-cached?
      (define-values (_target archive-reused?)
        (publish-content-file
         complete-root storage-directory archive-stage
         (odra-bundle-archive-request-archive-digest request)
         (odra-bundle-archive-request-archive-size request)))
      (when archive-reused?
        (set! reused
              (cons (odra-bundle-archive-request-archive-digest request) reused))))
    (define handles
      (for/list ([staged (in-list staged-members)])
        (define member (car staged))
        (define-values (target reused?)
          (publish-content-file complete-root storage-directory (cdr staged)
                                (odra-bundle-archive-member-digest member)
                                (odra-bundle-archive-member-size member)))
        (when reused?
          (set! reused (cons (odra-bundle-archive-member-digest member) reused)))
        (odra-bundle-content-handle
         (path->string target) (odra-bundle-archive-member-digest member)
         (odra-bundle-archive-member-size member)
         (odra-bundle-archive-member-kind member)
         (odra-bundle-archive-member-executable? member))))
    (delete-directory/files stage-root)
    (odra-bundle-acquisition
     (odra-bundle-archive-request-id request)
     (path->string archive-target) handles downloaded-bytes offline?
     (sort (remove-duplicates reused string=?) string<?))))

(define (acquire-language-bundle-bootstrap-member
         root request-id locations archive-digest archive-size
         member-path member-digest
         #:offline? [offline? #f]
         #:storage-directory [storage-directory "language-bundles"]
         #:member-byte-limit [member-byte-limit (* 8 1024 1024)]
         #:request-headers [request-headers (lambda (_location) (hash))]
         #:cancelled? [cancelled? (lambda () #f)]
         #:deadline-milliseconds [deadline-milliseconds 60000]
         #:redirect-limit [redirect-limit 4]
         #:retry-limit [retry-limit 2])
  (define request
    (odra-bundle-archive-request
     request-id locations archive-digest archive-size
     (list (odra-bundle-archive-member
            member-path member-digest member-byte-limit 'manifest #f))
     1 member-byte-limit))
  (define complete-root (path->complete-path root))
  (define stage-root
    (build-path complete-root storage-directory "staging"
                (string-append request-id "-bootstrap")))
  (define archive-target
    (acquisition-content-path complete-root storage-directory archive-digest))
  (define deadline (+ (current-inexact-monotonic-milliseconds)
                      deadline-milliseconds))
  (define created-stage? #f)
  (with-handlers
      ([exn:fail:acquisition?
        (lambda (observed)
          (with-handlers ([exn:fail? void])
            (when (and created-stage? (directory-exists? stage-root))
              (delete-directory/files stage-root)))
          (odra-bundle-acquisition-failure
           (exn:fail:acquisition-code observed) (exn-message observed)
           (exn:fail:acquisition-location observed)))]
       [exn:fail?
        (lambda (observed)
          (with-handlers ([exn:fail? void])
            (when (and created-stage? (directory-exists? stage-root))
              (delete-directory/files stage-root)))
          (odra-bundle-acquisition-failure 'cleanup (exn-message observed) ""))])
    (unless (directory-exists? complete-root)
      (make-directory* complete-root)
      (file-or-directory-permissions complete-root #o700))
    (for ([directory
           (in-list
            (list complete-root
                  (build-path complete-root storage-directory)
                  (build-path complete-root storage-directory "staging")
                  stage-root))])
      (ensure-private-acquisition-directory directory))
    (set! created-stage? #t)
    (define archive-stage (build-path stage-root "archive.tar.zst"))
    (define archive-cached?
      (verified-content-file? archive-target archive-digest archive-size))
    (define downloaded-bytes
      (cond
        [archive-cached? 0]
        [offline?
         (raise-acquisition 'offline-miss
                            "verified archive is absent from the offline content store")]
        [else
         (when (> redirect-limit 8)
           (raise-acquisition 'limit "redirect limit exceeds the acquisition maximum"))
         (when (> retry-limit 8)
           (raise-acquisition 'limit "retry limit exceeds the acquisition maximum"))
         (download-archive archive-stage request request-headers cancelled? deadline
                           redirect-limit retry-limit)]))
    (define archive-input (if archive-cached? archive-target archive-stage))
    (define staged-member
      (extract-bootstrap-member archive-input stage-root member-path member-digest
                                member-byte-limit cancelled? deadline))
    (define reused '())
    (unless archive-cached?
      (define-values (_target archive-reused?)
        (publish-content-file complete-root storage-directory archive-stage
                              archive-digest archive-size))
      (when archive-reused? (set! reused (cons archive-digest reused))))
    (define-values (member-target member-reused?)
      (publish-content-file complete-root storage-directory
                            (car staged-member) member-digest
                            (cdr staged-member)))
    (when member-reused? (set! reused (cons member-digest reused)))
    (delete-directory/files stage-root)
    (odra-bundle-bootstrap-acquisition
     request-id (path->string archive-target)
     (odra-bundle-content-handle
      (path->string member-target) member-digest (cdr staged-member)
      'manifest #f)
     downloaded-bytes offline?
     (sort (remove-duplicates reused string=?) string<?))))

(module+ test-support
  (provide current-acquisition-transport-open
           current-acquisition-archive-open
           (struct-out acquisition-response)))
