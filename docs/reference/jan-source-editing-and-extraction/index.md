<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Source Editing and Extraction Reference

Jan source editing and extraction operate on copied exact-revision contracts.
Focused editing prepares one owner-only source candidate. Noweb expands only
admitted named definitions. Tangling validates and stages a complete resource
plan before any writer receives output.

## Focused source editing

Opening a focused source edit records:

- one explicit operation and exact computation scope;
- the originating source-block identity and owner range;
- the exact body range and original-body digest;
- copied indentation; and
- an open lifecycle state.

The focused view receives a copied deindented body and uses the selected
language provider through ordinary editor behavior. It does not own the Jan
document.

Publication requires the same analysis and source revision, semantic owner,
body range, and original bytes. Jan reindents the edited body and constructs
one whole-source candidate by copying the prefix and suffix unchanged. The
source-block delimiters, surrounding indentation, and unrelated source remain
outside the replacement range. The editor owner performs the eventual atomic
transaction.

Abort closes the focused edit without a candidate. Staleness, malformed
indentation, cancellation, or insufficient output storage leaves the owner
document unchanged.

## Noweb definitions

Named source blocks, calls, and results contribute borrowed definitions to one
bounded expansion catalog. Document definitions have the highest precedence.
Factory, user, Workspace, and Project libraries participate only when their
documents were explicitly admitted; loading a library never executes it.

At one precedence level, a single definition replaces lower-precedence
definitions. Multiple definitions must all declare additive composition and
must have distinct deterministic order values. Their configured separator is
copied between fragments. Any other duplicate is a conflict.

Compatible `<<name>>` and `<<name(arguments)>>` references expand recursively.
`$arguments` remains literal copied substitution data. Continuation lines
inherit the whitespace prefix at the reference site. Missing, malformed,
ambiguous, cyclic, excessive-depth, or excessive-output expansion rejects the
whole result. A failed expansion retains its reference chain for inspection.

## Tangling

Each selected block supplies an exact source owner, checked provider resource,
fully expanded copied content, optional shebang, language-appropriate comment
prefix, mode, padding, stable order, and collision policy.

Tangling first validates and sorts every block by provider, resource, explicit
order, and source position. It then:

1. checks existing-resource ownership and overwrite policy;
2. groups blocks by exact target identity;
3. writes one shebang and optional provenance comments;
4. preserves stable block order and requested padding;
5. enforces per-target and aggregate byte limits;
6. records every source block's target outcome; and
7. marks every target complete only after the whole plan succeeds.

The result is caller-owned staged bytes plus target descriptors. This package
does not write, rename, chmod, or publish resources. A resource owner must
atomically publish each complete staged target and report the explicit
multi-resource outcome.

An unrelated existing resource requires overwrite authority. Replace-owned
policy accepts only resources already attributed to Jan generation. Collision,
cancellation, staleness, malformed source, allocation failure, or any resource
limit returns no complete plan.

## Current boundary

Slice 13 owns focused body candidates, noweb graphs and expansion, shared
library admission, complete tangle planning, provenance, collision policy, and
staged multi-target outcomes. Slice 14 owns deterministic batch execution and
the complete Computable Documents command and bridge surface. Linked editor
acceptance remains reserved for Slice 24.
