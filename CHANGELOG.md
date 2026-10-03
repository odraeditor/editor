<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Changelog

All notable changes to this project are documented here.

This project uses Semantic Versioning.

## Unreleased

## 0.2.0 - 2026-10-03

### Added

#### Structured documents and knowledge

- Jan provides structured editing for `.org` and `.jan` documents, including
  outline folding, structural navigation, lists, drawers, blocks, tables,
  footnotes, planning, agendas, clocks, capture, computation, export, source
  blocks, contextual actions, and reversible edits.
- Roman is available as the optional `odra.roman` package for linked knowledge
  work. It provides persistent Project indexes, node and alias search, stable
  links, references, relations, graph inspection and export, metadata editing,
  capture, daily notes, and SQLite-backed derived state while Jan files remain
  canonical.

#### Language support

- The basic language pack supports Jan, Odin, Racket, Go, Rust, TypeScript,
  JavaScript, HTML, and CSS. Local syntax presentation works independently of
  language servers, while configured servers can provide completion,
  diagnostics, navigation, formatting, and checked workspace edits.

#### Packages and agents

- Package catalogs support official and independently configured sources,
  verified releases, offline operation, attributed curation, advisories, and
  explicit trust decisions. Packages can be installed inactive, enabled,
  updated, rolled back, disabled, and removed.
- Installable agent packages can define deterministic or provider-backed
  agents with scoped grants, durable tasks and interactions, checked editor
  capabilities, typed results, audit records, cancellation, revocation, and
  restart recovery.

#### Files and version control

- Darek can show or hide hidden and ignored entries, sort and filter directory
  trees, refresh changed files, and display version-control and diagnostic
  decorations without losing the current selection.
- Ksawery provides full-canvas repository status, path and hunk staging,
  guarded discard, commit and history inspection, branches, tags, remotes,
  fetch and push, merge, rebase, cherry-pick, revert, bisect, conflicts,
  stashes, worktrees, reflog, blame, progress, cancellation, and retained
  process results.

#### Editing and interaction

- The optional Modal interaction profile provides Normal, Insert, Visual
  Character, and Visual Line states, counts, operators, search, text transfer,
  history, pane navigation, command entry, and terminal copy navigation.
  Direct interaction remains the default.
- Personal configuration can choose tabs or spaces and define logical
  indentation width separately from literal-tab display width, with Project,
  file-type, language, profile, and buffer-local overrides.
- Unsaved-work recovery checkpoints modified file-backed and pathless buffers.
  Startup recovery can inspect, compare, restore, or discard valid candidates
  and reports conflicts before touching source files.
- Commands, saves, recovery, language services, Projects, packages, and
  long-running operations use consistent feedback surfaces with measurable
  progress, diagnostic detail, cancellation, and portable fallbacks.

### Changed

#### Terminals

- Integrated terminals open below the editor by default and participate in
  ordinary pane navigation. Reopening reuses the lower pane; hiding it keeps
  the shell running and restores editing focus.

#### Interaction

- Equivalent operations across Core, Maksym, Darek, Ksawery, Jan, Jan source
  blocks, and Roman use familiar command identities and bindings. Documented
  deviations preserve Odra's safety and ownership rules.

#### Structured documents and packages

- Jan activates structured-document bindings only in `.org` and `.jan`
  buffers. Roman contributes its `C-c n` family only while the package is
  enabled and removes its commands and bindings when disabled.
- `package-discover` opens confirmed releases as a filterable candidate list.
  Selecting a release carries its exact identity into installation and shows
  the requested authorities in a single activation confirmation.

### Fixed

#### Structured documents and knowledge

- Jan outline cycling visibly folds subtree lines, and contextual checklist
  actions work from any position on the item line as one undoable edit.
- Roman node, alias, reference, relation, daily-note, link, metadata, and graph
  workflows provide navigable choices, preserve editing location and undo
  boundaries, and report usable graph destinations or textual fallback.
- Roman's personal brain uses one configured directory across Projects and
  standalone documents. Changing Projects no longer changes its corpus or
  capture and daily-note destinations.

#### Editing and interface

- Startup recovery no longer interrupts an unrelated file or Project. Other
  unsaved work remains available through `recover-unsaved-work`, and cancelling
  review returns to the file or directory you opened.
- Multi-key commands keep their original keymap owner while language or
  component bindings are active, so commands such as `C-x C-c` remain
  reliable after opening a Project file.
- Exiting the final integrated terminal returns to an editable scratch buffer
  instead of terminating Odra with a terminal-workflow error.
- Repeated Modal Replace changes work after returning to Normal, and command
  navigation launched from a terminal uses the correct editor context.
- Backspace respects logical indentation boundaries, while explicit
  normalization converts leading indentation to tabs or spaces without
  changing interior alignment.
- Pointer interaction selects the exact Darek row or represented buffer text,
  transfers keyboard focus only after a valid transition, and keeps drag
  selection out of gutters, separators, status rows, and neighboring panes.

#### Packages

- Package activation no longer closes Odra when personal configuration is
  absent, and the built-in official catalog refreshes from its public signed
  endpoint without user credentials.

## 0.1.0 - 2026-09-01

### Added

#### Editing and navigation

- Direct navigation and editing bindings cover graphemes, lines, words,
  indentation, pages, and overwrite input while prompts and lists retain their
  contextual behavior.
- Local document workflows open UTF-8 files, save associated documents, choose
  paths for new buffers, and protect unsaved work on exit.
- Multiple live buffers retain cursor and undo state, support full-path file
  selection, and provide a Buffer Menu for marked save and close operations.
