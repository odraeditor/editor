<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Racket Runtime Boundary Reference

The Odin bridge declarations are authoritative for copied native layouts,
limits, and callback operation codes. Racket contracts declare the dynamic
API and validate their local codec expectations against the native schema at
startup. Generate the Odin package documentation with:

```sh
odin doc src/hosting -in-source-order
odin doc src/bridge -in-source-order
odin doc src/command -in-source-order
```

## Package responsibilities

| Package | Responsibility | Does not own |
| --- | --- | --- |
| `hosting` | Racket CS lifecycle, owner thread, exception barrier, one scoped capability transport, rooted procedures, and copied values | Buffers, editor publication, or domain codecs |
| `bridge` | Fixed-capacity capabilities, generation checks, fixed transfer, search, buffer-session, and UI-role records, and explicit release | Racket lifecycle or command policy |
| `command` | Built-in declarations, keymap activation, transfer, search, buffer-session, and UI-role authority, bounded native and Racket turns, and coordinated shutdown | Package installation or scheduling |
| `transaction` | Private revisions, command composition, validation, normalized changesets, and publication authority | Racket runtime or feature-command policy |
| `editor` | Canonical text, revisions, working-revision storage, and reserved publication primitives | Racket values or native-boundary lifecycle |

## Runtime lifecycle

| Phase | Accepted operation | Next phase |
| --- | --- | --- |
| `Uninitialized` | `runtime_start` | `Ready` or terminal `Failed` |
| `Starting` | No external operation | `Ready` or `Failed` |
| `Ready` | Checked calls or `runtime_shutdown` | `Ready`, `Stopping`, or `Failed` |
| `Stopping` | No new operation | `Stopped` or `Failed` |
| `Stopped` | None | Terminal |
| `Failed` | None | Terminal |

The thread that calls `runtime_start` owns every later Racket entry and
shutdown. Wrong-thread and nested calls are rejected before entering Racket.
The runtime cannot restart after failure or shutdown.

### Startup contract schema

`bridge.NATIVE_CONTRACT_SCHEMA_VERSION` identifies the complete startup
contract. Odin serializes a fixed little-endian manifest containing every
published record width, aggregate limit, callback operation value, and failure
code used by the programmable boundaries. The current schema version is `15`.

`src/command/native-contracts.rkt` is the single Racket declaration of the
corresponding codec expectations. `runtime-start` validates the complete
manifest before the adapter roots or exposes any capability procedure. A
version, width, limit, operation, unknown-entry, duplicate-entry, missing-entry,
or exact-size mismatch leaves the runtime in `Failed` with a diagnostic bounded
by the native runtime buffer. No command turn is admitted after that failure.

Variable-length records retain concern-owned arithmetic and parsing. Their
fixed widths and maxima come from the validated contract table; each codec
still rejects truncated data, excess counts, invalid ranges, and non-exact
aggregate sizes before constructing a result or changing editor state.

### Scoped capability transport

Transaction, transfer, search, buffer-session, layout, UI-role, theme,
structural, language-service, and result-provider facades share one internal callback
transport. Each active turn binds a capability kind,
monotonically advancing transport generation, opaque domain token, owner
thread, optional domain context, and one fixed result envelope. The C adapter
accepts only one active transport turn and clears its callback and caller-owned
pointer before returning.

The common transport rejects wrong-kind, stale-generation, wrong-token,
cross-thread, nested, escaped, and post-release calls before a domain handler
can consume input. It initializes the fixed result envelope on every admitted
ABI call and rejects byte results larger than the caller-provided output
capacity. Domain modules remain responsible for operation identifiers, record
codecs, capability permissions, resource ceilings, and semantic failures.

## Hosting declarations

