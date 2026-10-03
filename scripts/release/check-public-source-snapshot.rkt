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
         racket/string
         "../plan-source-licensing.rkt")

(provide (struct-out snapshot-audit)
         read-closure-contract
         snapshot-audit-errors
         audit-public-source-snapshot)

(struct snapshot-audit
  (files first-party-files third-party-files binary-inputs errors)
  #:transparent)

(define canonical-copyright "SPDX-FileCopyrightText: 2026 Adrian PK")
(define canonical-license "SPDX-License-Identifier: GPL-3.0-only")
(define canonical-pointer "This file is part of Odra. See COPYING for license terms.")

(define sensitive-patterns
  (list (cons "private-key" #rx#"-----BEGIN [A-Z ]*PRIVATE KEY-----")
        (cons "maintainer-home" #rx#"/home/adrian/")
        (cons "private-forge-ssh" #rx#"ssh://forge@")
        (cons "private-forge-scp" #rx#"git@forge[.]adrianpk[.]com:")
        (cons "tailnet-host" #rx#"zeus[.]tail[[:alnum:]]*[.]ts[.]net")))

(define (hash-value table key [fallback #f])
  (if (hash? table) (hash-ref table key fallback) fallback))

(define (read-json-file path)
  (call-with-input-file path read-json))

(define (read-closure-contract path)
  (define value (read-json-file path))
  (unless (and (hash? value)
               (equal? (hash-value value 'schema) 1)
               (string? (hash-value value 'version))
               (andmap string? (hash-value value 'forbidden_prefixes '()))
               (andmap string? (hash-value value 'content_scan_exemptions '()))
               (andmap string? (hash-value value 'required_files '()))
               (andmap string? (hash-value value 'required_prefixes '()))
               (andmap string? (hash-value value 'declared_binary_inputs '())))
    (raise-arguments-error 'read-closure-contract
                           "invalid public source closure contract"
                           "path" path))
  value)

(define (path-under-prefix? path prefix)
  (string-prefix? path prefix))

(define (safe-relative-path? path)
  (and (string? path)
       (not (string=? path ""))
       (relative-path? (string->path path))
       (not (member ".." (string-split path "/")))
       (not (string-contains? path "\\"))))

(define (tree-files root)
  (sort
   (for/list ([path (in-list (find-files (lambda (_) #t) root #:follow-links? #f))]
              #:when (member (file-or-directory-type path #f) '(file link)))
     (path->string (find-relative-path root path)))
   string<?))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input)
      (bytes->hex-string (sha256-bytes input)))))

(define (utf8-file? path)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (bytes->string/utf-8 (file->bytes path))
    #t))

(define (inventory-included-entries inventory)
  (filter (lambda (entry)
            (equal? (hash-value entry 'classification) "include"))
          (hash-value inventory 'entries '())))

(define (inventory-excluded-entries inventory)
  (filter (lambda (entry)
            (equal? (hash-value entry 'classification) "exclude"))
          (hash-value inventory 'entries '())))

(define (entry-shape-errors tree entry)
  (define path (hash-value entry 'path))
  (define kind (hash-value entry 'kind))
  (define mode (hash-value entry 'mode))
  (define expected-sha256 (hash-value entry 'sha256))
  (define absolute (and (string? path) (build-path tree path)))
  (cond
    [(not (safe-relative-path? path))
     (list (format "inventory contains unsafe path: ~a" path))]
    [(not (file-or-directory-type absolute #f))
     (list (format "included inventory path is missing: ~a" path))]
    [(and (equal? kind "file")
          (not (eq? (file-or-directory-type absolute #f) 'file)))
     (list (format "inventory file has different type: ~a" path))]
    [(and (equal? kind "symlink")
          (not (eq? (file-or-directory-type absolute #f) 'link)))
     (list (format "inventory symlink has different type: ~a" path))]
    [(and (equal? kind "file")
          (not (equal? expected-sha256 (sha256-file absolute))))
     (list (format "included file digest differs: ~a" path))]
    [(and (equal? kind "symlink")
          (not (equal? expected-sha256
                       (bytes->hex-string
                        (sha256-bytes
                         (open-input-bytes
                          (string->bytes/utf-8
                           (path->string (resolve-path absolute)))))))))
     (list (format "included symlink digest differs: ~a" path))]
    [(and (equal? kind "file")
          (not (equal? mode
                       (if (= (bitwise-and
                               (file-or-directory-permissions absolute 'bits)
                               #o111)
                              0)
                           "100644"
                           "100755"))))
     (list (format "included file mode differs: ~a" path))]
    [else '()]))

(define (shape-errors output-root tree inventory summary)
  (define included (inventory-included-entries inventory))
  (define excluded (inventory-excluded-entries inventory))
  (define included-paths (map (lambda (entry) (hash-value entry 'path)) included))
  (define expected-tree-paths
    (sort (cons "release/public-source-manifest.json" included-paths) string<?))
  (define actual-tree-paths (tree-files tree))
  (define manifest-path (build-path tree "release" "public-source-manifest.json"))
  (define manifest
    (and (file-exists? manifest-path) (read-json-file manifest-path)))
  (append
   (if (equal? expected-tree-paths actual-tree-paths)
       '()
       (list "exported tree paths differ from the included inventory"))
   (append* (map (lambda (entry) (entry-shape-errors tree entry)) included))
   (for/list ([entry (in-list excluded)]
              #:when (file-or-directory-type
                      (build-path tree (hash-value entry 'path)) #f))
     (format "excluded inventory path exists in tree: ~a"
             (hash-value entry 'path)))
   (if (hash? manifest) '() '("public source manifest is missing or invalid"))
   (if (and (hash? manifest)
            (equal? (hash-value manifest 'source_commit)
                    (hash-value inventory 'source_commit))
            (equal? (hash-value manifest 'source_commit)
                    (hash-value summary 'source_commit))
            (equal? (hash-value manifest 'content_sha256)
                    (hash-value inventory 'content_sha256))
            (= (hash-value manifest 'included_files -1) (length included))
            (= (hash-value summary 'included_files -1) (length included)))
       '()
       '("snapshot manifest, summary, and inventory identities differ"))))

(define (privacy-errors tree paths contract)
  (define forbidden (hash-value contract 'forbidden_prefixes '()))
  (define exemptions (hash-value contract 'content_scan_exemptions '()))
  (append
   (for/list ([path (in-list paths)]
              #:when (ormap (lambda (prefix) (path-under-prefix? path prefix))
                            forbidden))
     (format "forbidden snapshot path: ~a" path))
   (append*
    (for/list ([path (in-list paths)]
               #:unless (member path exemptions)
               #:when (eq? (file-or-directory-type (build-path tree path) #f)
                            'file)
               #:when (utf8-file? (build-path tree path)))
      (define content (file->bytes (build-path tree path)))
      (for/list ([pattern (in-list sensitive-patterns)]
                 #:when (regexp-match? (cdr pattern) content))
        (format "sensitive content ~a appears in ~a" (car pattern) path))))))

(define (licensing-errors tree paths)
  (define reuse-path (build-path tree "REUSE.toml"))
  (define reuse-content
    (if (file-exists? reuse-path) (file->string reuse-path) ""))
  (append
   (if (file-exists? (build-path tree "COPYING"))
       '()
       '("COPYING is missing"))
   (append*
    (for/list ([path (in-list paths)]
               #:unless (string-prefix? path "third_party/")
               #:unless (string=? path "release/public-source-manifest.json")
               #:when (eq? (file-or-directory-type (build-path tree path) #f)
                            'file))
      (define disposition (classify-path path))
      (case (disposition-kind disposition)
        [(header)
         (define content (file->string (build-path tree path)))
         (if (and (string-contains? content canonical-copyright)
                  (string-contains? content canonical-license)
                  (string-contains? content canonical-pointer))
             '()
             (list (format "first-party source lacks the canonical notice: ~a"
                           path)))]
        [(metadata)
         (if (string-contains? reuse-content (format "\"~a\"" path))
             '()
             (list (format "first-party metadata lacks REUSE coverage: ~a"
                           path)))]
        [(review)
         (list (format "first-party source requires licensing review: ~a" path))]
        [else '()])))))

(define (closure-errors tree paths contract)
  (define required-files (hash-value contract 'required_files '()))
  (define required-prefixes (hash-value contract 'required_prefixes '()))
  (define declared-binaries
    (sort (hash-value contract 'declared_binary_inputs '()) string<?))
  (define actual-binaries
    (sort
     (for/list ([path (in-list paths)]
                #:when (eq? (file-or-directory-type (build-path tree path) #f)
                            'file)
                #:unless (utf8-file? (build-path tree path)))
       path)
     string<?))
  (append
   (for/list ([path (in-list required-files)]
              #:unless (file-exists? (build-path tree path)))
     (format "required source-closure file is missing: ~a" path))
   (for/list ([prefix (in-list required-prefixes)]
              #:unless (ormap (lambda (path) (string-prefix? path prefix)) paths))
     (format "required source-closure prefix is empty: ~a" prefix))
   (if (equal? declared-binaries actual-binaries)
       '()
       (list (format "binary input declaration differs: declared=~a actual=~a"
                     (length declared-binaries)
                     (length actual-binaries))))))

(define (audit-public-source-snapshot output-root contract)
  (define root (path->complete-path output-root))
  (define tree (build-path root "tree"))
  (define inventory-path (build-path root "inventory.json"))
  (define summary-path (build-path root "summary.json"))
  (unless (and (directory-exists? tree)
               (file-exists? inventory-path)
               (file-exists? summary-path))
    (raise-arguments-error 'audit-public-source-snapshot
                           "snapshot output is incomplete"
                           "output" root))
  (define inventory (read-json-file inventory-path))
  (define summary (read-json-file summary-path))
  (define paths (tree-files tree))
  (define binaries
    (for/list ([path (in-list paths)]
               #:when (eq? (file-or-directory-type (build-path tree path) #f)
                           'file)
               #:unless (utf8-file? (build-path tree path)))
      path))
  (define errors
    (append (shape-errors root tree inventory summary)
            (privacy-errors tree paths contract)
            (licensing-errors tree paths)
            (closure-errors tree paths contract)))
  (snapshot-audit
   (length paths)
   (count (lambda (path) (not (string-prefix? path "third_party/"))) paths)
   (count (lambda (path) (string-prefix? path "third_party/")) paths)
   (length binaries)
   errors))

(module+ main
  (define output-root #f)
  (define contract-path #f)
  (command-line
   #:program "check-public-source-snapshot.rkt"
   #:once-each
   [("--snapshot") path "Export output containing tree and inventory"
                         (set! output-root path)]
   [("--contract") path "Public source closure contract"
                         (set! contract-path path)])
  (unless (and output-root contract-path)
    (raise-user-error 'public-source-snapshot-audit
                      "snapshot and contract are required"))
  (define audit
    (audit-public-source-snapshot output-root
                                  (read-closure-contract contract-path)))
  (for ([error (in-list (snapshot-audit-errors audit))])
    (eprintf "public-source-snapshot: ~a\n" error))
  (unless (null? (snapshot-audit-errors audit)) (exit 1))
  (printf "public-source-snapshot: valid files=~a first-party=~a third-party=~a binary-inputs=~a\n"
          (snapshot-audit-files audit)
          (snapshot-audit-first-party-files audit)
          (snapshot-audit-third-party-files audit)
          (snapshot-audit-binary-inputs audit)))
