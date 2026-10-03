<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Package Authoring

An Odra package repository owns source, tests, documentation, and reproducible
release inputs. A catalog repository owns curation assertions and publication.
Installing a package never clones either repository.

## Canonical Source Layout

```text
package-name/
|-- odra-package.rktd
|-- entrypoint.rkt
|-- README.md
|-- LICENSE
|-- tests/
`-- scripts/
```

`odra-package.rktd` is an inert `#lang odra/config` record. It declares the
exact package identity and version, publisher and source revision, compatible
package API range, targets, authorities, artifacts, entrypoint, contributions,
documentation, and state-compatibility policy. Every artifact records a role,
kind, normalized relative path, SHA-256 digest, exact byte size, optional
target, and required authority.

## Command Entrypoints

A Racket command package declares the `racket-extension` authority and one
`racket-module` entrypoint artifact. The module must use `#lang racket/base`
and export `odra-package-contributions` as an immutable list created with
`make-command`. It may require `odra/commands`, other declared package modules,
and the direct Racket libraries admitted by the
[Installable Package Reference](index.md#restricted-command-runtime).

Declare every production module as a `racket-module` artifact. Package-relative
imports resolve only inside that verified module tree; an undeclared helper
module is unavailable even when it was present in the source repository.

Each exported command must match its manifest contribution exactly: identity,
requirements, and effects. Commands receive no editor internals. They read and
mutate text only through the checked command context supplied for one bounded
turn.

## Configured File Resources

A user can authorize named filesystem resources independently of the current
Project. Export `odra-package-resources` from personal `init.rkt`:

```racket
(require odra/commands)
(provide odra-package-resources)

(define odra-package-resources
  (list
   (make-package-resource
    #:package "example.notes"
    #:name 'notes
    #:root (build-path (find-system-path 'home-dir) "Documents" "notes")
    #:access 'read-write)))
```

The export is a list of at most 32 resources with unique package/name pairs.
Each resource has an absolute bounded root and `read` or `read-write` access;
the default is `read`. Invalid configuration preserves the last confirmed
configuration generation.

Package commands call `command-context-package-resource-root` with the
resource name. It returns the configured root or `#f`. The command context
contains only resources assigned to that package. The runtime also checks
package identity and confines file operations to admitted roots, including
physical path checks for symbolic-link escapes.

Resources require the enabled package's existing `project-read` authority.
Writes additionally require `project-write` and a `read-write` resource.
Configuration does not grant either manifest authority automatically. A
package cannot grant itself a new root or change the user's configuration.

## Agent Entrypoints

An agent or integration package may require `odra/agents` and export inert
agent and capability definitions beside ordinary commands. The manifest facets
are `agent` and `agent-capability`; every exported identity, requirement, and
effect must match its manifest declaration exactly.

Loading and activation publish copied definition metadata only. They do not
grant authority or invoke a capability handler. See the
[Agent Substrate Definition Reference](../agent-substrate/index.md) for the
public constructors, schema grammar, limits, and generation behavior.

## Release Construction

Build one deterministic `.tar.zst` per supported target. Its members are:

1. canonical `odra-package.rktd` first;
2. every target-independent artifact in manifest order; and
3. every artifact for the selected target in manifest order.

No undeclared file, symbolic link, device, absolute path, or parent traversal
is permitted. The release handoff records the manifest digest, archive digest,
compressed size, target, exact source revision, builder identity, and
reproducibility status.

Run the package's unit tests, deterministic rebuild check, and Odra release
validator before submitting it for curation. The ROT13 canary under
`~/Projects/odra-packages/rot13` is the minimal working example.

## Catalog Handoff

A curator assesses the immutable release and, after a human decision, publishes
an admitted, deprecated, quarantined, or withdrawn assertion. The assertion
binds the exact release and artifact; it does not grant runtime authority.

The catalog publishes the signed snapshot and assertion set before clients can
resolve the release. Artifact bytes may share the catalog origin or use another
HTTPS origin with an explicit credential binding. Installation verifies all
catalog, manifest, archive, and member identities before durable inactive
publication. The user grants requested authority only through
`package-enable`.

## Compatibility and Updates

Never replace bytes for an existing package identity and version. Publish a new
SemVer release and immutable archive. A compatible update is installed inactive
first, then activated with `package-update`; the previous confirmed release is
retained for `package-rollback`.

Changing authorities, contribution identities, effects, persistence schema, or
package API compatibility must be explicit in the new manifest. Cleanup policy
applies only after the exact release is inactive and unreachable.