| Declaration | Contract |
| --- | --- |
| `Runtime` | Owns the process-long Racket CS state and bounded diagnostic buffer. |
| `Scoped_Capability_Kind` | Identifies the concern facade using the shared transport. |
| `Scoped_Capability_Callback_Procedure` | Receives one checked kind, active generation, token, domain context, operation, copied payload, and fixed result envelope. |
| `runtime_start` | Boots Racket, validates the native contract schema and module startup, then roots cached procedures. |
| `runtime_call_scalar` | Performs the checked scalar proof and contains Racket exceptions. |
| `runtime_command_inspection_request` | Passes only scalar capability metadata and receives one byte range. |
| `runtime_command_transform` | Copies input into Racket and copies one replacement request back to Odin. |
| `runtime_load_keymap_profile` | Copies one complete bounded interaction-profile catalog into caller-owned fixed records. |
| `runtime_load_command_catalog` | Copies one complete bounded Racket command catalog into caller-owned fixed records. |
| `runtime_uppercase_current_line` | Invokes the rooted current-line command and copies its checked result. |
| `runtime_transaction_probe` | Lends one opaque transaction token to Racket for one contained synchronous turn. |
| `runtime_transaction_command` | Executes the production facade-backed Racket command while Odin retains commit authority. |
| `runtime_transfer_probe` | Lends one opaque transfer token and callback for a single synchronous dynamic extent. |
| `runtime_search_probe` | Lends one opaque search token and callback for a single synchronous dynamic extent. |
| `runtime_buffer_session_probe` | Lends one opaque buffer-session token and callback for a single synchronous dynamic extent. |
| `runtime_layout_probe` | Lends one opaque layout token and callback for a single synchronous dynamic extent. |
| `runtime_ui_role_probe` | Lends one opaque UI-role token and callback for a single synchronous dynamic extent. |
| `runtime_theme_probe` | Lends one opaque theme token and callback for a single synchronous dynamic extent. |
| `runtime_structural_probe` | Lends one opaque structural token and callback for a single synchronous dynamic extent. |
| `runtime_language_service_probe` | Lends one opaque language-service token and callback for a single synchronous dynamic extent. |
| `runtime_result_probe` | Lends one opaque result-provider token and callback for a single synchronous dynamic extent. |
| `runtime_project_directory_resolution`, `runtime_project_catalog_resolution` | Resolve copied Project directory and catalog observations. |
| `runtime_personal_configuration_startup` | Loads one bounded personal-configuration startup observation. |
| `runtime_project_promotion`, `runtime_project_unregister`, `runtime_promotion_suppression` | Execute copied Project lifecycle batches. |
| `runtime_workspace_command` | Executes one copied Workspace management batch. |
| `runtime_named_location_command`, `runtime_named_slot_command` | Execute copied saved-state batches. |
| `runtime_candidate_usage_load`, `runtime_candidate_usage_publish` | Load or publish bounded candidate history. |
| `runtime_shutdown` | Releases procedure roots, calls built-in cleanup, and deinitializes Racket CS. |
| `runtime_state` | Returns the current synchronous lifecycle phase. |
| `runtime_diagnostic` | Returns a runtime-owned view valid until the next operation. |

`Failure_Code` distinguishes lifecycle state, wrong thread, reentrancy,
runtime availability, Racket exception, and malformed result failures.

## Capability declarations

