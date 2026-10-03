<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Structured Editing Commands and Configuration

Jan publishes structured-editing, planning, computation, and output command
identities for `.org` and `.jan` documents. Both suffixes select the same
language, parser, command catalog, configuration, and behavior. Every command
resolves the active buffer, active view, exact Jan analysis generation, and
current point before it reads or changes state.

## Factory bindings

The Jan bundle activates its language-local map only while a `.org` or `.jan`
buffer is active. The bindings do not occupy the global Direct or modal maps.
Component and transient maps retain higher precedence when they are active.

The Direct profile provides these familiar document bindings:

| Family | Bindings |
| --- | --- |
| Visibility | `TAB` `jan-cycle`; `S-TAB` `jan-global-cycle` |
| Heading structure | `M-RET` `jan-insert-heading-after`; `M-Left` `jan-promote-heading`; `M-Right` `jan-demote-heading`; `M-Up` `jan-context-meta-up`; `M-Down` `jan-context-meta-down` |
| Heading navigation | `C-c C-n` `jan-next-heading`; `C-c C-p` `jan-previous-heading`; `C-c C-f` `jan-next-same-level-heading`; `C-c C-b` `jan-previous-same-level-heading`; `C-c C-u` `jan-parent-heading` |
| Planning | `C-c C-t` `jan-todo`; `C-c C-s` `jan-schedule`; `C-c C-d` `jan-deadline`; `C-c C-q` `jan-set-tags`; `C-c C-w` `jan-refile`; `C-c C-a` `jan-attach` |
| Context and export | `C-c C-c` `jan-context-action`; `C-c C-e` `jan-export` |
| Computable source | `C-c C-o` `jan-open-result`; `C-c C-v` followed by `p`, `n`, `e`, `o`, `v`, `u`, `g`, `r`, `b`, `s`, `d`, `t`, `f`, `c`, `j`, `l`, `i`, `I`, `z`, `a`, `h`, or `x` |
| Properties and clocks | `C-c C-x p` `jan-set-property`; `C-c C-x e` `jan-set-effort`; `C-c C-x C-i` `jan-clock-in`; `C-c C-x C-o` `jan-clock-out`; `C-c C-x C-q` `jan-clock-cancel`; `C-c C-x C-r` `jan-clock-report` |
| Archive | `C-c C-x C-a` `jan-archive-subtree`; `C-c C-x a` `jan-toggle-archive` |
| Tables and links | `C-c \|` `jan-create-table`; `C-c l` `jan-store-link` |
| Capture and agenda | `C-c c` `jan-capture`; `C-c a` `jan-agenda` |

The `C-c j` mnemonic aliases remain available for cycle, global cycle, heading
navigation, contextual action, TODO state, agenda, table recalculation, export,
and help at point. They resolve to the same command identities as the familiar
bindings. A conflicting duplicate sequence prevents map publication.

The modal Normal state provides `za`, `zA`, `]h`, `[h`, `ga`, `gT`, `gA`,
`gR`, `gE`, and `gH` for the corresponding Jan commands. Other Jan identities
remain available by name through `M-x` in the Direct profile or `:` in the
modal profile. Profile selection does not change Jan source meaning, target
resolution, transactions, or failures.

## Visibility and navigation

```text
jan-cycle
jan-toggle-drawer
jan-global-cycle
jan-show-overview
jan-show-contents
jan-show-all
jan-sparse-view
jan-next-heading
jan-previous-heading
jan-next-same-level-heading
jan-previous-same-level-heading
jan-parent-heading
jan-first-child-heading
jan-subtree-start
jan-subtree-end
jan-next-structural-element
jan-previous-structural-element
jan-next-list-item
jan-previous-list-item
jan-next-table-row
jan-previous-table-row
jan-next-table-cell
jan-previous-table-cell
jan-next-drawer
jan-previous-drawer
jan-next-block
jan-previous-block
jan-next-footnote
jan-previous-footnote
```

Visibility is view-local and never changes canonical source.
`jan-toggle-drawer` hides or reveals only the body of the complete drawer at
point. It preserves the opening and closing delimiters, other folds, document
revision, and undo history. A drawer hidden by another fold rejects instead of
revealing unrelated source. Navigation uses copied Jan targets and canonical
source positions. A missing destination reports no target rather than moving
approximately.

## Headings and subtrees

```text
jan-insert-heading-before
jan-insert-heading-after
jan-insert-heading-below
jan-split-heading
jan-promote-heading
jan-demote-heading
jan-move-subtree-up
jan-move-subtree-down
jan-clone-subtree
jan-kill-subtree
jan-sort-child-headings
jan-heading-to-list-item
jan-list-item-to-heading
```

## Lists, drawers, blocks, and regions

```text
jan-insert-list-item-before
jan-insert-list-item-after
jan-delete-list-item
jan-promote-list-item
jan-demote-list-item
jan-move-list-item-up
jan-move-list-item-down
jan-duplicate-list-item
jan-sort-list-items
jan-cycle-list-bullet
jan-repair-list-indentation
jan-insert-drawer
jan-insert-block
jan-select-structure
jan-move-structure-up
jan-move-structure-down
jan-delete-structure
```

## Tables

