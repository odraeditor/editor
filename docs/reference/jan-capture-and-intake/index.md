<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Capture and Intake Reference

Jan capture creates structured entries against an exact destination without
requiring the user to visit it first. Attachment and feed intake use the same
planning boundary: `src/jan_planning` validates copied inputs and returns
checked document rewrites or public-owner effect plans. It never performs file,
network, repository, credential, navigation, or document-publication effects.

## Capture templates

A confirmed template identifies its stable identity, selection key, label,
entry kind, literal or admitted-generator source, and exact resource and
structural target. It also declares the admitted substitution kinds, whether
to finish immediately or start a clock, empty-line policy, cursor policy,
applicability, and input and output limits.

Template values are explicit copied facts of these kinds:

- time;
- clipboard text;
- selected text;
- links;
- prompted values;
- file values; and
- extension-provided values.

Expansion recognizes `%{key}` substitutions and at most one `%?` cursor marker.
Every supplied value must be admitted by the template, every referenced key
must exist, duplicate keys reject, and copied input and expanded output remain
bounded. A provider-generated source is accepted only when its generator was
admitted before it reached the planner; expansion itself cannot acquire new
filesystem, process, network, or configuration authority.

The lifecycle is `Prepared` for immediate-finish captures or `Previewing` for
ordinary captures. Preview may enter `Editing`, replace its copied draft
atomically, and then prepare one exact Jan rewrite. Finalization validates the
current target revision and appends the complete draft through one
`language.Jan_Rewrite_Plan`. Abort clears the copied draft and publishes no
rewrite. Session descriptors expose byte counts, cursor position, lifecycle,
clock intent, and the count of sensitive values without exposing their text.

## Attachment ownership and actions

An attachment directory comes from a stable heading identifier, inherited
policy, an explicit directory, or a configured provider. One request binds the
exact heading and resource identities plus the selected policy.

Supported effect plans cover:

- copy, move, hard link, and supported symbolic link;
- provider-admitted download and synchronization;
- directory creation;
- open, list, and reveal through admitted Maksym navigation;
- rename and delete; and
- optional repository recording through admitted Ksawery public operations.

The returned plan says which resource effect, document-link change, Maksym
reveal, and repository record the corresponding public owners must perform.
It does not execute hidden shell commands or infer authority from a path.

## Recoverable attachment publication

Resource completion always precedes document-link publication. A copy, move,
link, download, rename, or delete cannot insert or alter a compatible
`[[attachment:resource-key]]` reference until its resource owner confirms the
effect. Rename replaces one exact existing reference; delete removes it;
duplicate or missing references reject rather than changing an ambiguous
heading.

The workflow records prepared, resource-committed, repository-pending,
completed, cancelled, failed, recovery-required, and rolled-back outcomes. A
document failure after a reversible resource effect exposes recovery and may
roll the resource back. A non-reversible delete or synchronization remains
explicitly recovery-required. Optional repository failure reports a partial
outcome without pretending that already committed resource and document work
was undone.

## Feed refresh and capture

RSS and Atom definitions contain a stable identity, endpoint, optional
credential reference, format, and retention limit. The network provider owns
retrieval and authentication. The planner accepts only copied provider results
from an explicitly invoked or scheduled refresh. `Document_Open` is rejected,
so loading a document cannot trigger network access.

Refresh performs exact identity deduplication against retained history and
earlier entries in the same result. It copies admitted unseen entries into an
owned snapshot, preserves deterministic order, applies entry and retention
limits, reports duplicates and truncation, and rejects malformed or duplicate
retention state. Closing the snapshot releases all copied provider text.

One copied feed entry projects title, link, and summary into ordinary capture
values. Feed capture therefore uses the same template, preview, exact-target,
abort, and finalization rules as any other capture source.

## Failures and privacy

- Stale scopes and targets reject before a rewrite is retained.
- Missing capabilities, providers, Maksym, Ksawery admission, or symbolic-link
  support remain explicit unavailable outcomes.
- Cancellation publishes no feed snapshot or capture rewrite.
- Fixed entry, text, and attachment limits reject or report truncation without
  unbounded ownership.
- Allocation failures release partial capture and feed state.
- Descriptors do not expose endpoints, credential references, private resource
  text, capture drafts, or sensitive substitution contents.

## Current delivery boundary

This package delivers capture, attachment, feed, recovery, and copied-state
contracts plus exact Jan rewrite plans. Public `jan-capture`, attachment, and
feed command registration remains in the Planning closure slice. Linked editor
and terminal acceptance remains reserved for the final Jan product closure
slice.