| Declaration | Contract |
| --- | --- |
| `Buffer_Capability` | Opaque 64-bit non-pointer token. |
| `Buffer_Capability_Registry` | Holds at most 64 live native buffer references. |
| `buffer_capability_registry_init` | Initializes one zero-value registry with a nonzero identity. |
| `buffer_capability_acquire` | Registers one live buffer and returns a token plus identity snapshot. |
| `buffer_capability_inspect` | Checks registry, generation, buffer, revision, and range before copying bytes. |
| `buffer_capability_splice` | Revalidates the capability and enters canonical editor publication. |
| `buffer_capability_release` | Consumes one exact-generation token without closing the buffer. |
| `buffer_capability_registry_close` | Closes only an empty registry and then becomes terminal. |
| `Transaction_Capability` | Opaque 64-bit non-pointer token for one command-scoped root transaction. |
| `Transaction_Capability_Registry` | Holds at most eight live transaction references in fixed storage. |
| `transaction_capability_acquire` | Binds one building root to registry, generation, command, and owner-thread identity. |
| `transaction_capability_inspect` | Copies bounded read-your-writes text from the private revision. |
| `transaction_capability_apply_batch` | Copies and validates fixed-layout batch records before private application. |
| `transaction_capability_splice` | Applies one sequential edit in current private coordinates. |
| `transaction_capability_nested_begin` | Creates one checked native savepoint for nested command composition. |
| `transaction_capability_nested_finish` | Joins or restores the current nested command and consumes its handle. |
| `transaction_capability_request_abort` | Requests root cancellation without granting commit authority. |
| `Transfer_Scope_Record` | Fixed 88-byte little-endian scalar identity record with no pointer fields. |
| `Transfer_Region_Record` | Fixed 128-byte copied point, mark, activation, and ordered-range record. |
| `Transfer_Ring_Header_Record` | Fixed 104-byte scope and occupancy header. |
| `Transfer_Ring_Entry_Record` | Fixed 40-byte copied retained-entry metadata record. |
| `Search_Scope_Record` | Fixed 96-byte search authority and generation identity. |
| `Search_Policy_Record` | Fixed 248-byte complete behavior and resource policy. |
| `Search_Session_Header_Record` | Fixed 568-byte header for bounded copied session arrays and text. |
| `Search_Occurrence_Record`, `Search_Capture_Record` | Fixed 48-byte and 24-byte copied match metadata. |
| `Search_Command_Request_Header_Record` | Fixed 264-byte semantic request and complete policy header. |
| `Search_Command_Result_Record` | Fixed 256-byte copied completion and resource-usage result. |
| `Result_Scope_Record` | Fixed 48-byte result-registry and generation identity. |
| `Result_Publication_Header_Record`, `Result_View_Header_Record` | Fixed 264-byte publication and 336-byte inspection headers. |
| `Result_Location_Record`, `Result_Group_Record` | Fixed 88-byte location and 24-byte group metadata. |
| `Result_Movement_Request_Record`, `Result_Outcome_Record` | Fixed 56-byte movement request and 96-byte copied outcome. |
| `Buffer_Session_Scope_Record` | Fixed 136-byte editor, authority, session, registry, and visible-target identity. |
| `Buffer_Session_Usage_Record` | Fixed 240-byte scope and exact aggregate accounting result. |
| `Buffer_Session_Descriptor_Header_Record`, `Buffer_Session_Descriptor_Record` | Fixed 152-byte header and 168-byte complete entry projection. |
| `Buffer_Session_Request_Header_Record`, `Buffer_Session_Decision_Record` | Fixed 264-byte request header and 72-byte marked decision. |
| `Buffer_Session_Outcome_Record` | Fixed 320-byte refreshed scope and copied lifecycle result. |
| `Structural_Scope_Record`, `Structural_Request_Record` | Fixed 160-byte authority scope and 200-byte generated request. |
| `Structural_Target_Record`, `Structural_Plan_Record` | Fixed 208-byte target and 224-byte indentation-plan headers with bounded trailing copies. |
| `Structural_Outcome_Record`, `Structural_Diagnostic_Record` | Fixed 264-byte refreshed result and 112-byte diagnostic header. |
| `Candidate_History_Load_Header_Record`, `Candidate_History_Entry_Record` | Fixed 64-byte observation header and 32-byte category, key-range, and sequence entry. |
| `Candidate_History_Publish_Header_Record` | Fixed 48-byte generation, entry-count, text-width, and expected-generation request. |
| `Candidate_History_Publication_Record` | Fixed 48-byte visible publication and synchronization result. |

A token encodes registry identity, a 32-bit generation, and a bounded slot.
It never encodes or exposes an Odin allocation address. A slot at maximum
generation is retired. Transaction resolution additionally checks transaction
identity, command identity, dynamic extent, owner thread, reentrancy, and
lifecycle.

## Command declarations

