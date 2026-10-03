<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Explanation

Explanation material develops the design and invariants behind the editor core.

- [Contiguous Strings and Persistent Ropes](text-storage/index.md) separates
  semantic correctness from storage strategy.
- [Atomic Splice Publication](atomic-splice-publication/index.md) explains the
  validate, prepare, and publish transaction boundary.
- [Why Commands Publish Through Transactions](atomic-edit-transactions/index.md)
  explains private revisions, composition, multibuffer publication, optimistic
  proposals, and post-commit observation.
- [Ownership and Lifetimes](ownership-and-lifetimes/index.md) explains who keeps
  each resource alive and when it expires.
- [Why the Editor Session Coordinates Complete Buffer Graphs](editor-session-ownership/index.md)
  explains stable graph ownership, checked identity, aggregate reservation,
  full-path selection, retained primary views, UI-root separation, truthful
  marked effects, copied programmable authority, MRU activation, detachment,
  and reverse-order cleanup.
- [Why Project Identity Is Local and One-Root](project-context-ownership/index.md)
  explains local authority, separate Workspace composition, explicit
  promotion, trust, and session ownership.
- [Why Opening a Dir Checks Local Project Authority](project-directory-resolution/index.md)
  explains exact local-record validation and why global discovery cannot
  establish Project identity by itself.
- [Why Project Trust Belongs to Local Identity](project-trust-boundary/index.md)
  explains exact trust isolation, executable capability admission,
  configuration rollback, bounded watcher hints, and unavailable-directory
  retention without restricting ordinary file access.
- [Why Project Commands Use Bounded Native Candidates](project-command-boundary/index.md)
  explains incremental publication, overlap deduplication, generation-bound
  selection, lifecycle composition, and the Project keymap policy.
- [Frontend-Independent Editor Views](frontend-independent-view/index.md)
  explains why logical view state, display projection, and terminal mechanics
  have separate owners.
- [Why Integrated Terminals Separate Process, State, and Presentation](integrated-terminal-ownership/index.md)
  explains PTY, emulator, editor, frontend, and Racket ownership boundaries.
- [Why Ksawery Owns a Full-Canvas Session](ksawery-session-ownership/index.md)
  explains exclusive interaction scope, retained editor presentation, Git
  authority, semantic observations, and deterministic cleanup.
- [Why Pane Layout Is a Native Transaction Kernel](pane-layout-kernel/index.md)
  explains binary topology, integer geometry, effective and stored point
  synchronization, pane-local buffer history, coordinated kill, scratch policy,
  spatial versus MRU order, distinct balance objectives, atomic publication,
  terminal projection, and geometry recovery.
- [Why Programmable Pane Layouts Use Copied Authority](programmable-pane-layouts/index.md)
  explains generation-checked Racket scopes, immutable hook snapshots,
  contained callback failures, and FIFO deferred transactions.
- [Why Selection Uses Point, Mark, and Region](selection/index.md) explains
  retained endpoints, activation, rendering, and history context.
- [Why Text Transfer Uses an Internal Kill Ring](text-transfer/index.md)
  explains atomic kill reservation, semantic coalescence, complete eviction,
  transient yank rotation, programmable bindings, and physical clipboard
  isolation.
- [Why Odin Hosts Racket](in-process-racket-hosting/index.md) explains the
  native data plane, programmable control plane, provider placement, copied
  capabilities, operational records, and lifecycle tradeoffs.
- [Core and Personal Command Boundaries](core-and-personal-command-boundaries/index.md)
  explains why factory and personal code share transactional editing concepts
  while using different loading, resource, authority, and recovery policies.
- [Why Named Commands Sit Between Input and Editing](programmable-command-routing/index.md)
  explains normalized input, compiled programmable keymaps, dispatch, and
  lifecycle completions.
- [Why Documents Are Separate from Buffers](document-lifecycle/index.md)
  explains association, safe publication, external observations, and checked
  exit decisions.
- [Why Reversible History Is Separate from Transactions](reversible-editing-history/index.md)
  explains prepublication reservation, fresh-revision navigation, alternate
  futures, linked multibuffer atomicity, retained ownership, and conservative
  pruning.
- [Why Search State Is Separate from Editor Text](search-ownership/index.md)
  explains immutable traversal, view-local sessions, command coordination,
  derived display, bounded progress, and deterministic cleanup.
- [Why Keymaps Are Layered](layered-keymaps/index.md) explains contextual
  activation, explicit precedence, prefix ownership, masks, semantic remaps,
  immutable compilation, short-lived interaction ownership, retained
  provenance, minimal protected recovery, copied inspection, and why command
  navigation uses checked registry identities.
- [Why Candidate Navigation Uses a Source-Neutral Session](candidate-session-ownership/index.md)
  explains copied discovery state, atomic replacement, identity-preserving
  selection, shared ordering, narrow input turns, and deterministic cleanup.
- [Why the UI Foundation Publishes Complete Logical Generations](extensible-ui-foundation/index.md)
  explains the model, projection, logical-surface, physical-renderer boundary;
  atomic proposals; checked generations; focus capture; measured bounds; and
  consumer-driven migration.
- [Why Transient Presentation Uses Profiles](transient-presentation-profiles/index.md)
  explains role-specific interaction families, semantic chrome slots, atomic
  profile generations, declared fallback, and the narrow first consumer.
- [Why Feedback Separates Meaning from Presentation](feedback-ownership/index.md)
  explains source authority, semantic lifecycle, routing, public text,
  diagnostic detail, exact actions, and capability-aware degradation.
