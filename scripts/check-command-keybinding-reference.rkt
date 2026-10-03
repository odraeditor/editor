#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/cmdline
         racket/file
         racket/list
         racket/match
         racket/path
         racket/runtime-path
         racket/set
         racket/string
         "../src/command/builtins.rkt"
         "../src/command/catalog.rkt"
         "../src/command/keymap-model.rkt"
         (only-in "../src/command/maksym.rkt" maksym-command-names))

(define-runtime-path repository-root "..")
(define output-directory-relative-path
  "docs/reference/command-and-keybinding-reference")
(define landing-relative-path
  (string-append output-directory-relative-path "/index.md"))
(define alphabetical-relative-path
  (string-append output-directory-relative-path "/alphabetical-index.md"))
(define official-relative-path
  "docs/reference/command-and-keybinding-reference/official-packages.rktd")
(define contextual-command-relative-path
  "docs/reference/command-and-keybinding-reference/contextual-commands.rktd")
(define contextual-binding-relative-paths
  '("docs/reference/maksym/index.md"
    "docs/reference/darek/index.md"))

(struct command (module name description bindings) #:transparent)

(define source-specifications
  (list
   (list "src/command/native.odin"
         '(native_definition native_text_argument_definition
           native_optional_text_definition language_document_command_definition)
         366)
   (list "src/command/jan_structured_commands.odin"
         '(jan_view_definition jan_edit_definition)
         88)
   (list "src/command/jan_planning_commands.odin"
         '(jan_planning_view_definition jan_planning_lifecycle_definition
           jan_planning_global_definition jan_planning_edit_definition)
         71)
   (list "src/command/jan_computation_commands.odin"
         '(jan_computation_view_definition jan_computation_lifecycle_definition
           jan_computation_global_definition jan_computation_global_edit_definition
           jan_computation_edit_definition)
         40)
   (list "src/command/jan_output_commands.odin"
         '(jan_output_view_definition jan_output_lifecycle_definition
           jan_output_global_definition jan_output_edit_definition)
         31)
   (list "src/command/language_interaction_commands.odin"
         '(language_document_command_definition language_factory_command_definition)
         21)
   (list "src/command/package_catalog_commands.odin"
         '(package_catalog_command_definition)
         22)))

(define special-key-names
  (hash 2 "Left" 3 "Right" 4 "Up" 5 "Down" 6 "Home" 7 "End"
        8 "Backspace" 9 "Delete" 10 "RET" 11 "TAB" 12 "Insert"
        13 "Prior" 14 "Next" 15 "ESC" 16 "F4"))

(define (repository-path relative)
  (build-path repository-root relative))

