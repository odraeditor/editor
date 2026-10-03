#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/file
         racket/list
         racket/match
         racket/path
         racket/port
         racket/string
         "../storage/record-codec.rkt")

(provide
 maximum-manual-package-files
 maximum-manual-package-bytes
 (struct-out odra-manual-package-source-request)
 (struct-out odra-manual-package-resolution-failure)
 odra-manual-package-resolved-source?
 odra-manual-package-resolved-source-id
 odra-manual-package-resolved-source-generation
 odra-manual-package-resolved-source-source-kind
 odra-manual-package-resolved-source-source-ref
 odra-manual-package-resolved-source-source-label
 odra-manual-package-resolved-source-resolved-source-revision
 odra-manual-package-resolved-source-artifact-digest
 odra-manual-package-resolved-source-manifest-digest
 odra-manual-package-resolved-source-content-path
 odra-manual-package-resolved-source-file-count
 odra-manual-package-resolved-source-content-bytes
 (contract-out
  [resolve-manual-package-source
   (->* (path-string? odra-manual-package-source-request?)
        (#:previous (or/c #f odra-manual-package-resolved-source?)
         #:cancelled? procedure?
         #:deadline-milliseconds exact-positive-integer?
         #:file-limit exact-positive-integer?
         #:byte-limit exact-positive-integer?)
        (or/c odra-manual-package-resolved-source?
              odra-manual-package-resolution-failure?))]))

(define maximum-manual-package-files 8192)
(define maximum-manual-package-bytes (expt 2 30))
(define maximum-source-reference-bytes 4096)
(define maximum-source-label-bytes 1024)
(define maximum-relative-path-bytes 4096)
(define maximum-git-diagnostic-bytes 4096)
(define transfer-buffer-bytes (* 64 1024))
(define digest-pattern #px"^[0-9a-f]{64}$")
(define revision-pattern #px"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
(define source-kinds '(development-directory git local-artifact))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (safe-relative-path? value)
  (and (bounded-text? value maximum-relative-path-bytes)
       (not (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." ".."))))))

(define (local-source-ref? value)
  (and (bounded-text? value maximum-source-reference-bytes)
       (absolute-path? (string->path value))))

(define (remote-git-source-ref? value)
  (and (bounded-text? value maximum-source-reference-bytes)
       (or (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]+$" value)
           (regexp-match?
            #px"^ssh://(?:[A-Za-z0-9._-]+@)?[^/@:#]+(?::[0-9]+)?/[^?#]+$"
            value))))

(define (source-ref? kind value)
  (case kind
    [(development-directory local-artifact) (local-source-ref? value)]
    [(git) (or (local-source-ref? value) (remote-git-source-ref? value))]
    [else #f]))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(struct odra-manual-package-source-request
  (generation source-kind source-ref source-label manifest-path)
  #:transparent
  #:guard
  (lambda (generation source-kind source-ref source-label manifest-path _)
    (unless
        (and (exact-positive-integer? generation)
             (memq source-kind source-kinds)
             (source-ref? source-kind source-ref)
             (if (eq? source-kind 'git)
                 (and (bounded-text? source-label maximum-source-label-bytes))
                 (not source-label))
             (if (eq? source-kind 'local-artifact)
                 (not manifest-path)
                 (safe-relative-path? manifest-path)))
      (raise-arguments-error 'odra-manual-package-source-request
                             "invalid bounded manual source request"))
    (values generation source-kind (copied source-ref)
            (and source-label (copied source-label))
            (and manifest-path (copied manifest-path)))))

(struct odra-manual-package-resolved-source
  (id generation source-kind source-ref source-label resolved-source-revision
      artifact-digest manifest-digest content-path file-count content-bytes)
  #:transparent
  #:guard
  (lambda (id generation source-kind source-ref source-label revision artifact-digest
              manifest-digest content-path file-count content-bytes _)
    (unless
        (and (string? id) (regexp-match? digest-pattern id)
             (exact-positive-integer? generation)
             (memq source-kind source-kinds)
             (source-ref? source-kind source-ref)
             (or (not source-label)
                 (bounded-text? source-label maximum-source-label-bytes))
             (if (eq? source-kind 'git)
                 (and (string? revision) (regexp-match? revision-pattern revision))
                 (not revision))
             (string? artifact-digest) (regexp-match? digest-pattern artifact-digest)
             (or (not manifest-digest)
                 (and (string? manifest-digest)
                      (regexp-match? digest-pattern manifest-digest)))
             (path-string? content-path) (absolute-path? content-path)
             (exact-positive-integer? file-count)
             (<= file-count maximum-manual-package-files)
             (exact-nonnegative-integer? content-bytes)
             (<= content-bytes maximum-manual-package-bytes))
      (raise-arguments-error 'odra-manual-package-resolved-source
                             "invalid immutable manual source result"))
    (values (copied id) generation source-kind (copied source-ref)
            (and source-label (copied source-label))
            (and revision (copied revision)) (copied artifact-digest)
            (and manifest-digest (copied manifest-digest))
            content-path file-count content-bytes)))

(define failure-codes
  '(cancelled git limit manifest publication source source-changed
              stale-generation timeout unsafe-path))

(struct odra-manual-package-resolution-failure (code field detail)
  #:transparent
  #:guard
  (lambda (code field detail _)
    (unless (and (memq code failure-codes) (symbol? field) (string? detail))
      (raise-arguments-error 'odra-manual-package-resolution-failure
                             "invalid manual source resolution failure"))
    (values code field (copied detail))))

(struct exn:fail:manual-resolution exn:fail (code field) #:transparent)
(struct content-file (path digest size executable?) #:transparent)

(define (raise-resolution code field detail)
  (raise
   (exn:fail:manual-resolution detail (current-continuation-marks) code field)))

(define (sha256-port input)
  (bytes->hex-string (sha256-bytes input)))

(define (file-digest path)
  (call-with-input-file path sha256-port #:mode 'binary))

(define (sha256-datum datum)
  (sha256-port
   (open-input-bytes (record-datum->module-bytes datum))))

(define (remaining-seconds deadline)
  (max 0.0 (/ (- deadline (current-inexact-monotonic-milliseconds)) 1000.0)))

(define (check-interruption cancelled? deadline)
  (when (cancelled?)
    (raise-resolution 'cancelled 'operation "manual source resolution was cancelled"))
  (when (<= (remaining-seconds deadline) 0)
    (raise-resolution 'timeout 'operation "manual source resolution deadline expired")))

(define (ensure-private-directory path)
  (when (link-exists? path)
    (raise-resolution 'unsafe-path 'directory
                      "manual package storage cannot be a symbolic link"))
  (unless (directory-exists? path)
    (make-directory path)
    (file-or-directory-permissions path #o700))
  (when (positive? (bitwise-and
                    (hash-ref (file-or-directory-stat path #f) 'mode) #o077))
    (raise-resolution 'publication 'directory
                      "manual package storage must be owner-only")))

(define (relative-string root path)
  (string-replace (path->string (find-relative-path root path)) "\\" "/"))

(define (executable-file? path)
  (positive? (bitwise-and
              (hash-ref (file-or-directory-stat path #f) 'mode) #o111)))

(define (copy-file-bounded source target cancelled? deadline remaining)
  (define size (file-size source))
  (when (> size remaining)
    (raise-resolution 'limit 'content-bytes
                      "manual package content exceeds its byte ceiling"))
  (call-with-input-file source
    (lambda (input)
      (call-with-output-file target
        (lambda (output)
          (define buffer (make-bytes transfer-buffer-bytes))
          (let loop ([total 0])
            (check-interruption cancelled? deadline)
            (define amount (read-bytes-avail! buffer input))
            (cond
              [(eof-object? amount) total]
              [else
               (write-bytes buffer output 0 amount)
               (loop (+ total amount))])))
        #:exists 'error #:mode 'binary #:permissions #o600))
    #:mode 'binary)
  (unless (= size (file-size source) (file-size target))
    (raise-resolution 'source-changed 'content
                      "manual source changed while it was being copied"))
  size)

(define (copy-directory-tree source target cancelled? deadline file-limit byte-limit)
  (define entries '())
  (define total 0)
  (define count 0)
  (define (walk current destination)
    (for ([path (in-list (sort (directory-list current #:build? #t)
                               string<? #:key path->string))])
      (check-interruption cancelled? deadline)
      (define name (path->string (file-name-from-path path)))
      (unless (and (equal? current source) (string=? name ".git"))
        (when (link-exists? path)
          (raise-resolution 'unsafe-path 'content
                            "manual source contains a symbolic link"))
        (define destination-path (build-path destination name))
        (cond
          [(directory-exists? path)
           (make-directory destination-path)
           (file-or-directory-permissions destination-path #o700)
           (walk path destination-path)]
          [(file-exists? path)
           (set! count (add1 count))
           (when (> count file-limit)
             (raise-resolution 'limit 'file-count
                               "manual package contains too many files"))
           (define size
             (copy-file-bounded path destination-path cancelled? deadline
                                (- byte-limit total)))
           (set! total (+ total size))
           (define relative (relative-string source path))
           (unless (safe-relative-path? relative)
             (raise-resolution 'unsafe-path 'content
                               "manual source contains an unsafe path"))
           (set! entries
                 (cons (content-file relative (file-digest destination-path)
                                     size (executable-file? path))
                       entries))]
          [else
           (raise-resolution 'unsafe-path 'content
                             "manual source contains a special filesystem object")]))))
  (walk source target)
  (when (zero? count)
    (raise-resolution 'source 'content "manual package source is empty"))
  (values (sort entries string<? #:key content-file-path) total))

(define (content-file->datum value)
  (list (content-file-path value) (content-file-digest value)
        (content-file-size value) (content-file-executable? value)))

(define (tree-digest files)
  (sha256-datum
   (list 'manual-package-tree 1 (map content-file->datum files))))

(define (manifest-digest target manifest-path)
  (define path (build-path target (string->path manifest-path)))
  (unless (and (file-exists? path) (not (link-exists? path)))
    (raise-resolution 'manifest 'manifest-path
                      "manual package manifest is absent from resolved content"))
  (file-digest path))

(define (split-nul value)
  (let loop ([start 0] [index 0] [parts '()])
    (cond
      [(= index (bytes-length value))
       (reverse
        (if (= start index) parts (cons (subbytes value start index) parts)))]
      [(zero? (bytes-ref value index))
       (loop (add1 index) (add1 index)
             (if (= start index) parts (cons (subbytes value start index) parts)))]
      [else (loop start (add1 index) parts)])))

(define (git-environment)
  (define environment (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! environment #"GIT_TERMINAL_PROMPT" #"0")
  (environment-variables-set! environment #"GIT_SSH_COMMAND"
                              #"ssh -oBatchMode=yes")
  environment)

(define (port->bounded-bytes input limit)
  (define value (read-bytes (add1 limit) input))
  (cond
    [(eof-object? value) #""]
    [(> (bytes-length value) limit)
     (close-input-port input)
     #f]
    [else value]))

(define (run-git cancelled? deadline #:output-limit [output-limit 4096]
                 . arguments)
  (check-interruption cancelled? deadline)
  (define-values (process output input errors)
    (parameterize ([current-environment-variables (git-environment)])
      (apply subprocess #f #f #f "/usr/bin/git" arguments)))
  (close-output-port input)
  (define output-channel (make-channel))
  (define error-channel (make-channel))
  (thread
   (lambda ()
     (channel-put output-channel (port->bounded-bytes output output-limit))))
  (thread
   (lambda ()
     (channel-put error-channel
                  (port->bounded-bytes errors maximum-git-diagnostic-bytes))))
  (with-handlers
      ([exn:fail:manual-resolution?
        (lambda (observed)
          (subprocess-kill process #t)
          (subprocess-wait process)
          (raise observed))])
    (let loop ()
      (check-interruption cancelled? deadline)
      (unless (sync/timeout (min 0.05 (remaining-seconds deadline)) process)
        (loop))))
  (subprocess-wait process)
  (define stdout (channel-get output-channel))
  (define stderr (channel-get error-channel))
  (when (and output (not (port-closed? output))) (close-input-port output))
  (when (and errors (not (port-closed? errors))) (close-input-port errors))
  (unless stdout
    (raise-resolution 'limit 'git-output
                      "Git command output exceeds its byte ceiling"))
  (unless (zero? (subprocess-status process))
    (raise-resolution
     'git 'source
     (let ([detail
            (if stderr
                (string-trim (bytes->string/utf-8 stderr #\uFFFD))
                "")])
       (if (string=? detail "") "Git source resolution failed" detail))))
  stdout)

(define (run-git-to-file destination expected-size cancelled? deadline . arguments)
  (check-interruption cancelled? deadline)
  (call-with-output-file destination
    (lambda (output)
      (define-values (process child-output input errors)
        (parameterize ([current-environment-variables (git-environment)])
          (apply subprocess output #f #f "/usr/bin/git" arguments)))
      (when child-output (close-input-port child-output))
      (close-output-port input)
      (define error-channel (make-channel))
      (thread
       (lambda ()
         (channel-put
          error-channel
          (port->bounded-bytes errors maximum-git-diagnostic-bytes))))
      (with-handlers
          ([exn:fail:manual-resolution?
            (lambda (observed)
              (subprocess-kill process #t)
              (subprocess-wait process)
              (raise observed))])
        (let loop ()
          (check-interruption cancelled? deadline)
          (unless (sync/timeout (min 0.05 (remaining-seconds deadline)) process)
            (loop))))
      (subprocess-wait process)
      (define stderr (channel-get error-channel))
      (when (and errors (not (port-closed? errors))) (close-input-port errors))
      (unless (zero? (subprocess-status process))
        (raise-resolution
         'git 'content
         (let ([detail
                (if stderr
                    (string-trim (bytes->string/utf-8 stderr #\uFFFD))
                    "")])
           (if (string=? detail "") "Git blob resolution failed" detail)))))
    #:exists 'error #:mode 'binary #:permissions #o600)
  (unless (= (file-size destination) expected-size)
    (raise-resolution 'git 'content "Git blob size changed during resolution")))

(define (git-tree-entry value)
  (match
      (regexp-match #px#"^([0-9]+) ([^ ]+) ([0-9a-f]+)\t(.*)$" value)
    [(list _ mode type object path)
     (unless (and (bytes=? type #"blob")
                  (member mode '(#"100644" #"100755") bytes=?))
       (raise-resolution 'unsafe-path 'git-tree
                         "Git tree contains a link, submodule, or special entry"))
     (define path-string (bytes->string/utf-8 path #\uFFFD))
     (unless (and (safe-relative-path? path-string)
                  (bytes=? path (string->bytes/utf-8 path-string)))
       (raise-resolution 'unsafe-path 'git-tree
                         "Git tree contains an unsafe or invalid path"))
     (list path-string (bytes->string/utf-8 object)
           (bytes=? mode #"100755"))]
    [_ (raise-resolution 'git 'tree "Git returned an invalid tree record")]))

(define (copy-git-tree repository revision target cancelled? deadline
                       file-limit byte-limit)
  (define raw
    (run-git cancelled? deadline
             #:output-limit (* file-limit (+ maximum-relative-path-bytes 128))
             "-C" (path->string repository)
             "ls-tree" "-rz" "--full-tree" "-r" revision))
  (define tree (map git-tree-entry (split-nul raw)))
  (when (or (null? tree) (> (length tree) file-limit))
    (raise-resolution 'limit 'file-count
                      "Git package tree is empty or exceeds its file ceiling"))
  (define total 0)
  (define files
    (for/list ([entry (in-list tree)])
      (check-interruption cancelled? deadline)
      (define relative (car entry))
      (define object (cadr entry))
      (define executable? (caddr entry))
      (define size-text
        (string-trim
         (bytes->string/utf-8
          (run-git cancelled? deadline "-C" (path->string repository)
                   "cat-file" "-s" object))))
      (define size (string->number size-text))
      (unless (and (exact-nonnegative-integer? size)
                   (<= (+ total size) byte-limit))
        (raise-resolution 'limit 'content-bytes
                          "Git package tree exceeds its byte ceiling"))
      (define destination (build-path target (string->path relative)))
      (make-directory* (path-only destination))
      (file-or-directory-permissions (path-only destination) #o700)
      (run-git-to-file destination size cancelled? deadline
                       "-C" (path->string repository)
                       "cat-file" "blob" object)
      (when executable? (file-or-directory-permissions destination #o700))
      (set! total (+ total size))
      (content-file relative (file-digest destination)
                    size executable?)))
  (values files total))

(define (resolve-git request repository target cancelled? deadline file-limit byte-limit)
  (run-git cancelled? deadline "init" "--bare" (path->string repository))
  (run-git cancelled? deadline "-C" (path->string repository)
           "remote" "add" "origin"
           (odra-manual-package-source-request-source-ref request))
  (run-git cancelled? deadline "-C" (path->string repository)
           "fetch" "--depth=1" "--filter=blob:none"
           "origin" (odra-manual-package-source-request-source-label request))
  (define revision
    (string-trim
     (bytes->string/utf-8
      (run-git cancelled? deadline "-C" (path->string repository)
               "rev-parse" "--verify" "FETCH_HEAD^{commit}"))))
  (unless (regexp-match? revision-pattern revision)
    (raise-resolution 'git 'revision "Git did not resolve an exact commit"))
  (define-values (files total)
    (copy-git-tree repository revision target cancelled? deadline
                   file-limit byte-limit))
  (values files total revision))

(define (write-metadata stage kind files digest)
  (define bytes
    (record-datum->module-bytes
     (list 'manual-package-content 1 kind digest
           (map content-file->datum files))))
  (call-with-output-file (build-path stage ".odra-manual-content.rktd")
    (lambda (output) (write-bytes bytes output))
    #:exists 'error #:mode 'binary #:permissions #o600)
  bytes)

(define (publish-content root stage digest metadata)
  (define prefix-root (build-path root "package-manual" "content" "sha256"))
  (define digest-root (build-path prefix-root (substring digest 0 2)))
  (for ([directory
         (in-list (list root (build-path root "package-manual")
                        (build-path root "package-manual" "content")
                        prefix-root digest-root))])
    (ensure-private-directory directory))
  (define target (build-path digest-root digest))
  (cond
    [(or (directory-exists? target) (link-exists? target) (file-exists? target))
     (define metadata-path (build-path target ".odra-manual-content.rktd"))
     (unless (and (directory-exists? target) (not (link-exists? target))
                  (file-exists? metadata-path) (not (link-exists? metadata-path))
                  (bytes=? metadata (file->bytes metadata-path)))
       (raise-resolution 'publication 'content
                         "immutable manual content path contains different data"))
     (delete-directory/files stage)]
    [else (rename-file-or-directory stage target #f)])
  (build-path target "payload"))

(define (request-consistent? request previous)
  (and (= (odra-manual-package-source-request-generation request)
          (add1 (odra-manual-package-resolved-source-generation previous)))
       (eq? (odra-manual-package-source-request-source-kind request)
            (odra-manual-package-resolved-source-source-kind previous))
       (string=? (odra-manual-package-source-request-source-ref request)
                 (odra-manual-package-resolved-source-source-ref previous))
       (equal? (odra-manual-package-source-request-source-label request)
               (odra-manual-package-resolved-source-source-label previous))))

(define (resolve-manual-package-source
         root request #:previous [previous #f]
         #:cancelled? [cancelled? (lambda () #f)]
         #:deadline-milliseconds [deadline-milliseconds 60000]
         #:file-limit [file-limit maximum-manual-package-files]
         #:byte-limit [byte-limit maximum-manual-package-bytes])
  (define complete-root (path->complete-path root))
  (define deadline (+ (current-inexact-monotonic-milliseconds)
                      deadline-milliseconds))
  (define stage #f)
  (with-handlers
      ([exn:fail:manual-resolution?
        (lambda (observed)
          (when (and stage (directory-exists? stage))
            (with-handlers ([exn:fail? void]) (delete-directory/files stage)))
          (odra-manual-package-resolution-failure
           (exn:fail:manual-resolution-code observed)
           (exn:fail:manual-resolution-field observed)
           (exn-message observed)))]
       [exn:fail?
        (lambda (observed)
          (when (and stage (directory-exists? stage))
            (with-handlers ([exn:fail? void]) (delete-directory/files stage)))
          (odra-manual-package-resolution-failure
           'source 'operation (exn-message observed)))])
    (when (or (> file-limit maximum-manual-package-files)
              (> byte-limit maximum-manual-package-bytes))
      (raise-resolution 'limit 'request
                        "manual source limits exceed native maxima"))
    (cond
      [(and previous (not (request-consistent? request previous)))
       (raise-resolution 'stale-generation 'generation
                         "manual reload does not follow the prior exact generation")]
      [(and (not previous)
            (not (= (odra-manual-package-source-request-generation request) 1)))
       (raise-resolution 'stale-generation 'generation
                         "initial manual source generation must be one")])
    (for ([directory
           (in-list (list complete-root (build-path complete-root "package-manual")
                          (build-path complete-root "package-manual" "staging")))])
      (ensure-private-directory directory))
    (set! stage
          (make-temporary-file
           "resolve-~a" 'directory
           (build-path complete-root "package-manual" "staging")))
    (file-or-directory-permissions stage #o700)
    (define payload (build-path stage "payload"))
    (make-directory payload)
    (file-or-directory-permissions payload #o700)
    (define kind (odra-manual-package-source-request-source-kind request))
    (define source
      (string->path (odra-manual-package-source-request-source-ref request)))
    (define-values (files total revision content-kind)
      (case kind
        [(development-directory)
         (unless (and (directory-exists? source) (not (link-exists? source)))
           (raise-resolution 'source 'source-ref
                             "development source is not a regular directory"))
         (define-values (resolved-files resolved-total)
           (copy-directory-tree source payload cancelled? deadline
                                file-limit byte-limit))
         (values resolved-files resolved-total #f 'tree)]
        [(local-artifact)
         (unless (and (file-exists? source) (not (link-exists? source)))
           (raise-resolution 'source 'source-ref
                             "local artifact is not a regular file"))
         (define destination (build-path payload "artifact"))
         (define size
           (copy-file-bounded source destination cancelled? deadline byte-limit))
         (define value
           (content-file "artifact" (file-digest destination) size #f))
         (values (list value) size #f 'artifact)]
        [(git)
         (define repository (build-path stage "repository.git"))
         (define-values (resolved-files resolved-total resolved-revision)
           (resolve-git request repository payload cancelled? deadline
                        file-limit byte-limit))
         (delete-directory/files repository)
         (values resolved-files resolved-total resolved-revision 'tree)]))
    (define artifact-digest
      (if (eq? content-kind 'artifact)
          (content-file-digest (car files))
          (tree-digest files)))
    (define observed-manifest
      (and (odra-manual-package-source-request-manifest-path request)
           (manifest-digest
            payload (odra-manual-package-source-request-manifest-path request))))
    (define metadata (write-metadata stage content-kind files artifact-digest))
    (define target (publish-content complete-root stage artifact-digest metadata))
    (set! stage #f)
    (odra-manual-package-resolved-source
     (sha256-datum
      (list 'manual-package-resolved-source 1
            (odra-manual-package-source-request-generation request)
            kind
            (odra-manual-package-source-request-source-ref request)
            (odra-manual-package-source-request-source-label request)
            revision artifact-digest observed-manifest))
     (odra-manual-package-source-request-generation request)
     kind
     (odra-manual-package-source-request-source-ref request)
     (odra-manual-package-source-request-source-label request)
     revision artifact-digest observed-manifest target (length files) total)))
