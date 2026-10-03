<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Contextual Authoring Reference

Jan contextual authoring is the Stage 2 package boundary for bounded editing
configuration, source-syntax completion, structure templates, hard
indentation, contextual action, speed-key admission, and semantic repetition.
It consumes exact Jan Document Language analysis without adding parser syntax,
executing code, or acquiring file, process, network, or external-resource
authority.

## Editing configuration

`src/command/jan.rkt` exposes immutable Racket values for startup visibility,
rich presentation, hard indentation, structure templates, completion sources,
and selection among already admitted preview adapters. A configuration admits
at most 256 templates, 256 completion sources, and 1 MiB of copied template and
provider data.

Personal configuration loads the API as `odra/jan` and exports one complete
value:

```racket
#lang racket/base

(require odra/jan)

(provide odra-jan-editing-configuration)

(define odra-jan-editing-configuration
  (jan-editing-configuration
   #:startup-visibility 'contents
   #:templates
   (list (jan-template 'note 'block
                       "#+begin_note\n\n#+end_note\n"))
   #:completion-sources
   (list (jan-completion-source 'team-states 'task-state
                                '("READY" "DONE")))))
```

`Editing_Configuration` is the native owner. It validates the complete
candidate, copies every retained string, and then replaces the confirmed
generation atomically. Invalid, conflicting, stale, over-limit, or
allocation-failed candidates leave the prior generation unchanged. The owner
starts with factory presentation, `contents` startup visibility, the factory
LaTeX adapter, source fallback for images, and no configured contributions.

Configuration cannot add syntax, commands, protected bindings, future-stage
operations, adapter authority, or executable callbacks. Factory completion and
templates remain available when configured contributions are absent or
rejected. A configured key that matches a protected factory template never
replaces the factory definition.

## Contextual completion

`contextual_completion_prepare` accepts an explicit syntax family at a valid
source position. Factory values cover keywords, task-state tokens, tags,
property names, link forms, targets, block names, languages, header arguments,
and file-local settings. Confirmed configured sources may add values to the
same closed families.

Every result copies candidate and provider text and retains the exact source,
analysis, configuration, and provider generations. Factory candidates precede
configured candidates; duplicate configured text is ignored without changing
factory provenance. One result admits at most 512 candidates and 256 KiB of
copied text.

Candidate acceptance produces a checked rewrite for the exact syntax owner.
It inserts source text only. For example, a configured source may insert a task
token or language name, but it cannot enable task transitions or source-block
execution.

## Templates and hard indentation

Factory templates include headings, lists, drawers, source and quote blocks,
and tables. Confirmed Racket configuration may add bounded source-only
templates for declared document, heading, list, drawer, block, table, or
paragraph contexts. `template_expansion_plan_prepare` resolves the key against
the exact configuration generation and inserts one complete source form
through one checked transaction and undo unit.

`hard_indentation_plan_prepare` is an explicit source-changing operation. It
keeps headings at the left margin and normalizes admitted list and block lines
according to the configured width. Visual indentation remains a separate view
projection.

## Contextual action and speed keys

`context_action_resolve` inspects copied syntax at point and selects the
highest stable `Authoring_Context` precedence, using the smallest range to
break ties. Its result exposes the context, concrete semantic command, target,
precedence, status, and future owner.

Recognized task, property, time, table-formula, source-execution, and citation
contexts return `Unavailable` with the responsible later Jan stage. They never
fall through to an unrelated Stage 2 command.

`speed_key_resolve` admits `n`, `p`, and the contextual tab action only when
point is exactly at a declared heading, list, table, block, or drawer prefix.
The same keys remain ordinary text elsewhere. The application publishes direct
and modal bindings over the same semantic command identities.

## Semantic repetition

`semantic_repeat_capture` records the repeat family, command, contextual kind,
buffer identity, source revision, and configuration generation. It retains no
byte range or parser-node identity. `semantic_repeat_resolve` inspects the
current analysis and resolves a fresh target at the current point before
returning the concrete repeated command.

## Focused validation

Use:

```sh
make jan-structured-editing-focused-test
odin check src/jan_editing -no-entry-point -vet -warnings-as-errors
odin check src/command -no-entry-point -vet -warnings-as-errors
```

These commands test the Racket and native models and static packages without
building or running the Odra application. Linked direct/modal behavior is
covered once by `jan-structured-editing-acceptance`.