```text
jan-create-table
jan-align-table
jan-insert-table-row
jan-delete-table-row
jan-move-table-row-up
jan-move-table-row-down
jan-duplicate-table-row
jan-insert-table-column
jan-delete-table-column
jan-move-table-column-left
jan-move-table-column-right
jan-duplicate-table-column
jan-insert-table-separator
jan-delete-table-separator
jan-edit-table-cell
```

These commands operate on non-executing pipe tables. Formula evaluation remains
owned by Computable Documents and is unavailable in Stage 2.

## Footnotes and contextual authoring

```text
jan-visit-footnote
jan-create-footnote
jan-normalize-footnote
jan-renumber-footnotes
jan-move-footnote-up
jan-move-footnote-down
jan-complete
jan-expand-template
jan-indent
jan-context-action
jan-repeat
jan-present
jan-request-preview
jan-inspect-availability
```

Footnote operations are local to the current document. Completion and templates
insert source syntax only. Presentation and preview retain terminal source
fallback. Contextual action executes at a source block through the computation
boundary and otherwise resolves the current structured-document owner.

## Computable source blocks

The Direct profile uses the familiar `C-c C-v` prefix in both `.org` and
`.jan` buffers:

| Binding | Command | Operation |
| --- | --- | --- |
| `C-c C-v p` / `n` | `jan-previous-block` / `jan-next-block` | Navigate source blocks. |
| `C-c C-v e` | `jan-execute` | Execute at point through the configured adapter and authority policy. |
| `C-c C-v o` | `jan-open-result` | Visit the adjacent result owned by the current block. |
| `C-c C-v v` | `jan-expand-source` | Present adapter-independent expanded source. Unresolved noweb references require an admitted library. |
| `C-c C-v u` | `jan-goto-source-head` | Visit the current source block header. |
| `C-c C-v g` / `r` | `jan-goto-named-source` / `jan-goto-named-result` | Select a named source or result and visit it against the captured document revision. |
| `C-c C-v b` / `s` | `jan-execute-buffer` / `jan-execute-subtree` | Execute an explicit buffer or subtree scope. |
| `C-c C-v d` | `jan-demarcate-source` | Split at a line boundary while retaining the language and header arguments. |
| `C-c C-v t` / `f` | `jan-tangle` / `jan-tangle-file` | Stage checked tangle targets for the current scope or document. |
| `C-c C-v c` | `jan-check-source` | Report syntax validity, adapter availability, and executability. |
| `C-c C-v j` | `jan-insert-header-argument` | Insert the selected explicit `:key value` at the current source header. |
| `C-c C-v l` | `jan-load-in-session` | Load through the associated adapter session when available. |
| `C-c C-v i` | `jan-library-load` | Admit an explicit Jan source library. |
| `C-c C-v I` | `jan-view-source-info` | Show language, range, body size, result ownership, and effective hash. |
| `C-c C-v z` | `jan-switch-to-session-with-code` | Open the associated adapter session with current source when available. |
| `C-c C-v a` | `jan-source-hash` | Report Jan's stable effective-source hash. |
| `C-c C-v h` | `jan-babel-help` | Present the active binding family. |
| `C-c C-v x` | `jan-edit-source` | Open the focused source editor. |

`C-c C-c` executes when point is in a source block. `C-c C-o` opens its
adjacent result. `M-Up` and `M-Down` load or display the associated session
inside a source block; elsewhere the same keys retain Jan subtree movement.

Adapter-dependent commands remain registered when no adapter is configured.
Their feedback distinguishes missing adapters, malformed source, rejected
authority, cancellation, and failed execution. A rejected operation preserves
the document.

## Configuration

Personal configuration may export one immutable
`odra-jan-editing-configuration` value from `odra/jan`:

```racket
#lang racket/base

(require odra/jan)

(provide odra-jan-editing-configuration)

(define odra-jan-editing-configuration
  (jan-editing-configuration
   #:startup-visibility 'contents
   #:presentation
   (jan-presentation
    #:compose-markup? #t
    #:prettify-entities? #t
    #:visual-indent-width 2
    #:number-headings? #f
    #:hard-indent-width 2)
   #:templates
   (list (jan-template 'note 'block
                       "#+begin_note\n\n#+end_note\n"))
   #:completion-sources
   (list (jan-completion-source 'team-states 'task-state
                                '("READY" "DONE")))))
```

Configuration replacement is atomic. Invalid, stale, conflicting, limited, or
allocation-failed values preserve the prior confirmed generation and factory
fallback. Configuration can add source templates and completion values, but it
cannot add syntax, commands, bindings, future-stage semantics, executable
callbacks, or resource authority.

## Transactions, failures, and inspection

An admitted source mutation becomes one checked Jan rewrite plan, one editor
transaction, and one undo unit. The application rechecks revision and owner
generations before commit. Stale analysis, malformed source, incompatible
targets, limits, cancellation, allocation faults, and unavailable capabilities
produce a diagnostic and no partial source change.

Use `jan-inspect-availability` for 13 operational and six explicitly
unavailable optional records, with no remaining future-stage records. Use
`jan-language-status` for language, provider, analysis, resource, and
availability state.

## Validation boundary

`make jan-structured-editing-focused-test` validates the independent models and
static packages. `make jan-structured-editing-acceptance` builds the linked
application and verifies `.org` and `.jan` parity, direct and modal invocation,
visibility, navigation, representative structural families, terminal fallback,
undo, redo, save, checked rejection, and clean exit through a PTY.
