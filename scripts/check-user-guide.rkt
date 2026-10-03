#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         racket/string)

(provide check-user-guide)

(define link-pattern #px"\\[([^]]+)\\]\\(([^)#]+)(?:#[^)]+)?\\)")
(define navigation-label-pattern
  #px"^(?:Previous:|Next:|User Guide$|Getting Started$|Editing$|Buffers and Panes$|Search and Navigation$|Files, Projects, and Workspaces$|Language Intelligence$|Interface$|Customization$)")
(define forbidden-getting-started-forms
  (list (cons #px"\\.build/odra" "build-tree executable")
        (cons #px"\\bODRA_BIN\\b" "executable-selection variable")
        (cons #px"build-and-launch\\.md" "source-build acquisition route")))

(define (canonical path)
  (simplify-path (path->complete-path path) #f))

(define (markdown-file? path)
  (and (file-exists? path)
       (equal? (path-get-extension path) #".md")))

(define (local-link? link)
  (and (not (regexp-match? #px"^[A-Za-z][A-Za-z0-9+.-]*:" link))
       (not (string-prefix? link "/"))))

(define (resolve-link source link)
  (and (local-link? link)
       (canonical (build-path (path-only source) link))))

(define (links-from source)
  (for*/list ([match (in-list (regexp-match* link-pattern
                                              (file->string source)
                                              #:match-select values))]
              [target (in-value (resolve-link source (caddr match)))]
              #:when target)
    (cons (cadr match) target)))

(define (path-inside? root target)
  (define parts
    (explode-path (find-relative-path (canonical root) (canonical target))))
  (and (not (member 'up parts))
       (not (member 'same parts))))

(define (guide-markdown-files root)
  (sort
   (for/list ([path (in-directory root)]
              #:when (markdown-file? path))
     (canonical path))
   path<?))

(define (guide-directories root)
  (sort
   (cons (canonical root)
         (for/list ([path (in-directory root)]
                    #:when (directory-exists? path))
           (canonical path)))
   path<?))

(define (guide-target root target)
  (define normalized
    (if (directory-exists? target)
        (build-path target "index.md")
        target))
  (and (path-inside? root normalized)
       (markdown-file? normalized)
       (canonical normalized)))

(define (reachable-guide-files root entrypoint)
  (let loop ([pending (list (canonical entrypoint))]
             [seen '()])
    (cond
      [(null? pending) seen]
      [(member (car pending) seen) (loop (cdr pending) seen)]
      [else
       (define source (car pending))
       (define targets
         (for*/list ([link (in-list (links-from source))]
                     [target (in-value (guide-target root (cdr link)))]
                     #:when target)
           target))
       (loop (append (cdr pending) targets) (cons source seen))])))

(define (index-registers? source expected)
  (and (markdown-file? source)
       (for/or ([link (in-list (links-from source))])
         (equal? (canonical (cdr link)) (canonical expected)))))

(define (visible-title source)
  (for/first ([line (in-list (file->lines source))]
              #:when (string-prefix? line "# "))
    line))

(define (first-run-contract-failures guide-root)
  (define getting-started-root (build-path guide-root "getting-started"))
  (define installation-entrypoint
    (build-path getting-started-root "install-odra.md"))
  (define published-linux-route
    (canonical (build-path getting-started-root "install-linux-preview.md")))
  (define failures '())

  (define (fail! message . arguments)
    (set! failures (cons (apply format message arguments) failures)))

  (when (directory-exists? getting-started-root)
    (unless (markdown-file? installation-entrypoint)
      (fail! "~a: installation-method entrypoint is missing"
             installation-entrypoint))

    (when (markdown-file? installation-entrypoint)
      (define allowed-entrypoint-targets
        (list (canonical (build-path guide-root "index.md"))
              (canonical (build-path getting-started-root "index.md"))
              published-linux-route))
      (define entrypoint-links (links-from installation-entrypoint))
      (unless (for/or ([link (in-list entrypoint-links)])
                (equal? (canonical (cdr link)) published-linux-route))
        (fail! "~a: published Linux installation route is missing"
               installation-entrypoint))
      (for ([link (in-list entrypoint-links)])
        (unless (member (canonical (cdr link)) allowed-entrypoint-targets)
          (fail! "~a: unavailable installation route is linked: ~a"
                 installation-entrypoint
                 (cdr link)))))

    (for* ([source (in-list (guide-markdown-files getting-started-root))]
           [forbidden (in-list forbidden-getting-started-forms)]
           #:when (regexp-match? (car forbidden) (file->string source)))
      (fail! "~a: Getting Started contains a ~a"
             source
             (cdr forbidden))))

  (reverse failures))

(define (check-user-guide root docs-index tutorials-index)
  (define guide-root (canonical root))
  (define guide-index (build-path guide-root "index.md"))
  (define failures '())

  (define (fail! message . arguments)
    (set! failures (cons (apply format message arguments) failures)))

  (unless (directory-exists? guide-root)
    (fail! "~a: canonical User Guide root is missing" guide-root))

  (when (directory-exists? guide-root)
    (unless (markdown-file? guide-index)
      (fail! "~a: root index is missing" guide-index))

    (when (markdown-file? guide-index)
      (unless (equal? (visible-title guide-index) "# User Guide")
        (fail! "~a: visible title must be exactly User Guide" guide-index))

      (define root-targets
        (for*/list ([link (in-list (links-from guide-index))]
                    [target (in-value (guide-target guide-root (cdr link)))]
                    #:when target)
          target))
      (for ([directory (in-list (directory-list guide-root #:build? #t))]
            #:when (directory-exists? directory))
        (define part-index (canonical (build-path directory "index.md")))
        (unless (member part-index root-targets)
          (fail! "~a: root index does not register part ~a"
                 guide-index
                 (file-name-from-path directory)))))

    (for ([directory (in-list (guide-directories guide-root))])
      (define index (build-path directory "index.md"))
      (unless (markdown-file? index)
        (fail! "~a: guide directory has no index.md" directory)))

    (when (markdown-file? guide-index)
      (define reachable (reachable-guide-files guide-root guide-index))
      (for ([path (in-list (guide-markdown-files guide-root))])
        (unless (member path reachable)
          (fail! "~a: guide chapter is unreachable from the root index" path))))

    (for* ([source (in-list (guide-markdown-files guide-root))]
           [link (in-list (links-from source))]
           #:when (regexp-match? navigation-label-pattern (car link)))
      (unless (path-inside? guide-root (cdr link))
        (fail! "~a: navigation link escapes the User Guide: ~a"
               source
               (car link)))))

  (for ([failure (in-list (first-run-contract-failures guide-root))])
    (fail! "~a" failure))

  (unless (index-registers? docs-index guide-index)
    (fail! "~a: documentation index does not register the User Guide"
           docs-index))
  (unless (index-registers? tutorials-index guide-index)
    (fail! "~a: tutorials index does not register the User Guide"
           tutorials-index))

  (reverse failures))

(module+ main
  (define failures
    (check-user-guide "docs/tutorials/user-guide"
                      "docs/index.md"
                      "docs/tutorials/index.md"))
  (unless (null? failures)
    (for-each displayln failures)
    (exit 1))
  (printf "Checked the canonical User Guide structure; all chapters are indexed and reachable.\n"))

(module+ test
  (require rackunit)

  (define (write-text path content)
    (make-parent-directory* path)
    (call-with-output-file path
      #:exists 'truncate
      (lambda (output) (display content output))))

  (define (with-guide-fixture procedure)
    (define root (make-temporary-file "odra-user-guide-check~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define guide (build-path root "docs" "tutorials" "user-guide"))
        (define docs-index (build-path root "docs" "index.md"))
        (define tutorials-index (build-path root "docs" "tutorials" "index.md"))
        (write-text (build-path guide "index.md")
                    "# User Guide\n\n[Part](part/index.md)\n")
        (write-text (build-path guide "part" "index.md")
                    "# Part\n\n[Chapter](chapter.md)\n")
        (write-text (build-path guide "part" "chapter.md")
                    "# Chapter\n\n[User Guide](../index.md)\n")
        (write-text docs-index
                    "# Docs\n\n[User Guide](tutorials/user-guide/index.md)\n")
        (write-text tutorials-index
                    "# Tutorials\n\n[User Guide](user-guide/index.md)\n")
        (procedure guide docs-index tutorials-index))
      (lambda () (delete-directory/files root))))

  (define (add-first-run-fixture guide)
    (write-text (build-path guide "index.md")
                (string-append
                 "# User Guide\n\n"
                 "[Part](part/index.md)\n\n"
                 "[Getting Started](getting-started/index.md)\n"))
    (write-text (build-path guide "getting-started" "index.md")
                (string-append
                 "# Getting Started\n\n"
                 "[Choose an Installation Method](install-odra.md)\n"))
    (write-text (build-path guide "getting-started" "install-odra.md")
                (string-append
                 "# Choose an Installation Method\n\n"
                 "[Linux preview](install-linux-preview.md)\n"))
    (write-text (build-path guide "getting-started" "install-linux-preview.md")
                "# Install Linux Preview\n"))

  (test-case "accepts one complete indexed guide"
    (with-guide-fixture
     (lambda (guide docs-index tutorials-index)
       (check-equal? (check-user-guide guide docs-index tutorials-index) '()))))

  (test-case "rejects a directory without an index"
    (with-guide-fixture
     (lambda (guide docs-index tutorials-index)
       (delete-file (build-path guide "part" "index.md"))
       (check-true
        (for/or ([failure (in-list (check-user-guide guide docs-index tutorials-index))])
          (string-contains? failure "has no index.md"))))))

  (test-case "rejects an unreachable chapter"
    (with-guide-fixture
     (lambda (guide docs-index tutorials-index)
       (write-text (build-path guide "part" "orphan.md") "# Orphan\n")
       (check-true
        (for/or ([failure (in-list (check-user-guide guide docs-index tutorials-index))])
          (string-contains? failure "unreachable"))))))

  (test-case "rejects navigation outside the guide"
    (with-guide-fixture
     (lambda (guide docs-index tutorials-index)
       (write-text (build-path guide "part" "chapter.md")
                   "# Chapter\n\n[Next: Elsewhere](../../../outside.md)\n")
       (check-true
        (for/or ([failure (in-list (check-user-guide guide docs-index tutorials-index))])
          (string-contains? failure "navigation link escapes"))))))

  (test-case "accepts the published first-run route"
    (with-guide-fixture
     (lambda (guide docs-index tutorials-index)
       (add-first-run-fixture guide)
       (check-equal? (check-user-guide guide docs-index tutorials-index) '()))))

  (test-case "rejects a build-tree executable in Getting Started"
    (with-guide-fixture
     (lambda (guide docs-index tutorials-index)
       (add-first-run-fixture guide)
       (write-text (build-path guide "getting-started" "install-linux-preview.md")
                   "# Install Linux Preview\n\n```sh\n.build/odra\n```\n")
       (check-true
        (for/or ([failure (in-list (check-user-guide guide docs-index tutorials-index))])
          (string-contains? failure "build-tree executable"))))))

  (test-case "rejects an unavailable installation route"
    (with-guide-fixture
     (lambda (guide docs-index tutorials-index)
       (add-first-run-fixture guide)
       (write-text (build-path guide "getting-started" "install-odra.md")
                   (string-append
                    "# Choose an Installation Method\n\n"
                    "[Linux preview](install-linux-preview.md)\n\n"
                    "[Build from source](build-and-launch.md)\n"))
       (check-true
        (for/or ([failure (in-list (check-user-guide guide docs-index tutorials-index))])
          (string-contains? failure "unavailable installation route")))))))
