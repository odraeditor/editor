#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         racket/file
         racket/cmdline
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system
         "publication-identity.rkt")

(provide public-source-policy-schema
         (struct-out export-rule)
         (struct-out export-policy)
         (struct-out path-classification)
         (struct-out source-entry)
         (struct-out source-inventory)
         (struct-out source-export-result)
         read-export-policy
         export-policy-errors
         export-policy-valid?
         export-policy-sha256
         classify-export-path
         build-source-inventory
         source-entry->jsexpr
         source-inventory->jsexpr
         source-inventory-sha256
         export-public-source!)

(define public-source-policy-schema 1)

(define identifier-pattern #px"^[a-z0-9][a-z0-9._-]*$")

(struct export-rule (match pattern classification reason) #:transparent)
(struct export-policy (schema version rules source) #:transparent)
(struct path-classification (path classification reason pattern) #:transparent)
(struct source-entry
  (path mode kind object-id classification reason sha256)
  #:transparent)
(struct tree-entry
  (path mode kind object-id classification reason)
  #:transparent)
(struct source-inventory
  (source-commit
   source-date-epoch
   policy-version
   policy-sha256
   content-sha256
   entries)
  #:transparent)
(struct source-export-result
  (root inventory-sha256 content-sha256 tree-sha256 included excluded)
  #:transparent)

(define (hash-value table key [fallback #f])
  (if (hash? table) (hash-ref table key fallback) fallback))

(define (string->classification value)
  (and (string? value)
       (case (string->symbol value)
         [(include exclude reject) (string->symbol value)]
         [else #f])))

(define (string->match value)
  (and (string? value)
       (case (string->symbol value)
         [(exact prefix) (string->symbol value)]
         [else #f])))

(define (jsexpr->rule value)
  (export-rule (string->match (hash-value value 'match))
               (hash-value value 'pattern)
               (string->classification (hash-value value 'classification))
               (hash-value value 'reason)))

(define (read-export-policy path)
  (define complete-path (path->complete-path path))
  (define source
    (call-with-input-file complete-path read-json))
  (define raw-rules (hash-value source 'rules '()))
  (export-policy (hash-value source 'schema)
                 (hash-value source 'version)
                 (if (list? raw-rules) (map jsexpr->rule raw-rules) '())
                 source))

(define (safe-policy-path? value)
  (and (string? value)
       (not (string=? value ""))
       (relative-path? (string->path value))
       (not (member ".." (string-split value "/")))
       (not (string-contains? value "\\"))
       (not (regexp-match? #px"[[:cntrl:]]" value))))

(define (rule-errors rule index)
  (append
   (if (member (export-rule-match rule) '(exact prefix))
       '()
       (list (format "rule ~a has an invalid match type" index)))
   (if (safe-policy-path? (export-rule-pattern rule))
       '()
       (list (format "rule ~a has an unsafe pattern" index)))
   (if (if (eq? (export-rule-match rule) 'prefix)
           (and (string? (export-rule-pattern rule))
                (string-suffix? (export-rule-pattern rule) "/"))
           (and (string? (export-rule-pattern rule))
                (not (string-suffix? (export-rule-pattern rule) "/"))))
       '()
       (list (format "rule ~a pattern shape differs from its match type" index)))
   (if (member (export-rule-classification rule) '(include exclude reject))
       '()
       (list (format "rule ~a has an invalid classification" index)))
   (if (and (string? (export-rule-reason rule))
            (regexp-match? identifier-pattern (export-rule-reason rule)))
       '()
       (list (format "rule ~a has an invalid reason" index)))))

(define (export-policy-errors policy)
  (define rules (export-policy-rules policy))
  (append
   (if (equal? (export-policy-schema policy) public-source-policy-schema)
       '()
       (list (format "policy schema must be ~a" public-source-policy-schema)))
   (if (and (string? (export-policy-version policy))
            (regexp-match? identifier-pattern (export-policy-version policy)))
       '()
       '("policy version must be a stable identifier"))
   (if (pair? rules) '() '("policy requires at least one rule"))
   (append*
    (for/list ([rule (in-list rules)]
               [index (in-naturals 1)])
      (rule-errors rule index)))
   (if (= (length rules)
          (length
           (remove-duplicates
            (map (lambda (rule)
                   (cons (export-rule-match rule)
                         (export-rule-pattern rule)))
                 rules))))
       '()
       '("policy contains duplicate path matchers"))))

(define (export-policy-valid? policy)
  (null? (export-policy-errors policy)))

(define (export-policy-sha256 policy)
  (unless (export-policy-valid? policy)
    (raise-arguments-error 'export-policy-sha256
                           "invalid export policy"
                           "errors" (export-policy-errors policy)))
  (canonical-jsexpr-sha256 (export-policy-source policy)))

(define (rule-matches? rule path)
  (case (export-rule-match rule)
    [(exact) (string=? path (export-rule-pattern rule))]
    [(prefix) (string-prefix? path (export-rule-pattern rule))]
    [else #f]))

(define (classify-export-path policy path)
  (unless (export-policy-valid? policy)
    (raise-arguments-error 'classify-export-path
                           "invalid export policy"
                           "errors" (export-policy-errors policy)))
  (unless (safe-policy-path? path)
    (raise-arguments-error 'classify-export-path
                           "unsafe repository path"
                           "path" path))
  (define matches
    (filter (lambda (rule) (rule-matches? rule path))
            (export-policy-rules policy)))
  (unless (= (length matches) 1)
    (raise-arguments-error
     'classify-export-path
     (if (null? matches)
         "repository path is unclassified"
         "repository path has ambiguous classifications")
     "path" path
     "matching rules" (map export-rule-pattern matches)))
  (define rule (car matches))
  (path-classification path
                       (export-rule-classification rule)
                       (export-rule-reason rule)
                       (export-rule-pattern rule)))

(define git-commit-pattern #px"^[0-9a-f]{40}$")
(define git-tree-line-pattern
  #px"^([0-9]{6}) ([a-z]+) ([0-9a-f]{40})\t(.+)$")

(define (required-git)
  (or (find-executable-path "git")
      (raise-user-error 'public-source-export "git is unavailable")))

(define (run-git/capture repository arguments #:binary? [binary? #f])
  (define-values (process output input errors)
    (apply subprocess
           #f
           #f
           #f
           (required-git)
           "-C"
           (path->string (path->complete-path repository))
           arguments))
  (close-output-port input)
  (define captured-output
    (if binary? (port->bytes output) (port->string output)))
  (define captured-errors (port->string errors))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (raise-user-error 'public-source-export
                      "git command failed: git ~a: ~a"
                      (string-join arguments " ")
                      (string-trim captured-errors)))
  captured-output)

(define (exact-source-commit repository requested)
  (unless (and (string? requested) (regexp-match? git-commit-pattern requested))
    (raise-arguments-error 'build-source-inventory
                           "source commit must be a full lowercase object ID"
                           "source commit" requested))
  (define resolved
    (string-trim
     (run-git/capture repository (list "rev-parse" (string-append requested "^{commit}")))))
  (unless (string=? requested resolved)
    (raise-arguments-error 'build-source-inventory
                           "source commit did not resolve to itself"
                           "requested" requested
                           "resolved" resolved))
  resolved)

(define (commit-source-date-epoch repository commit)
  (define value
    (string-trim
     (run-git/capture repository (list "show" "-s" "--format=%ct" commit))))
  (define parsed (string->number value))
  (unless (exact-nonnegative-integer? parsed)
    (raise-user-error 'public-source-export
                      "commit has an invalid source date epoch: ~a"
                      value))
  parsed)

(define (split-null-terminated value)
  (filter (lambda (item) (not (bytes=? item #"")))
          (regexp-split #rx#"\0" value)))

(define (parse-tree-entry raw)
  (define line
    (with-handlers ([exn:fail?
                     (lambda (_)
                       (raise-user-error
                        'public-source-export
                        "repository path is not valid UTF-8"))])
      (bytes->string/utf-8 raw)))
  (define match (regexp-match git-tree-line-pattern line))
  (unless match
    (raise-user-error 'public-source-export
                      "git tree entry is malformed: ~s"
                      line))
  (values (list-ref match 1)
          (list-ref match 2)
          (list-ref match 3)
          (list-ref match 4)))

(define (entry-kind mode type)
  (cond
    [(and (string=? type "blob") (string=? mode "120000")) 'symlink]
    [(string=? type "blob") 'file]
    [(string=? type "commit") 'submodule]
    [else 'unsupported]))

(define (sha256-bytes-hex value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (for-each-git-blob repository object-ids procedure)
  (define-values (process output input errors)
    (subprocess #f
                #f
                #f
                (required-git)
                "-C"
                (path->string (path->complete-path repository))
                "cat-file"
                "--batch"))
  (for ([object-id (in-list object-ids)])
    (displayln object-id input)
    (flush-output input)
    (define header (read-line output 'any))
    (define match
      (and (string? header)
           (regexp-match #px"^([0-9a-f]{40}) blob ([0-9]+)$" header)))
    (unless match
      (close-output-port input)
      (subprocess-kill process #t)
      (raise-user-error 'public-source-export
                        "git returned an invalid blob header: ~s"
                        header))
    (define size (string->number (list-ref match 2)))
    (define content (read-bytes size output))
    (unless (and (bytes? content) (= (bytes-length content) size))
      (close-output-port input)
      (subprocess-kill process #t)
      (raise-user-error 'public-source-export
                        "git returned a truncated blob: ~a"
                        object-id))
    (unless (equal? (read-byte output) 10)
      (close-output-port input)
      (subprocess-kill process #t)
      (raise-user-error 'public-source-export
                        "git returned a malformed blob terminator: ~a"
                        object-id))
    (procedure object-id content))
  (close-output-port input)
  (subprocess-wait process)
  (define captured-errors (port->string errors))
  (unless (zero? (subprocess-status process))
    (raise-user-error 'public-source-export
                      "git cat-file batch failed: ~a"
                      (string-trim captured-errors))))

(define (git-blob-digests repository object-ids)
  (define digests (make-hash))
  (for-each-git-blob
   repository
   (remove-duplicates object-ids)
   (lambda (object-id content)
     (hash-set! digests object-id (sha256-bytes-hex content))))
  digests)

(define (source-entry->jsexpr entry)
  (hasheq 'path (source-entry-path entry)
          'mode (source-entry-mode entry)
          'kind (symbol->string (source-entry-kind entry))
          'classification (symbol->string
                           (source-entry-classification entry))
          'reason (source-entry-reason entry)
          'sha256 (or (source-entry-sha256 entry) #f)))

(define (included-content-jsexpr entries)
  (for/list ([entry (in-list entries)]
             #:when (eq? (source-entry-classification entry) 'include))
    (source-entry->jsexpr entry)))

(define (source-inventory->jsexpr inventory)
  (hasheq 'schema 1
          'source_commit (source-inventory-source-commit inventory)
          'source_date_epoch (source-inventory-source-date-epoch inventory)
          'policy
          (hasheq 'version (source-inventory-policy-version inventory)
                  'sha256 (source-inventory-policy-sha256 inventory))
          'content_sha256 (source-inventory-content-sha256 inventory)
          'entries (map source-entry->jsexpr
                        (source-inventory-entries inventory))))

(define (source-inventory-sha256 inventory)
  (canonical-jsexpr-sha256 (source-inventory->jsexpr inventory)))

(define (case-collision-errors paths)
  (for/list ([group
              (in-list
               (group-by string-downcase paths))]
             #:when (> (length group) 1))
    (format "repository paths collide when case-folded: ~a"
            (string-join (sort group string<?) ", "))))

(define (build-source-inventory repository commit policy)
  (unless (export-policy-valid? policy)
    (raise-arguments-error 'build-source-inventory
                           "invalid export policy"
                           "errors" (export-policy-errors policy)))
  (define exact-commit (exact-source-commit repository commit))
  (define tree-output
    (run-git/capture repository
                     (list "ls-tree" "-rz" "--full-tree" exact-commit)
                     #:binary? #t))
  (define tree-entries
    (for/list ([raw (in-list (split-null-terminated tree-output))])
      (define-values (mode type object-id path) (parse-tree-entry raw))
      (define classification (classify-export-path policy path))
      (define kind (entry-kind mode type))
      (when (eq? kind 'unsupported)
        (raise-user-error 'public-source-export
                          "unsupported Git tree entry: ~a ~a"
                          type path))
      (when (eq? kind 'submodule)
        (raise-user-error 'public-source-export
                          "submodules are not supported in public source: ~a"
                          path))
      (when (eq? (path-classification-classification classification) 'reject)
        (raise-user-error 'public-source-export
                          "source policy rejects ~a: ~a"
                          path
                          (path-classification-reason classification)))
      (tree-entry path
                  mode
                  kind
                  object-id
                  (path-classification-classification classification)
                  (path-classification-reason classification))))
  (define blob-digests
    (git-blob-digests
     repository
     (for/list ([entry (in-list tree-entries)]
                #:when (eq? (tree-entry-classification entry) 'include))
       (tree-entry-object-id entry))))
  (define entries
    (for/list ([entry (in-list tree-entries)])
      (source-entry (tree-entry-path entry)
                    (tree-entry-mode entry)
                    (tree-entry-kind entry)
                    (tree-entry-object-id entry)
                    (tree-entry-classification entry)
                    (tree-entry-reason entry)
                    (and (eq? (tree-entry-classification entry) 'include)
                         (hash-ref blob-digests
                                   (tree-entry-object-id entry))))))
  (define sorted-entries (sort entries string<? #:key source-entry-path))
  (define collisions (case-collision-errors (map source-entry-path sorted-entries)))
  (unless (null? collisions)
    (raise-arguments-error 'build-source-inventory
                           "repository contains case-colliding paths"
                           "errors" collisions))
  (define content-sha256
    (canonical-jsexpr-sha256 (included-content-jsexpr sorted-entries)))
  (source-inventory exact-commit
                    (commit-source-date-epoch repository exact-commit)
                    (export-policy-version policy)
                    (export-policy-sha256 policy)
                    content-sha256
                    sorted-entries))

(define (write-canonical-json-file! path value)
  (make-parent-directory* path)
  (call-with-output-file path
    #:exists 'truncate/replace
    (lambda (output)
      (write-bytes (canonical-json-bytes value) output)
      (newline output))))

(define (empty-directory? path)
  (and (directory-exists? path)
       (null? (directory-list path))))

(define (prepare-export-destination output-root)
  (define complete (path->complete-path output-root))
  (cond
    [(not (file-or-directory-type complete #f))
     (make-directory* (path-only complete))]
    [(empty-directory? complete) (void)]
    [else
     (raise-arguments-error 'export-public-source!
                            "output must be absent or an empty directory"
                            "output" complete)])
  complete)

(define (safe-link-target? value)
  (and (string? value)
       (not (string=? value ""))
       (relative-path? (string->path value))
       (not (member ".." (string-split value "/")))
       (not (string-contains? value "\\"))))

(define (write-source-entry! tree-root entry content)
  (define destination (build-path tree-root (source-entry-path entry)))
  (make-parent-directory* destination)
  (case (source-entry-kind entry)
    [(file)
     (call-with-output-file destination
       #:exists 'error
       (lambda (output) (write-bytes content output)))
     (file-or-directory-permissions
      destination
      (if (string=? (source-entry-mode entry) "100755") #o755 #o644))]
    [(symlink)
     (define target
       (with-handlers ([exn:fail?
                        (lambda (_)
                          (raise-user-error
                           'public-source-export
                           "symlink target is not valid UTF-8: ~a"
                           (source-entry-path entry)))])
         (bytes->string/utf-8 content)))
     (unless (safe-link-target? target)
       (raise-user-error 'public-source-export
                         "symlink target is unsafe: ~a -> ~a"
                         (source-entry-path entry)
                         target))
     (make-file-or-directory-link target destination)]
    [else
     (raise-user-error 'public-source-export
                       "cannot materialize source entry kind: ~a"
                       (source-entry-kind entry))]))

(define (normalize-tree-times! tree-root source-date-epoch)
  (define paths
    (sort (find-files (lambda (_) #t) tree-root #:follow-links? #f)
          >
          #:key (lambda (path)
                  (length (explode-path
                           (find-relative-path tree-root path))))))
  (for ([path (in-list paths)]
        #:unless (eq? (file-or-directory-type path #f) 'link))
    (file-or-directory-modify-seconds path source-date-epoch))
  (file-or-directory-modify-seconds tree-root source-date-epoch))

(define (export-manifest-jsexpr inventory inventory-sha256 included excluded)
  (hasheq 'schema 1
          'model "odra-public-source-snapshot"
          'source_commit (source-inventory-source-commit inventory)
          'source_date_epoch (source-inventory-source-date-epoch inventory)
          'policy
          (hasheq 'version (source-inventory-policy-version inventory)
                  'sha256 (source-inventory-policy-sha256 inventory))
          'inventory_sha256 inventory-sha256
          'content_sha256 (source-inventory-content-sha256 inventory)
          'included_files included
          'excluded_files excluded))

(define (generated-manifest-record sha256)
  (hasheq 'path "release/public-source-manifest.json"
          'mode "100644"
          'kind "file"
          'classification "include"
          'reason "generated-release-metadata"
          'sha256 sha256))

(define (export-public-source! repository commit policy output-root)
  (define destination (prepare-export-destination output-root))
  (define parent (path-only destination))
  (define staging
    (make-temporary-file "public-source-export-~a" 'directory parent))
  (with-handlers
      ([exn:fail?
        (lambda (error)
          (when (directory-exists? staging) (delete-directory/files staging))
          (raise error))])
    (define inventory (build-source-inventory repository commit policy))
    (define included-entries
      (filter (lambda (entry)
                (eq? (source-entry-classification entry) 'include))
              (source-inventory-entries inventory)))
    (define excluded
      (- (length (source-inventory-entries inventory))
         (length included-entries)))
    (define tree-root (build-path staging "tree"))
    (make-directory tree-root)
    (define remaining-entries included-entries)
    (for-each-git-blob
     repository
     (map source-entry-object-id included-entries)
     (lambda (object-id content)
       (define entry (car remaining-entries))
       (unless (string=? object-id (source-entry-object-id entry))
         (raise-user-error 'public-source-export
                           "blob stream identity differs: ~a"
                           (source-entry-path entry)))
       (write-source-entry! tree-root entry content)
       (set! remaining-entries (cdr remaining-entries))))
    (define inventory-jsexpr (source-inventory->jsexpr inventory))
    (define inventory-sha256 (canonical-jsexpr-sha256 inventory-jsexpr))
    (write-canonical-json-file! (build-path staging "inventory.json")
                                inventory-jsexpr)
    (define export-manifest
      (export-manifest-jsexpr inventory
                              inventory-sha256
                              (length included-entries)
                              excluded))
    (define manifest-path
      (build-path tree-root "release" "public-source-manifest.json"))
    (write-canonical-json-file! manifest-path export-manifest)
    (file-or-directory-permissions manifest-path #o644)
    (define manifest-sha256
      (sha256-bytes-hex (file->bytes manifest-path)))
    (define tree-sha256
      (canonical-jsexpr-sha256
       (append (included-content-jsexpr included-entries)
               (list (generated-manifest-record manifest-sha256)))))
    (write-canonical-json-file!
     (build-path staging "summary.json")
     (hasheq 'schema 1
             'source_commit (source-inventory-source-commit inventory)
             'inventory_sha256 inventory-sha256
             'content_sha256 (source-inventory-content-sha256 inventory)
             'tree_sha256 tree-sha256
             'included_files (length included-entries)
             'excluded_files excluded))
    (normalize-tree-times! tree-root
                           (source-inventory-source-date-epoch inventory))
    (when (directory-exists? destination) (delete-directory destination))
    (rename-file-or-directory staging destination)
    (source-export-result destination
                          inventory-sha256
                          (source-inventory-content-sha256 inventory)
                          tree-sha256
                          (length included-entries)
                          excluded)))

(module+ main
  (define repository #f)
  (define commit #f)
  (define policy-path #f)
  (define output-root #f)
  (command-line
   #:program "public-source-export.rkt"
   #:once-each
   [("--repository") path "Canonical source repository" (set! repository path)]
   [("--commit") value "Exact canonical source commit" (set! commit value)]
   [("--policy") path "Public source path policy" (set! policy-path path)]
   [("--output") path "Absent or empty export destination" (set! output-root path)])
  (unless (and repository commit policy-path output-root)
    (raise-user-error 'public-source-export
                      "repository, commit, policy, and output are required"))
  (define result
    (export-public-source! repository
                           commit
                           (read-export-policy policy-path)
                           output-root))
  (printf "public_source_export=valid inventory=~a content=~a tree=~a included=~a excluded=~a output=~a\n"
          (source-export-result-inventory-sha256 result)
          (source-export-result-content-sha256 result)
          (source-export-result-tree-sha256 result)
          (source-export-result-included result)
          (source-export-result-excluded result)
          (source-export-result-root result)))
