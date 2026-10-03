<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Completion Reference

Language completion is a provider-independent, revision-bound interaction.
The factory provider obtains candidates from the active language service, then
Odra copies and normalizes them before filtering, presenting, or applying any
edit.

## Availability

Completion is available when the active document has a selected language,
belongs to an eligible trusted Project, has a synchronized language-service
binding at the current revision, and the server negotiated completion support.
An unsupported, missing, failed, or restarting service leaves ordinary editing
available.

`complete-at-point` requests candidates explicitly. Server-advertised trigger
characters start completion automatically. Identifier input may also start it
after the configured minimum prefix when identifier invocation is enabled.

## Commands and bindings

| Command | Factory binding | Behavior |
| --- | --- | --- |
| `complete-at-point` | `C-M-i` | Request completion at the cursor. |
| `completion-next` | `C-n`, Down | Select the next visible candidate. |
| `completion-previous` | `C-p`, Up | Select the previous visible candidate. |
| `completion-first` | `M-<` | Select the first visible candidate. |
| `completion-last` | `M->` | Select the last visible candidate. |
| `completion-accept` | Enter, Tab | Apply the selected candidate. |
| `completion-cancel` | `M-x` | Cancel through the named command. |
| `completion-inspect` | `M-x` | Inspect the selected candidate. |
| `completion-show-documentation` | `M-?` | Toggle available detail or documentation. |
| `describe-completion-state` | `M-x` | Report session state, counts, and selection. |

`C-g` remains the protected cancellation binding while completion is active.
Unmatched text input falls through to the source buffer and refines or replaces
the current request. Moving the source cursor outside the compatible context,
switching views, or invalidating the document authority dismisses the session.

## Candidate presentation

The selected generation appears in a compact interactive candidate popup
anchored to the source cursor. The source text view retains focus. Candidate
kinds, annotations, full-row selection, the single border, and unavailable
state use semantic roles from the active theme. The terminal renderer lowers
candidate-kind roles through its enriched icon catalog and uses the existing
text labels when `ODRA_ICON_PROFILE=portable`. Narrow or unsupported terminal
geometry uses the declared shared fallback instead of changing completion
semantics.

Complete result batches are filtered locally while their request remains
compatible. Incomplete batches request a newer provider generation after input
changes. Selection is stable by candidate identity where the new generation
still contains the selected item.

## Acceptance

Acceptance validates the exact controller, session, request, provider,
document, revision, view, batch, projection, and candidate generations. It
applies the primary edit and all admitted non-overlapping additional edits as
one transaction and one history unit. Undo and redo therefore reverse or
restore the complete candidate effect together.

Read-only documents, stale authority, invalid ranges, overlapping edits,
resource overflow, and transaction failure publish no partial text.

## Configuration

Personal completion configuration is one complete value exported from
`init.rkt`:

```racket
#lang racket/base

(require odra/completion)

(provide odra-completion-configuration)

(define odra-completion-configuration
  (completion-configuration
   #:enabled? #t
   #:explicit? #t
   #:identifier? #f
   #:trigger-character? #t
   #:minimum-prefix 2
   #:case-sensitive-prefix? #t
   #:case-insensitive-prefix? #t
   #:subsequence? #t))
```

The factory role names are `language-service`, `factory-completion`, and
`interactive-candidate`. Selected bounds are 128 candidates, 8 additional
edits per candidate, 256 bytes per short text field, 1,024 detail bytes, 512
resolve bytes, 16 role implementations, 1,024 role replacements, and 1,024
request replacements. Invalid complete configuration preserves the last valid
generation.

The factory starts automatically on server-advertised trigger characters.
Identifier-prefix invocation is disabled by default and remains available as
an opt-in policy.

Run `M-x reload-personal-commands` to publish one checked replacement
generation. Reload cancels any active completion interaction before the new
configuration becomes visible.

## Inspection and recovery

Use `M-x describe-completion-state` for the active session and
`M-x describe-language-service` for provider, process, capability, document,
and failure state. `Completion Invalid` means no completion session is active.
`Completion unavailable for current document` means the current document has
no eligible synchronized provider.

A timeout, process failure, service restart, provider replacement, document
change, or explicit cancellation retires the matching request and removes its
transient input map. Late responses cannot reopen it.
