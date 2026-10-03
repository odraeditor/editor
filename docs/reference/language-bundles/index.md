<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Bundle Reference

This reference defines the public bundle manifest, Racket authoring API,
catalog and installed-state behavior, commands, bindings, trust boundary,
limits, failures, and compatibility evidence.

## Bundle Manifest

A bundle has one stable identity and one semantic version. It declares:

| Field | Contract |
| --- | --- |
| Identity | Stable lowercase dotted or hyphenated symbol. |
| Display and description | Bounded user-facing text. |
| Version | Semantic version; prerelease identifiers are admitted. |
| API range | Inclusive minimum and maximum Odra bundle API versions. |
| Publisher and source | Stable provenance identities. |
| Targets | Unique `(platform architecture)` pairs for Darwin, Linux, or Windows on AArch64 or x86-64. |
| License and provenance | Copied bounded metadata. |
| Dependencies | Bundle identity, compatible version range, optional flag, facets, and target restrictions. |
| Authorities | Explicit capabilities requested by the bundle. |
| Languages | Stable identity, display name, suffix and filename selectors. |
| Syntax providers | Grammar artifact and symbol, ABI range, query artifacts, captures, injections, resource profile, and authority. |
| Services | Direct command vector, languages, root markers, settings, features, enablement, and default selection. |
| Formatters | Command, language-service, or Racket implementation; roots, scopes, input/output mode, deadline, and output bound. |
| Commands | Semantic identity, description, implementation, requirements, effects, availability, provenance, and optional replacement. |
| Keymaps | Languages, states, context, bindings, precedence constraints, remaps, and provenance. |
| Artifacts | Identity, kind, normalized relative path, SHA-256, byte size, targets, and optional authority. |
| Entrypoint | Optional normalized relative Racket module path. |

The canonical JSON representation is described by
`assets/language-bundles/author-kit/language-bundle.schema.json`. One Racket
entrypoint exports exactly one `odra-language-bundle` value. Loading does not
register contributions.

## Racket Authoring API

Require the author surface with:

```racket
(require odra/language-bundles)
```

It exports immutable constructors for `language-support-bundle`,
`tree-sitter-syntax-provider`, `language-injection`, `language-service`,
`language-formatter`, `language-command`, `language-keymap`,
`language-bundle-artifact`, `language-bundle-dependency`, and
`language-bundle-authority`.

Personal configuration continues to use `(require odra/languages)` and the
`language`, `language-service`, `language-support`, and `language-support-set`
constructors. Both routes normalize to copied semantic records. A higher
precedence definition replaces a complete lower-precedence identity; it does
not patch individual fields.

## Authorities and Trust

Admitted authorities are `racket-extension`, `external-process`,
`project-read`, `project-write`, `network-acquisition`, and `native-grammar`.
An installed or signed bundle receives no authority merely because it exists.
First activation presents the exact authority delta unless prior policy
already grants that publisher and authority set.

Native grammars require `native-grammar`. Language-server launch requires
`external-process` and a trusted Project. Network catalog acquisition is
separate from runtime process and Project access. Bundles never receive raw
grammar pointers, parser cursors, process handles, registries, canonical
buffers, or transaction publication methods.

## Catalogs and Acquisition

Catalog snapshots are bounded, signed, and identified by source and
generation. Resolution selects one exact compatible bundle version and target
deterministically. Acquisition verifies transport result, archive size and
digest, normalized members, manifest and artifact declarations, signature
evidence, dependencies, API range, platform, architecture, and requested
authorities before content enters the immutable store.

Confirmed cached content supports offline restart. A failed refresh does not
replace the last confirmed catalog. Tampered catalog, archive, manifest,
grammar, query, or content fails closed.

## Lifecycle and Durable State

The lifecycle distinguishes `installed-disabled`, prepared activation, active
confirmed content, failed or quarantined candidates, and removed content.
State records carry format and state generations, confirmed lock generation,
installed bundle records, active and previous locks, operations, aggregate
accounting, and a checksum.

Installation publishes verified content without implying activation.
Enablement builds a complete candidate registry and publishes it atomically on
restart. Update retains the prior confirmed version as a rollback target.
Rollback restores that retained predecessor. Disablement removes live
contributions while preserving installed artifacts. Removal drops an
unrequired installed version and its obsolete predecessor reference;
unreachable managed content becomes eligible for garbage collection.

Interrupted or invalid state is reconstructed from confirmed records. A
failure before durable publication changes no installed state. Activation
failure preserves the previous registries and lock. Safe startup uses the last
confirmed generation rather than partially prepared contributions.

## Interactive Commands

| Command | Result |
| --- | --- |
| `describe-language-support` | Inspect effective support for the active document. |
| `describe-language-service` | Inspect the selected service session and negotiated features. |
| `describe-language-bundle` | Inspect one bundle and its lifecycle. |
| `language-support-doctor` | Diagnose selectors, providers, artifacts, executables, trust, resources, and recovery. |
| `language-bundle-list` | List Factory and installed bundles with exact states. |
| `language-bundle-search` | Search confirmed catalog snapshots. |
| `language-bundle-install` | Resolve, review, acquire, verify, and install one exact candidate. |
| `language-bundle-enable` | Review authority and prepare atomic activation. |
| `language-bundle-disable` | Deactivate contributions and preserve installed artifacts. |
| `language-bundle-update` | Prepare and activate one compatible newer version. |
| `language-bundle-rollback` | Restore the retained prior confirmed version. |
| `language-bundle-remove` | Deactivate and remove an unrequired installed version. |
| `language-bundle-refresh-catalogs` | Refresh configured sources without changing installed state. |

