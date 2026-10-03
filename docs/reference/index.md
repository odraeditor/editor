<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Reference

Reference material states the current editor-core vocabulary and contracts.

- [Command and Keybinding Reference](command-and-keybinding-reference/index.md),
  the module-oriented appendix for shipped public commands and factory
  bindings.
- [Editor Core API](editor-core/index.md)
- [Integrated Terminal Reference](integrated-terminal/index.md), including
  commands, lifetime, effects, image fallback, limits, and Racket observation.
- [Linux Preview Package Reference](linux-preview-package/index.md), including
  stable identity, public filenames, baseline libraries, verification,
  immutability, and failure behavior.
- [Release Publication Manifest Reference](release-publication/index.md),
  including candidate identity, snapshot identity, artifacts, phases,
  canonical encoding, and credential boundaries.
- [Verification Evidence Reference](verification-evidence/index.md), including
  workflow identities, native bundles, measured resources, privacy, and
  independent product and evidence outcomes.
- [Editor Session Reference](editor-session/index.md), including checked entry
  graphs, aggregate policy, create and open admission, full-path selection,
  retained views, startup and Buffer Menu list roots, marked execution, MRU
  activation, detachment, and cleanup.
- [Project Context Reference](project-context/index.md), including checked
  one-root identity, local authority, global discovery, exact Dir resolution,
  trust, scoped candidates and buffers, commands, limits, and failures.
- [Dir, Project, and Workspace Storage Reference](dir-project-workspace-storage/index.md),
  including target local and global record schemas, ownership, limits, atomic
  publication, catalog validation, and read-only legacy inventory.
- [Configuration System Reference](configuration-system/index.md), including
  user-level root resolution, `init.rkt`, functional configuration,
  operational state classes, Project discovery, and Workspace composition
  ownership.
- [Unsaved-Work Recovery Reference](unsaved-work-recovery/index.md), including
  private checkpoints, startup candidates, conflict handling, actions,
  configuration, retention, and source preservation.
- [Project Promotion Reference](project-promotion/index.md), including direct
  promotion, abandonment decisions, suppression state, trust, publication,
  recovery, and terminal behavior.
- [Workspace Composition Reference](workspace-composition/index.md), including
  durable ordered Project sets, startup selection, member resolution, atomic
  activation, Project-scoped focus, limits, failures, and cleanup.
- [Project and Workspace Migration Reference](project-workspace-migration/index.md),
  including legacy mappings, deterministic planning, journaled publication,
  restart behavior, rejections, failures, source preservation, and command
  statuses.
- [Programmable Buffer Session Reference](programmable-buffer-sessions/index.md),
  including copied capability shapes, Racket procedures, record widths,
  limits, ownership, and failure containment.
- [Editor View and Display Reference](editor-view/index.md)
- [Pane Layout Reference](pane-layout/index.md), including tree identity,
  integer geometry, terminal projection, pane status and separators, factory
  commands, manual resize, dimension and area balance, resize recovery, focus
  and MRU, pane-local buffer history, replacement, coordinated kill, soft and
  hard dedication, other-pane display policy, checked Racket configuration,
  copied programmable capabilities, hooks, deferred mutations, split, close,
  keep-only, limits, failures, accounting, and teardown.
- [Status Bar Reference](status-bar/index.md), including pane-local buffer
  state, identity, position, document, pane, Workspace, Project, language and
  diagnostic context, exact-width composition, Unicode-safe narrow-pane
  degradation, theme ownership, programmable provider lifecycle, limits,
  failures, and cleanup.
- [Feedback and Progress Reference](feedback-and-progress/index.md), including
  producer channels, semantic records, factory destinations, retained history,
  checked actions, recovery, bounds, and terminal fallback.
- [Gutter Reference](gutter/index.md), including logical absolute, relative,
  and hybrid numbering, view-local overrides, personal configuration,
  programmable provider records, commands, geometry, limits, lifecycle, and
  failures.
- [Selection Reference](selection/index.md)
- [Interaction Compatibility Reference](interaction-compatibility/index.md),
  including the versioned case ledger, applicability boundary, conflict
  policy, and binding migration rules.
- [Maksym Reference](maksym/index.md), including directory opening, stable
  navigation, metadata presentation, editable filenames, direct checked
  application, bounds, and failures.
- [Darek Reference](darek/index.md), including panel lifecycle, tree navigation,
  Workspace roots, opening and preview, filesystem actions, keymap helpers,
  semantic presentation, bounds, and ownership.