| Declaration | Contract |
| --- | --- |
| `MAX_COMMAND_TEXT_BYTES` | Limits each inspected input and replacement to 4 KiB. |
| `buffer_command_run` | Runs at most two Racket calls and publishes at most one splice. |
| `buffer_command_shutdown` | Requires an empty capability registry before stopping Racket. |
| `built_in_base_command_definitions` | Returns the native and contextual base declarations composed with the admitted Racket catalog. |
| `racket_profile_reload` | Transfers and atomically activates one complete Racket-defined interaction-profile catalog. |
| `racket_command_execute` | Runs one bounded Racket command against a private transaction capability. |
| `Transfer_Capability_Context` | Borrows exact native owners and grants an immutable operation set for one programmable turn. |
| `transfer_capability_scope` | Captures editor, authority, view, buffer, ring, and command-registry identities and generations. |
| `racket_transfer_turn` | Runs one contained Racket selection or transfer composition over copied records. |
| `Search_Capability_Context` | Borrows exact native owners and grants policy inspection, session inspection, or semantic invocation. |
| `search_capability_scope` | Captures editor, authority, view, buffer, command-registry, interaction, and policy generations. |
| `racket_search_turn` | Runs one contained Racket search or replacement composition over copied bounded records. |
| `Result_Capability_Context` | Borrows one exact result registry and grants immutable inspection, publication, and movement authority. |
| `result_capability_scope` | Captures the current result registry, set, generation, and selection identity. |
| `racket_result_turn` | Runs one contained Racket result-provider composition over copied bounded records. |
| `Buffer_Session_Capability_Context` | Borrows the native session coordinator and grants an immutable operation set for one programmable turn. |
| `buffer_session_capability_scope` | Captures editor, authority, session, registry, and visible-target generations. |
| `racket_buffer_session_turn` | Runs one contained Racket buffer-session composition over copied bounded records. |
| `Structural_Capability_Context` | Borrows one exact structural editor and grants immutable inspection and operation authority. |
| `structural_capability_scope` | Captures editor, analysis, registry, authority, and capability generations. |
| `racket_structural_turn` | Runs one contained Racket structural composition over copied bounded records. |
| `Command_Result` | Retains the checked transaction publication and copied byte counts until explicit close. |

The command sequence is begin, acquire capability, enter Racket, compose private
edits, release capability, validate, then publish. No Racket call occurs after
publication begins.

## Racket module map

The Racket tree is organized by stable responsibility. A module may export a
contracted subsystem API without becoming a user-extension API; the intended
consumer is explicit below.

### Runtime and hosting boundary

| Location | Canonical responsibility | Intended consumers |
| --- | --- | --- |
| `src/hosting/runtime-boundary.rkt` | Complete production procedure manifest rooted by the adapter | C adapter only |
| `src/hosting/runtime.rkt` | Process-long Racket lifecycle and startup schema validation | Runtime boundary |
| `src/hosting/scoped-capability.rkt` | Sole callback FFI lookup, dynamic extent, owner-thread checks, non-reentrancy, and result envelope | Concern facades and hosting bridges |
| `src/hosting/*-bridge.rkt` | Fixed-record conversion for one concern; no domain policy or canonical state | Runtime boundary |
| `src/command/native-contracts.rkt` | Racket expectations for the native schema | Runtime and every record codec |

`runtime-boundary.rkt` is an explicit manifest, not an arbitrary re-export
module. Adding or removing a procedure rooted by the native adapter requires a
corresponding edit there.

The maintained local Project-search provider stays entirely on the native side
of this boundary so filesystem traversal and matching do not require one
Racket crossing per file or match. Its published locations enter the same
result-set owner used by admitted Racket result providers. User extensions may
provide analogous search commands through copied result-provider records, but
they do not receive Project registries, filesystem walkers, source owners, or
native pointers.

The concern bridges have one predictable owner:

| Concern | Hosting bridge |
| --- | --- |
| Command catalog and keymap profiles | `command-catalog-bridge.rkt`, `keymap-profile-bridge.rkt` |
| Buffer sessions, layouts, UI roles, and themes | `buffer-session-bridge.rkt`, `layout-bridge.rkt`, `ui-role-bridge.rkt`, `theme-bridge.rkt` |
| Structural and language-service providers | `structural-bridge.rkt`, `language-service-bridge.rkt` |
| Result providers | `result-provider-bridge.rkt` |
| Project opening and lifecycle | `project-opening-bridge.rkt`, `project-promotion-bridge.rkt` |
| Workspaces and named state | `workspace-bridge.rkt`, `named-location-bridge.rkt`, `named-slot-bridge.rkt` |
| Personal configuration and candidate history | `personal-configuration-bridge.rkt`, `candidate-usage-bridge.rkt` |

All paths in this table are under `src/hosting/`.

### Commands and keymaps

