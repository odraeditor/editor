<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# How-to Guides

How-to guides give direct procedures for working with the current core.

- [Validate the Editor Core](validation/index.md) runs static checks, tests,
  history models, multibuffer profiles, documentation inspection, and
  benchmarks.
- [Publish Development to Main](publish-through-staging/index.md) promotes
  integrated work directly from `dev`, then leaves bounded Main Check and
  exhaustive nightly evidence in Forgejo.
- [Prepare and Publish an Odra Release](publish-linux-preview/index.md) exports
  a curated source snapshot, builds and retains the Linux bundle, prepares the
  matching User Guide, and publishes the exact candidate through a separate
  explicit dispatch.
- [Open, Edit, and Save a Local Document](run-terminal-view/index.md) builds
  the terminal frontend and exercises its complete single-document lifecycle.
- [Configure Editing History at Runtime](configure-editing-history/index.md)
  replaces the complete in-memory retention policy through the embedded Racket
  facade without restarting Odra.
- [Use the System Clipboard](use-system-clipboard/index.md) exports copied or
  killed text through the supported presentation path and diagnoses fallback.
- [Configure Integrated Terminals](configure-integrated-terminal/index.md)
  selects shells, attention, bounded automation, and safe effect policy.
- [Troubleshoot Integrated Terminals](troubleshoot-integrated-terminal/index.md)
  separates session, process, presentation, and resource failures.
- [Update the Terminal Emulator Dependency](update-terminal-emulator-dependency/index.md)
  admits and verifies a new immutable `libghostty-vt` input set.
- [Configure Programmable Search Policy](configure-search/index.md) replaces
  or overrides copied search and replacement policy inside the embedded
  Racket runtime.
- [Configure Personal Startup](configure-personal-init/index.md) creates a
  minimal `init.rkt`, grows it into user-authored modules, separates it from
  operational state, and checks startup feedback.
- [Define and Reload Personal Commands](define-personal-commands/index.md)
  authors a modular Racket text command, contributes a binding, inspects the
  active state, reloads changes, deactivates the set, and recovers from a
  rejected candidate.
- [Configure and Reload a Programmable Gutter](configure-programmable-gutter/index.md)
  publishes, inspects, replaces, diagnoses, and removes one personal marker
  provider.
- [Manage Multiple Buffers](manage-multiple-buffers/index.md) creates named
  buffers, opens or reuses local files, switches by complete selection label,
  operates the Buffer Menu, executes marked saves and kills, and explains
  startup, exit, and programmable-boundary validation.
- [Open Dirs](open-dirs/index.md) opens or replaces a filesystem root without
  creating Project metadata, navigates its files, and diagnoses Project-scope
  rejection.
- [Promote Dirs to Projects](promote-dirs/index.md) creates explicit local
  Project identity and handles promotion decisions when leaving a Dir.
- [Migrate Legacy Project State](migrate-project-workspaces/index.md) previews
  and explicitly applies the source-preserving conversion from global
  multi-dir records to local Projects and global Workspaces.
- [Manage Pane Layouts](manage-pane-layouts/index.md) splits, focuses, closes,
  resizes, balances dimensions or pane areas, changes and displays buffers,
  coordinates buffer kill, maximizes terminal panes, and recovers a preserved
  tree after external geometry becomes insufficient.
- [Manage Maksym Changes](manage-maksym-files/index.md) prepares, applies,
  cancels, and recovers checked editable filename changes.
- [Troubleshoot Darek](troubleshoot-darek/index.md) recovers unavailable roots,
  narrow panel geometry, preview limitations, rejected file operations, and
  unexpected effective bindings.
- [Configure Other-Pane Display Policy](configure-pane-display-policy/index.md)
  replaces the bounded automatic destination order and split thresholds
  through the checked embedded Racket boundary.
- [Validate Pane Layouts](validate-pane-layouts/index.md) selects fast native,
  runtime-only, focused acceptance, resource, and complete repository gates
  without repeating the same layout suites.
- [Configure a Runtime Keymap Profile](configure-keymaps/index.md) constructs
  checked Racket maps and operations, stages one complete session candidate,
  preserves contextual prompt and shared-list behavior, and validates
  transactional reload, rollback, `M-x` discovery, availability, and active
  binding reinforcement, protected recovery, and copied inspection.
