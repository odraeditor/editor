#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         racket/string)

(provide check-user-guide-usability)

(define link-pattern #px"\\[([^]]+)\\]\\(([^)#]+)(?:#[^)]+)?\\)")

(define forbidden-forms
  (list (cons #px"\\.build/odra" "build-tree executable")
        (cons #px"\\bODRA_BIN\\b" "executable-selection variable")
        (cons #px"/tmp/odra-user-guide" "temporary guide root")
        (cons #px"examples/user-guide-workspace" "repository exercise path")
        (cons #px"scripts/setup-user-guide-workspace\\.rkt"
              "repository setup helper")
        (cons #px"(?m:^make odra$)" "source-build prerequisite")))

(define provenance-pattern
  #px"(?i:supplied|supplies|chapter-created|created by|create |creates |pasting|pasted)")

(define guide-file-pattern
  #px"(?:~|\\$HOME)/odra-guide/(?:work|config)/[^`[:space:]]+\\.(?:txt|md|rkt|odin)")

(define reset-requirements
  (list
   (cons "editing/move-and-edit-text.md" "reset notes")
   (cons "buffers-and-panes/work-with-buffers.md" "reset notes")
   (cons "search-and-navigation/replace-text.md" "reset notes")
   (cons "search-and-navigation/navigate-results.md" "reset notes")
   (cons "search-and-navigation/search-projects-and-symbols.md"
         "reset workspace-state")
   (cons "files-projects-workspaces/choose-a-working-context.md"
         "reset report-console-promotion")
   (cons "files-projects-workspaces/manage-a-project.md"
         "reset report-console-promotion")
   (cons "files-projects-workspaces/manage-a-workspace.md"
         "reset workspace-state")
   (cons "files-projects-workspaces/darek/manage-resources.md"
         "reset forecast-engine")
   (cons "files-projects-workspaces/maksym/edit-filenames.md"
         "reset forecast-engine")
   (cons "language-intelligence/syntax-and-structure.md"
         "reset workspace-state")
   (cons "customization/personal-configuration.md"
         "reset configuration-examples")))

(define (canonical path)
  (simplify-path (path->complete-path path) #f))

(define (markdown-file? path)
  (and (file-exists? path)
       (equal? (path-get-extension path) #".md")))

(define (chapter-files root)
  (sort
   (for/list ([path (in-directory root)]
              #:when (and (markdown-file? path)
                          (not (equal? (path->string (file-name-from-path path))
                                       "index.md"))))
     (canonical path))
   path<?))

(define (local-link-targets source)
  (for/list ([match (in-list (regexp-match* link-pattern
                                             (file->string source)
                                             #:match-select values))]
             #:when (not (regexp-match? #px"^[A-Za-z][A-Za-z0-9+.-]*:"
                                        (caddr match))))
    (canonical (build-path (path-only source) (caddr match)))))

(define (relative-name root source)
  (path->string (find-relative-path (canonical root) source)))

(define (check-user-guide-usability root)
  (define guide-root (canonical root))
  (define setup-path
    (canonical (build-path guide-root "getting-started" "prepare-exercises.md")))
  (define failures '())

  (define (fail! source message)
    (set! failures
          (cons (format "~a: ~a" (relative-name guide-root source) message)
                failures)))

  (for ([source (in-list (chapter-files guide-root))])
    (define content (file->string source))
    (define relative (relative-name guide-root source))
    (define lines (string-split content "\n"))
    (define (launch-line? line)
      (regexp-match? #px"(^|[[:space:]])odra([[:space:]]|$)" line))

    (for ([forbidden (in-list forbidden-forms)]
          #:when (regexp-match? (car forbidden) content))
      (fail! source (format "contains a ~a" (cdr forbidden))))

    (when (and (regexp-match? #px"(?:~|\\$HOME)/odra-guide" content)
               (not (equal? source setup-path))
               (not (member setup-path (local-link-targets source))))
      (fail! source "uses the guide area without linking the setup checkpoint"))

    (when (and (regexp-match? guide-file-pattern content)
               (not (regexp-match? provenance-pattern content)))
      (fail! source "names an exercise file without explicit provenance"))

    (when (for/or ([line (in-list lines)])
            (and (string-contains? line "XDG_CONFIG_HOME=")
                 (launch-line? line)))
      (fail! source "inlines guide isolation into an Odra launch"))

    (when (and (for/or ([line (in-list lines)])
                 (and (or (string-contains? line "COLORTERM=")
                          (string-contains? line "TERM="))
                      (launch-line? line)))
               (not (string=? relative "interface/themes.md")))
      (fail! source "uses a terminal capability launch outside the theme exercise"))

    (when (and (for/or ([line (in-list lines)])
                 (and (string-prefix? line "PATH=")
                      (launch-line? line)))
               (not (string=?
                     relative
                     "language-intelligence/language-services-and-diagnostics.md")))
      (fail! source "uses a PATH launch outside the provider-failure exercise"))

    (when (and (member relative
                       (map car reset-requirements))
               (let ([required (assoc relative reset-requirements)])
                 (not (string-contains? content (cdr required)))))
      (fail! source "omits its required deterministic reset")))

  (define themes
    (build-path guide-root "interface" "themes.md"))
  (when (markdown-file? themes)
    (define content (file->string themes))
    (unless (and (string-contains? content "one-off")
                 (string-contains? content "Resume ordinary guide work"))
      (fail! (canonical themes)
             "does not bound capability overrides and restore ordinary launch")))

  (define provider-failure
    (build-path guide-root
                "language-intelligence"
                "language-services-and-diagnostics.md"))
  (when (markdown-file? provider-failure)
    (define content (file->string provider-failure))
    (unless (and (string-contains? content "capability experiment")
                 (string-contains? content "Resume ordinary guide work"))
      (fail! (canonical provider-failure)
             "does not bound the PATH experiment and restore ordinary launch")))

  (reverse failures))

(module+ main
  (define failures
    (check-user-guide-usability "docs/tutorials/user-guide"))
  (unless (null? failures)
    (for-each displayln failures)
    (exit 1))
  (printf "Checked User Guide first-run usability contracts.\n"))

(module+ test
  (require rackunit)

  (define (write-text path content)
    (make-parent-directory* path)
    (call-with-output-file path
      #:exists 'truncate
      (lambda (output) (display content output))))

  (define (with-fixture procedure)
    (define root (make-temporary-file "odra-user-guide-usability~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define guide (build-path root "docs" "tutorials" "user-guide"))
        (write-text (build-path guide "getting-started" "prepare-exercises.md")
                    "# Prepare Exercises\n")
        (procedure guide))
      (lambda () (delete-directory/files root))))

  (test-case "accepts installed-reader paths with provenance and setup"
    (with-fixture
     (lambda (guide)
       (write-text
        (build-path guide "part" "chapter.md")
        (string-append
         "# Chapter\n\n"
         "[Prepare](../getting-started/prepare-exercises.md)\n\n"
         "The kit supplies `~/odra-guide/work/dirs/notes/review.md`.\n\n"
         "```sh\nodra ~/odra-guide/work/dirs/notes/review.md\n```\n"))
       (check-equal? (check-user-guide-usability guide) '()))))

  (test-case "rejects repository paths inline isolation and missing provenance"
    (with-fixture
     (lambda (guide)
       (write-text
        (build-path guide "part" "chapter.md")
        (string-append
         "# Chapter\n\n"
         "```sh\n"
         ".build/odra\n"
         "XDG_CONFIG_HOME=/tmp/odra-user-guide-config odra "
         "~/odra-guide/work/dirs/notes/review.md\n"
         "```\n"))
       (define failures (check-user-guide-usability guide))
       (check-true
        (for/or ([failure (in-list failures)])
          (string-contains? failure "build-tree executable")))
       (check-true
        (for/or ([failure (in-list failures)])
          (string-contains? failure "without linking")))
       (check-true
        (for/or ([failure (in-list failures)])
          (string-contains? failure "without explicit provenance")))
       (check-true
        (for/or ([failure (in-list failures)])
          (string-contains? failure "inlines guide isolation"))))))

  (test-case "rejects missing reset and misplaced capability overrides"
    (with-fixture
     (lambda (guide)
       (write-text
        (build-path guide "editing" "move-and-edit-text.md")
        (string-append
         "# Move and Edit Text\n\n"
         "[Prepare](../getting-started/prepare-exercises.md)\n\n"
         "The kit supplies `~/odra-guide/work/dirs/notes/review.md`.\n\n"
         "```sh\nCOLORTERM=truecolor TERM=xterm-256color odra\n```\n"))
       (define failures (check-user-guide-usability guide))
       (check-true
        (for/or ([failure (in-list failures)])
          (string-contains? failure "required deterministic reset")))
       (check-true
        (for/or ([failure (in-list failures)])
          (string-contains? failure "outside the theme exercise")))))))