- Point, mark, and active-region commands provide visible selection and restore
  the complete selection through editing history.
- Copy, cut, delete, paste, and paste rotation use a bounded internal kill ring
  with optional system clipboard integration.
- Forward and backward incremental search supports literal text and regular
  expressions, history, case and boundary controls, replace-all, interactive
  query replacement, result navigation, and Project-wide search.
- Symbol-at-point search and the active-buffer symbol navigator provide typed
  filtering, checked visits, return-location history, and a generic Unicode
  fallback.
- Reversible editing includes semantic typing groups, undo and redo, alternate
  history branches, selective undo, configurable retention, and atomic history
  across multiple buffers.
- Atomic command transactions publish every admitted edit together or leave
  all affected buffers unchanged.
- Candidate navigation covers commands, buffers, documents, Project files,
  Projects, Workspaces, filesystem paths, named locations, and stored values
  with incremental matching and stable selection.

#### Buffers, panes, and terminals

- Integrated terminal sessions provide independent local PTYs, terminal-backed
  buffers, full-screen input, retained copy and navigation, Workspace defaults,
  and coordinated cleanup.
- Interactive terminal editing supports Unicode-aware cursor movement, text
  insertion and deletion, scrolling, and visible status information.
- Multiple terminal panes support horizontal and vertical splits, independent
  cursor and viewport positions, pane-local history, focus movement, closing,
  maximizing, and recovery when the terminal becomes too small.
- Pane controls display buffers elsewhere, dedicate panes, resize them one cell
  at a time, balance dimensions or visible areas, and expose layout behavior to
  Racket configuration.

#### Files, Projects, and Workspaces

- Project contexts support temporary or durable directory membership, named
  catalogs, trusted local configuration, scoped file and buffer operations,
  refresh, and close workflows.
- Directory-first opening navigates ordinary filesystem roots without creating
  Project metadata, while registered Projects retain Project-specific trust,
  configuration, commands, and language services.
- One-root local Projects and ordered multi-Project Workspaces replace the
  global multi-directory Project lifecycle with source-preserving migration.
- Darek provides a persistent side panel with lazy directory trees, semantic
  icons, keyboard navigation, Project and Workspace roots, file visits,
  creation, rename, move, copy, confirmed deletion, preview, adjustable
  placement, Project narrowing, directory compression, and contextual help.
- Maksym provides directory buffers with fuzzy opening and entry jumps,
  detailed or simplified listings, refresh and sorting, split-pane placement,
  and reviewed rename, move, and deletion batches.

#### Language intelligence

- Eligible Project documents can request language completion with incremental
  filtering, candidate detail, atomic edits, undo and redo, personal
  configuration, inspection, cancellation, and contained provider failure.
- Trusted Projects can start an external language service, synchronize
  documents, present and navigate current diagnostics, inspect service health,
  and request a contained restart while unavailable servers leave editing
  usable.
- Odin files receive automatic incremental syntax presentation with semantic
  terminal colors, state inspection, and plain-text fallback.
- Odin structural editing provides named-node movement, expanding selection,
  reversible grammar-aware indentation, direct and `M-x` commands, and
  plain-text fallback.

#### Interface

- Logical line numbers support absolute, relative, and hybrid modes, current
  line presentation, left or right placement, per-view commands, and automatic
  hiding in narrow panes.
- The Gutter presents diagnostics and clipping indicators with collision
  handling, terminal-safe glyphs, detail popups, inspection, refresh, primary
  actions, and programmable providers.
- Pane-local Status Bars present buffer, document, pane, Workspace, Project,
  language-service, diagnostic, size, path, position, and progress information
  with compact layouts for narrow panes.
- Shared programmable presentation covers panes, status, Startup, Buffer Menu,
  candidate navigation, Project inventory, keymap inspection, prompts, search,
  replacement, and diagnostics with native fallback behavior.
- Session-wide themes include four Wrocław palettes and a color-minimal
  terminal baseline with command selection, inspection, full-view updates, and
  safe fallback after rejected definitions.

#### Configuration and programmability

- Personal Racket commands loaded from `init.rkt` support `M-x` discovery,
  text inspection and replacement, one-unit undo, personal keybindings, live
  reload and deactivation, resource limits, state inspection, and contained
  failures.
- In-process Racket configuration controls commands, search policy, history
  retention, text transfer, buffer operations, keymaps, and Project behavior.
- Layered contextual keymaps provide protected, shared, and profile-specific
  binding scopes plus `M-x` discovery for native and Racket commands.

### Fixed

#### Editing and documents

- Tab inserts one policy-sized indentation unit in editable buffers while
  prompts, candidate lists, and tree surfaces retain their contextual action.
- Home and End keys work in ordinary and terminal application modes.
- CRLF documents render without exposing carriage-return artifacts.
- Clipboard export works correctly through supported terminal multiplexers.
- Rejected or stale interactive operations preserve the prior editor state
  instead of publishing partial changes.

#### Interface

- Colored themes cover the complete terminal canvas, including empty rows and
  cells beyond rendered text.
- Colored themes apply their selection background to active text regions.
- List selections remain inside their interface surface instead of extending
  into the surrounding canvas.

#### Language intelligence

- Odin syntax presentation preserves distinct styles for functions,
  parameters, comments, types, variables, constants, and macros.

#### Layout and Projects

- Pane splitting remains available under ordinary process stack limits instead
  of terminating the editor.
- Directory promotion and abandonment prompts retain their selected root,
  display all decisions, and complete from either an editor view or Startup.
