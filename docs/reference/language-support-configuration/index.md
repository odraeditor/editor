<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Support Configuration Reference

Odra accepts one optional `odra-language-support` export from personal
`init.rkt`. The export is declarative data: it defines language associations,
language-service commands, and explicit selections without exposing native
registry or process lifecycle operations.

## Support Levels

| Level | Languages and services | Contract |
| --- | --- | --- |
| Maintained | Odin with OLS; Racket with Racket Language Server; Go with `gopls v0.23.0`; Rust with `rust-analyzer` | Odra owns the factory definitions, local syntax providers, defaults, pinned acceptance, inspection, and failure-isolation evidence. The server executables remain external. |
| Configurable | Any language and conforming standard-I/O server | The definition uses the public constructors and shared runtime. Compatibility depends on the server, requested features, and Odra's implemented LSP adapters. |

TypeScript, JavaScript, HTML, and CSS have documented configuration recipes.
They are not yet maintained or pinned interoperability targets.

Import the public API with:

```racket
(require odra/languages)
```

## Constructors

| Constructor | Purpose |
| --- | --- |
| `language` | Define one language identity and its exact filename or suffix selectors. |
| `language-service` | Define one server command and its supported languages, root markers, JSON profile, environment, features, and selection policy. |
| `language-support` | Compose one language with zero or more directly associated services. |
| `language-support-set` | Compose one complete contribution containing several languages, services, and explicit selections. |

All constructors copy admitted collections and text into immutable values.
They raise a compact Racket argument exception when a value is malformed,
duplicated, unknown, or outside its bound.

## Minimal Configuration

This configuration adds Zig recognition and one default server:

```racket
#lang racket/base

(require odra/languages)

(provide odra-language-support)

(define odra-language-support
  (language-support
   #:language 'zig
   #:suffixes '(".zig")
   #:server
   (language-service
    #:id 'zls
    #:command '("zls"))))
```

A service nested through `language-support` inherits the surrounding language.
When it is the only server, it also becomes that language's default. No native
capability numbers, registration calls, or process handles are required.

## Multiple Languages

Use `language-support-set` for a complete multi-language contribution:

```racket
#lang racket/base

(require odra/languages)

(provide odra-language-support)

(define odra-language-support
  (language-support-set
   #:languages
   (list
    (language #:id 'zig #:suffixes '(".zig"))
    (language #:id 'racket
              #:suffixes '(".rkt")))
   #:services
   (list
    (language-service
     #:id 'zls
     #:languages '(zig)
     #:command '("zls")
     #:root-markers '("build.zig"))
    (language-service
     #:id 'racket-langserver
     #:languages '(racket)
     #:command '("racket" "-l" "racket-langserver")
     #:root-markers '("info.rkt")
     #:features '(diagnostics completion)))
   #:selections
   (hasheq 'zig 'zls
           'racket 'racket-langserver)))
```

`#:selections` is an immutable hash from language identity to service identity.
The referenced service must be admitted when the native candidate is
normalized.

## Basic Language Pack Profiles

The documented basic pack uses these ordinary profiles:

| Language identity | Selectors | Service identity | Command | Root markers | Evidence level |
| --- | --- | --- | --- | --- | --- |
| `racket` | `.rkt` | `racket-langserver` | `racket -l racket-langserver` | `info.rkt` | Maintained Factory support |
| `go` | `.go` | `gopls` | `gopls serve` | `go.work`, `go.mod` | Maintained Factory support |
| `rust` | `.rs` | `rust-analyzer` | `rust-analyzer` | `Cargo.toml` | Maintained Factory support |
| `typescript` | `.ts`, `.tsx`, `.mts`, `.cts` | `typescript-language-server` | `typescript-language-server --stdio` | `tsconfig.json`, `jsconfig.json`, `package.json` | Configuration recipe |
| `javascript` | `.js`, `.jsx`, `.mjs`, `.cjs` | `typescript-language-server` | `typescript-language-server --stdio` | `tsconfig.json`, `jsconfig.json`, `package.json` | Configuration recipe |
| `html` | `.html`, `.htm` | `vscode-html-language-server` | `vscode-html-language-server --stdio` | Membership root | Configuration recipe |
| `css` | `.css` | `vscode-css-language-server` | `vscode-css-language-server --stdio` | Membership root | Configuration recipe |

