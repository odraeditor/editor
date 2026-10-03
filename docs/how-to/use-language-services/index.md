<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Set Up and Diagnose Language Services

Use this guide to install external servers, use maintained Factory language
support, configure additional languages through `init.rkt`, inspect catalog and
session health, recover one failed selection, and run focused interoperability
gates.

## Know the Support Level

Odra distinguishes maintained support from configurable interoperability:

| Level | Languages | Evidence |
| --- | --- | --- |
| Maintained | Odin through OLS; Racket through Racket Language Server; Go through `gopls v0.23.0`; Rust through `rust-analyzer` | Factory definitions, offline local syntax, pinned interoperability, concurrent-session, failure-isolation, and cleanup checks. |
| Configuration recipes | TypeScript, JavaScript, HTML, and CSS | Public catalog contracts and known standard-I/O server commands; these combinations are not yet maintained or pinned by Odra. |

Racket and Go local syntax remains active when their external servers are
absent. A personally configured language gets filename recognition even when
it has no syntax provider. Server features remain limited to the
language-independent adapters implemented by Odra.

## Make Maintained Servers Discoverable

Install an OLS build compatible with the Odin toolchain used by your Project.
Odra does not download, install, update, or configure OLS. Confirm that the
executable is available through the environment used to start Odra:

```sh
command -v ols
ols --version
```

The factory definition requests the executable name `ols`. Discovery uses a
controlled executable lookup and never evaluates a shell command. Odra does
not create or rewrite `ols.json` or other Project files.

For maintained Racket support, install Racket Language Server and confirm its
package record in the launch environment:

```sh
raco pkg show --all --long racket-langserver
```

The process is external and isolated from Odra's embedded Racket configuration
runtime. The Factory bundle already owns `.rkt` recognition, local syntax, the
`racket -l racket-langserver` service command, and `info.rkt` root discovery.

For maintained Go support, install the accepted `gopls` version and confirm it
in the launch environment:

```sh
go install golang.org/x/tools/gopls@v0.23.0
command -v gopls
gopls version
```

The Factory bundle already owns `.go` recognition, local syntax, the `gopls
serve` command, and nearest `go.work` or `go.mod` root discovery.

For maintained Rust support, install `rust-analyzer` and the matching standard
library sources, then confirm the executable in the launch environment:

```sh
rustup component add rust-analyzer rust-src
command -v rust-analyzer
rust-analyzer --version
```

The Factory bundle already owns `.rs` recognition, local syntax and structure,
the direct `rust-analyzer` command, nearest `Cargo.toml` root discovery, and
language-service formatting. No Personal Rust definition is required.

## Install Servers for the Basic Language Pack

Install only the servers needed by your Projects. Confirm every executable in
the same environment that starts Odra.

For TypeScript, JavaScript, HTML, and CSS:

```sh
npm install -g typescript-language-server typescript vscode-langservers-extracted
command -v typescript-language-server
command -v vscode-html-language-server
command -v vscode-css-language-server
```

Odra does not run these installation commands. It resolves configured
executables only after a valid catalog generation is confirmed.

## Configure Additional Languages

Racket, Go, and Rust require no Personal definition. Add the following complete
export to personal `init.rkt` only for the additional web configuration
recipes. Preserve unrelated imports, exports, and definitions already present
in the module.

```racket
#lang racket/base

(require odra/languages)

(provide odra-language-support)

(define odra-language-support
  (language-support-set
   #:languages
   (list
    (language #:id 'typescript #:display-name "TypeScript"
              #:suffixes '(".ts" ".tsx" ".mts" ".cts"))
    (language #:id 'javascript #:display-name "JavaScript"
              #:suffixes '(".js" ".jsx" ".mjs" ".cjs"))
    (language #:id 'html #:display-name "HTML"
              #:suffixes '(".html" ".htm"))
    (language #:id 'css #:display-name "CSS" #:suffixes '(".css")))
   #:services
   (list
    (language-service
     #:id 'typescript-language-server
     #:languages '(typescript javascript)
     #:command '("typescript-language-server" "--stdio")
     #:root-markers '("tsconfig.json" "jsconfig.json" "package.json")
     #:features '(diagnostics completion))
    (language-service
     #:id 'vscode-html-language-server
     #:languages '(html)
     #:command '("vscode-html-language-server" "--stdio")
     #:features '(diagnostics completion))
    (language-service
     #:id 'vscode-css-language-server
     #:languages '(css)
     #:command '("vscode-css-language-server" "--stdio")
     #:features '(diagnostics completion)))
   #:selections
   (hasheq
    'typescript 'typescript-language-server
    'javascript 'typescript-language-server
    'html 'vscode-html-language-server
    'css 'vscode-css-language-server)))
```

Save the file and run `M-x reload-personal-commands`. The command reloads the
complete personal configuration generation despite its historical name. One
invalid definition rejects the complete candidate and preserves the previous
confirmed generation.

This contribution is data, not a bundled server distribution. Remove languages
or services that you do not use. A missing executable produces unavailable
health only for its selection and does not disable maintained local syntax for
another language.

## Satisfy the Trust Boundary

Open the source through a local Project whose one root is trusted. A confirmed
filename or suffix selects a language, but that alone does not authorize an
external process.

Use [Manage Project Trust and Refresh](../manage-project-trust/index.md) to
inspect, grant, or revoke the exact local Project trust. Revocation removes the
affected synchronized documents, invalidates their diagnostics, and begins
bounded service teardown. It does not close the editor buffers.