- [Manage a Project Root](manage-project-directories/index.md) opens and
  inspects a one-root Project, operates on its content, and uses Workspaces for
  multi-root composition.
- [Inspect Project Discovery](manage-project-catalog/index.md) compares global
  discovery references with authoritative local Project records.
- [Manage Project Trust and Refresh](manage-project-trust/index.md) explains
  one-root trust, admitted local configuration, and root reconciliation.
- [Operate on Project Content](operate-on-project-content/index.md) navigates
  Project files, directories, and buffers; performs scoped save, close, and
  refresh operations; and discovers the factory Project commands.
- [Validate the Extensible UI Foundation](validate-extensible-ui-foundation/index.md)
  runs the independent lifecycle model, generated production equivalence,
  representation study, focused package checks, documentation gate, and full
  repository validation.
- [Validate Programmable UI Roles](validate-programmable-ui-roles/index.md)
  checks schemas, Racket contracts, provider replacement, fallback,
  mixed-language containment, resource profiles, and teardown.
- [Inspect Interaction Profile Compatibility](inspect-interaction-profile-compatibility/index.md)
  diagnoses active and inactive catalog definitions, binding scopes, shared
  selectors, state admission, command-entry surfaces, and rejected candidates.
- [Configure and Validate Factory Syntax Presentation](configure-factory-syntax-presentation/index.md)
  selects terminal color capability, inspects active analysis, reproduces
  pinned dependencies, and runs parser, resource, and terminal acceptance.
- [Use and Validate Structured Syntax](use-structured-syntax/index.md) runs the
  six factory commands, inspects exact structural state and rejection, and
  selects focused native, Racket, PTY, and repository validation gates.
- [Use and Diagnose Jan Documents](use-jan-documents/index.md) opens `.org` and
  `.jan` through one factory language, inspects and lints current syntax,
  verifies exact saves, and distinguishes unavailable later-stage behavior.
- [Select, Inspect, and Validate Themes](select-and-inspect-themes/index.md)
  selects confirmed factory or admitted themes, reads copied state, recovers
  from rejection, and runs focused terminal acceptance.
- [Set Up and Diagnose Language Services](use-language-services/index.md)
  installs and configures maintained or external servers, defines the Go,
  Rust, TypeScript, JavaScript, HTML, and CSS base pack, checks Project trust,
  interprets copied health, recovers failures, and selects focused or complete
  acceptance.
- [Manage Language Bundles](manage-language-bundles/index.md) inspects,
  installs, enables, updates, rolls back, disables, removes, and recovers
  bundles through factory-owned commands.
- [Manage Package Catalogs](manage-package-catalogs/index.md) enrolls,
  configures, refreshes, disables, replaces, removes, and diagnoses explicit
  catalog trust roots and endpoints.
- [Acquire a Package Manually](acquire-a-package-manually/index.md) resolves an
  exact directory, artifact, or Git revision without fabricating curation or
  activation.
- [Curate a Package Release](curate-a-package-release/index.md) bootstraps the
  public curator kit, records attributable evidence and a human decision, and
  prepares deterministic offline-signed publication.
- [Respond to Package Advisories](respond-to-package-advisories/index.md)
  inspects separately trusted advice and applies bounded local response,
  correction, override, and recovery policy.
- [Operate and Diagnose Local Agents](operate-local-agents/index.md) discovers
  agents, decides requests, cancels work, follows reconciliation, and inspects
  attributable audit history.
- [Author and Validate an Agent Package](author-agent-packages/index.md)
  defines agent and capability packages, runs generic conformance, exercises
  lifecycle failures, and prepares compatible updates.
- [Diagnose Language Support](diagnose-language-support/index.md) separates
  selector, syntax, service, formatter, trust, capability, lifecycle, and
  resource failures and applies the reported recovery.
- [Author a Language Bundle](author-language-bundles/index.md) starts from the
  public template, declares bounded contributions, validates conformance, and
  creates a deterministic archive.
- [Configure and Diagnose Language Completion](configure-language-completion/index.md)
  requests candidates, adjusts factory invocation and filtering, inspects
  current state, and recovers unavailable provider sessions.