- [Ksawery Reference](ksawery/index.md), including full-canvas
  session lifecycle, semantic Status and History identity, revision inspection
  and ranges, checked commits, path detail, complete-path stage and unstage,
  process limits, failures, and excluded operations.
- [Text Transfer Reference](text-transfer/index.md), including the internal
  kill ring and optional physical clipboard adapter.
- [Editor Core Terminology](terminology/index.md)
- [Racket Runtime Boundary Reference](racket-runtime-boundary/index.md),
  including the current module map, public and internal boundaries,
  initialization, dependency direction, procedure ownership, and common
  change guide.
- [Programmable Command Reference](programmable-commands/index.md)
- [Personal Commands Reference](personal-commands/index.md), including public
  Racket modules, definitions, command contexts, measured limits, atomic
  activation, inspection, diagnostics, lifecycle, and recovery.
- [Direct Navigation Reference](direct-navigation/index.md), including factory
  bindings, movement, overwrite, paging, contextual ownership, and profile
  compatibility boundaries.
- [Modal Interaction Profile Reference](modal-interaction-profile/index.md),
  including session and startup selection, Normal, Insert, Replace, and Visual
  states, navigation, operators, text transfer, named text slots, Status Bar
  state, cursor intent, failures, and ownership.
- [Local Document Lifecycle Reference](document-lifecycle/index.md)
- [Atomic Edit Transaction Reference](atomic-edit-transactions/index.md)
- [Reversible Editing History Reference](reversible-editing-history/index.md),
  including linked multibuffer identities, navigation, pruning, and limits.
- [Search and Replacement Reference](search-and-replacement/index.md),
  including incremental and query commands, responses, expression dialect,
  scopes, states, smart case, programmable policy and composition, limits,
  failures, and cleanup.
- [Search Result Navigation Reference](search-result-navigation/index.md),
  including materialization, result generations, filtering, refresh, checked
  editing, atomic application, common location movement, limits, and copied
  programmable providers.
- [Symbol Navigation Reference](symbol-navigation/index.md), including
  provider-neutral symbols, `M-s .`, the active-buffer navigator, fallback,
  result integration, limits, and ownership.
- [Contextual Keymap Reference](contextual-keymaps/index.md), including profile,
  map, context, and owner identities; deterministic layers; binding operations;
  remaps; runtime prompt and list-tool maps; provenance; selected limits;
  failure preservation; interactive command catalogs; `M-x` navigation;
  providers, availability, complete sequence notation; protected recovery;
  bounded inspection commands and records; and cleanup.
- [Interaction Profile Compatibility Contract Reference](interaction-profile-compatibility/index.md),
  including bounded profile catalogs, explicit interaction states, binding
  scopes, shared selectors, state-aware command effects, command-entry surface
  identities, selected limits, structural validation, copied Racket catalog
  composition and transport, immutable compatibility inspection, failures, and
  the current integration boundary.
- [Candidate Session Reference](candidate-session/index.md), including copied
  source snapshots, stable identities, matching, ranking, generations,
  ownership, accounting, limits, failures, and source-adapter boundaries.
- [Extensible UI Foundation Reference](extensible-ui-foundation/index.md),
  including logical surfaces, copied projections and snapshots, atomic root
  publication, focus capture, renderer capabilities, limits, failures, and
  migration constraints.
- [Transient Presentation Profile Reference](transient-presentation-profiles/index.md),
  including contextual role and profile generations, semantic chrome slots,
  selection, theme and frontend lowering, fallback, inspection, limits, and
  the current extension boundary.
- [Programmable UI Roles Reference](programmable-ui-roles/index.md), including
  current roles, copied records, provider lifecycle, Racket capabilities,
  session scope, built-in fallback, limits, failures, and bootstrap privileges.
- [Syntax Analysis Contract Reference](syntax-analysis-contracts/index.md),
  including language and provider identities, single-active provider
  lifecycle, exact-revision syntax records, selected dependency and resource
  policy, failures, inspection, and the deferred package-loading seam.
- [Language Catalog Reference](language-catalog/index.md), including immutable
  catalog generations, provider-independent language identities, selector and
  source precedence, factory Odin, Jan, Racket, and Go data, limits, failures,
  and copied inspection.
- [Language Support Reference](language-support/index.md), including the
  uniform discovery pages for all nine basic-pack languages and installed
  language documentation.
