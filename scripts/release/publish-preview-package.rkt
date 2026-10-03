#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system
         "preview-identity.rkt")

(provide (struct-out publication-result)
         publication-file-errors
         publish-preview-package!)

(struct publication-result (state files urls) #:transparent)
(struct publication-file (name path digest) #:transparent)
(struct remote-file (file url status digest) #:transparent)

(define safe-component-pattern #px"^[A-Za-z0-9][A-Za-z0-9._-]*$")
(define secure-server-pattern #px"^https://[^[:space:]/]+(?:/[^[:space:]]*)?$")

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (regular-file? path)
  (eq? (file-or-directory-type path #f) 'file))

(define (artifact-url server-url owner package version filename)
  (string-append (string-trim server-url "/" #:left? #f)
                 "/api/packages/" owner "/generic/" package "/" version "/"
                 filename))

(define (publication-files identity directory)
  (for/list ([name (in-list (list (preview-archive-name identity)
                                  (preview-checksum-name identity)
                                  (preview-terms-name identity)
                                  (preview-notices-name identity)))])
    (define path (build-path directory name))
    (publication-file name
                      path
                      (if (regular-file? path) (sha256-file path) ""))))

(define (checksum-record path)
  (if (regular-file? path)
      (string-split (string-trim (file->string path)))
      '()))

(define (publication-file-errors identity directory)
  (define files (publication-files identity directory))
  (define archive (first files))
  (define checksum (second files))
  (define terms (third files))
  (define notices (fourth files))
  (define checksum-fields (checksum-record (publication-file-path checksum)))
  (append
   (for/list ([file (in-list files)]
              #:unless (regular-file? (publication-file-path file)))
     (format "publication file is unavailable: ~a" (publication-file-name file)))
   (if (and (= (length checksum-fields) 2)
            (equal? (first checksum-fields) (publication-file-digest archive))
            (equal? (second checksum-fields) (publication-file-name archive)))
       '()
       '("checksum does not identify the publication archive"))
   (if (and (regular-file? (publication-file-path terms))
            (positive? (file-size (publication-file-path terms))))
       '()
       '("public preview terms are empty"))
   (if (and (regular-file? (publication-file-path notices))
            (positive? (file-size (publication-file-path notices))))
       '()
       '("public third-party notices are empty"))))

(define (sanitized-message message token)
  (if (and (string? token) (not (string=? token "")))
      (string-replace message token "[redacted]")
      message))

(define (raise-registry-error token format-string . values)
  (raise-user-error
   'preview-publication
   "~a"
   (sanitized-message (apply format format-string values) token)))

(define (curl-request method url token [upload-path #f])
  (define curl (find-executable-path "curl"))
  (unless curl
    (raise-registry-error token "curl is unavailable"))
  (define response-path (make-temporary-file "preview-registry-response-~a"))
  (define header-path (make-temporary-file "preview-registry-header-~a"))
  (dynamic-wind
   (lambda ()
     (call-with-output-file header-path
       #:exists 'truncate
       (lambda (output)
         (when token (fprintf output "Authorization: token ~a\n" token))))
     (file-or-directory-permissions header-path #o600))
   (lambda ()
     (define arguments
       (append
        (list "--silent"
              "--show-error"
              "--output" (path->string response-path)
              "--write-out" "%{http_code}"
              "--request" method)
        (if token (list "--header" (string-append "@" (path->string header-path))) '())
        (if upload-path (list "--upload-file" (path->string upload-path)) '())
        (list url)))
     (define-values (process standard-output standard-input standard-error)
       (apply subprocess #f #f #f curl arguments))
     (close-output-port standard-input)
     (define status-text (string-trim (port->string standard-output)))
     (define error-text (string-trim (port->string standard-error)))
     (subprocess-wait process)
     (unless (zero? (subprocess-status process))
       (raise-registry-error token
                             "registry request failed: ~a"
                             (if (string=? error-text "")
                                 "curl failed"
                                 error-text)))
     (define status (string->number status-text))
     (unless (exact-nonnegative-integer? status)
       (raise-registry-error token "registry returned an invalid HTTP status"))
     (values status
             (and (= status 200) (sha256-file response-path))))
   (lambda ()
     (when (file-exists? header-path) (delete-file header-path))
     (when (file-exists? response-path) (delete-file response-path)))))

(define (curl-probe url token)
  (curl-request "GET" url token))

(define (curl-put url token path)
  (define-values (status _) (curl-request "PUT" url token path))
  status)

(define (verify-public-materials! public-remotes token public-probe)
  (for ([remote (in-list public-remotes)])
    (define-values (public-status public-digest)
      (public-probe (remote-file-url remote) #f))
    (unless (and (= public-status 200)
                 (equal? public-digest
                         (publication-file-digest
                          (remote-file-file remote))))
      (raise-registry-error
       token
       "publication is incomplete; public file is unavailable: ~a"
       (publication-file-name (remote-file-file remote))))))

(define (validate-publication-authority! server-url owner package token)
  (unless (and (string? server-url)
               (regexp-match? secure-server-pattern server-url))
    (raise-registry-error token "registry server URL must be a fixed HTTPS endpoint"))
  (for ([component (in-list (list owner package))])
    (unless (and (string? component)
                 (regexp-match? safe-component-pattern component))
      (raise-registry-error token "registry owner and package name must be safe components")))
  (unless (and (string? token)
               (not (string=? token ""))
               (not (regexp-match? #rx"[\r\n]" token)))
    (raise-registry-error token "publication token is unavailable or malformed")))

(define (probe-files files server-url owner package version token probe)
  (for/list ([file (in-list files)])
    (define url
      (artifact-url server-url owner package version (publication-file-name file)))
    (define-values (status digest) (probe url token))
    (unless (member status '(200 401 403 404))
      (raise-registry-error token
                            "registry probe failed for ~a with HTTP ~a"
                            (publication-file-name file)
                            status))
    (when (member status '(401 403))
      (raise-registry-error token "registry authentication failed"))
    (remote-file file url status digest)))

(define (remote-matches? remote)
  (and (= (remote-file-status remote) 200)
       (equal? (remote-file-digest remote)
               (publication-file-digest (remote-file-file remote)))))

(define (publish-preview-package! identity directory server-url owner package token
                                  #:probe [probe curl-probe]
                                  #:put [put curl-put]
                                  #:public-probe [public-probe probe])
  (validate-publication-authority! server-url owner package token)
  (define file-errors (publication-file-errors identity directory))
  (unless (null? file-errors)
    (raise-registry-error token "~a" (string-join file-errors "; ")))
  (define files (publication-files identity directory))
  (define version (preview-version identity))
  (define remote-files
    (probe-files files server-url owner package version token probe))
  (define existing (filter (lambda (remote) (= (remote-file-status remote) 200))
                           remote-files))
  (cond
    [(= (length existing) (length files))
     (unless (andmap remote-matches? existing)
       (raise-registry-error token
                             "registry version conflicts with local artifacts"))
     (verify-public-materials! (drop remote-files 2) token public-probe)
     (publication-result 'existing
                         (map publication-file-name files)
                         (map remote-file-url remote-files))]
    [(pair? existing)
     (define mismatched
       (filter (lambda (remote) (not (remote-matches? remote))) existing))
     (if (pair? mismatched)
         (raise-registry-error token
                               "registry version conflicts with local artifacts")
         (raise-registry-error
          token
          "registry version is incomplete; existing files: ~a"
          (string-join
           (map (lambda (remote)
                  (publication-file-name (remote-file-file remote)))
                existing)
           ", ")))]
    [else
     (define uploaded '())
     (for ([remote (in-list remote-files)])
       (define file (remote-file-file remote))
       (define status
         (put (remote-file-url remote) token (publication-file-path file)))
       (when (member status '(401 403))
         (raise-registry-error
          token
          "registry authentication failed after files [~a]"
          (string-join (reverse uploaded) ", ")))
       (unless (= status 201)
         (raise-registry-error
          token
          "publication is incomplete after files [~a]; upload of ~a returned HTTP ~a"
          (string-join (reverse uploaded) ", ")
          (publication-file-name file)
          status))
       (set! uploaded (cons (publication-file-name file) uploaded)))
     (verify-public-materials! (drop remote-files 2) token public-probe)
     (publication-result 'published
                         (reverse uploaded)
                         (map remote-file-url remote-files))]))

(define (write-publication-summary! directory result identity files)
  (make-directory* directory)
  (define records
    (for/list ([name (in-list (publication-result-files result))]
               [url (in-list (publication-result-urls result))])
      (define file
        (findf (lambda (candidate) (equal? (publication-file-name candidate) name))
               files))
      (hasheq 'name name 'url url 'sha256 (publication-file-digest file))))
  (call-with-output-file (build-path directory "publication.json")
    #:exists 'truncate
    (lambda (output)
      (write-json
       (hasheq 'schema 1
               'status (symbol->string (publication-result-state result))
               'tag (preview-identity-tag identity)
               'version (preview-version identity)
               'commit (preview-identity-main-commit identity)
               'files records)
       output)
      (newline output)))
  (call-with-output-file (build-path directory "publication.md")
    #:exists 'truncate
    (lambda (output)
      (fprintf output "# Linux Preview Publication\n\n")
      (fprintf output "Status: `~a`\n\n" (publication-result-state result))
      (fprintf output "Tag: `~a`\n\n" (preview-identity-tag identity))
      (fprintf output "Commit: `~a`\n\n" (preview-identity-main-commit identity))
      (for ([record (in-list records)])
        (fprintf output "- [~a](~a) — `sha256:~a`\n"
                 (hash-ref record 'name)
                 (hash-ref record 'url)
                 (hash-ref record 'sha256))))))

(module+ main
  (define directory #f)
  (define server-url #f)
  (define owner #f)
  (define package #f)
  (define tag #f)
  (define commit #f)
  (define source-date-epoch #f)
  (define summary-directory #f)
  (define forgejo-summary #f)
  (command-line
   #:program "publish-preview-package.rkt"
   #:once-each
   [("--directory") path "Validated publication files" (set! directory path)]
   [("--server-url") value "Trusted Forgejo server URL" (set! server-url value)]
   [("--owner") value "Forgejo package owner" (set! owner value)]
   [("--package") value "Generic package name" (set! package value)]
   [("--tag") value "Validated stable tag" (set! tag value)]
   [("--commit") value "Validated release commit" (set! commit value)]
   [("--source-date-epoch") value "Validated source timestamp"
                                   (set! source-date-epoch
                                         (string->number value))]
   [("--summary-directory") path "Publication evidence directory"
                                  (set! summary-directory path)]
   [("--forgejo-summary") path "Forgejo step summary path"
                               (set! forgejo-summary path)])
  (for ([required (in-list (list directory server-url owner package tag commit
                                 source-date-epoch summary-directory
                                 forgejo-summary))])
    (unless required
      (raise-user-error 'preview-publication "all arguments are required")))
  (define identity
    (preview-identity tag commit commit source-date-epoch preview-platform))
  (define identity-errors (preview-identity-errors identity))
  (unless (null? identity-errors)
    (raise-user-error 'preview-publication
                      "release identity is invalid: ~a"
                      (string-join identity-errors "; ")))
  (define token (getenv "ODRA_PREVIEW_PACKAGE_TOKEN"))
  (define result
    (publish-preview-package! identity directory server-url owner package token))
  (define files (publication-files identity directory))
  (write-publication-summary! summary-directory result identity files)
  (call-with-output-file forgejo-summary
    #:exists 'append
    (lambda (output)
      (display (file->string (build-path summary-directory "publication.md"))
               output)))
  (printf "preview_publication=~a tag=~a commit=~a files=~a\n"
          (publication-result-state result)
          tag
          commit
          (length (publication-result-files result))))

(module+ test
  (require rackunit)

  (define commit "0123456789abcdef0123456789abcdef01234567")
  (define identity
    (preview-identity "v0.1.0" commit commit 1798761600 preview-platform))
  (define token "opaque-test-token")
  (define server-url "https://forge.example")

  (define (write-file path content)
    (make-parent-directory* path)
    (call-with-output-file path
      #:exists 'truncate
      (lambda (output) (display content output))))

  (define (with-fixture procedure)
    (define root (make-temporary-file "preview-publication-test-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (define archive (build-path root (preview-archive-name identity)))
       (define checksum (build-path root (preview-checksum-name identity)))
       (define terms (build-path root (preview-terms-name identity)))
       (define notices (build-path root (preview-notices-name identity)))
       (write-file archive "canonical preview archive")
       (write-file checksum
                   (format "~a  ~a\n"
                           (sha256-file archive)
                           (preview-archive-name identity)))
       (write-file terms "# Preview Terms\n\nPublic preview terms.\n")
       (write-file notices "# Third-Party Notices\n\nPublic notices.\n")
       (procedure root (publication-files identity root)))
     (lambda () (delete-directory/files root))))

  (define (public-probe-for files)
    (lambda (url supplied-token)
      (check-false supplied-token)
      (define file
        (findf (lambda (candidate)
                 (string-suffix? url (publication-file-name candidate)))
               files))
      (values 200 (and file (publication-file-digest file)))))

  (test-case "uploads one complete immutable package"
    (with-fixture
     (lambda (root files)
       (define uploaded '())
       (define result
         (publish-preview-package!
          identity root server-url "owner" "odra-preview" token
          #:probe (lambda (_url _token) (values 404 #f))
          #:put (lambda (url _token _path)
                  (set! uploaded (cons url uploaded))
                  201)
          #:public-probe (public-probe-for files)))
       (check-equal? (publication-result-state result) 'published)
       (check-equal? (length uploaded) 4)
       (check-regexp-match
        #rx"/api/packages/owner/generic/odra-preview/0.1.0/"
        (first uploaded)))))

  (test-case "accepts an existing identical complete version"
    (with-fixture
     (lambda (root files)
       (define digests (map publication-file-digest files))
       (define index 0)
       (define result
         (publish-preview-package!
          identity root server-url "owner" "odra-preview" token
          #:probe (lambda (_url _token)
                    (define digest (list-ref digests index))
                    (set! index (add1 index))
                    (values 200 digest))
          #:public-probe (public-probe-for files)
          #:put (lambda (_url _token _path)
                  (error 'test "upload must not run"))))
       (check-equal? (publication-result-state result) 'existing))))

  (test-case "rejects conflicting and partial versions"
    (with-fixture
     (lambda (root files)
       (define digest (publication-file-digest (first files)))
       (check-exn
        #rx"conflicts with local artifacts"
        (lambda ()
          (publish-preview-package!
           identity root server-url "owner" "odra-preview" token
           #:probe (lambda (_url _token) (values 200 (make-string 64 #\0)))
           #:put void)))
       (define calls 0)
       (check-exn
        #rx"version is incomplete"
        (lambda ()
          (publish-preview-package!
           identity root server-url "owner" "odra-preview" token
           #:probe (lambda (_url _token)
                     (set! calls (add1 calls))
                     (if (= calls 1) (values 200 digest) (values 404 #f)))
           #:put void))))))

  (test-case "reports authentication and mid-upload failure without secrets"
    (with-fixture
     (lambda (root files)
       (check-exn
        (lambda (failure)
          (and (regexp-match? #rx"authentication failed" (exn-message failure))
               (not (regexp-match? (regexp token) (exn-message failure)))))
        (lambda ()
          (publish-preview-package!
           identity root server-url "owner" "odra-preview" token
           #:probe (lambda (_url _token) (values 401 #f))
           #:put void)))
       (define uploads 0)
       (check-exn
        #rx"publication is incomplete after files"
        (lambda ()
          (publish-preview-package!
           identity root server-url "owner" "odra-preview" token
           #:probe (lambda (_url _token) (values 404 #f))
           #:put (lambda (_url _token _path)
                   (set! uploads (add1 uploads))
                   (if (= uploads 1) 201 500))
           #:public-probe
           (lambda (_url _token)
             (values 200 (publication-file-digest (fourth files))))))))))

  (test-case "requires public notices after upload"
    (with-fixture
     (lambda (root _files)
       (check-exn
        #rx"public file is unavailable"
        (lambda ()
          (publish-preview-package!
           identity root server-url "owner" "odra-preview" token
           #:probe (lambda (_url _token) (values 404 #f))
           #:put (lambda (_url _token _path) 201)
           #:public-probe (lambda (_url _token) (values 404 #f))))))))

  (test-case "rejects unsafe registry authority"
    (with-fixture
     (lambda (root _files)
       (check-exn
        #rx"fixed HTTPS endpoint"
        (lambda ()
          (publish-preview-package!
           identity root "http://attacker.example" "owner" "odra-preview" token
           #:probe void
           #:put void)))
       (check-exn
        #rx"safe components"
        (lambda ()
          (publish-preview-package!
           identity root server-url "../owner" "odra-preview" token
           #:probe void
           #:put void)))))))
