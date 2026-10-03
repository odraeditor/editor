<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Author a Language Bundle

Create a third-party bundle with stable identities, bounded artifacts, a local
syntax provider, a service profile, semantic commands, and both interaction
profiles. The author kit validates the same public contracts used by installed
bundles.

## Start from the Template

Copy `assets/language-bundles/author-kit/template/` to a working directory
outside the repository. Keep the exported value name exactly
`odra-language-bundle` and update the example bundle, language, provider,
service, command, keymap, artifact, publisher, and source identities.

The entrypoint uses:

```racket
(require odra/language-bundles)
```

Loading the module returns one immutable bundle value. It performs no
registration and receives no native parser, process, registry, buffer, or
transaction authority.

## Add Artifacts and Declarations

1. Build a compatible Tree-sitter shared library for every declared target.
2. Add highlight queries and any explicit injection queries.
3. Declare each artifact path, byte size, lowercase SHA-256 digest, target, and
   required authority.
4. Declare selectors and syntax providers, including grammar symbol and ABI.
5. Declare a language service as a direct argument vector and real root
   markers. Do not use a shell command.
6. Declare formatter behavior, semantic commands, and `language-context`
   keymaps for Direct and Modal states.
7. Declare dependencies, authorities, supported Odra API range, platform and
   architecture targets, provenance, and license.

The JSON Schema at
`assets/language-bundles/author-kit/language-bundle.schema.json` describes the
canonical bridge manifest. The Racket constructors remain the authoring API.

## Validate and Conform

From an Odra source checkout, run:

```sh
racket scripts/language-bundle-author.rkt validate /path/to/bundle.rkt
racket scripts/language-bundle-author.rkt conform /path/to/bundle.rkt
```

`validate` checks bounded loading, target and API compatibility, artifact
existence, byte size, and digest. `conform` additionally requires at least one
language, syntax provider, service, semantic command, Direct map, and Modal
map. Fix every diagnostic before packaging.

## Build a Deterministic Archive

```sh
racket scripts/language-bundle-author.rkt archive \
  /path/to/bundle.rkt /path/to/example-language-1.0.0.tar
sha256sum /path/to/example-language-1.0.0.tar
```

The builder sorts members, normalizes USTAR metadata, and reports the archive
digest, bytes, and member count. Rebuilding unchanged inputs must produce the
same bytes.

Publish that exact archive through a signed catalog entry containing the
matching bundle identity, version, target, digest, size, source, dependencies,
and authority evidence. Test install, enable, restart, syntax, a real service
capability, Direct and Modal routing, update, rollback, disable, remove, tamper
rejection, offline reuse, and cleanup through the public lifecycle.

For all constructors and fields, see the
[Language Bundle Reference](../../reference/language-bundles/index.md).