- [Language Bundle Reference](language-bundles/index.md), including manifests,
  Racket authoring APIs, catalogs, durable state, lifecycle, trust, commands,
  bindings, capabilities, limits, failures, and version evidence.
- [Package Catalog Reference](package-catalogs/index.md), including identity,
  authority, registration, endpoints, signed snapshots, exact mirrors,
  federation, commands, limits, and failures.
- [Installable Package Reference](installable-packages/index.md), including
  generic manifests, installed state, lifecycle commands, activation locks,
  operation journals, reachability, persistence, recovery, and language-bundle
  migration, plus the [Package Authoring Reference](installable-packages/authoring.md).
- [Agent Substrate Definition Reference](agent-substrate/index.md), including
  public package constructors, inert schemas, definition metadata, resource
  limits, atomic package generations, copied inspection, local interaction,
  authority controls, audit, recovery, and the no-authority boundary.
- [Agent Package Authoring Reference](agent-substrate/authoring.md), including
  public API usage, manifest alignment, compatibility, migration, security,
  conformance fixtures, and troubleshooting.
- [Roman Linked Knowledge Reference](roman/index.md), including the Project
  corpus, stable identities, commands, native Jan adapter, SQLite index,
  authority, lifecycle, managed-space isolation, limits, and failures.
- [Package Curation Reference](package-curation/index.md), including exact
  releases, submissions, assessments, human decisions, assertions,
  publication, manual provenance, limits, and curator tooling.
- [Package Advisory Reference](package-advisories/index.md), including issuers,
  generations, selectors, evidence, actions, local response, overrides, limits,
  and failures.
- [Language Support Configuration Reference](language-support-configuration/index.md),
  including public Racket constructors, direct personal configuration,
  maintained and configurable support levels, factory Racket and Go profiles,
  additional-language recipes, package facets, source precedence, defaults,
  limits, atomic reload, inspection, recovery, and validation.
- [Jan Document Language Analysis Reference](jan-document-language-analysis/index.md),
  including the accepted baseline, exact analysis scopes, complete source-form
  vocabulary, copied records, rewrite and availability boundaries, resource
  policy, failures, parser provenance, and focused validation.
- [Jan Structural Syntax Reference](jan-structural-syntax/index.md), including
  the concrete tree taxonomy, external scanner, Odin projection, outline
  forest, contextual admission, source ownership, recovery, limits, cleanup,
  and its relationship to inline classification.
- [Jan Inline Syntax and Index Reference](jan-inline-syntax-and-indexes/index.md),
  including all inline node families, context and precedence, confirmed
  configuration, typed attributes, semantic source-fact indexes, generation
  checks, limits, and the no-effects boundary.
- [Jan Incremental Analysis and Rewrite Reference](jan-incremental-analysis-and-rewrites/index.md),
  including copied-tree updates, atomic generation publication,
  last-confirmed inspection, minimal owned rewrites, transaction adaptation,
  rejection, resource limits, and cleanup.
- [Jan Factory Language Integration Reference](jan-factory-language-integration/index.md),
  including suffix and explicit selection, shared buffer ownership, provider
  isolation, revision-bound syntax presentation, degradation, inspection, and
  unchanged factory Odin behavior.
- [Jan Inspection and Lint Reference](jan-inspection-and-lint/index.md),
  including public commands, syntax paths, lint diagnostics, copied bridge
  records, baseline, limits, failures, and final capability availability.
- [Jan Capability Ledger](jan-stage-1-capabilities/index.md), including
  linked language, editing, planning, computation, output, provider, and
  extension behavior plus explicit optional-dependency availability.
- [Jan Product Surface Reference](jan-product-surface/index.md), including
  command discovery, configuration precedence, capability states, backends,
  provider authority, resource ceilings, extensions, and recovery.
- [Jan Structured Editing Contracts Reference](jan-structured-editing-contracts/index.md),
  including exact Stage 2 scopes, generic view-local hidden ranges,
  deterministic visibility transitions, availability, limits, failures,
  cleanup, and focused package validation.
- [Jan Outline Editing Reference](jan-outline-editing/index.md), including
  structural navigation, local and global visibility derivation, atomic heading
  and subtree rewrites, sparse projections, exact source navigation, limits,
  failures, and cleanup.
- [Jan List and Structure Editing Reference](jan-list-and-structure-editing/index.md), including
  plain-list operations, complete drawer and block editing, factory templates,
  fold and selection ranges, atomic structural regions, later-stage semantic
  boundaries, limits, failures, and cleanup.
