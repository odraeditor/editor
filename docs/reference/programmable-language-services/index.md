<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Programmable Language Service Reference

This reference describes provider composition and Project-scoped document
synchronization for the language-independent service owner. OLS is the factory
provider and interoperability case; language-specific values remain registry
data rather than process, protocol, or synchronization behavior.

## Provider Registry

`Provider_Registry` owns copied service definitions, provider identities,
selection generations, executable resolutions, resource accounting, and the
active definition. Definitions move through proposal, confirmation, selection,
disable, replacement, and restoration operations. Every checked operation uses
the exact registry, definition, and provider generation.

The factory definition selects `ols`, the Project-membership root policy, Odin
language identity, UTF-16 positions, incremental synchronization, and the
bounded default limits, deadlines, and restart policy. A programmable
definition can replace it atomically. A failed replacement preserves the
current factory definition, provider, and selection generation. Factory
restoration remains available after selection, disable, or replacement.

Executable discovery accepts either one explicit path or one controlled search
path. It checks executable regular files directly and never evaluates a shell.
Resolved executable paths are copied into registry-owned storage.

## Hosted Composition

The fixed language-service capability records carry registry, selection,
Project, membership, definition, provider, and session generations. Racket
constructs immutable copied definitions and invokes provider operations only
inside the dynamically scoped host turn. Odin validates record widths, enum
values, limits, policy values, text offsets, JSON options, access, and current
generations before changing registry state.

Hosted callbacks are owner-thread-only, non-reentrant, and invalid after the
turn returns. Racket exceptions become contained host failures. No Racket
value, pointer, or exception object becomes registry state.

## Project Scope

A document synchronizer is bound to one exact session, Project, membership,
root policy, language set, negotiated position encoding, synchronization mode,
and service policy. Creation requires a current trusted Project membership.
Open, change, save, close, and recovery revalidate that identity and reject:

1. untrusted or revoked memberships;
2. paths outside the selected root;
3. external files that are not Project members;
4. stale Project, membership, session, document, or revision generations; and
5. languages outside the copied definition set.

Project overlap resolution remains owned by `src/project`. The synchronizer
consumes the exact selected membership rather than reproducing path precedence
or trust rules.

## Document Synchronization

Open publication starts at document version 1. Each accepted canonical
revision advances the LSP version exactly once. Full synchronization sends the
complete target text. Incremental synchronization converts the edited UTF-8
byte range into the negotiated UTF-8, UTF-16, or UTF-32 LSP range against the
exact base text. Both modes publish the same target revision and text.

Notifications are copied into a bounded FIFO queue. Queue depth, queue bytes,
change count, synchronization bytes, URI bytes, and retained bytes are checked
before publication. Acknowledgment removes only the exact head generation.
Recovery discards stale queued work and emits one full current-state change.
Save and close preserve the current canonical revision contract.

## Failures and Cleanup

Invalid definitions, missing executables, malformed JSON, policy overflow,
stale generations, trust changes, root violations, unsupported languages,
revision mismatches, queue limits, allocation failures, and closed owners
return stable failure records without partial publication.

Closing a synchronizer releases every copied language, path, URI, text, change,
and queued body. Closing the registry releases definitions, providers,
arguments, environment values, languages, JSON, roots, and executable paths.
Graceful process exit treats pipe EOF as stream closure, then reaps the child
before releasing process storage.

## Factory Application Workflow

`src/odra` owns one language-service workflow for the editor session. It
reconciles the active Project, current trusted memberships, provider selection,
eligible file-backed buffers, document revisions, saves, closes, Project
replacement, trust revocation, and editor shutdown. Multiple views of one
buffer share one document binding and diagnostic generation.

The workflow starts no process for an untrusted membership, unsupported
language, external file, missing executable, or invalid provider definition.
Those outcomes remain copied inspectable health while buffers, panes, history,
search, themes, saves, and exit continue normally.

`describe-language-service` presents registry and session inspection without
exposing an owned process or borrowed protocol storage. A failed and reaped
session may consume one explicit `restart-language-service` attempt; active or
exhausted sessions reject without starting another child.

## Acceptance

```sh
make language-service-workflow-acceptance
```

The target runs the same native registry, process session, Project membership,
document synchronizer, and diagnostic store against a data-only fixture
language server and the installed OLS executable. It verifies initialization,
the `initialized` notification, negotiated full and incremental
synchronization, diagnostic publication, open, change, save, close, graceful
shutdown, reaping, and zero retained native bytes. It then runs a real PTY
workflow for trusted activation, inspection, candidates, `M-g n`, `M-g p`,
editing, panes, themes, resize, missing-server fallback, save, exit, and
terminal restoration. This is a focused language-service gate, not the full
repository suite.
