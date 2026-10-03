<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Understand Provider Fallback

Language providers add syntax, structure, diagnostics, symbols, and completion.
Core editing remains available when a provider is missing, unsupported, or
unavailable.

This chapter exercises those capabilities across supported, unsupported,
trusted, and failed-provider contexts.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md), then complete
[Use Language Services and Diagnostics](language-services-and-diagnostics.md).
The notes and Project files used below are supplied by the exercise kit.

## Start from the Editor Baseline

Open `~/odra-guide/work/dirs/notes/editing-practice.txt`. Insert text, move
point, make a selection, undo and redo, search, save, split the pane, and
switch buffers.
These operations do not require language recognition or an external process.

Run `M-x describe-language-state`. The document uses the plain-text
association. It remains a complete editable document even though syntax and
structural capabilities are absent.

Press `C-M-i`. `Completion unavailable for current document` reports the
missing semantic capability without starting an empty interaction or changing
the source.

## Read the Capability Ladder

Each layer is admitted independently against current editor state:

| Layer | What it may add | Outcome when unavailable |
| --- | --- | --- |
| Editor | Text, point, selection, history, files, buffers, panes, and search | This baseline remains available. |
| Syntax | Revision-matched semantic roles | The document uses plain presentation. |
| Structure | Movement, selection, and indentation from the current syntax tree | Structural commands are checked no-ops. |
| Language service | Project-scoped diagnostics, symbols, and negotiated features | Editing continues without a service session. |
| Completion | Current semantic candidates and checked text edits | The request reports unavailable and applies nothing. |
| Presentation | Theme-aware spans, markers, result lists, and transient surfaces | Semantic state remains authoritative; constrained presentation may degrade or close. |

Fallback never means applying an older syntax tree, diagnostic, symbol, or
completion batch. A missing capability removes only that capability. A stale
generation is rejected rather than approximated from newer text.

## Compare Four Current Contexts

Compare these contexts to see which language capabilities are available while
document editing continues.

### Plain Text

Keep `editing-practice.txt` open. Syntax uses the plain association,
structural commands do nothing, no language service starts, and completion is
unavailable. Ordinary editing remains intact.

### Syntax Without a Service

Open `Forecast Engine/main.odin` from an ordinary Dir or an untrusted Project.
The maintained syntax provider can still present revision-matched semantic
roles and structural commands can use its current tree. The context does not
authorize the external language-service process, so diagnostics and semantic
completion remain unavailable.

### Syntax with a Trusted Service

Open the exact trusted `Forecast Engine` Project and select `main.odin`. Run
`M-x describe-language-state` and `M-x describe-language-service`.

The syntax provider owns syntax analysis; the Project-scoped service owns its
negotiated semantic publications. A current diagnostic or completion batch is
admitted only for the exact document revision and provider generation that
produced it.

### Failed External Provider

Repeat the disposable exiting-provider exercise from
[Use Language Services and Diagnostics](language-services-and-diagnostics.md#exercise-failure-containment).
The service reaches a contained failed state. Syntax and structure remain
available because they do not depend on that process, while diagnostics,
symbols, and completion publish no new semantic results. Text editing remains
immediate throughout the failure and bounded restart attempt.

## Distinguish Missing from Stale

A capability may be absent because the document has no matching provider, the
Project is not trusted, the executable is unavailable, or the service did not
negotiate that feature. Inspection reports the applicable boundary and the
command performs no destructive action.

A stale result is different: a provider existed, but its document revision,
Project generation, session, request, or candidate authority no longer matches
current state. Odra retires that result. It never keeps stale diagnostics for
navigation or accepts stale completion edits as a fallback.

When either case occurs, continue editing first. Restore eligibility only when
you need the missing language capability.

## Understand Current Factory Availability

The maintained factory setup associates the case-sensitive `.odin` suffix with
the bundled Odin syntax definition and uses `ols` for trusted Project
language-service sessions. The case-sensitive `.org` and `.jan` suffixes both
select the bundled Jan document language. Other suffixes use plain text unless
an explicit checked language selection applies.

That availability is narrower than the editor contracts. Syntax, structure,
services, diagnostics, symbols, completion, and their presentation have stable
ownership boundaries so another provider can supply the same normalized
capabilities without replacing canonical editor state.

Syntax analysis is not a substitute completion provider. When no eligible
synchronized semantic service can complete the current document, completion
reports unavailable instead of deriving speculative candidates from syntax
captures.

## Verify the Result

You have completed this chapter when plain text remains fully editable, syntax
and structure work without external-process authority, a trusted supported
Project admits current service results, an exiting service is contained, and
no missing or stale provider state blocks ordinary editing or publishes an
approximation.

For current provider setup and recovery, see
[Set Up and Diagnose Language Services](../../../how-to/use-language-services/index.md)
and
[Configure and Diagnose Language Completion](../../../how-to/configure-language-completion/index.md).
For exact ownership contracts, see the
[Syntax Analysis Contract Reference](../../../reference/syntax-analysis-contracts/index.md),
[Structural Syntax Contract Reference](../../../reference/structural-syntax-contracts/index.md),
[Language Service Contract Reference](../../../reference/language-service-contracts/index.md),
and
[Language Completion Reference](../../../reference/language-completion/index.md).

---

[Previous: Use Language Completion](language-completion.md) ·
[User Guide](../index.md) ·
[Next: Structured Documents](../structured-documents/index.md)
