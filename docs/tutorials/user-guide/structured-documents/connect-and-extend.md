<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Connect and Extend Jan

This chapter inspects and uses Jan providers, from registration and
availability through trust, authority, and execution.

## Inspect Before Acting

Open the supplied
`~/odra-guide/work/projects/forecast-engine/notes/jan-workflows/00-start-here.org`
after completing
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md).
Use `M-x` to discover the Jan provider and extension inspection commands
available in the current build. Inspect provider identity, provenance,
generation, capability family, availability, declared authority, limits, and
latest failure.

A registered provider is only a candidate source of behavior. It cannot grant
itself filesystem, process, network, credential, clipboard, document-mutation,
or publication authority. Every invocation binds exact generations and a
checked authority subset.

## Use External Links and Protocols

`M-x jan-protocol-handle` accepts a versioned, authenticated, bounded request.
Inspect its caller, operation, provider, freshness, nonce, payload size, and
required resource action. Replayed, stale, oversized, unauthenticated, or
unsupported requests fail before an effect plan exists.

Following a custom link or previewing media uses the same provider boundary.
Opening the document or moving point over the link never contacts a provider.

## Protect and Synchronize Content

Run `M-x jan-encrypt-subtree` only on the supplied non-secret sample. The
request contains a credential handle, not credential bytes. The document keeps
opaque content if the provider is unavailable. Use
`M-x jan-decrypt-subtree` to decrypt it. Successful decryption does not change
the plaintext save policy.

`jan-mobile-push`, `jan-mobile-pull`, and `jan-mobile-reconcile` operate on
transport-neutral staged manifests. Review checksums, base versions,
attachments, provider generation, and conflict count. Divergent entries stay
conflicted until an explicit reconciliation decision exists; Jan never uses a
silent last-writer-wins overwrite.

## Inspect Extensions

An extension generation can contribute hooks, packages, properties, mapping,
agenda sources and views, capture templates, custom links, exporters, filters,
citation processors, table translators, dynamic blocks, execution adapters,
publishing providers, and synchronization providers. Use
`M-x jan-dynamic-block-update` only after inspection confirms the selected
provider and operation.

Activation is atomic. A duplicate identity, missing parent, cycle, stale
generation, undeclared authority, invalid result, or resource breach rejects
the candidate generation and keeps the last confirmed generation active.

## Verify the Result

You have completed this chapter when you can distinguish a declared provider
from an available one, identify the exact authority required by an invocation,
observe one rejected request with no effect, and confirm that source remains
editable after provider failure.

See [Why Jan Keeps Authority Outside Providers](../../../explanation/jan-authority-and-provider-boundaries/index.md)
for the design model and the
[Jan Extension Surface Reference](../../../reference/jan-extension-surface/index.md)
for exact contribution contracts.

---

[Previous: Export and Publish](export-and-publish.md) ·
[Structured Documents](index.md) ·
[Next: Recover Jan Workflows](recover-jan-workflows.md)