- [Jan Table Editing Reference](jan-table-editing/index.md), including
  non-executing construction and structural edits, rectangular transfer,
  Unicode-aware presentation, focused cells, formula inspection, limits,
  failures, and cleanup.
- [Jan Rich Presentation Reference](jan-rich-presentation/index.md), including
  source-preserving semantic projection, markup and entities, visual outline
  policy, local footnotes, bounded preview adapters, fallback, limits, and
  cleanup.
- [Jan Contextual Authoring Reference](jan-contextual-authoring/index.md),
  including bounded configuration, completion, templates, hard indentation,
  contextual precedence, future-stage outcomes, speed-key admission, semantic
  repetition, and focused validation.
- [Jan Structured Editing Commands and Configuration](jan-structured-editing-commands/index.md),
  including the complete public command catalog, direct and modal bindings,
  configuration entrypoint, transaction behavior, inspection, and linked
  acceptance boundary.
- [Jan Planning Contracts Reference](jan-planning-contracts/index.md), including
  exact Stage 3 identities, bounded requests and results, checked workflow,
  source-set, capture, and agenda configuration, active-clock recovery,
  capability lifecycle, resource limits, and focused validation.
- [Jan Tasks and Metadata Reference](jan-tasks-and-metadata/index.md), including
  workflow transitions, dependencies, progress, habits, priorities, tags,
  properties, editable owners, and captured column views.
- [Jan Time Workflows Reference](jan-time-workflows/index.md), including
  canonical timestamps, zone and DST decisions, recurrence, atomic planning
  edits, durable clocks, effort, relative timers, and notification isolation.
- [Jan Refile and Archive Reference](jan-refile-and-archive/index.md), including
  candidate constraints, same- and cross-document subtree movement, recoverable
  publication, archive origin metadata, restoration, and visibility policy.
- [Jan Capture and Intake Reference](jan-capture-and-intake/index.md), including
  bounded templates, preview and abort, recoverable attachment effects,
  explicit RSS/Atom refresh, deduplication, retention, privacy, and cleanup.
- [Jan Agenda Queries Reference](jan-agenda-queries/index.md), including
  revision-bound source indexes, query families, filters, stable sorting,
  grouping, truncation, source-health inspection, and cache invalidation.
- [Jan Planning and Agenda Operations Reference](jan-planning-and-agenda-operations/index.md),
  including the complete public planning command catalog, copied bridge ABI,
  exact agenda navigation and source reveal, remote edits, bulk policy,
  refresh and export handoffs, capability state, and recovery inspection.
- [Jan Computation Contracts Reference](jan-computation-contracts/index.md),
  including exact computation identities, copied requests and lifecycle
  records, typed result descriptors, checked Racket adapter and deny-first
  policy generations, resource limits, and focused validation.
- [Jan Formulas and Plots Reference](jan-formulas-and-plots/index.md), including
  copied table snapshots, compatible references, bounded algebra, lookup,
  dependency order, atomic recalculation, debug traces, text plots, Gnuplot
  handoffs, failure preservation, and later-slice execution boundaries.
- [Jan Execution Adapters Reference](jan-execution-adapters/index.md), including
  exact header precedence, adapter selection, typed serialization, deny-first
  authority, one-shot confirmation, process requests, cancellation, timeout,
  quarantine, diagnostics, cleanup, and explicit no-execution triggers.
- [Jan Results, Sessions, and Cache Reference](jan-results-sessions-and-cache/index.md),
  including complete typed decoding, exact-owner publication candidates,
  bounded post-processing, explicit session recovery, complete cache keys,
  inspection, deterministic eviction, and source-independent deletion.
- [Jan Source Editing and Extraction Reference](jan-source-editing-and-extraction/index.md),
  including focused owner-only edits, indentation and delimiter preservation,
  admitted noweb libraries, bounded expansion, complete tangle plans, checked
  resources, collision policy, provenance, and staged multi-target outcomes.
- [Jan Computation Operations Reference](jan-computation-operations/index.md),
  including the complete public command catalog, deterministic bounded batches,
  atomic and best-effort publication accounting, capability transitions, copied
  bridge records, failures, and no-effect guarantees.
- [Jan Output Contracts Reference](jan-output-contracts/index.md), including
  exact export scopes, explicit setting precedence, admitted includes, bounded
  macros, normalized projections, ordered filters, checked destinations,
  durable manifests, protocol and extension records, limits, and focused
  validation.