| Location | Canonical responsibility | Intended consumers |
| --- | --- | --- |
| `src/command/catalog.rkt` | Racket command definitions, metadata, provenance, catalog composition, and Racket dispatch | Command-catalog bridge and command authors |
| `src/command/keymap-model.rkt` | Immutable typed keys, sequences, bindings, maps, profiles, composition, and validation | Keymap authors and facade |
| `src/command/builtins.rkt` | Shipped interaction-profile and binding definitions | Keymap facade only |
| `src/command/keymaps.rkt` | Canonical keymap facade, staged candidates, and factory profile catalogs | Keymap-profile bridge and configuration code |
| `src/command/keymap-inspection.rkt` | Copied keymap inspection requests and results | Command catalog and bridge |
| `src/command/transaction.rkt` | Transaction capability facade | Racket editing commands |
| `src/command/transfer.rkt`, `search.rkt`, `buffers.rkt`, `structural.rkt`, `language-services.rkt`, `results.rkt` | Concern-specific programmable command facades and copied values | Command implementations and hosting bridges |
| `src/command/search-bridge.rkt` | Low-level search record transport behind `search.rkt` | Search facade only |
| `src/command/transform.rkt` | Original bounded transform boundary retained by the runtime contract | Runtime boundary |

Command identities are semantic. Racket supplies programmable definitions and
implementations; Odin validates the complete candidate catalog, owns the active
registry, resolves keymaps, admits invocation, and publishes effects.

### Configuration and policies

| Location | Canonical responsibility | Intended consumers |
| --- | --- | --- |
| `src/configuration/platform-roots.rkt` | Platform configuration, state, cache, package-data, Project-catalog, and legacy Project root policy | Startup boundary and semantic root consumers |
| `src/configuration/root.rkt` | Configuration-root path derivation and path classification | Configuration domains |
| `src/configuration/personal.rkt` | Bounded `init.rkt` observation, syntax validation, reload proposal, and diagnostics | Personal-configuration bridge |
| `src/history/configuration.rkt` | Copied history-policy configuration exchange | Runtime boundary |
| `src/history/navigation.rkt` | Navigation-history intent helpers | History consumers |
| `src/layout/display-policy-configuration.rkt` | Copied display-policy configuration exchange | Runtime boundary |

Personal configuration loading currently validates and transfers a Racket
module proposal. It is not a general-purpose evaluator for arbitrary editor
extensions yet.

### Operational state and storage

| Location | Canonical responsibility | Intended consumers |
| --- | --- | --- |
| `src/project/records.rkt` | Project record data and codecs | Project persistence and bridges |
| `src/project/persistence.rkt` | Local Project identity and global discovery persistence | Project operations |
| `src/project/promotion.rkt`, `promotion-suppressions.rkt` | Promotion, inspection, and prompt-suppression behavior | Project bridge |
| `src/project/candidate-usage.rkt` | Bounded canonical candidate-recency state | Candidate-usage bridge |
| `src/workspace/records.rkt`, `persistence.rkt`, `management.rkt` | Workspace records, durable storage, and composition operations | Workspace bridge |
| `src/saved-state/records.rkt`, `persistence.rkt` | Shared named-state record and durable catalog | Named-state modules |
| `src/saved-state/named-locations.rkt`, `named-slots.rkt`, `named-layouts.rkt` | Domain behavior for locations, typed slots, and layout snapshots | Named-state bridges and commands |
| `src/migration/records.rkt`, `persistence.rkt`, `planner.rkt`, `executor.rkt` | Journal, deterministic planning, and explicit migration publication | Migration command path |
| `src/migration/legacy-inventory.rkt`, `private/legacy-catalog.rkt`, `private/legacy-records.rkt` | Read-only legacy discovery and private legacy codecs | Migration subsystem only |
| `src/storage/record-codec.rkt` | Deterministic Racket-module record encoding and decoding | Persistence modules |
| `src/storage/record-store.rkt` | Domain-neutral catalog and generation storage | Persistence modules |
| `src/storage/durable-file.rkt` | Sole production POSIX FFI for staged write, sync, rename, and cleanup | Record store and persistence modules |

Domain modules own record meaning, validation, recovery policy, and paths.
Storage modules own only reusable encoding and durable publication mechanics.

Subsystem APIs use `contract-out` contracts and guarded structure exports. The
C adapter still validates returned shapes and bounds: contract failure is a
Racket exception, and the native ABI cannot trust a dynamic representation.

## Public and internal boundaries

The current Racket APIs have four distinct audiences:

