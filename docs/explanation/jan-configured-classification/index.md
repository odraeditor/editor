<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Classifies Configured Syntax in Odin

Some Jan source shapes are concrete punctuation, while others become semantic
only under the configuration confirmed for one analysis. Keeping these two
decisions separate makes the generated parser reproducible without allowing a
grammar table to become hidden product configuration.

## Concrete syntax establishes candidates

Tree-sitter recognizes stable delimiter and token boundaries: citations,
footnote references, links, targets, timestamps, markup, scripts, cookies,
entities, inline calls, source snippets, and table cells. It preserves spelling
and byte ranges and can recover around incomplete input.

That tree cannot decide whether `READY` is a task state, whether `example:` is
a registered scheme, or whether a plain word names a declared radio target.
Those answers can change without changing source bytes or regenerating the
parser.

## Confirmation turns policy into identity

Odin stores configurable names and policies in bounded copied arrays. Atomic
confirmation rejects empty, duplicate, oversized, or unsupported policy
values, then binds the content digest to a generation. Analysis accepts the
configuration only when that complete identity matches its scope.

Consequently, two equal documents analyzed under different task keywords or
link schemes do not masquerade as the same semantic result. Consumers compare
the full analysis scope and reject stale configuration just as they reject a
stale document revision or parser generation.

## Context can depend on the whole document

A radio link illustrates why concrete parsing is insufficient. The occurrence
is meaningful only when the same accepted analysis contains a matching radio
target and radio-link classification is enabled. Odin derives that node after
the concrete tree is copied, excludes escaped occurrences and target
declarations, and keeps the result under the same range and resource limits.

The same boundary records task-state case, tag and property policy, entity and
block membership, registered schemes, file-local setting recognition, and
emphasis-boundary validity. Unknown or invalid candidates remain ordinary,
preserved source; classification never rewrites them.

## Compatible expressions keep their dialect

Document fields that store Org-compatible regular expressions retain that
dialect as typed metadata. Treating the same bytes as a Racket or unrelated
host expression would silently change escaping, grouping, repetition, and case
semantics. A later API may explicitly accept a native Racket regexp for native
configuration, but source fields continue to report their own dialect.

## Indexes are source facts, not effects

Semantic indexes are derived only after concrete ranges and configured
classification pass. They share the exact node identities, ranges, revision,
configuration digest, and analysis generation. This prevents an index from
outliving the tree that justified it.

A link fact does not resolve or open a resource. A citation fact does not read
a bibliography. A timestamp fact does not calculate an agenda. A call, source,
formula, result, or block fact does not execute code. Later stages consume the
shared source facts under their own authority and failure contracts.