- [Why Programmable UI Roles Keep Native Fallbacks](programmable-ui-roles/index.md)
  explains copied provider authority, generation checks, confirmation before
  activation, contained failure, and narrow bootstrap privileges.
- [Why Interaction Profiles Share Canonical Commands](profile-compatible-command-routing/index.md)
  explains why profiles, states, scopes, bindings, and command-entry surfaces
  reuse one registered command identity instead of creating parallel command
  systems or reserving arbitrary keys.
- [Why Agent Interaction Uses One Authority Path](agent-authority-and-interaction/index.md)
  explains generation-checked selection, inert messages, distinct request and
  result states, direct specialist access, audit, and reconciliation.
- [Why Syntax Presentation Is Revision-Bound](revision-bound-syntax-presentation/index.md)
  explains exact-revision publication, plain-text fallback, shared per-buffer
  analysis, provider lifecycle, and semantic role separation.
- [Why Jan Separates Concrete Parsing from Document Meaning](jan-lossless-analysis/index.md)
  explains the concrete-tree and typed-analysis boundary, lossless source
  ownership, configuration identity, future-stage visibility, and the narrow
  JavaScript grammar-generation seam.
- [Why Jan Projects Structure in Odin](jan-structural-projection/index.md)
  explains dynamic heading forests, contextual admission, checked lossless
  publication, private parser lifetime, and the remaining staged boundaries.
- [Why Jan Classifies Configured Syntax in Odin](jan-configured-classification/index.md)
  explains the concrete-versus-semantic boundary, content-addressed
  configuration, document-wide radio links, compatible regexp ownership,
  source-fact indexes, and why indexing grants no external effects.
- [Why Jan Publishes Revisions Before Rewrites](jan-revision-fidelity/index.md)
  explains copied-tree candidates, last-confirmed inspection, minimal source
  ownership, ordinary transaction admission, and failure atomicity.
- [Why Jan Reuses Buffer and Syntax Ownership](jan-shared-language-ownership/index.md)
  explains identical suffix semantics, one analysis per buffer, atomic
  provider and configuration invalidation, shared semantic presentation, and
  editable-text degradation.
- [Why Jan Delivers Document Fidelity Before Document Workflows](jan-stage-boundaries/index.md)
  explains why complete recognition, source ownership, explicit availability,
  and failure containment precede structured editing and later workflow stages.
- [Why Jan Structured Editing Has Its Own Static Package](jan-structured-editing-package-boundary/index.md)
  explains the analysis, generic view, Stage 2 domain, and application adapter
  boundaries; anchor-owned hidden ranges; prepared visibility transitions; and
  the focused development loop.
- [Why Jan Keeps Authority Outside Providers](jan-authority-and-provider-boundaries/index.md)
  separates provider declaration, admission, availability, scoped authority,
  result acceptance, canonical ownership, optional tools, and partial effects.
- [Why Structural Syntax Reuses Canonical Editor Ownership](structural-syntax-ownership/index.md)
  explains one retained tree, copied targets, shared command identities,
  atomic indentation, effective multi-view selection, and plain-text fallback.
- [Why Themes Are Session-Owned Complete Definitions](session-theme-ownership/index.md)
  explains complete role mappings, atomic publication, copied Racket
  composition, renderer lowering, fallback, baseline, and non-persistence.
- [Why Language Services Use a Native Process Owner](language-service-ownership/index.md)
  explains advisory server authority, complete process ownership, bounded
  nonblocking work, generations, framing separation, position conversion,
  programmability, and deterministic teardown.
- [Why Language Workflows Use Static Package Boundaries](language-workflow-package-boundaries/index.md)
  explains the compile-time dependency direction, focused Odin and cached
  Racket feedback loops, language onboarding paths, timing evidence, and
  single-run nightly admission.
- [Why Language Completion Separates Provider, Session, and Acceptance](language-completion/index.md)
  explains copied provider advice, revision-bound interaction state, shared
  presentation, stable extension roles, and transaction-owned publication.
- [Why Language Support Uses Bundles](language-support-bundles/index.md)
  explains immutable contribution groups, uniform Factory and installed
  records, authority review, atomic generations, rollback, and attribution.
- [Why Curation and Trust Stay Separate](package-curation-and-trust/index.md)
  separates signatures, assessments, human admission, installation,
  capability consent, activation, official defaults, and independent curation.
- [Why Package Catalog Federation Uses Explicit Trust Roots](package-catalog-federation/index.md)
  explains distributed governance, local enrollment, exact mirrors, forks,
  conflicts, and retained offline state.
- [Why Roman Remains an Optional Package](roman-architecture/index.md)
  explains canonical Jan source, rebuildable SQLite projections, managed-space
  ownership, the generic native semantic boundary, package authority, modular
  verified loading, and non-destructive disablement.
- [Why Local Syntax and Language Services Are Separate](local-syntax-and-language-services/index.md)
  explains independent provider lifetimes, trust, failure containment, and why
  syntax-aware editing survives an unavailable external server.
- [Why Embedded Languages Require Explicit Injections](embedded-language-support/index.md)
  explains parent and child provider ownership, HTML script/style composition,
  deterministic ranges, and the boundary against guessed injections.
- [Why Programmable Gutters Publish Immutable Generations](programmable-gutter-ownership/index.md)
  explains copied Racket definitions, atomic native admission, shared factory
  composition, command routing, render-turn borrowing, and bounded teardown.