1. `runtime-boundary.rkt` is private to the embedded adapter and is the only
   production root manifest.
2. Command catalogs, keymap models, and concern facades are subsystem APIs for
   built-in programmable behavior and future supported extensions.
3. Configuration modules expose stable configuration concepts; user files do
   not import hosting internals or raw callback bindings.
4. Hosting bridges, native contracts, storage mechanics, migration-private
   codecs, and test support are internal implementation.

No code outside `src/hosting/scoped-capability.rkt` resolves the native callback
FFI directly. No Racket module owns canonical buffers, views, layouts,
registries, or publication authority.

## Initialization and procedure ownership

Startup has one explicit direction:

1. Odin creates the process-long hosting runtime and supplies the native
   contract manifest.
2. The adapter instantiates the embedded `src/hosting/runtime-boundary.rkt`
   module. `src/hosting/runtime_boundary_manifest.h` declares the matching
   native procedure-root table.
3. `runtime-start` validates schema version `15` and all fixed limits, widths,
   operations, and failure codes before any capability is exposed.
4. The adapter roots the exact procedures declared by its procedure table and
   exported by `runtime-boundary.rkt`.
5. Racket produces copied command catalogs, typed interaction profiles,
   configuration observations, policies, and persisted-domain batches.
6. Odin validates each complete candidate and atomically publishes the active
   native registry or state generation.
7. Later command turns lend one scoped capability, copy inputs and results, and
   return to Odin before native publication begins.
8. Shutdown rejects live capabilities, releases procedure roots, runs Racket
   cleanup, and deinitializes the runtime in native-owned order.

Module loading alone does not register commands, keymaps, or operational
state. Registration and activation happen through these explicit batches.

## Dependency and ownership direction

```text
Racket definition or policy
  -> concern facade or domain module
  -> hosting bridge / scoped capability
  -> C adapter
  -> Odin validation, canonical state, and publication

Racket domain persistence
  -> storage/record-store.rkt
  -> storage/durable-file.rkt
  -> private file publication
```

Odin owns lifecycle, active registries, canonical editor state, native
resources, admission, and commit authority. Racket owns authoring,
composition, policy, copied definitions, and domain-specific operational
records. The built-in provider may use an Odin mechanism while retaining a
Racket facade and semantic command identity; extension providers use the same
admitted semantic contract without acquiring native ownership.

## Common change guide

| Change | Canonical owner | Related boundary |
| --- | --- | --- |
| Change a shipped binding | `src/command/builtins.rkt` | Typed constructors in `keymap-model.rkt` |
| Change keymap representation or composition | `src/command/keymap-model.rkt` | Candidate facade in `keymaps.rkt` |
| Change native key resolution or precedence | `src/interaction/layered_resolver.odin` and `src/interaction/resolver.odin` | Racket supplies only validated candidates |
| Define or change a Racket command | `src/command/catalog.rkt` | Use the relevant concern facade |
| Change native command admission or execution | `src/command/` and `src/interaction/command_catalog.odin` | Keep semantic identities compatible |
| Add a Racket convenience API | The concern module under `src/command/`, `src/configuration/`, or its state domain | Do not add a catch-all helper module |
| Change personal configuration loading | `src/configuration/personal.rkt` | Path policy in `root.rkt`; adapter shape in the personal bridge |
| Add or replace a provider | The semantic concern facade and its hosting bridge | Native provider owner stays in its Odin subsystem |
| Expose a new native primitive to Racket | Concern bridge, `scoped-capability.rkt`, `native-contracts.rkt`, and `runtime-boundary.rkt` | Adapter and native schema must change together |
| Change Project, Workspace, or saved-state persistence | The domain `records.rkt` and `persistence.rkt` | Reuse `src/storage/`; do not move domain policy into it |
| Change initialization | `src/hosting/runtime-boundary.rkt` and `runtime.rkt` | `runtime_boundary_manifest.h`, adapter, and native startup must agree |
| Add tests | Adjacent Racket `module+ test` or concern test module | Add composed Odin tests only for native-boundary behavior |

## Ownership and value lifetimes