All commands are direct argument vectors. Racket, Go, and Rust require no
Personal definition; their Factory bundles own recognition, syntax, service,
formatter, and recovery metadata. The complete copy-ready Personal contribution
for the remaining configuration recipes is in
[Set Up and Diagnose Language Services](../../how-to/use-language-services/index.md#configure-additional-languages).

## Language Fields

`language` accepts:

| Keyword | Default | Contract |
| --- | --- | --- |
| `#:id` | required | Non-empty symbol, at most 64 UTF-8 bytes. |
| `#:display-name` | identity text | Non-empty text, at most 96 UTF-8 bytes. |
| `#:filenames` | `'()` | Up to 8 unique names without path separators. |
| `#:suffixes` | `'()` | Up to 8 unique dot-prefixed suffixes. |

One language may have at most 16 selectors in total.

## Service Fields

`language-service` accepts:

| Keyword | Default | Contract |
| --- | --- | --- |
| `#:id` | required | Non-empty symbol, at most 96 UTF-8 bytes. |
| `#:display-name` | identity text | Non-empty text, at most 96 UTF-8 bytes. |
| `#:languages` | `'()` | Unique language identities; a top-level service must name at least one. |
| `#:command` | required | Non-empty argument list; its first value is the executable. |
| `#:root-markers` | `'()` | Unique relative paths used for later root resolution. |
| `#:initialization-options` | `(hasheq)` | Bounded immutable JSON value. |
| `#:settings` | `(hasheq)` | Bounded immutable JSON value. |
| `#:environment` | `(hash)` | Immutable string-to-string mapping. |
| `#:features` | `'(diagnostics completion)` | Unique admitted symbolic features. |
| `#:enabled?` | `#t` | Whether the definition is eligible for selection. |
| `#:default?` | `#f` | Whether the definition participates in default selection. |

Admitted features are `diagnostics`, `completion`, `navigation`, `hover`,
`references`, `symbols`, `signature-help`, `rename`, `formatting`,
`semantic-tokens`, and `code-actions`.

The constructor accepts known symbolic identities so one configuration format
can evolve. Acceptance does not imply that every identity is implemented.
Each feature activates only when a language-independent Odra adapter, native
policy, the effective definition, and server negotiation all admit it.

Commands contain at most 64 parts and 64 KiB in total; the executable is at
most 4 KiB. A service has at most 16 root markers and 64 environment entries.
Initialization options and settings each contain at most 65,536 JSON values
and 64 levels; together they occupy at most 1 MiB before the complete
contribution is encoded into the 128 KiB startup bridge payload.

## Effective Runtime Behavior

Every admitted service field controls one exact runtime stage:

| Field | Runtime effect |
| --- | --- |
| `#:command` | Resolves one executable and passes the remaining values directly as its argument vector without a shell. |
| `#:root-markers` | Selects the nearest contained root used as process working directory, `rootPath`, `rootUri`, workspace folder, session identity, and synchronization boundary. |
| `#:initialization-options` | Sends the copied JSON value as `initializationOptions` in the LSP `initialize` request. |
| `#:settings` | Sends the copied JSON value through `workspace/didChangeConfiguration` after initialization. |
| `#:environment` | Adds exact key/value overrides to the child environment; inspection reports only the key count and redacted values. |
| `#:features` | Restricts implemented client features before server capability negotiation; a feature activates only when policy, implementation, and negotiation all admit it. |
| `#:enabled?` | Removes a disabled definition from effective selection without making the catalog malformed. |
| `#:default?` | Participates in deterministic default selection when no explicit selection applies. |

Executable lookup checks an explicit path first, followed by an admitted
package artifact, a distributed artifact, and controlled `PATH` lookup. A
missing executable leaves the definition selected as unavailable and keeps
ordinary editing usable. Odra does not invoke a shell or install a missing
server.

Reload prepares the language catalog, service catalog, and new definition
records before publication. An equivalent profile reuses its existing handle
and process. A changed profile receives a replacement handle; its prior
healthy session may remain as the bounded replacement fallback until the new
session initializes. Unrelated language/root sessions are retained.

## Contribution and Reload Semantics

The personal export is one complete contribution source, not a field patch.
Factory, personal, trusted Project, and package-fixture inputs pass through the
same native validator while retaining source scope, trust, generation, and
provenance.

The export participates in the existing atomic personal configuration
generation. An exception, invalid selector, duplicate identity, conflict,
excessive value, stale generation, bridge overflow, or native rejection
prevents the whole new generation from publishing. Reload preserves the last
confirmed generation; initial rejection preserves factory configuration.

Project contributions require trusted Project membership. Package
contributions are optional sources and do not add another selection layer.

Effective source precedence is exact trusted Project, Personal, Package, then
Factory. A higher-precedence record replaces one complete lower record; it does
not patch individual fields. Same-precedence package identity conflicts reject
both conflicting effective candidates symmetrically. Removing a higher source
restores the next valid lower source for only the affected language scope.

An activated package may contribute language definitions, service definitions,
one verified executable artifact, server defaults, ordinary commands,
documentation, and inspection metadata. Its validated discovery record derives
the applicable `language`, `language-service`, `syntax`, `formatter`,
`commands`, and `theme` facets, affected language identities, platforms,
architectures, and required authorities. These facets are inert metadata: they
do not grant authority, activate code, establish precedence, or select a
service.

Package discovery, installation, activation, update, rollback, and removal
remain owned by the package ecosystem. This contract does not define a
language-server package manager.

## Inspection and Recovery

`M-x describe-language-support` is the catalog view for the active document.
It reports the confirmed catalog and source generations, associations,
definitions, source and scope, explicit or default selection, shadowing,
conflicts, root trace, executable provenance, latest rejected generation,
resource accounting, and applicable bounds.

`M-x describe-language-service` is the selected-session view. It reports the
effective profile, process and protocol state, synchronized documents,
negotiated features, diagnostics, failures, and bounded resource state.

`M-x restart-language-service` spends the bounded explicit restart for the
active document's selected failed session. It does not change the catalog or
service selection. A missing executable remains a valid but unavailable
definition and does not prevent ordinary editing.

## Focused Validation

```sh
make language-support-config-test
make language-workflow-focused-test
make gopls-language-service-acceptance \
  GOPLS_EXECUTABLE="$(command -v gopls)"
make rust-language-support-test
make rust-language-service-acceptance \
  RUST_ANALYZER_EXECUTABLE="$(command -v rust-analyzer)"
```

The first target checks the public constructors, personal loading and bridge,
atomic reload behavior, all source adapters, allocation faults, and exact
candidate cleanup. The second compiles the static syntax and service workflow
packages without building or linking the complete editor executable. The third
proves Factory Go interoperability against the pinned `gopls v0.23.0`
executable without building Odra. The Rust targets verify the maintained
syntax, interaction, root, edit, failure, cleanup, and real-server protocol
paths without building the complete editor.

The complete integrated and PTY gate is
`make language-service-extensibility-acceptance`. It is part of exhaustive
nightly verification and is not the ordinary edit-test loop.
