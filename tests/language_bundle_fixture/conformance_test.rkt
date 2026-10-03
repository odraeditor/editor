#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         json
         racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         rackunit
         "bundle.rkt"
         (prefix-in bundle: "../../src/command/language-bundles.rkt")
         "../../src/language_bundle/acquisition.rkt"
         (submod "../../src/language_bundle/acquisition.rkt" test-support)
         "../../src/language_bundle/activation-candidate.rkt"
         "../../src/language_bundle/activation-runtime.rkt"
         "../../src/language_bundle/catalog-contracts.rkt"
         "../../src/language_bundle/catalog-integrity.rkt"
         (submod "../../src/language_bundle/catalog-integrity.rkt" test-support)
         "../../src/language_bundle/catalog-resolution.rkt"
         "../../src/language_bundle/factory-bundles.rkt"
         "../../src/language_bundle/lifecycle.rkt"
         "../../src/language_bundle/state-persistence.rkt"
         "../../src/language_bundle/state-records.rkt")

(define-runtime-path fixture-root ".")
(define grammar-path
  (string->path
   (or (getenv "ODRA_EXTERNAL_BUNDLE_GRAMMAR")
       (path->string
        (build-path fixture-root "../../.build/syntax-provider-fixture/libtree-sitter-odin.so")))))

(define public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define secret-key
  (string-append
   "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
   public-key))
(define key-id
  "21fe31dfa154a261626bf854046fd2271b7bed4b6abe45aa58877ef47f9721b9")