(define (command-name? value)
  (and (string? value)
       (regexp-match? #px"^[a-z][a-z0-9-]*$" value)))

(define (call-end text open-position)
  (let loop ([position (add1 open-position)] [depth 1] [quoted? #f]
             [escaped? #f])
    (cond
      [(>= position (string-length text)) #f]
      [else
       (define character (string-ref text position))
       (cond
         [quoted?
          (cond
            [escaped? (loop (add1 position) depth #t #f)]
            [(char=? character #\\) (loop (add1 position) depth #t #t)]
            [(char=? character #\") (loop (add1 position) depth #f #f)]
            [else (loop (add1 position) depth #t #f)])]
         [(char=? character #\") (loop (add1 position) depth #t #f)]
         [(char=? character #\() (loop (add1 position) (add1 depth) #f #f)]
         [(char=? character #\))
          (if (= depth 1)
              position
              (loop (add1 position) (sub1 depth) #f #f))]
         [else (loop (add1 position) depth #f #f)])])))

(define (call-strings text start end)
  (let loop ([position start] [values '()])
    (cond
      [(>= position end) (reverse values)]
      [(char=? (string-ref text position) #\")
       (define literal-end
         (let find ([candidate (add1 position)] [escaped? #f])
           (cond
             [(>= candidate end) #f]
             [escaped? (find (add1 candidate) #f)]
             [(char=? (string-ref text candidate) #\\)
              (find (add1 candidate) #t)]
             [(char=? (string-ref text candidate) #\") candidate]
             [else (find (add1 candidate) #f)])))
       (unless literal-end
         (error 'command-reference "unterminated string literal"))
       (define literal (substring text position (add1 literal-end)))
       (loop (add1 literal-end)
             (cons (read (open-input-string literal)) values))]
      [else (loop (add1 position) values)])))

(define (constructor-commands relative-path constructors)
  (define text (file->string (repository-path relative-path)))
  (for*/list ([constructor (in-list constructors)]
              [match-position
               (in-list
                (regexp-match-positions*
                 (pregexp
                  (format "\\b~a[[:space:]]*\\(" (regexp-quote (symbol->string constructor))))
                 text))]
              #:do [(define open-position
                      (sub1 (cdr match-position)))
                    (define end (call-end text open-position))]
              #:when end
              #:do [(define strings
                      (call-strings text (add1 open-position) end))
                    (define name
                      (for/first ([value (in-list strings)]
                                  #:when (command-name? value))
                        value))]
              #:when (and name (>= (length strings) 2)))
    (command (module-for-command name)
             name
             (last strings)
             '())))

(define (module-for-command name)
  (cond
    [(string-prefix? name "maksym-") "Maksym"]
    [(string-prefix? name "darek-") "Darek"]
    [(string-prefix? name "ksawery-") "Ksawery"]
    [(string-prefix? name "jan-") "Jan"]
    [else "Core"]))

(define (racket-commands)
  (for/list ([definition
              (in-list
               (odra-command-catalog-definitions (factory-command-catalog)))])
    (define name (odra-command-definition-name definition))
    (command (module-for-command name)
             name
             (odra-command-definition-description definition)
             '())))

(define (official-commands)
  (read-command-data official-relative-path))

(define (read-command-data relative-path)
  (call-with-input-file (repository-path relative-path)
    (lambda (input)
      (for/list ([entry (in-list (read input))])
        (match entry
          [(list module name description bindings)
           (unless (and (string? module) (command-name? name)
                        (string? description) (list? bindings))
             (error 'command-reference "invalid command data entry: ~s" entry))
           (command module name description bindings)]
          [_ (error 'command-reference "invalid command data entry: ~s" entry)])))))

(define (contextual-commands)
  (define commands (read-command-data contextual-command-relative-path))
  (define maksym-names (map symbol->string maksym-command-names))
  (define module-source
    (file->string (repository-path "src/maksym_module/module.odin")))
  (for ([item (in-list commands)])
    (unless (and (string=? (command-module item) "Maksym")
                 (member (command-name item) maksym-names)
                 (string-contains? module-source
                                   (format "\"~a\"" (command-name item))))
      (error 'command-reference
             "contextual command is absent from the Maksym command contract: ~a"
             (command-name item))))
  commands)

(define (ksawery-contextual-commands)
  (define parsed
    (constructor-commands
     "src/command/contextual.odin"
     '(interaction_action_definition interaction_text_definition)))
  (unless (= (length parsed) 98)
    (error 'command-reference
           "src/command/contextual.odin yielded ~a commands; expected 98"
           (length parsed)))
  (define commands
    (filter (lambda (item)
              (string-prefix? (command-name item) "ksawery-"))
            parsed))
  (unless (= (length commands) 61)
    (error 'command-reference
           "Ksawery contextual catalog yielded ~a commands; expected 61"
           (length commands)))
  commands)

(define (scalar-name scalar)
  (define value (integer->char scalar))
  (case value
    [(#\space) "SPC"]
    [else (string value)]))

(define (stroke-name stroke)
  (define modifiers (odra-key-stroke-modifiers stroke))
  (define base
    (if (= (odra-key-stroke-kind stroke) 1)
        (scalar-name (odra-key-stroke-scalar stroke))
        (hash-ref special-key-names (odra-key-stroke-kind stroke))))
  (string-append
   (if (bitwise-bit-set? modifiers 0) "C-" "")
   (if (bitwise-bit-set? modifiers 1) "M-" "")
   (if (bitwise-bit-set? modifiers 2) "S-" "")
   (if (bitwise-bit-set? modifiers 3) "Super-" "")
   (if (bitwise-bit-set? modifiers 4) "Hyper-" "")
   base))

(define (sequence-name sequence)
  (string-join
   (for/list ([stroke (in-list (odra-key-sequence-strokes sequence))])
     (stroke-name stroke))
   " "))

(define (profile-binding-records label profile)
  (for*/list ([keymap (in-list (odra-interaction-profile-maps profile))]
              [binding (in-list (odra-keymap-bindings keymap))]
              #:when (memq (odra-binding-operation binding) '(bind replace))
              #:when (positive? (string-length (odra-binding-command binding))))
    (list (odra-binding-command binding)
          label
          (sequence-name (odra-binding-sequence binding)))))

(define (contextual-binding-records relative-path)
  (define lines (file->lines (repository-path relative-path)))
  (let loop ([remaining lines] [inside-table? #f] [records '()])
    (cond
      [(null? remaining) (reverse records)]
      [else
       (define line (car remaining))
       (cond
         [(string=? line "| Command | Binding | Behavior |")
          (loop (cdr remaining) #t records)]
         [(and inside-table?
               (regexp-match #px"^\\| (.*?) \\| (.*?) \\| .* \\|$" line))
          =>
          (lambda (matched)
            (define command-names
              (regexp-match* #px"`([a-z][a-z0-9-]+)`" (second matched)
                             #:match-select second))
            (define binding-cell (third matched))
            (define bindings
              (if (string=? binding-cell "none")
                  '()
                  (map string-trim
                       (string-split (string-replace binding-cell "`" "") ","))))
            (define new-records
              (if (null? command-names)
                  '()
                  (for/list ([binding (in-list bindings)]
                             [index (in-naturals)])
                    (list (list-ref command-names
                                    (modulo index (length command-names)))
                          "Contextual"
                          binding))))
            (loop (cdr remaining) #t (append (reverse new-records) records)))]
         [inside-table?
          (loop (cdr remaining) (string-prefix? line "| ---") records)]
         [else (loop (cdr remaining) #f records)])])))

(define (ksawery-module-binding-records)
  (define lines
    (file->lines (repository-path "src/ksawery_module/module.odin")))
  (define records
    (for/list ([line (in-list lines)]
               #:do [(define matched
                       (regexp-match
                        #px"^\\s*case \"(ksawery-[a-z0-9-]+)\": key = '(.)'\\s*$"
                        line))]
               #:when matched)
      (list (second matched) "Contextual" (third matched))))
  (unless (= (length records) 56)
    (error 'command-reference
           "Ksawery module keymap yielded ~a bindings; expected 56"
           (length records)))
  records)

(define ksawery-dispatcher-binding-records
  '(("ksawery-stashes" "Contextual" "z l")
    ("ksawery-stashes" "Contextual" "z z")
    ("ksawery-worktrees" "Contextual" "Z Z")
    ("ksawery-worktrees" "Contextual" "Z l")
    ("ksawery-reflog" "Contextual" "l r")
    ("ksawery-blame" "Contextual" "B B")
    ("ksawery-blame" "Contextual" "B b")))

(define (factory-bindings)
  (remove-duplicates
   (append
    (profile-binding-records "Direct" (factory-interaction-profile-definition))
    (profile-binding-records "Modal" (factory-modal-interaction-profile-definition))
    (append*
     (for/list ([relative-path (in-list contextual-binding-relative-paths)])
       (contextual-binding-records relative-path)))
    (ksawery-module-binding-records)
    ksawery-dispatcher-binding-records)
   equal?))

(define (attach-bindings commands)
  (define by-name
    (for/fold ([result (hash)]) ([record (in-list (factory-bindings))])
      (hash-update result (first record)
                   (lambda (current) (cons (rest record) current)) '())))
  (define command-names (list->set (map command-name commands)))
  (define unresolved
    (sort
     (remove-duplicates
      (for/list ([record (in-list (factory-bindings))]
                 #:unless (set-member? command-names (first record)))
        (first record)))
     string<?))
  (unless (null? unresolved)
    (error 'command-reference "factory bindings lack command entries: ~a"
           (string-join unresolved ", ")))
  (for/list ([item (in-list commands)])
    (if (pair? (command-bindings item))
        item
        (struct-copy command item
                     [bindings
                      (sort (remove-duplicates
                             (hash-ref by-name (command-name item) '()) equal?)
                            string<? #:key (lambda (entry)
                                             (string-append (first entry) "\0" (second entry))))]))))

(define (ensure-unique commands)
  (define names (map command-name commands))
  (define duplicates
    (for/list ([name (in-list (remove-duplicates names))]
               #:when (> (count (lambda (candidate) (string=? name candidate)) names) 1))
      name))
  (unless (null? duplicates)
    (error 'command-reference "duplicate command identities: ~a"
           (string-join duplicates ", ")))
  commands)

(define (command-family item)
  (define module (command-module item))
  (define name (command-name item))
  (cond
    [(string=? module "Roman")
     (cond [(regexp-match? #rx"^roman-(index|space|diagnose)" name) "Index and storage"]
           [(regexp-match? #rx"^roman-(relations|graph)" name) "Relations and graph"]
           [(regexp-match? #rx"^roman-(alias|tag|ref-)" name) "Metadata and references"]
           [(regexp-match? #rx"^roman-(capture|daily)" name) "Capture and daily knowledge"]
           [else "Nodes and links"])]
    [(string=? module "Jan")
     (cond [(regexp-match? #rx"^jan-(cycle|toggle-drawer|show|sparse|next|previous|parent|first-child|subtree)" name) "Visibility and navigation"]
           [(regexp-match? #rx"^jan-(insert-heading|split-heading|promote-heading|demote-heading|move-subtree|clone-subtree|kill-subtree|sort-child|heading-to|list-item-to)" name) "Headings and subtrees"]
           [(regexp-match? #rx"^jan-.*(list|drawer|structure)" name) "Lists, drawers, and structures"]
           [(regexp-match? #rx"^jan-.*table" name) "Tables and formulas"]
           [(regexp-match? #rx"^jan-(todo|schedule|deadline|planning|agenda|clock|effort|priority|set-tags|set-property|refile|archive)" name) "Planning and agenda"]
           [(regexp-match? #rx"^jan-(capture|feed|attach)" name) "Capture and intake"]
           [(regexp-match? #rx"^jan-(execute|open-result|expand-source|goto-.*source|goto-.*result|tangle|check-source|insert-header|load-in-session|library|view-source|switch-to-session|source-hash|babel|edit-source|session|cache|result)" name) "Computation and source blocks"]
           [(regexp-match? #rx"^jan-(export|publish|output|citation|bibliography)" name) "Export and publishing"]
           [(regexp-match? #rx"^jan-(inspect|lint|language|diagnose|present|preview|request-preview)" name) "Inspection and presentation"]
           [else "Editing and metadata"])]
    [(string=? module "Maksym")
     (cond [(regexp-match? #rx"(open|visit|parent|next|previous)" name) "Opening and navigation"]
           [(regexp-match? #rx"(mark|unmark|selection)" name) "Target sets"]
           [(regexp-match? #rx"(rename|copy|move|delete|apply|create)" name) "Filesystem changes"]
           [else "Listing and presentation"])]
    [(string=? module "Darek")
     (cond [(regexp-match? #rx"(toggle|focus|next|previous|parent|child|expand|collapse)" name) "Panel and navigation"]
           [(regexp-match? #rx"(create|rename|copy|move|delete|remove)" name) "Resource operations"]
           [else "Opening and presentation"])]
    [(string=? module "Ksawery")
     (cond [(regexp-match? #rx"(stage|unstage|discard|mark|unmark)" name) "Status and staging"]
           [(regexp-match? #rx"(commit|amend|fixup|history|reflog|blame)" name) "History and commits"]
           [(regexp-match? #rx"(branch|tag|merge|rebase|cherry|revert|bisect)" name) "Branches and sequences"]
           [(regexp-match? #rx"(fetch|push|remote|clone|submodule|subtree|stash|worktree)" name) "Remotes and repositories"]
           [else "Inspection and operations"])]
    [(string=? module "Official packages") "Canary packages"]
    [else
     (cond [(regexp-match? #rx"^(help|apropos|describe|where-is|info|open-tutorial|execute-extended)" name) "Help and discovery"]
           [(regexp-match? #rx"^(cursor|goto|scroll|recenter|next-location|previous-location|save-location|visit-location|list-location)" name) "Movement and locations"]
           [(regexp-match? #rx"^(select|set-mark|pop-selection|narrow|widen)" name) "Selection and narrowing"]
           [(regexp-match? #rx"^(search|isearch|query-replace|occur|highlight|unhighlight)" name) "Search and replacement"]
           [(regexp-match? #rx"^(find|write-file|save|insert-file|buffer|switch-to-buffer|next-buffer|previous-buffer|kill-buffer|list-buffers)" name) "Files and buffers"]
           [(regexp-match? #rx"^(pane|split|delete-other|other-pane|balance|store-layout|restore-layout)" name) "Panes and layouts"]
           [(regexp-match? #rx"^(project|workspace)" name) "Projects and workspaces"]
           [(regexp-match? #rx"^(terminal|shell|async-shell|compile|recompile)" name) "Terminals and processes"]
           [(regexp-match? #rx"^(language|completion|complete-at-point|diagnostic|structural|syntax)" name) "Language intelligence"]
           [(regexp-match? #rx"^package" name) "Packages"]
           [(regexp-match? #rx"^(theme|gutter|status-bar)" name) "Interface"]
           [(regexp-match? #rx"^(delete|insert|kill|copy|yank|undo|redo|uppercase|lowercase|capitalize|transpose|indent|toggle-overwrite|store-|increment-number)" name) "Editing and text transfer"]
           [else "Editor lifecycle and tools"])]))

(define module-order
  (hash "Core" 0 "Maksym" 1 "Darek" 2 "Ksawery" 3 "Jan" 4
        "Roman" 5 "Official packages" 6))

(define module-file-names
  (hash "Core" "core.md"
        "Maksym" "maksym.md"
        "Darek" "darek.md"
        "Ksawery" "ksawery.md"
        "Jan" "jan.md"
        "Roman" "roman.md"
        "Official packages" "official-packages.md"))

(define module-links
  (hash "Core" "../editor-core/index.md"
        "Maksym" "../maksym/index.md"
        "Darek" "../darek/index.md"
        "Ksawery" "../ksawery/index.md"
        "Jan" "../jan-structured-editing-commands/index.md"
        "Roman" "../roman/index.md"
        "Official packages" "../installable-packages/index.md"))

(define module-family-orders
  (hash
   "Core"
   '("Help and discovery" "Movement and locations" "Selection and narrowing"
     "Editing and text transfer" "Files and buffers" "Panes and layouts"
     "Search and replacement" "Projects and workspaces" "Language intelligence"
     "Terminals and processes" "Packages" "Interface" "Editor lifecycle and tools")
   "Maksym"
   '("Opening and navigation" "Listing and presentation" "Target sets"
     "Filesystem changes")
   "Darek"
   '("Panel and navigation" "Opening and presentation" "Resource operations")
   "Ksawery"
   '("Status and staging" "History and commits" "Branches and sequences"
     "Remotes and repositories" "Inspection and operations")
   "Jan"
   '("Visibility and navigation" "Headings and subtrees"
     "Lists, drawers, and structures" "Tables and formulas"
     "Editing and metadata" "Planning and agenda" "Capture and intake"
     "Computation and source blocks" "Export and publishing"
     "Inspection and presentation")
   "Roman"
   '("Index and storage" "Nodes and links" "Relations and graph"
     "Metadata and references" "Capture and daily knowledge")
   "Official packages"
   '("Canary packages")))

(define (family-rank module family)
  (define order (hash-ref module-family-orders module '()))
  (or (index-of order family) (length order)))

(define (markdown-text value)
  (string-replace
   (string-replace
    (string-replace
     (string-replace value "&" "&amp;")
     "<" "&lt;")
    ">" "&gt;")
   "|" "\\|"))

(define (binding-text item)
  (define records (command-bindings item))
  (if (null? records)
      "M-x only"
      (let* ([sequences-for
              (lambda (label)
                (sort (remove-duplicates
                       (for/list ([entry (in-list records)]
                                  #:when (string=? (first entry) label))
                         (second entry))
                       string=?)
                      string<?))]
             [direct (sequences-for "Direct")]
             [modal (sequences-for "Modal")]
             [contextual (sequences-for "Contextual")]
             [render-sequences
              (lambda (label sequences)
                (format "~a: ~a" label
                        (string-join
                         (map (lambda (sequence)
                                (format "`~a`" (markdown-text sequence)))
                              sequences)
                         ", ")))])
        (cond
          [(and (pair? direct) (equal? direct modal))
           (string-join
            (filter values
                    (list (render-sequences "Direct/Modal" direct)
                          (and (pair? contextual)
                               (render-sequences "Contextual" contextual))))
            "; ")]
          [else
           (string-join
            (filter values
                    (list (and (pair? direct)
                               (render-sequences "Direct" direct))
                          (and (pair? modal)
                               (render-sequences "Modal" modal))
                          (and (pair? contextual)
                               (render-sequences "Contextual" contextual))))
            "; ")]))))

(define (ordered-modules commands)
  (sort (remove-duplicates (map command-module commands))
        < #:key (lambda (name) (hash-ref module-order name 99))))

(define (render-page title render-body)
  (define output (open-output-string))
  (define (line [value ""]) (displayln value output))
  (line "<!--")
  (line "SPDX-FileCopyrightText: 2026 Adrian PK")
  (line "SPDX-License-Identifier: GPL-3.0-only")
  (line)
  (line "This file is part of Odra. See COPYING for license terms.")
  (line "-->")
  (line)
  (line (format "# ~a" title))
  (line)
  (render-body line)
  (get-output-string output))

(define (render-command-table line commands command-cell)
  (line "| Command | Default binding | Description |")
  (line "| --- | --- | --- |")
  (for ([item (in-list commands)])
    (line
     (format "| ~a | ~a | ~a |"
             (command-cell item)
             (binding-text item)
             (markdown-text (command-description item))))))

(define (render-landing commands)
  (render-page
   "Command and Keybinding Reference"
   (lambda (line)
  (line "This appendix lists the public commands shipped by Odra and its baseline")
  (line "official packages. It records factory bindings; `M-x only` means that a")
  (line "command is available by name but has no factory key sequence.")
  (line)
  (line "Personal configuration and installed packages can change the active catalog.")
  (line "Use `describe-bindings`, `describe-key`, and `where-is` for the current")
  (line "session. Module references remain authoritative for complete behavior and")
  (line "failure semantics.")
  (line)
  (line "## Browse by module")
  (line)
  (for ([module (in-list (ordered-modules commands))])
    (define module-count
      (count (lambda (item) (string=? module (command-module item))) commands))
    (line (format "- [~a](~a) -- ~a ~a."
                  module
                  (hash-ref module-file-names module)
                  module-count
                  (if (= module-count 1) "command" "commands"))))
  (line)
  (line "## Browse alphabetically")
  (line)
  (line "The [Alphabetical Index](alphabetical-index.md) maps every command name")
  (line "to its primary entry in the owning module page."))))

(define (render-alphabetical-index commands)
  (render-page
   "Alphabetical Command Index"
   (lambda (line)
     (line "Every command links to its primary entry in the owning module page.")
     (line)
     (line "| Command | Module |")
     (line "| --- | --- |")
     (for ([item (in-list (sort commands string<? #:key command-name))])
       (line
        (format "| [`~a`](~a#command-~a) | ~a |"
                (command-name item)
                (hash-ref module-file-names (command-module item))
                (command-name item)
                (command-module item)))))))

(define (render-module-reference module commands)
  (render-page
   (format "~a Commands" module)
   (lambda (line)
    (line "[Command and Keybinding Reference](index.md) | [Alphabetical Index](alphabetical-index.md)")
    (line)
    (line (format "Detailed behavior: [~a Reference](~a)."
                  module (hash-ref module-links module)))
    (line)
    (define module-commands
      (filter (lambda (item) (string=? module (command-module item))) commands))
    (define families
      (sort (remove-duplicates (map command-family module-commands))
            < #:key (lambda (family) (family-rank module family))))
    (for ([family (in-list families)])
      (line)
      (line (format "## ~a" family))
      (line)
      (render-command-table
       line
       (sort (filter (lambda (candidate)
                       (string=? family (command-family candidate)))
                     module-commands)
             string<? #:key command-name)
       (lambda (item)
         (format "<a id=\"command-~a\"></a>`~a`"
                 (command-name item) (command-name item))))))))

(define (render-references commands)
  (append
   (list (cons landing-relative-path (render-landing commands))
         (cons alphabetical-relative-path (render-alphabetical-index commands)))
   (for/list ([module (in-list (ordered-modules commands))])
     (cons (string-append output-directory-relative-path "/"
                          (hash-ref module-file-names module))
           (render-module-reference module commands)))))

(define (all-commands)
  (define parsed
    (append*
     (for/list ([specification (in-list source-specifications)])
       (define relative-path (first specification))
       (define parsed-source
         (constructor-commands relative-path (second specification)))
       (define expected-count (third specification))
       (unless (= (length parsed-source) expected-count)
         (error 'command-reference
                "~a yielded ~a commands; expected ~a"
                relative-path (length parsed-source) expected-count))
       parsed-source)))
  (define native-with-literal
    (cons
     (command "Core" "keyboard-quit"
              "Cancel pending input or deactivate the active region." '())
     parsed))
  (attach-bindings
   (ensure-unique
    (append native-with-literal
            (racket-commands)
            (contextual-commands)
            (ksawery-contextual-commands)
            (official-commands)))))

(module+ test
  (require rackunit)

  (define commands (all-commands))
  (check-equal? (length commands) 756)
  (define by-name
    (for/hash ([item (in-list commands)])
      (values (command-name item) item)))
  (check-equal?
   (command-bindings (hash-ref by-name "darek-next-node"))
   '(("Contextual" "Down") ("Contextual" "n")))
  (check-equal?
   (command-bindings (hash-ref by-name "maksym-mark-entry"))
   '(("Contextual" "m")))
  (check-equal?
   (command-bindings (hash-ref by-name "roman-node-find"))
   '(("Direct" "C-c n f") ("Modal" "C-c n f")))
  (check-equal?
   (command-bindings (hash-ref by-name "ksawery-stage"))
   '(("Contextual" "s")))
  (check-equal?
   (command-bindings (hash-ref by-name "ksawery-stashes"))
   '(("Contextual" "z l") ("Contextual" "z z")))
  (define references (render-references commands))
  (check-equal? (length references) 9)
  (check-true
   (string-contains? (cdr (second references)) "| Command | Module |"))
  (for ([reference (in-list (cddr references))])
    (check-false
     (string-contains? (cdr reference) "| Command | Module |"))
    (check-true
     (string-contains?
      (cdr reference)
      "| Command | Default binding | Description |"))))

(define write? #f)
(command-line
 #:program "check-command-keybinding-reference.rkt"
 #:once-each
 [("--write") "Regenerate the command reference." (set! write? #t)])

(define commands (all-commands))
(define references (render-references commands))

(cond
  [write?
   (for ([reference (in-list references)])
     (define output-path (repository-path (car reference)))
     (make-parent-directory* output-path)
     (call-with-output-file output-path
       (lambda (output) (display (cdr reference) output))
       #:exists 'truncate/replace)
     (printf "command-reference: wrote ~a\n" (car reference)))]
  [else
   (define failures
     (for/list ([reference (in-list references)]
                #:do [(define output-path (repository-path (car reference)))]
                #:unless (and (file-exists? output-path)
                              (string=? (cdr reference)
                                        (file->string output-path))))
       (car reference)))
   (unless (null? failures)
     (for ([relative-path (in-list failures)])
       (eprintf "command-reference: missing or stale ~a\n" relative-path))
     (eprintf "command-reference: run with --write\n")
     (exit 1))
   (printf "command-reference: current commands=~a pages=~a\n"
           (length commands) (length references))])