## Inspect Current Support and Health

With a supported buffer active, first run:

```text
M-x describe-language-support
```

Confirm the document association, contributing source, selected service,
resolved root, executable state, precedence, and any rejected or shadowed
candidate. Then run:

```text
M-x describe-language-service
```

Read the session rows in this order:

1. `Provider` and `Executable` confirm selection and executable resolution.
2. `Session`, `Process`, and `Protocol` show lifecycle state and negotiated
   capabilities.
3. `Documents` and `Diagnostics` show synchronized ownership and current
   publication counts.
4. `Failures` and `Standard error` identify the latest contained failure.
5. `Policy` records the active resource, deadline, and restart bounds.

Press `C-g` to close the inspection.

| Result | Meaning | Action |
| --- | --- | --- |
| `Executable_Not_Found` | The selected executable was not found in the startup environment. | Correct `PATH`, then restart Odra or publish a relevant configuration generation. |
| `phase=Active`, `state=Running` | The service is initialized and owns the listed document bindings. | No recovery is required. |
| `phase=Failed`, `state=Reaped` | The child failed and has been collected. | Inspect stderr, then request one explicit restart. |
| `Restart_Exhausted` | The bounded restart allowance has been spent. | Correct the server or configuration and start a fresh editor session. |
| No service session | The buffer is ineligible, outside the active Project, or the Project is untrusted. | Check the association, selected Project, local trust, and executable state. |

## Request One Restart

Run:

```text
M-x restart-language-service
```

The request is accepted only for the current failed, reaped session. An active
session returns `Invalid_Session`; repeated recovery after the allowance is
spent returns `Restart_Exhausted`. The command never loops indefinitely.

## Navigate Current Diagnostics

Use `M-x list-language-diagnostics` for a filterable current generation. Use
`M-g n` and `M-g p` for next and previous navigation. `No current language
diagnostics` means no current publication is available; it is not an editing
failure.

If an edit makes a candidate stale, request a new list after the next server
publication. Odra rejects stale navigation rather than moving to a range from
an older document revision.

## Understand Package Contributions

An activated package can contribute the same language and service records as
personal configuration. Its validated discovery record can appear under
`language`, `language-service`, `syntax`, `formatter`, `commands`, and `theme`
facets at the same time. Facets never grant authority, activate a package, or
select a server.

Package acquisition, activation, update, rollback, and removal remain package
ecosystem operations. The current language-support delivery verifies this
boundary with deterministic package fixtures; it does not add a public
language-server package manager.

## Apply Project Policy Safely

A trusted Project can select an existing service or contribute one complete
Project-scoped replacement. It cannot patch a lower-precedence definition
field by field, affect another Project, escape its membership root, weaken
native limits, or execute while untrusted.

Revoking trust prevents new requests and begins bounded shutdown without
closing documents. Use `M-x describe-language-support` to distinguish global
Personal configuration from the effective Project-scoped selection.

## Reproduce Focused Acceptance

The maintained acceptance environment uses OLS `dev_2026_06-1`, upstream tag
`dev-2026-06`, commit `ca8eb6da44c2b1c9e63736af05a5c3a5a298ea82`,
and executable SHA-256
`54c114d2dea3c9189710888da6591ea0d90bc543899cc736fc02bc019e6145b2`.
The version is acceptance evidence, not an automatic installation requirement.

Run the focused factory workflow:

```sh
make language-service-workflow-acceptance
```

The target runs the generic process and synchronization path against both the
deterministic fixture server and the installed OLS executable, then runs a real
PTY scenario covering trusted discovery, visible diagnostics, navigation,
editing, panes, theme selection, resize, missing-server fallback, save, and
terminal restoration. It is not the full repository suite.

Check Factory Go interoperability without building Odra:

```sh
make gopls-language-service-acceptance \
  GOPLS_EXECUTABLE="$(command -v gopls)"
```

This focused target confirms `gopls v0.23.0`, loads the Factory Go profile,
exchanges LSP initialization and synchronization, observes diagnostics and
completion, and verifies clean shutdown.

Check Factory Rust syntax, interaction, root, edit, failure, and cleanup paths
without building Odra:

```sh
make rust-language-support-test
```

Check the pinned real `rust-analyzer` protocol path:

```sh
make rust-language-service-acceptance \
  RUST_ANALYZER_EXECUTABLE="$(command -v rust-analyzer)"
```

The second target loads the public Rust profile, initializes the selected Cargo
root, observes diagnostics and completion, and verifies clean shutdown. When
no system executable is supplied, the repository target downloads the exact
hashed acceptance asset into `.build/`; it does not install it globally.

The complete delivery gate is:

```sh
make language-service-extensibility-acceptance
```

It includes the integrated application and PTY path. Do not use it as the
ordinary edit-test loop. Daily exhaustive verification runs it through the
repository nightly workflow; daytime language changes use
`make language-workflow-focused-test` and the smallest changed-owner test.

## Upstream Setup References

- [gopls documentation](https://go.dev/gopls/)
- [rust-analyzer installation](https://rust-analyzer.github.io/book/installation.html)
- [TypeScript Language Server](https://github.com/typescript-language-server/typescript-language-server)
- [VS Code language servers extracted for HTML and CSS](https://github.com/hrsh7th/vscode-langservers-extracted)

For exact constructors, source precedence, feature admission, package facets,
inspection, and bounds, use the
[Language Support Configuration Reference](../../reference/language-support-configuration/index.md).
