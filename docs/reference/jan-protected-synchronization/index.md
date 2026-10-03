<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Protected Synchronization Reference

Jan protection and synchronization coordinate encrypted subtrees and mobile
document sets without owning keys, plaintext persistence, filesystem mutation,
transport, or conflict application. `jan_output` validates exact provider,
Resource, digest, generation, and policy inputs and returns copied plans to the
established credential, Resource, transaction, and remote-access owners.

## Protection providers

A protection provider descriptor carries a stable identity, exact generation,
encrypt and decrypt capabilities, availability, admission, and credential
generation. Selection requires one exact provider and the requested capability.
Duplicate, stale, unavailable, unadmitted, unsupported, or credential-mismatched
providers reject before a plan exists.

Requests carry only a nonzero credential handle and generation. No request,
plan, result, diagnostic, undo record, or log contract contains key bytes. The
credential owner resolves and uses the handle during an immediate provider
handoff.

## Explicit subtree encryption and decryption

Every protection request binds one exact Resource revision, source range,
input digest, input state, provider generation, credential generation, and
output byte limit. Encryption accepts plaintext input; decryption accepts only
opaque encrypted input. Both require an explicit command trigger.

Search, agenda, export, publication, and background-index triggers cannot
create a decryption plan. Protection results are accepted only when compatible
document markers and archive behavior remain preserved.

Completed encryption returns an opaque encrypted descriptor and cannot report
plaintext exposure. Completed decryption returns a transient decrypted
descriptor that may be visible to the interactive view. Failed and cancelled
results contain no output digest, bytes, or plaintext exposure.

## Secret and plaintext isolation

Every completed provider result is accompanied by a redacted audit. The audit
must confirm zero retained credential bytes and zero secret bytes in
diagnostics, undo serialization, and logs. Decryption results must also confirm
that plaintext was not persisted as part of the provider operation.

Encrypted content retains its exact source byte range and digest when a
provider is unavailable or decryption fails. It remains opaque to search,
agenda, export, publication, and indexing rather than disappearing or becoming
partially interpreted. A transient decrypted view remains hidden from those
background consumers unless a later explicit workflow changes canonical
source.

## Plaintext save policy

Saving a transient decrypted subtree is a separate explicit operation with one
of three policies:

- `deny` never permits plaintext persistence;
- `confirm` requires an explicit positive confirmation for that request; and
- `allow` permits the explicit save under already confirmed policy.

An absent policy, implicit save, ordinary encrypted descriptor, or missing
confirmation under `confirm` rejects. Decryption itself never implies save
authority.

## Synchronization providers and staging

A synchronization provider declares identity, exact generation, availability,
admission, and a transport class: local, Pola, peer-to-peer, or hosted. The
transport changes only the selected effect owner. It cannot change entry
selection, checksums, reconciliation, or application semantics.

A project request selects:

- an exact staging Resource and revision;
- push and pull generations;
- an entry ceiling and retention generations; and
- no attachments, referenced attachments, or all selected attachments.

Staging requires at least one selected document. Every staged document or
attachment records Resource identity, base and local revisions, base and local
digests, and a staging checksum equal to the local digest. Duplicate Resources,
invalid revisions, malformed checksums, excessive candidates, unavailable
providers, and cancellation reject before staging effects. Entries are ordered
by Resource identity so every transport receives the same manifest semantics.

## Three-way reconciliation

Pulled observations carry the exact Resource, remote revision, original base
digest, remote digest, and checksum validation. Reconciliation classifies each
entry as:

- unchanged;
- changed only locally;
- changed only remotely;
- converged independently to the same content; or
- divergent conflict.

Unchanged, local-only, and converged entries keep local state. Remote-only
entries produce an exact accept-remote candidate. Divergent entries remain
`unresolved` until an explicit keep-local, accept-remote, or manual-merge
decision exists. A manual merge requires a new digest and revision newer than
both local and remote revisions.

Any unresolved divergence leaves the reconciliation state `conflicted` and no
apply plan can be created. Extra, duplicate, or non-conflict decisions reject
instead of being ignored.

## Application and recovery

Once every conflict is resolved, application candidates are ordered by
Resource identity. Each result must match the manifest, Resource identity,
expected local revision, chosen result revision, and chosen digest. A failed
application reports no result revision or digest.

The durable workflow records prepared, pushed, received, conflicted, applied,
reconciliation-required, and expired boundaries. An interruption retains the
last durable state and enters reconciliation-required. Explicit recovery
returns to that exact state; it cannot skip conflict presentation or claim an
apply result.

Temporary staging resources must be cleaned. Expired unprotected retained
resources must be removed, while protected or current generations must remain.

## Failure and no-overwrite guarantees

Malformed manifests, stale generations, unavailable providers, invalid
checksums, duplicate resources, interruption, divergent content, incomplete
decisions, stale application revisions, secret leakage, and cleanup failures
remain attributable outcomes. Pull never silently overwrites divergent local
content. Failure preserves opaque encrypted source, local Resources, staging
state, and the last durable synchronization boundary.

## Focused validation

Use:

```sh
make jan-output-focused-test
```

The target checks deterministic protection and synchronization models,
credential isolation, semantic opacity, plaintext-save policy, attachment
selection, transport neutrality, checksums, base versions, three-way
classification, explicit conflict resolution, application order, interruption
recovery, cleanup, and strict `src/jan_output` tests. It does not resolve a
credential, invoke encryption, stage or transfer a file, mutate a Resource,
build `src/odra`, or run a repository-wide gate.
