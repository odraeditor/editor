<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Keeps Authority Outside Providers

Jan supports many workflows that can touch files, processes, credentials,
networks, remote stores, and document text. It also supports programmable
providers. Treating provider registration as permission would combine
discovery, trust, capability, and execution into one unsafe decision.

## Five separate decisions

Jan keeps these decisions distinct:

1. **Declaration** says that a provider claims a capability family.
2. **Admission** validates identity, provenance, schema, generations, limits,
   dependencies, and conflicts.
3. **Availability** reports whether the provider can currently perform an
   operation.
4. **Authority** grants one bounded invocation a subset of the provider's
   declared needs.
5. **Acceptance** lets the owning subsystem validate a copied result before it
   changes canonical state or creates an effect.

The separation applies to factory adapters and configured providers. A bundled
identity is not a universal permission.

## Owners retain effects

The editor owns canonical text and revisions. Transactions own document
mutation. Resource owners read and write files. The process owner starts and
stops child processes. Credential owners resolve opaque handles. Remote and
protocol owners perform network effects. Jan packages prepare and validate
copied plans across those boundaries.

This ownership makes failure local. A provider cannot retain a syntax pointer,
write editor memory, turn an old revision into a current one, or report direct
mutation as a valid result.

## Generations make change visible

Configuration, catalogs, providers, analyses, documents, and resources carry
exact generations or revisions. An invocation names the values it inspected.
If one changed, the operation is stale and must be prepared again. This avoids
silently applying a valid result to the wrong state.

Provider replacement is atomic. The complete candidate generation is admitted
or the last confirmed generation remains active. Missing parents, duplicate
identities, cycles, undeclared authority, invalid results, and resource-limit
breaches cannot produce a partially active catalog.

## Optional tools stay optional

Native parsing, editing, table calculation, text plotting, and native output do
not depend on an optional process. Tool-backed export, source execution,
citation processing, remote publishing, encryption, and synchronization expose
unavailable as an ordinary capability state. The document remains editable and
unrelated workflows continue.

## Partial effects remain explicit

Source-preserving rejection does not imply that external systems can always be
rolled back. A local build can finish before remote upload fails. A staged
synchronization can exist before application. Jan retains manifests,
attribution, checksums, completed counts, and recovery state instead of
rewriting partial work as success or silently discarding it.

This model lets new providers extend Jan without becoming alternate owners of
editor state or bypassing local control.

See the [Jan Product Surface Reference](../../reference/jan-product-surface/index.md)
for the concrete provider families and the
[Jan Extension Surface Reference](../../reference/jan-extension-surface/index.md)
for invocation and result contracts.
