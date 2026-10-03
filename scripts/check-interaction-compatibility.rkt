#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/cmdline
         racket/file
         racket/list
         racket/runtime-path
         racket/string
         rackunit
         "../src/command/keymaps.rkt"
         (prefix-in bundle: "../src/command/language-bundles.rkt")
         (prefix-in language: "../src/command/languages.rkt")
         "../src/language_bundle/factory-bundles.rkt")

(provide check-interaction-compatibility)

(define-runtime-path default-fixture
  "../tests/interaction_compatibility/cases.tsv")
(define-runtime-path ksawery-host-boundary
  "../src/ksawery_module/host_boundary.odin")
(define-runtime-path ksawery-status-dispatcher
  "../src/ksawery_module/ksawery_status_dispatcher.odin")
(define-runtime-path darek-workflow
  "../src/odra/darek_workflow.odin")
(define-runtime-path darek-pointer-workflow
  "../src/odra/pointer_workflow.odin")

(define expected-header
  '(scope case_id area applicability expected_binding expected_command
    binding_class behavior_class evidence review_state review_notes))

(define (fixture-lines path)
  (for/list ([line (in-list (file->lines path))]
             #:unless (or (string=? line "") (string-prefix? line "#")))
    line))

(define (parse-row line)
  (regexp-split #rx"\t" line))

(define (ensure condition format-string . values)
  (unless condition
    (apply raise-user-error 'interaction-compatibility format-string values)))

(define (direct-bindings)
  (odra-keymap-bindings
   (car (odra-interaction-profile-maps
         (factory-interaction-profile 1)))))

(define (stroke scalar [modifiers 0])
  (odra-key-stroke 1 (char->integer scalar) modifiers))

(define control #x01)
(define meta #x02)

(define expected-case-count 190)
(define expected-applicable-count 178)
(define expected-excluded-count 12)

(define (field-count rows index expected)
  (count (lambda (row) (string=? (list-ref row index) expected)) rows))

(define (special kind [modifiers 0])
  (odra-key-stroke kind 0 modifiers))

(define (binding-command bindings . strokes)
  (for/first ([candidate (in-list bindings)]
              #:when (equal? (odra-key-sequence-strokes
                              (odra-binding-sequence candidate))
                             strokes))
    (odra-binding-command candidate)))

(define (check-interaction-compatibility fixture-path)
  (define lines (fixture-lines fixture-path))
  (ensure (pair? lines) "fixture is empty")
  (define header (map string->symbol (parse-row (car lines))))
  (ensure (equal? header expected-header) "fixture header is not canonical")
  (define rows (map parse-row (cdr lines)))
  (ensure (= (length rows) expected-case-count)
          "expected ~a cases, found ~a" expected-case-count (length rows))
  (for ([row (in-list rows)] [line-number (in-naturals 9)])
    (ensure (= (length row) (length expected-header))
            "line ~a has ~a fields, expected ~a"
            line-number (length row) (length expected-header)))
  (define case-ids (map cadr rows))
  (ensure (= (length case-ids) (length (remove-duplicates case-ids)))
          "case identities are not unique")
  (for ([scope+count (in-list '(("core" . 108)
                                ("maksym" . 26)
                                ("darek" . 5)
                                ("jan-babel" . 26)
                                ("ksawery" . 19)
                                ("roman" . 6)))])
    (ensure (= (count (lambda (row) (string=? (car row) (car scope+count))) rows)
               (cdr scope+count))
            "scope ~a is incomplete" (car scope+count)))
  (ensure (andmap (lambda (row) (string=? (list-ref row 9) "reviewed")) rows)
          "fixture contains an unreviewed case")
  (ensure (= (field-count rows 3 "applicable") expected-applicable-count)
          "fixture applicable-case boundary changed")
  (ensure (= (field-count rows 3 "excluded") expected-excluded-count)
          "fixture exclusion boundary changed")
  (for ([class+count (in-list '(("exact" . 176)
                                ("composition" . 1)
                                ("normalized-alias" . 1)
                                ("not-applicable" . 12)))])
    (ensure (= (field-count rows 6 (car class+count)) (cdr class+count))
            "binding class ~a changed" (car class+count)))
  (for ([class+count (in-list '(("match" . 95)
                                ("behavior-match" . 12)
                                ("adapted" . 66)
                                ("partial-match" . 5)
                                ("not-applicable" . 12)))])
    (ensure (= (field-count rows 7 (car class+count)) (cdr class+count))
            "behavior class ~a changed" (car class+count)))
  (for ([row (in-list rows)]
        #:when (string=? (list-ref row 3) "applicable"))
    (ensure (and (not (string=? (list-ref row 4) ""))
                 (not (string=? (list-ref row 5) ""))
                 (not (string=? (list-ref row 8) "")))
            "applicable case ~a lacks binding, command, or evidence" (cadr row)))

  (define bindings (direct-bindings))
  (define prefix (list (stroke #\x control) (stroke #\r)))
  (define (register-command scalar)
    (apply binding-command bindings (append prefix (list (stroke scalar)))))
  (ensure (equal? (register-command #\space) "store-position")
          "C-x r SPC must store a position")
  (ensure (equal? (register-command #\s) "store-region-text")
          "C-x r s must store the active region")
  (ensure (equal? (register-command #\i) "insert-slot")
          "C-x r i must insert named text")
  (ensure (equal? (register-command #\w) "store-layout")
          "C-x r w must store the current layout")
  (ensure (equal? (register-command #\j) "visit-slot")
          "C-x r j must visit a typed named slot")
  (ensure (not (register-command #\f))
          "C-x r f is not applicable in the terminal UI")
  (ensure (not (member "store-text" (map odra-binding-command bindings)))
          "prompted arbitrary text storage must remain a named command")
  (ensure
   (not (for/or ([binding (in-list bindings)])
          (string-prefix? (odra-binding-command binding) "jan-")))
   "Jan bindings must not leak into the global Direct map")
  (define control-x (stroke #\x control))
  (for ([case (in-list
               (list (list "C-x C-v" "find-alternate-file" control-x (stroke #\v control))
                     (list "C-x C-w" "write-file" control-x (stroke #\w control))
                     (list "C-x s" "save-some-buffers" control-x (stroke #\s))
                     (list "C-x i" "insert-file" control-x (stroke #\i))
                     (list "C-x C-q" "toggle-read-only" control-x (stroke #\q control))
                     (list "C-x Right" "next-buffer" control-x (special 3))
                     (list "C-x Left" "previous-buffer" control-x (special 2))
                     (list "M-<" "cursor-buffer-start" (stroke #\< meta))
                     (list "M->" "cursor-buffer-end" (stroke #\> meta))
                     (list "M-Right" "cursor-next-word" (special 3 meta))
                     (list "M-Left" "cursor-previous-word" (special 2 meta))
                     (list "M-g g" "goto-line" (stroke #\g meta) (stroke #\g))
                     (list "M-g c" "goto-char" (stroke #\g meta) (stroke #\c))
                     (list "M-s w" "search-word" (stroke #\s meta) (stroke #\w))
                     (list "M-s o" "occur" (stroke #\s meta) (stroke #\o))
                     (list "M-s h ." "highlight-symbol-at-point"
                           (stroke #\s meta) (stroke #\h) (stroke #\.))
                     (list "M-s h p" "highlight-phrase"
                           (stroke #\s meta) (stroke #\h) (stroke #\p))
                     (list "M-s h r" "highlight-regexp"
                           (stroke #\s meta) (stroke #\h) (stroke #\r))
                     (list "M-s h l" "highlight-lines-matching-regexp"
                           (stroke #\s meta) (stroke #\h) (stroke #\l))
                     (list "M-s h u" "unhighlight-regexp"
                           (stroke #\s meta) (stroke #\h) (stroke #\u))
                     (list "C-k" "kill-line" (stroke #\k control))
                     (list "M-DEL" "backward-kill-word" (special 8 meta))
                     (list "M-d" "kill-word" (stroke #\d meta))
                     (list "C-x C-o" "delete-blank-lines" control-x (stroke #\o control))
                     (list "M-q" "fill-paragraph" (stroke #\q meta))
                     (list "M-t" "transpose-words" (stroke #\t meta))
                     (list "M-u" "upcase-word" (stroke #\u meta))
                     (list "M-l" "downcase-word" (stroke #\l meta))
                     (list "M-c" "capitalize-word" (stroke #\c meta))
                     (list "M-;" "comment-dwim" (stroke #\; meta))
                     (list "M-/" "dabbrev-expand" (stroke #\/ meta))
                     (list "C-M-\\" "indent-lines"
                           (stroke #\\ (bitwise-ior control meta)))
                     (list "C-x TAB" "indent-rigidly"
                           control-x (special 11))))])
    (define label (car case))
    (define expected (cadr case))
    (define actual (apply binding-command bindings (cddr case)))
    (ensure (equal? actual expected) "~a must resolve to ~a" label expected))

  (define ksawery-source
    (file->string ksawery-host-boundary))
  (define ksawery-dispatcher-source
    (file->string ksawery-status-dispatcher))
  (for ([forbidden (in-list
                    '("case 'd': return .Ksawery_Discard"
                      "case 'r': return .Result_Refresh"
                      "case 'm': return .Ksawery_Mark"
                      "case 'M': return .Ksawery_Unmark"
                      "case 'C': return .Ksawery_Clear_Marks"))])
    (ensure (not (string-contains? ksawery-source forbidden))
            "forbidden Ksawery binding remains: ~a" forbidden))
  (for ([required (in-list
                   '("case 'g': return .Result_Refresh"
                     "case 'k': return .Ksawery_Discard"
                     "case '*': return .Ksawery_Mark"
                     "case '-': return .Ksawery_Unmark"
                     "case '0': return .Ksawery_Clear_Marks"))])
    (ensure (string-contains? ksawery-source required)
            "relocated Ksawery binding is missing: ~a" required))
  (for ([required (in-list
                   '("case 'd': return .Diff, true"
                     "case 'r': return .Rebase, true"
                     "case 'm': return .Merge, true"
                     "case 'M': return .Remote, true"
                     "case 'C': return .Clone, true"
                     "case 'i': return .Ignore, true"
                     "case 'I': return .Init, true"
                     "case 'o': return .Submodule, true"
                     "case 'O': return .Subtree, true"
                     "case 'T': return .Notes, true"
                     "case 'w': return .Apply_Patches, true"
                     "case 'W': return .Format_Patches, true"
                     "case '>': return .Sparse_Checkout, true"
                     "case 'z': return .Stash, true"
                     "case 'Z': return .Worktree, true"
                     "case 'l': return .Log, true"
                     "case 'B': return .Blame, true"
                     "case '?': return .Overview, true"))])
    (ensure (string-contains? ksawery-dispatcher-source required)
            "familiar Ksawery family is missing: ~a" required))
  (define darek-source (file->string darek-workflow))
  (define darek-pointer-source (file->string darek-pointer-workflow))
  (for ([required (in-list
                   '("darek_resource_sequence('t', 'h'), \"darek-toggle-hidden-files\""
                     "darek_resource_sequence('t', 'i'), \"darek-toggle-vcs-ignored\""
                     "darek_resource_sequence('t', 'a'), \"darek-toggle-file-watch\""
                     "darek_resource_sequence('t', 'g'), \"darek-toggle-vcs-decorations\""
                     "darek_resource_sequence('t', 'd'), \"darek-toggle-vcs-decorations\""
                     "command_context_prompt_scalar('s', {}), \"darek-select-sort\""
                     "command_context_prompt_scalar('!', {}), \"darek-shell-command\""
                     "command_context_prompt_scalar('!', {.Alt}), \"darek-shell-command-project\""
                     "command_context_prompt_scalar('m', {.Alt}), \"darek-bulk-actions\""
                     "darek_modified_special(.Enter, {.Alt}), \"darek-context-actions\""))])
    (ensure (string-contains? darek-source required)
            "familiar Darek presentation binding is missing: ~a" required))
  (ensure
   (string-contains? darek-pointer-source
                     "command_context_pointer_present_darek_actions")
   "secondary-pointer Darek context actions are missing")
  (define jan-maps
    (bundle:odra-language-support-bundle-keymaps factory-jan-language-bundle))
  (define jan-direct
    (for/first ([keymap (in-list jan-maps)]
                #:when (eq? (bundle:odra-language-keymap-id keymap) 'jan.direct))
      keymap))
  (define jan-modal
    (for/first ([keymap (in-list jan-maps)]
                #:when (eq? (bundle:odra-language-keymap-id keymap) 'jan.modal))
      keymap))
  (ensure jan-direct "Jan Direct bundle map is missing")
  (ensure jan-modal "Jan modal bundle map is missing")
  (define jan-language
    (car (bundle:odra-language-support-bundle-languages factory-jan-language-bundle)))
  (ensure (equal? (language:odra-language-suffixes jan-language) '(".org" ".jan"))
          "Jan Babel interaction must be identical for .org and .jan")
  (define jan-direct-bindings (bundle:odra-language-keymap-bindings jan-direct))
  (for ([expected
         (in-list
          '(("TAB" . jan-cycle)
            ("S-TAB" . jan-global-cycle)
            ("M-RET" . jan-insert-heading-after)
            ("M-LEFT" . jan-promote-heading)
            ("M-RIGHT" . jan-demote-heading)
            ("M-UP" . jan-context-meta-up)
            ("M-DOWN" . jan-context-meta-down)
            ("C-c C-c" . jan-context-action)
            ("C-c C-o" . jan-open-result)
            ("C-c C-v p" . jan-previous-block)
            ("C-c C-v n" . jan-next-block)
            ("C-c C-v e" . jan-execute)
            ("C-c C-v o" . jan-open-result)
            ("C-c C-v v" . jan-expand-source)
            ("C-c C-v u" . jan-goto-source-head)
            ("C-c C-v g" . jan-goto-named-source)
            ("C-c C-v r" . jan-goto-named-result)
            ("C-c C-v b" . jan-execute-buffer)
            ("C-c C-v s" . jan-execute-subtree)
            ("C-c C-v d" . jan-demarcate-source)
            ("C-c C-v t" . jan-tangle)
            ("C-c C-v f" . jan-tangle-file)
            ("C-c C-v c" . jan-check-source)
            ("C-c C-v j" . jan-insert-header-argument)
            ("C-c C-v l" . jan-load-in-session)
            ("C-c C-v i" . jan-library-load)
            ("C-c C-v I" . jan-view-source-info)
            ("C-c C-v z" . jan-switch-to-session-with-code)
            ("C-c C-v a" . jan-source-hash)
            ("C-c C-v h" . jan-babel-help)
            ("C-c C-v x" . jan-edit-source)
            ("C-c C-t" . jan-todo)
            ("C-c C-s" . jan-schedule)
            ("C-c C-d" . jan-deadline)
            ("C-c C-q" . jan-set-tags)
            ("C-c C-w" . jan-refile)
            ("C-c C-a" . jan-attach)
            ("C-c C-e" . jan-export)
            ("C-c |" . jan-create-table)
            ("C-c c" . jan-capture)
            ("C-c a" . jan-agenda)
            ("C-c l" . jan-store-link)))])
    (ensure (eq? (hash-ref jan-direct-bindings (car expected) #f) (cdr expected))
            "Jan binding ~a must resolve to ~a" (car expected) (cdr expected)))
  (define babel-rows
    (filter (lambda (row) (string=? (car row) "jan-babel")) rows))
  (ensure (= (count (lambda (row) (string=? (list-ref row 6) "exact")) babel-rows) 26)
          "Jan Babel must retain all 26 exact familiar bindings")
  (ensure (not (ormap (lambda (row) (string=? (list-ref row 6) "alternate")) babel-rows))
          "Jan Babel cannot retain alternate bindings")
  (ensure (not (ormap (lambda (row) (string=? (list-ref row 7) "reference-only")) babel-rows))
          "Jan Babel cannot retain reference-only behavior")
  (define roman-rows
    (filter (lambda (row) (string=? (car row) "roman")) rows))
  (ensure (andmap (lambda (row)
                    (and (string=? (list-ref row 6) "exact")
                         (string=? (list-ref row 7) "match")))
                  roman-rows)
          "Roman familiar bindings must retain exact command semantics")
  '(fixture direct-profile ksawery-status darek-presentation jan-document-map jan-babel-map roman-map))

(module+ test
  (check-equal?
   (check-interaction-compatibility default-fixture)
   '(fixture direct-profile ksawery-status darek-presentation jan-document-map jan-babel-map roman-map)))

(module+ main
  (define fixture-path "tests/interaction_compatibility/cases.tsv")
  (command-line
   #:program "check-interaction-compatibility"
   #:once-each
   [("--fixture") path "Compatibility fixture path"
                    (set! fixture-path path)])
  (define checked (check-interaction-compatibility fixture-path))
  (printf "interaction-compatibility: pass cases=~a applicable=~a excluded=~a checks=~a\n"
          expected-case-count
          expected-applicable-count
          expected-excluded-count
          (length checked)))