(define facets '(command formatter keymap language service syntax-provider))
(define authorities '(external-process native-grammar project-read))

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
  (bytes-append header content (make-bytes padding 0)))

(define (tar-archive members)
  (bytes-append
   (apply bytes-append
          (for/list ([member (in-list members)])
            (tar-file (car member) (cdr member))))
   (make-bytes 1024 0)))

(define fixture-members
  (list
   (cons "manifest/bundle.rkt" (file->bytes (build-path fixture-root "bundle.rkt")))
   (cons "grammar/libtree-sitter-quill.so" (file->bytes grammar-path))
   (cons "queries/highlights.scm"
         (file->bytes (build-path fixture-root "queries/highlights.scm")))
   (cons "server/server.rkt" (file->bytes (build-path fixture-root "server.rkt")))))

(define member-kinds '(manifest tree-sitter-grammar query racket-module))
(define member-ids '(quill.manifest quill.grammar quill.highlights quill.server))
(define archive-members
  (for/list ([member (in-list fixture-members)] [kind (in-list member-kinds)])
    (odra-bundle-archive-member
     (car member) (sha256 (cdr member)) (bytes-length (cdr member)) kind #f)))
(define archive-bytes (tar-archive fixture-members))
(define archive-request
  (odra-bundle-archive-request
   "org.example.quill" '("/fixture/quill.tar")
   (sha256 archive-bytes) (bytes-length archive-bytes)
   archive-members 16 (* 32 1024 1024)))

(define artifact-metadata
  (for/hasheq ([id (in-list member-ids)] [member (in-list archive-members)])
    (values id
            (cons (odra-bundle-archive-member-digest member)
                  (odra-bundle-archive-member-size member)))))

(define (raw-archive-open path)
  (values (open-input-file path #:mode 'binary) (lambda (_) #t)))

(define (signed-catalog root manifest-digest artifact-bytes)
  (define signing-key (odra-catalog-signing-key key-id 'ed25519 public-key))
  (define source
    (odra-catalog-source
     "local-quill" 'local-file
     (path->string (path->complete-path (build-path root "catalog.rktd")))
     10
     (odra-catalog-refresh-policy 'manual 0 86400)
     (list signing-key) 'offline #f
     (odra-catalog-resource-limits
      maximum-catalog-snapshot-bytes maximum-catalog-entries
      maximum-catalog-artifact-descriptors 60000 0 0)))
  (define entries
    (for/list ([version (in-list '("1.0.0" "1.1.0"))])
      (odra-catalog-entry
       "org.example.quill" version "1.0.0" "2.0.0"
       (list (odra-catalog-target 'linux 'x86-64))
       manifest-digest '("manifest/bundle.rkt")
       "Quill" "External language conformance fixture"
       facets authorities '() (length archive-members) artifact-bytes #f #f)))
  (define placeholder
    (odra-catalog-signature
     'ed25519 key-id "odra-language-catalog-v1" (make-string 128 #\0)))
  (define unsigned
    (odra-catalog-snapshot
     1 "local-quill" 1 (make-string 64 #\0)
     (odra-catalog-expiry 1 1000 2)
     (catalog-entries-digest entries) key-id placeholder entries 4096))
  (define detached
    (odra-catalog-signature
     'ed25519 key-id "odra-language-catalog-v1"
     (sign-for-test (catalog-snapshot-signature-message unsigned) secret-key)))
  (define signed-without-digest
    (struct-copy odra-catalog-snapshot unsigned [signature detached]))
  (define signed
    (struct-copy
     odra-catalog-snapshot signed-without-digest
     [snapshot-digest (catalog-snapshot-content-digest signed-without-digest)]))
  (call-with-output-file (odra-catalog-source-endpoint source)
    (lambda (output) (write signed output) (newline output))
    #:exists 'truncate/replace)
  (values source signed))

(define (acquisition-handles acquisition)
  (for/hasheq ([id (in-list member-ids)]
               [handle (in-list (odra-bundle-acquisition-content acquisition))])
    (define content-path (odra-bundle-content-handle-path handle))
    (values
     id
     (odra-bundle-artifact-handle
      id
      (odra-bundle-content-handle-digest handle)
      (odra-bundle-content-handle-size handle)
      (if (path? content-path) (path->string content-path) content-path)
      #t))))

(define (install-request version handles manifest-digest)
  (define value (make-quill-bundle version artifact-metadata))
  (odra-bundle-install-request
   (odra-bundle-preparation-input
    value 'package "" authorities handles (hasheq) 0)
   manifest-digest 'linux 'x86-64
   "User approved the signed fixture source and native grammar"
   (cdr (hash-ref artifact-metadata 'quill.manifest))
   (for/sum ([metadata (in-hash-values artifact-metadata)]) (cdr metadata))))

(define (result-state result)
  (odra-bundle-lifecycle-result-state result))

(define (effective-entry snapshot kind identity)
  (hash-ref (odra-bundle-runtime-snapshot-effective snapshot) (cons kind identity)))

(define (write-message output value)
  (define body (jsexpr->bytes value))
  (fprintf output "Content-Length: ~a\r\n\r\n" (bytes-length body))
  (write-bytes body output)
  (flush-output output))

(define (read-message input)
  (check-not-false (sync/timeout 15 input) "fixture server response timed out")
  (define content-length #f)
  (let loop ()
    (define line (read-line input 'any))
    (cond
      [(eof-object? line) (fail-check "fixture server closed its output")]
      [(string=? line "")
       (check-not-false content-length "fixture response omitted Content-Length")
       (bytes->jsexpr (read-bytes content-length input))]
      [else
       (define match (regexp-match #rx"(?i:^Content-Length:[ ]*([0-9]+)$)" line))
       (when match (set! content-length (string->number (cadr match))))
       (loop)])))

(define (check-real-service server-path root)
  (define executable (find-executable-path "racket"))
  (check-not-false executable "racket executable is required for the fixture service")
  (define-values (server server-output server-input server-error)
    (subprocess #f #f #f executable server-path))
  (dynamic-wind
   void
   (lambda ()
     (define root-uri (string-append "file://" (path->string root)))
     (write-message
      server-input
      (hasheq 'jsonrpc "2.0" 'id 1 'method "initialize"
              'params (hasheq 'processId 'null 'rootUri root-uri
                              'capabilities (hasheq))))
     (define initialized (read-message server-output))
     (check-true
      (hash? (hash-ref (hash-ref initialized 'result (hasheq)) 'capabilities #f)))
     (write-message
      server-input
      (hasheq 'jsonrpc "2.0" 'id 2 'method "textDocument/completion"
              'params
              (hasheq 'textDocument (hasheq 'uri (string-append root-uri "/main.quill"))
                      'position (hasheq 'line 0 'character 1))))
     (define completion (read-message server-output))
     (check-equal?
      (hash-ref (car (hash-ref completion 'result)) 'label)
      "quillValue")
     (write-message server-input
                    (hasheq 'jsonrpc "2.0" 'id 3 'method "shutdown" 'params 'null))
     (check-equal? (hash-ref (read-message server-output) 'id) 3)
     (write-message server-input
                    (hasheq 'jsonrpc "2.0" 'method "exit" 'params 'null))
     (check-not-false (sync/timeout 15 server) "fixture server shutdown timed out")
     (subprocess-wait server)
     (check-equal? (subprocess-status server) 0 (port->string server-error)))
   (lambda ()
     (when (eq? (subprocess-status server) 'running) (subprocess-kill server #t))
     (close-output-port server-input)
     (close-input-port server-output)
     (close-input-port server-error))))

(test-case "external bundle completes signed acquisition activation and removal"
  (check-false (factory-language-bundle-find 'org.example.quill))
  (define root (make-temporary-file "odra-quill-conformance-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
   void
   (lambda ()
     (define manifest-digest (car (hash-ref artifact-metadata 'quill.manifest)))
     (define-values (source snapshot)
       (signed-catalog
        root manifest-digest
        (for/sum ([metadata (in-hash-values artifact-metadata)]) (cdr metadata))))
     (check-true (verify-catalog-snapshot source snapshot))
     (define resolved-v1
       (resolve-catalog-candidates
        (list source) (list snapshot)
        (list (odra-catalog-resolution-request
               "org.example.quill" "1.0.0" "1.0.0" facets))
        'linux 'x86-64 "1.0.0" 100
        #:granted-authorities authorities))
     (check-true (odra-catalog-resolution? resolved-v1))
     (check-equal?
      (odra-catalog-resolved-bundle-version
       (car (odra-catalog-resolution-bundles resolved-v1)))
      "1.0.0")
     (define tampered-entry
       (struct-copy odra-catalog-entry
                    (car (odra-catalog-snapshot-entries snapshot))
                    [summary "tampered"]))
     (define tampered
       (struct-copy odra-catalog-snapshot snapshot
                    [entries (cons tampered-entry
                                   (cdr (odra-catalog-snapshot-entries snapshot)))]))
     (check-eq?
      (odra-catalog-integrity-failure-code
       (verify-catalog-snapshot source tampered))
      'entries-digest)

     (define acquisition
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_)
               (acquisition-response 200 (hash) (open-input-bytes archive-bytes)))]
            [current-acquisition-archive-open raw-archive-open])
         (acquire-language-bundle root archive-request)))
     (check-true (odra-bundle-acquisition? acquisition))
     (define offline
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_) (error 'transport "offline acquisition used transport"))]
            [current-acquisition-archive-open raw-archive-open])
         (acquire-language-bundle root archive-request #:offline? #t)))
     (check-true (odra-bundle-acquisition? offline))
     (check-true (odra-bundle-acquisition-offline? offline))
     (define handles (acquisition-handles acquisition))
     (define request-v1 (install-request "1.0.0" handles manifest-digest))
     (define request-v2 (install-request "1.1.0" handles manifest-digest))
     (define manager
       (make-bundle-lifecycle-manager root #:inputs (list request-v1 request-v2)))
     (check-eq? (result-state (bundle-lifecycle-install! manager request-v1)) 'installed)
     (check-eq?
      (result-state
       (bundle-lifecycle-enable! manager "org.example.quill" "1.0.0"))
      'enable)
     (define active (bundle-lifecycle-runtime-snapshot manager))
     (for ([key (in-list
                 (list (cons 'language 'quill)
                       (cons 'syntax-provider 'quill.syntax)
                       (cons 'service 'quill.fixture-lsp)
                       (cons 'formatter 'quill.format)
                       (cons 'command 'quill.describe)
                       (cons 'keymap 'quill.direct)
                       (cons 'keymap 'quill.modal)))])
       (check-equal?
        (odra-bundle-runtime-entry-bundle-id
         (effective-entry active (car key) (cdr key)))
        "org.example.quill"))
     (check-equal?
      (bundle:odra-language-keymap-states
       (odra-bundle-runtime-entry-value
        (effective-entry active 'keymap 'quill.direct)))
      '(direct))
     (check-equal?
      (bundle:odra-language-keymap-states
       (odra-bundle-runtime-entry-value
        (effective-entry active 'keymap 'quill.modal)))
      '(modal-normal))

     (define restarted
       (make-bundle-lifecycle-manager root #:inputs (list request-v1 request-v2)))
     (check-not-false (bundle-lifecycle-runtime-snapshot restarted))
     (check-eq? (result-state (bundle-lifecycle-update! restarted request-v2)) 'updated)
     (check-eq?
      (result-state (bundle-lifecycle-rollback! restarted "org.example.quill"))
      'rolled-back)
     (check-eq?
      (result-state (bundle-lifecycle-disable! restarted "org.example.quill"))
      'disable)
     (check-real-service
      (odra-bundle-artifact-handle-handle (hash-ref handles 'quill.server)) root)
     (check-eq?
      (result-state
       (bundle-lifecycle-remove! restarted "org.example.quill" "1.1.0"))
      'removed)
     (check-eq?
      (result-state
       (bundle-lifecycle-remove! restarted "org.example.quill" "1.0.0"))
      'removed)
     (check-false
      (odra-language-bundle-state-previous-lock
       (bundle-lifecycle-state restarted)))
     (define paths-by-digest
       (for/hash ([handle (in-hash-values handles)])
         (values (odra-bundle-artifact-handle-digest handle)
                 (odra-bundle-artifact-handle-handle handle))))
     (define collected
       (bundle-lifecycle-garbage-collect!
        restarted
        (sort (remove-duplicates (hash-keys paths-by-digest) string=?) string<?)
        (lambda (digest)
          (define path (hash-ref paths-by-digest digest))
          (and (file-exists? path) (delete-file path) #t))))
     (check-eq? (result-state collected) 'garbage-collected)
     (check-equal?
      (sort (odra-bundle-lifecycle-result-values collected) string<?)
      (sort (hash-keys paths-by-digest) string<?)))
   (lambda () (delete-directory/files root))))
