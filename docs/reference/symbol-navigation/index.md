<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Symbol Navigation Reference

Odra exposes one provider-neutral symbol model for active-buffer search and
navigation. Language providers publish revision-bound observations; they do
not open documents, move point, render rows, or own result navigation.

## Commands

| Entry | Behavior |
| --- | --- |
| `M-s .` / `search-symbol-at-point` | Resolve the symbol under or adjacent to point, then start the ordinary forward literal search with symbol boundaries. |
| `M-x symbol-navigator` | Publish the active buffer symbol index into the common result surface. |
| Text in the result surface | Filter the copied symbol projection without changing the canonical result set. |
| Up, Down, `M-p`, `M-n`, `<`, `>` | Move through visible symbols using common result navigation. |
| `RET` | Visit the selected revision-checked symbol and retain the prior location. |
| `g` | Rebuild the active-buffer index and replace the exact result generation. |
| `q`, `C-g` | Close the result surface and return to the active buffer. |

Rows show the canonical symbol name followed by provider-neutral kind and
containing-scope annotations. Duplicate names remain separate locations.

## Provider order and fallback

Odra first uses a revision-current active language provider advertising symbol
support. The maintained Odin provider extracts declarations from its current
syntax tree. When no current provider index exists, a language-independent
Unicode scanner supplies a bounded buffer-local token index. Symbol-at-point
search uses the same current-provider preference and generic boundary fallback.

Stale revisions never authorize movement. Cancellation and resource failures
remain failures rather than silently publishing partial authority. A bounded
index that reaches its count, memory, hierarchy, or work limit reports itself
as incomplete and carries continuation metadata.

## Ownership and limits

Symbol descriptors contain a stable generation-local identity, kind, optional
parent and containing scope, exact buffer and document identity, source
revision, half-open byte range, provider identity, and result generation.
Names are limited to 512 bytes, containing scopes to 1 KiB, annotations to
4 KiB, hierarchy to 128 levels, and one index to 65,536 symbols, 32 MiB of
retained storage, 64 MiB of temporary storage, and 1,048,576 work items.

The result-set adapter copies admitted names and annotations, keeps result
identity separate from rendered text, and declares symbol results read-only.
The common result registry owns publication, selection, refresh generation,
activation, unified location movement, and cleanup.

The same registry and location commands also serve active-buffer search,
Project text search, and diagnostics. Symbol providers remain responsible only
for their own revision-current index and never inherit Project-search file
traversal or source-fingerprint authority.