- [Jan Native Output Backends Reference](jan-native-output-backends/index.md),
  including plain-text encoding policy, safe full and minimal HTML, Markdown,
  normalized Jan/Org, raw-content control, unsupported-form diagnostics,
  inspection, bounds, and deterministic offline goldens.
- [Jan Tool Output Backends Reference](jan-tool-output-backends/index.md),
  including LaTeX, Beamer, PDF, ODT, Texinfo, Info, man-page, and iCalendar
  source and tool plans, exact availability, cleanup, bounds, and deterministic
  offline goldens.
- [Jan Citations and Bibliographies Reference](jan-citations-and-bibliographies/index.md),
  including exact bibliography resources, CSL and LaTeX processor adapters,
  key resolution, cache identity, variants, affixes, backend rendering,
  bibliography planning, completion, failures, and offline goldens.
- [Jan Publishing Reference](jan-publishing/index.md), including bounded Racket
  project configuration, deterministic discovery and composition, complete
  manifests, exact incremental reuse, links, static and generated outputs,
  local and remote outcomes, retry, reconciliation, cleanup, and retention.
- [Jan External Protocols Reference](jan-external-protocols/index.md), including
  admitted link and media provider capabilities, versioned authenticated
  store-link, capture, and source-location requests, payload and time bounds,
  replay protection, checked results, and no-effect failures.
- [Jan Protected Synchronization Reference](jan-protected-synchronization/index.md),
  including credential-handle-only subtree encryption and decryption, opaque
  preservation, plaintext-save policy, transport-neutral staging, checksums,
  three-way conflict reconciliation, ordered application, recovery, cleanup,
  and retention.
- [Jan Extension Surface Reference](jan-extension-surface/index.md), including
  atomic provider generations, lifecycle hooks, packages, properties, mapping,
  agenda and capture contributions, custom links, exporters, filters,
  processors, translators, dynamic blocks, adapters, authority boundaries,
  failure containment, inspection, and conformance.
- [Tree-sitter Odin Analysis Reference](tree-sitter-odin-analysis/index.md),
  including vendored provenance, offline reproduction, foreign ownership,
  initial and incremental parsing, query mapping, resource evidence, failures,
  and the current application boundary.
- [Structural Syntax Contract Reference](structural-syntax-contracts/index.md),
  including exact tree scopes, copied named-node targets, traversal,
  indentation plans, selected limits, failures, cleanup, and the deferred
  editor-command seam.
- [Structural Editor Operations Reference](structural-editor-operations/index.md),
  including exact command scopes, navigation, expanding selection,
  multi-view synchronization, atomic indentation, history, failures, and
  ownership.
- [Programmable Structural Commands Reference](programmable-structural-commands/index.md),
  including canonical routes, copied Racket values, scoped authority, record
  widths, native parity, failure containment, and cleanup.
- [Semantic Syntax Presentation Reference](semantic-syntax-presentation/index.md),
  including semantic UI roles, factory styles, exact-revision decorations,
  terminal color degradation, precedence, application composition, focused PTY
  acceptance, limits, failures, and cleanup.
- [Theme System Reference](theme-system/index.md), including native identities,
  immutable complete definitions, factory palettes, selection lifecycle,
  fallback, safe baseline, limits, accounting, failures, cleanup, copied Racket
  records, programmable lifecycle operations, and capability containment.
- [Language Service Contract Reference](language-service-contracts/index.md),
  including generic identities, process ownership, bounded LSP framing,
  JSON-RPC records, positions, lifecycle, deadlines, restart, limits, failures,
  cleanup, and the provider seam.
- [Programmable Language Service Reference](programmable-language-services/index.md),
  including copied Racket definitions, native provider admission, factory OLS
  data, trusted Project roots, document synchronization, replacement and
  restoration, accounting, and real-server acceptance.
- [Language Diagnostics Reference](language-diagnostics/index.md), including
  revision-bound publication, normalization, semantic presentation, candidate
  generations, native and programmable commands, limits, failures, and cleanup.
- [Language Completion Reference](language-completion/index.md), including
  invocation, filtering, interactive bindings, theme-aware presentation,
  atomic acceptance, configuration, inspection, limits, and recovery.
- [License Reference](license/index.md), including the `GPL-3.0-only` scope,
  copyright notice, complete license location, source snapshot preservation,
  and third-party attribution boundary.