Semantic editing commands are `complete-at-point`, `language-show-hover`,
`language-go-to-definition`, `language-find-references`,
`language-document-symbols`, `language-workspace-symbols`,
`language-signature-help`, `language-rename`, `language-format-buffer`,
`language-format-region`, and `language-code-actions`.

## Factory Language Bindings

Completion uses `C-M-i` in Direct editing and Modal Insert state.

| Direct | Modal Normal | Command |
| --- | --- | --- |
| `C-c C-l h` | `K` | `language-show-hover` |
| `C-c C-l d` | `g d` | `language-go-to-definition` |
| `C-c C-l r` | `g r` | `language-find-references` |
| `C-c C-l s` | `g l s` | `language-document-symbols` |
| `C-c C-l S` | `g l S` | `language-workspace-symbols` |
| `C-c C-l n` | `g l n` | `language-rename` |
| `C-c C-l f` | `g l f` | `language-format-buffer` |
| `C-c C-l a` | `g l a` | `language-code-actions` |
| `C-c C-l i` | `g l i` | `describe-language-support` |
| `C-c C-l R` | `g l R` | `restart-language-service` |

Modal Visual Character and Visual Line bind `g l f` to
`language-format-region` and `g l a` to applicable code actions. Management
commands remain discoverable through `M-x` and do not occupy editing keys.

## Basic Pack Capability Matrix

| Language | Selectors | Local syntax | Service | Formatter |
| --- | --- | --- | --- | --- |
| Jan | `.org`, `.jan` | Tree-sitter plus native Jan analysis | none | specialized Jan edits |
| Odin | `.odin` | Tree-sitter | `ols` | none declared |
| Racket | `.rkt` | Tree-sitter default readtable | `racket -l racket-langserver` | service, buffer and range |
| Go | `.go` | Tree-sitter | `gopls serve` | service, buffer and range |
| Rust | `.rs` | Tree-sitter | `rust-analyzer` | service, buffer and range |
| JavaScript | `.js`, `.jsx`, `.mjs`, `.cjs` | JavaScript and JSX providers | `typescript-language-server --stdio` | service, buffer and range |
| TypeScript | `.ts`, `.tsx`, `.mts`, `.cts` | TypeScript and TSX providers | `typescript-language-server --stdio` | service, buffer and range |
| HTML | `.html`, `.htm` | Tree-sitter with script/style injections | `vscode-html-language-server --stdio` | service, buffer and range |
| CSS | `.css` | Tree-sitter | `vscode-css-language-server --stdio` | service, buffer and range |

## Bounds and Failure Behavior

Manifest construction enforces these public maxima:

| Resource | Maximum |
| --- | --- |
| Loaded bundle module | 2 MiB |
| Bundle identity | 96 UTF-8 bytes |
| Display name | 128 UTF-8 bytes |
| Description | 4,096 UTF-8 bytes |
| Relative artifact path | 4,096 UTF-8 bytes |
| Provenance | 256 UTF-8 bytes |
| Dependencies | 256 |
| Artifacts | 1,024 |
| Contributions | 640 |
| Targets | 16 |
| References within a contribution | 8,192 |
| Formatter timeout | 600,000 ms |
| Formatter output | 64 MiB |
| One artifact declaration | 1 TiB |

Catalog snapshots are limited to 64 MiB, 65,536 entries, 262,144 artifact
descriptors, 64 source keys, 16 locations per entry, 8 redirects, 8 retries,
and a 600,000 ms request deadline. Archives allow at most 8,192 members and
1 GiB expanded content. Installed state format `2` admits 1,024 bundles, 64
in-flight operation records, and 16,384 content references. Inspection emits
at most 4,096 bounded lines.

Syntax providers additionally bound grammar ABI, query compilation, captures,
injections, source bytes, parse work, retained trees, and ordinary, demanding,
or boundary resource profiles. Services bound framing, messages,
synchronization, requests, results, deadlines, restarts, and teardown.

Expected failures include incompatible API, target, dependency, grammar ABI,
or executable; signature, digest, archive, cache, manifest, query, server,
formatter, and workspace-edit failures; denied authority; untrusted Projects;
stale generations; cancellation; allocation or resource exhaustion; and
interrupted lifecycle operations. Provider failure is contained to its
language, root, document, or injected region. Ordinary editing and the last
confirmed generation remain available.

## Author Conformance Commands

```sh
racket scripts/language-bundle-author.rkt validate /path/to/bundle.rkt
racket scripts/language-bundle-author.rkt conform /path/to/bundle.rkt
racket scripts/language-bundle-author.rkt archive \
  /path/to/bundle.rkt /path/to/bundle.tar
```

The validator reports compatibility and artifact diagnostics. Conformance
requires language, syntax, service, command, Direct, and Modal contributions.
Archive creation is deterministic and refuses a nonconforming bundle.

## Version Evidence

The bundle API and all nine Factory bundles are version `1.0.0`, with API range
`1.0.0` through `1.0.0`. Exact grammar, query, artifact, and accepted service
versions are recorded on each page in the
[Language Support Reference](../language-support/index.md) and are observable
through bundle and support inspection.
