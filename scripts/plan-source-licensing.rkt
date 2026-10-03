#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/file
         racket/list
         racket/port
         racket/string
         racket/system)

(provide classify-path
         disposition-kind
         disposition-method)

(struct disposition (kind method reason) #:transparent)

(define copyright-text "2026 Adrian PK")
(define license-identifier "GPL-3.0-only")
(define copyright-field
  (string-append "SPDX-FileCopyrightText: " copyright-text))
(define license-field
  (string-append "SPDX-License-Identifier: " license-identifier))
(define license-pointer "This file is part of Odra. See COPYING for license terms.")

(define metadata-extensions
  '(".1" ".gz" ".ics" ".json" ".lock" ".png" ".rktd" ".tsv" ".txt"
         ".xz" ".zst"))

(define (path-prefix? path prefix)
  (string-prefix? path prefix))

(define (path-extension path)
  (define matched (regexp-match #px"(\\.[^./]+)$" path))
  (and matched (string-downcase (cadr matched))))

(define (fixture-path? path)
  (regexp-match? #px"(^|/)(fixtures?|snapshots?|goldens?)(/|$)" path))

(define (license-text-path? path)
  (or (member path '("COPYING" "LICENSE" "LICENSE.md" "LICENSE.txt"
                     "REUSE.toml"))
      (regexp-match? #px"^release/[^/]+/PREVIEW_TERMS\\.md$" path)
      (path-prefix? path "LICENSES/")))

(define (content-preserving-path? path)
  (fixture-path? path))

(define (agent-instruction-path? path)
  (or (string=? path "AGENTS.md")
      (path-prefix? path ".agents/")))

(define (header method reason)
  (disposition 'header method reason))

(define (classify-header path)
  (define extension (path-extension path))
  (cond
    [(string=? path "Makefile")
     (header 'hash-top "Make syntax supports hash comments")]
    [(string=? path "assets/docs/user-guide/bin/odra-guide")
     (header 'hash-after-shebang "Executable shell source keeps its shebang first")]
    [(regexp-match? #px"(^|/)Containerfile(?:\\..+)?$" path)
     (header 'hash-top "Containerfile syntax supports hash comments")]
    [(string=? path "src/display/unicode17_data.odin")
     (header 'slash-generated "The source generator must emit the notice")]
    [(member extension '(".odin"))
     (header 'slash-top "Odin supports line comments")]
    [(member extension '(".rkt" ".scrbl"))
     (header 'semicolon-after-lang "Racket keeps its language declaration first")]
    [(member extension '(".scm"))
     (header 'semicolon-top "Scheme supports semicolon comments")]
    [(member extension '(".sh" ".py"))
     (header 'hash-after-shebang "Script headers follow an optional shebang")]
    [(member extension '(".c" ".h" ".js" ".mjs" ".ts" ".tsx"))
     (header 'slash-top "The source format supports line comments")]
    [(member extension '(".css"))
     (header 'block-top "CSS supports block comments")]
    [(member extension '(".md"))
     (header 'html-after-frontmatter "Markdown keeps optional frontmatter first")]
    [(member extension '(".html"))
     (header 'html-top "HTML supports comments")]
    [(member extension '(".jan" ".org"))
     (header 'hash-top "Jan and Org documents support hash comments")]
    [(member extension '(".svg"))
     (header 'xml-after-declaration "SVG keeps an optional XML declaration first")]
    [(member extension '(".tex" ".texi"))
     (header 'percent-top "TeX supports percent comments")]
    [(or (member extension '(".build" ".editorconfig" ".gitattributes"
                             ".gitignore" ".mk" ".toml" ".yaml" ".yml"))
         (regexp-match? #px"(^|/)Dockerfile(?:\\..+)?$" path))
     (header 'hash-top "The configuration format supports hash comments")]
    [else #f]))

(define (classify-path path)
  (cond
    [(path-prefix? path "third_party/")
     (disposition 'preserve 'external "Preserve upstream copyright and license metadata")]
    [(license-text-path? path)
     (disposition 'preserve 'license-text "License texts do not require an annotation header")]
    [(agent-instruction-path? path)
     (disposition 'metadata 'reuse-toml
                  "Keep agent instructions free from repeated licensing context")]
    [(content-preserving-path? path)
     (disposition 'metadata 'reuse-toml "Keep signed, generated, or fixture content byte-stable")]
    [(classify-header path) => values]
    [(member (path-extension path) metadata-extensions)
     (disposition 'metadata 'reuse-toml "Associate metadata without changing file contents")]
    [else
     (disposition 'review 'manual "No explicit repository policy matches this path")]))

(define (git-tracked-files)
  (define git (find-executable-path "git"))
  (unless git
    (raise-user-error 'plan-source-licensing "git is not available"))
  (define-values (process stdout stdin stderr)
    (subprocess #f #f #f git "ls-files" "-z"))
  (close-output-port stdin)
  (define output (port->bytes stdout))
  (define diagnostic (port->string stderr))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (raise-user-error 'plan-source-licensing
                      "git ls-files failed: ~a"
                      (string-trim diagnostic)))
  (sort
   (for/list ([entry (in-list (regexp-split #rx#"\0" output))]
              #:unless (zero? (bytes-length entry)))
     (bytes->string/utf-8 entry))
   string<?))

(define (count-by items key)
  (for/fold ([counts (hash)]) ([item (in-list items)])
    (hash-update counts (key item) add1 0)))

(define (sorted-counts counts)
  (sort (hash->list counts) string<? #:key (lambda (entry) (format "~a" (car entry)))))

(define (display-counts title counts)
  (displayln title)
  (for ([entry (in-list (sorted-counts counts))])
    (printf "  ~a: ~a\n" (car entry) (cdr entry))))

(define (display-details plans)
  (displayln "kind\tmethod\tpath\treason")
  (for ([entry (in-list plans)])
    (define path (car entry))
    (define plan (cdr entry))
    (printf "~a\t~a\t~a\t~a\n"
            (disposition-kind plan)
            (disposition-method plan)
            path
            (disposition-reason plan))))

(define (line-ending content)
  (if (regexp-match? #rx"\r\n" content) "\r\n" "\n"))

(define (join-lines newline lines)
  (string-append (string-join lines newline) newline newline))

(define (notice-for method newline)
  (case method
    [(slash-top slash-generated)
     (join-lines newline
                 (list (string-append "// " copyright-field)
                       (string-append "// " license-field)
                       "//"
                       (string-append "// " license-pointer)))]
    [(semicolon-after-lang semicolon-top)
     (join-lines newline
                 (list (string-append "; " copyright-field)
                       (string-append "; " license-field)
                       ";"
                       (string-append "; " license-pointer)))]
    [(hash-after-shebang hash-top)
     (join-lines newline
                 (list (string-append "# " copyright-field)
                       (string-append "# " license-field)
                       "#"
                       (string-append "# " license-pointer)))]
    [(percent-top)
     (join-lines newline
                 (list (string-append "% " copyright-field)
                       (string-append "% " license-field)
                       "%"
                       (string-append "% " license-pointer)))]
    [(block-top)
     (join-lines newline
                 (list "/*"
                       (string-append " * " copyright-field)
                       (string-append " * " license-field)
                       " *"
                       (string-append " * " license-pointer)
                       " */"))]
    [(html-after-frontmatter html-top)
     (join-lines newline
                 (list "<!--"
                       copyright-field
                       license-field
                       ""
                       license-pointer
                       "-->"))]
    [(xml-after-declaration)
     (join-lines newline
                 (list "<!--"
                       copyright-field
                       license-field
                       ""
                       license-pointer
                       "-->"))]
    [else
     (raise-user-error 'source-licensing "unsupported header method: ~a" method)]))

(define (first-line-end content)
  (define match (regexp-match-positions #px"\r?\n" content))
  (if match (cdar match) (string-length content)))

(define (markdown-frontmatter-end content)
  (and (regexp-match? #px"^---[ \t]*\r?\n" content)
       (let* ([opening-end (first-line-end content)]
              [closing
               (regexp-match-positions
                #px"(?m:^---[ \t]*\r?\n)"
                content
                opening-end)])
         (and closing (cdar closing)))))

(define (insertion-position path method content)
  (case method
    [(semicolon-after-lang)
     (unless (regexp-match? #px"^#lang[ \t]" content)
       (raise-user-error 'source-licensing
                         "~a: Racket source does not start with #lang"
                         path))
     (first-line-end content)]
    [(hash-after-shebang)
     (if (string-prefix? content "#!") (first-line-end content) 0)]
    [(xml-after-declaration)
     (if (string-prefix? content "<?xml") (first-line-end content) 0)]
    [(html-after-frontmatter)
     (or (markdown-frontmatter-end content) 0)]
    [else 0]))

(define (canonical-content path plan content)
  (define method (disposition-method plan))
  (define newline (line-ending content))
  (define notice (notice-for method newline))
  (define position (insertion-position path method content))
  (define remainder (substring content position))
  (cond
    [(string-prefix? remainder notice) content]
    [else
     (define nearby-end (min (string-length remainder) 512))
     (define nearby (substring remainder 0 nearby-end))
     (define comment-prefix
       (case method
         [(slash-top slash-generated) "//"]
         [(semicolon-after-lang semicolon-top) ";"]
         [(hash-after-shebang hash-top) "#"]
         [(percent-top) "%"]
         [(block-top) "/*"]
         [(html-after-frontmatter html-top xml-after-declaration) "<!--"]
         [else ""]))
     (when (and (string-prefix? remainder comment-prefix)
                (or (string-contains? nearby "SPDX-FileCopyrightText:")
                    (string-contains? nearby "SPDX-License-Identifier:")))
       (raise-user-error 'source-licensing
                         "~a: conflicting or misplaced SPDX metadata near the header"
                         path))
     (string-append (substring content 0 position) notice remainder)]))

(define (metadata-paths plans)
  (for/list ([entry (in-list plans)]
             #:when (eq? 'metadata (disposition-kind (cdr entry))))
    (car entry)))

(define (toml-string value)
  (string-append
   "\""
   (string-replace (string-replace value "\\" "\\\\") "\"" "\\\"")
   "\""))

(define (reuse-metadata-content paths)
  (string-append
   "# " copyright-field "\n"
   "# " license-field "\n"
   "#\n"
   "# " license-pointer "\n\n"
   "version = 1\n\n"
   "[[annotations]]\n"
   "path = [\n"
   (apply string-append
          (for/list ([path (in-list paths)])
            (string-append "  " (toml-string path) ",\n")))
   "]\n"
   "precedence = \"aggregate\"\n"
   "SPDX-FileCopyrightText = " (toml-string copyright-text) "\n"
   "SPDX-License-Identifier = " (toml-string license-identifier) "\n"))

(define (atomic-write-string path content)
  (define permissions
    (and (file-exists? path) (file-or-directory-permissions path 'bits)))
  (call-with-atomic-output-file
   path
   (lambda (output _temporary-path)
     (display content output)))
  (when permissions
    (file-or-directory-permissions path permissions)))

(define (planned-header-changes plans)
  (for/list ([entry (in-list plans)]
             #:when (eq? 'header (disposition-kind (cdr entry)))
             #:when
             (let* ([path (car entry)]
                    [content (file->string path)])
               (not (string=? content
                              (canonical-content path (cdr entry) content)))))
    (car entry)))

(define (apply-headers! plans)
  (for/fold ([changed 0]) ([entry (in-list plans)]
                           #:when (eq? 'header
                                      (disposition-kind (cdr entry))))
    (define path (car entry))
    (define content (file->string path))
    (define updated (canonical-content path (cdr entry) content))
    (if (string=? content updated)
        changed
        (begin
          (atomic-write-string path updated)
          (add1 changed)))))

(define (write-reuse-metadata! plans)
  (define expected (reuse-metadata-content (metadata-paths plans)))
  (define current
    (and (file-exists? "REUSE.toml") (file->string "REUSE.toml")))
  (if (equal? current expected)
      #f
      (begin
        (atomic-write-string "REUSE.toml" expected)
        #t)))

(define (check-license-text!)
  (unless (file-exists? "COPYING")
    (raise-user-error 'source-licensing "COPYING is missing")))

(define (check-licensing! plans)
  (check-license-text!)
  (define missing (planned-header-changes plans))
  (define expected-metadata
    (reuse-metadata-content (metadata-paths plans)))
  (define metadata-valid?
    (and (file-exists? "REUSE.toml")
         (string=? (file->string "REUSE.toml") expected-metadata)))
  (unless (and (null? missing) metadata-valid?)
    (for ([path (in-list missing)])
      (eprintf "source-licensing: missing canonical header: ~a\n" path))
    (unless metadata-valid?
      (eprintf "source-licensing: REUSE.toml does not match tracked metadata files\n"))
    (exit 1))
  (printf "Source licensing is complete: headers=~a metadata=~a preserved=~a.\n"
          (for/sum ([entry (in-list plans)])
            (if (eq? 'header (disposition-kind (cdr entry))) 1 0))
          (length (metadata-paths plans))
          (for/sum ([entry (in-list plans)])
            (if (eq? 'preserve (disposition-kind (cdr entry))) 1 0))))

(define (display-plan files plans details?)
  (define kind-counts
    (count-by plans (lambda (entry) (disposition-kind (cdr entry)))))
  (define method-counts
    (count-by plans (lambda (entry) (disposition-method (cdr entry)))))
  (printf "Tracked files: ~a\n" (length files))
  (display-counts "Disposition:" kind-counts)
  (display-counts "Method:" method-counts)
  (define review-paths
    (for/list ([entry (in-list plans)]
               #:when (eq? 'review (disposition-kind (cdr entry))))
      (car entry)))
  (unless (null? review-paths)
    (displayln "Manual review:")
    (for-each (lambda (path) (printf "  ~a\n" path)) review-paths))
  (when details?
    (display-details plans))
  (values review-paths kind-counts))

(module+ main
  (define details? #f)
  (define mode 'dry-run)
  (command-line
   #:program "plan-source-licensing.rkt"
   #:once-each
   [("--details") "List the deterministic disposition for every tracked file"
                    (set! details? #t)]
   #:once-any
   [("--dry-run") "Report the changes without modifying files"
                   (set! mode 'dry-run)]
   [("--check") "Reject missing or inconsistent source licensing"
                 (set! mode 'check)]
   [("--apply") "Apply canonical headers and REUSE metadata"
                 (set! mode 'apply)])
  (define files (git-tracked-files))
  (define plans
    (for/list ([path (in-list files)])
      (cons path (classify-path path))))
  (define-values (review-paths _kind-counts)
    (display-plan files plans details?))
  (unless (null? review-paths)
    (raise-user-error 'source-licensing
                      "manual review is required before source licensing can proceed"))
  (case mode
    [(dry-run)
     (printf "Would update ~a headers and ~a metadata file.\n"
             (length (planned-header-changes plans))
             (if (and (file-exists? "REUSE.toml")
                      (string=? (file->string "REUSE.toml")
                                (reuse-metadata-content
                                 (metadata-paths plans))))
                 0
                 1))
     (displayln "No files were modified.")]
    [(check) (check-licensing! plans)]
    [(apply)
     (define changed (apply-headers! plans))
     (define metadata-changed? (write-reuse-metadata! plans))
     (printf "Applied source licensing: headers=~a metadata=~a.\n"
             changed
             (if metadata-changed? 1 0))]))

(module+ test
  (require rackunit)

  (test-case "Classifies Odin source headers"
    (define plan (classify-path "src/editor/editor.odin"))
    (check-equal? (disposition-kind plan) 'header)
    (check-equal? (disposition-method plan) 'slash-top))

  (test-case "Keeps Racket language first"
    (define plan (classify-path "scripts/check-example.rkt"))
    (check-equal? (disposition-kind plan) 'header)
    (check-equal? (disposition-method plan) 'semicolon-after-lang))

  (test-case "Keeps script shebang first"
    (define plan (classify-path "scripts/check-example.sh"))
    (check-equal? (disposition-kind plan) 'header)
    (check-equal? (disposition-method plan) 'hash-after-shebang))

  (test-case "Preserves external source metadata"
    (define plan (classify-path "third_party/example/parser.c"))
    (check-equal? (disposition-kind plan) 'preserve)
    (check-equal? (disposition-method plan) 'external))

  (test-case "Uses metadata for fixtures"
    (define plan (classify-path "tests/example/fixtures/input.odin"))
    (check-equal? (disposition-kind plan) 'metadata)
    (check-equal? (disposition-method plan) 'reuse-toml))

  (test-case "Keeps agent instructions free from inline notices"
    (define plan (classify-path ".agents/PLAYBOOKS.md"))
    (check-equal? (disposition-kind plan) 'metadata)
    (check-equal? (disposition-method plan) 'reuse-toml))

  (test-case "Annotates Markdown after frontmatter"
    (define plan (classify-path "ops/default/ticket/open/example.md"))
    (check-equal? (disposition-kind plan) 'header)
    (check-equal? (disposition-method plan) 'html-after-frontmatter))

  (test-case "Flags unknown formats for review"
    (define plan (classify-path "src/example/source.unknown"))
    (check-equal? (disposition-kind plan) 'review)
    (check-equal? (disposition-method plan) 'manual))

  (test-case "Places Racket notice after language declaration"
    (define plan (classify-path "scripts/example.rkt"))
    (define content "#lang racket/base\n\n(displayln \"example\")\n")
    (define updated (canonical-content "scripts/example.rkt" plan content))
    (check-true (string-prefix? updated "#lang racket/base\n; SPDX-FileCopyrightText:"))
    (check-equal? (canonical-content "scripts/example.rkt" plan updated)
                  updated))

  (test-case "Places Markdown notice after frontmatter"
    (define plan (classify-path "docs/example.md"))
    (define content "---\ntitle: Example\n---\n\n# Example\n")
    (define updated (canonical-content "docs/example.md" plan content))
    (check-true
     (string-prefix? updated
                     "---\ntitle: Example\n---\n<!--\nSPDX-FileCopyrightText:")))

  (test-case "Keeps third-party sources outside Odra metadata"
    (define plans
      (list (cons "third_party/example.c"
                  (classify-path "third_party/example.c"))))
    (check-equal? (metadata-paths plans) '()))

  (test-case "Preserves release-specific legal terms"
    (define plan
      (classify-path "release/linux-x86_64/PREVIEW_TERMS.md"))
    (check-equal? (disposition-kind plan) 'preserve)
    (check-equal? (disposition-method plan) 'license-text))

  (test-case "Atomic replacement preserves executable permission"
    (define path (make-temporary-file "source-licensing-~a.sh"))
    (dynamic-wind
      (lambda ()
        (file-or-directory-permissions path #o700))
      (lambda ()
        (atomic-write-string path "#!/usr/bin/env bash\n")
        (check-equal? (file-or-directory-permissions path 'bits) #o700))
      (lambda ()
        (when (file-exists? path) (delete-file path))))))