| Value | Owner | Valid until |
| --- | --- | --- |
| Racket runtime and cached procedure roots | `hosting.Runtime` | Successful runtime shutdown |
| Native buffer reference | `bridge.Buffer_Capability_Registry` | Exact capability release |
| Capability token | Caller | Release consumes the token or registry lifetime ends |
| Racket transaction session | `call-with-transaction` dynamic extent | The command callback returns or escapes |
| Native transaction capability | `bridge.Transaction_Capability_Registry` | Exact release at command-boundary cleanup |
| Inspection input bytes | Command temporary allocator, then Racket copy | Command turn ends |
| Racket transfer session | Shared scoped transport and `call-with-text-transfer` dynamic extent | The transfer callback returns or escapes |
| Active scoped callback and native user data | C adapter | The owning runtime facade returns |
| Region, ring, and entry results | Racket immutable values copied from Odin | Racket reachability ends |
| Racket search context | `call-with-search` dynamic extent | The search callback returns or escapes |
| Policy, session, occurrence, capture, and command results | Racket immutable values copied from Odin | Racket reachability ends |
| Racket buffer session | `call-with-buffer-session` dynamic extent on its owning Racket thread | The buffer-session callback returns or escapes |
| Scope, handle, descriptor, usage, outcome, UI-root, decision, and failure values | Racket immutable values copied from Odin | Racket reachability ends |
| Replacement bytes | Racket, then command temporary allocator | Publication returns |
| Runtime diagnostic view | `hosting.Runtime` | Next runtime operation |
| Change and undo text | `editor.Buffer` | Next successful splice or buffer close |

## Failure mapping

| Layer | Examples | Canonical effect |
| --- | --- | --- |
| Hosting | Wrong phase, wrong thread, nested entry, Racket exception, wrong envelope | No editor publication |
| Bridge | Wrong registry, stale generation, closed buffer, wrong buffer, stale revision, malformed transfer, search, or buffer-session record | No editor publication |
| Command | Invalid request, authority mismatch, stale view, ring, session, entry, or UI root, copy bound, allocation failure, cancellation, malformed replacement | No unvalidated command effect |
| Transaction | Stale revision, overlap, exhausted budget, invalid capability result, normalization mismatch | Every private participant aborts; no publication |
| Editor | Invalid UTF-8 boundary, resource bound, preparation failure | Prepared resources released; no publication |

Successful publication advances the revision exactly once. Every expected
failure before publication preserves exact canonical text and revision.

## Repository commands

| Command | Scope |
| --- | --- |
| `make hosting-test` | Racket contracts, lifecycle, isolated command scenarios, comparative probes, and startup failures |
| `make command-benchmark` | Ordinary and forced-GC command-turn measurements |
| `make transfer-command-benchmark` | Transfer-boundary latency and zero-retained-storage evidence |
| `make search-command-benchmark` | Search-boundary latency, callback count, and zero-retained-storage evidence |
| `make buffer-session-command-benchmark` | Copied descriptor-batch latency, callback count, and zero-retained-storage evidence |
| `make buffer-session-acceptance` | Generated, resource, mixed-language, benchmark, PTY, accounting, and teardown evidence for multiple buffers. |
| `make hosting-benchmark` | Candidate comparison plus selected command measurements |
| `make hosting-evidence` | Complete focused hosting tests and measurements |
| `make docs-check` | Generated Odin documentation and local Markdown links |
| `make verify` | Full mixed-language repository gate, including documentation checks |

The stable normative contracts are
[`In-Process Racket Runtime Boundary`](../../../ops/default/spec/stable/in-process-racket-runtime-boundary.md),
[`Native and Programmable Provider Pattern`](../../../ops/default/spec/stable/native-and-programmable-provider-pattern.md),
[`Contextual Programmable Keymaps`](../../../ops/default/spec/stable/contextual-programmable-keymaps.md),
[`Configuration System`](../../../ops/default/spec/stable/configuration-system.md),
[`Atomic Edit Transactions`](../../../ops/default/spec/stable/atomic-edit-transactions.md),
and [`Selection and Text Transfer`](../../../ops/default/spec/stable/selection-and-text-transfer.md).
The search boundary is specified by
[`Search and Replacement`](../../../ops/default/spec/stable/search-and-replacement.md).
The buffer-session boundary is specified by
[`Multiple Buffers and Documents`](../../../ops/default/spec/stable/multiple-buffers-and-documents.md).
