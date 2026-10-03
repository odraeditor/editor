<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Output Contracts Reference

Jan output is the static Stage 5 domain over exact Jan Document Language,
Planning, and Computable Documents projections. `src/jan_output` defines copied
export values, deterministic pipeline plans, resource limits, publication and
synchronization manifests, protocol admission, extension records, and lifecycle
states without rendering a backend or publishing an effect.

## Package boundary

`src/jan_output` owns normalized output values and coordination contracts. It
consumes exact Jan analysis scopes and copied values from the planning and
computation domains. Generic resource, process, credential, remote-access,
clipboard, terminal, transaction, and editor owners retain their effects and
canonical state.

The package does not retain parser pointers, mutate canonical source, write a
resource, invoke a converter, access a network, read a credential, place data
on the clipboard, or register application commands. The
[Jan Native Output Backends Reference](../jan-native-output-backends/index.md)
defines the delivered factory-native renderers. Tool-backed output, citations,
publishing, and external protocols are defined by their linked references
below. Protected synchronization and the programmable extension surface are
also defined below.

## Export pipeline

An output request binds one nonzero operation to:

- an exact Jan analysis and source revision;
- confirmed configuration, backend, filter, and provider generations;
- a document, subtree, region, visible projection, or agenda selection;
- one stable backend identity;
- resolved general and backend-specific settings;
- admitted exact-version includes and bounded macro expansions;
- one ordered exact-generation filter chain;
- comment, archive, task, code, result, drawer, property, numbering, exclusion,
  and table-of-contents policy;
- a preview, buffer, clipboard, or checked resource destination; and
- a complete resource policy no greater than the factory ceilings.

The request must be explicit. Opening, parsing, presenting, indexing, saving,
or inspecting a document cannot create an admitted output plan.

`prepare_output_plan` validates the complete request before returning a plan.
The plan is a copied, non-effectful handoff; it does not render, write, launch,
or publish anything.

## Setting precedence

Scalar settings resolve from lowest to highest precedence:

1. factory;
2. user Racket configuration;
3. Workspace;
4. Project;
5. document;
6. ancestor subtree, outermost to innermost;
7. selected subtree; and
8. explicit invocation.

A backend-specific value beats a general value only at the same source scope.
The latest source order breaks ties at that exact specificity. Inspection
retains the winner and shadowed count. Additive settings compose in source order
and cannot mix with scalar values under one key.

Document settings request behavior but never grant process, filesystem,
network, credential, clipboard, or publication authority.

## Includes, macros, and projection

Every include identifies an admitted Resource API identity, exact revision,
parent, depth, optional line range, and minimum heading level. Duplicate or
cyclic identities, stale revisions, invalid ranges, or excessive depth reject
the whole plan.

Macros require a known identity, bounded arguments, finite depth, and bounded
expansion size. Undefined or recursive expansions reject before normalization.
Macro content remains inert data.

Projection policy controls comments, commented headings, archived content,
drawers, properties, tasks, code, results, excluded tags, heading numbering,
and table-of-contents depth. It changes only the copied normalized tree; source
bytes remain unchanged.

## Filters, diagnostics, and destinations

Filters have stable identities, exact filter generation, explicit order, and
availability. Duplicate identities or positions, stale generations, and
unavailable filters reject the complete plan.

Diagnostics identify severity, contract field, exact source range, and bounded
message size. Output descriptors bind completion, generations, bytes,
diagnostics, and candidate resource counts. Invalid provider output cannot
reach a destination.

Preview, buffer, and clipboard destinations carry no resource identity.
Resource destinations require a checked Resource identity and expected
revision. Overwrite is an explicit requested policy, not authority to publish.

## Durable and external records

Publication manifests carry schema version, identity, exact operation and
configuration generations, entry and target counts, and one recoverable state:
candidate, local-complete, remote-partial, published,
reconciliation-required, or failed.

Synchronization manifests carry exact provider generation, entry and conflict
counts, and prepared, pushed, received, conflicted, applied,
reconciliation-required, or expired state. A divergent entry remains a
conflict until an explicit decision exists.

Protocol requests require an explicit invocation, exact provider generation,
and a bounded encoded payload before parsing or transport. Extension records
carry copied identity, ownership class, provider generation, resource count,
and availability; registration grants no effect authority.

## Capability inventory

Factory-native declarations cover the export pipeline, plain text, HTML,
Markdown, and normalized Jan/Org. Factory-adapter declarations cover Beamer,
LaTeX/PDF, ODT, Texinfo/Info, calendar, man-page output, and citation
processors. Configured-provider declarations cover publishing, protocols,
encryption, synchronization, and extensions.

Declaration does not imply availability. Optional-tool absence is an explicit
unavailable state and does not invalidate source or unrelated backends.

## Resource limits

| Resource | Limit |
| --- | ---: |
| Included resources | 1,024 |
| Include depth | 128 |
| Macro expansions | 4,096 |
| Normalized nodes | 1,048,576 |
| Generated output | 256 MiB |
| Diagnostics | 65,536 |
| Manifest entries | 65,536 |
| Links | 16,384 |
| Publication targets | 4,096 |
| Active provider operations | 128 |
| Aggregate export cache | 512 MiB |
| Encoded protocol payload | 1 MiB |
| Settings | 4,096 |
| Filters | 256 |
| Entries between cancellation checks | 4,096 |

Elapsed-time and RSS limits are mandatory checked inputs. Providers may reduce
factory ceilings but cannot enlarge them.

## Failure and no-effect guarantees

Malformed, stale, missing, unavailable, unauthorized, conflicting, cyclic,
over-limit, cancelled, allocation-failed, provider-invalid, or incomplete work
returns an attributable failure. Rejection preserves canonical source and
confirmed generations. It cannot publish partial output, overwrite a checked
resource, invoke another backend, transport a protocol payload, resolve a
synchronization conflict, or activate an extension.

## Focused validation

Use:

```sh
make jan-output-focused-test
```

The target runs independent Racket models for precedence, includes, macros,
normalization, manifests, incremental reuse, protocols, synchronization,
extensions, resources, lifecycle, and resource profiles, followed by strict
unoptimized `src/jan_output` tests. It does not import or build `src/odra`, run
a backend, access an external tool, or publish an output.

See [Jan Tool Output Backends Reference](../jan-tool-output-backends/index.md)
for deterministic adapter source, exact optional-tool plans, availability,
temporary-resource cleanup, and backend-specific failure behavior.

See [Jan Citations and Bibliographies Reference](../jan-citations-and-bibliographies/index.md)
for exact bibliography sources, processor selection, key resolution, cache
identity, rendering, completion, and source-preserving failures.

See [Jan Publishing Reference](../jan-publishing/index.md) for bounded Racket
project configuration, deterministic discovery, complete manifests, exact
incremental reuse, local and remote outcomes, retry, reconciliation, cleanup,
and retention.

See [Jan External Protocols Reference](../jan-external-protocols/index.md) for
admitted link and media providers, authenticated versioned entrypoints,
payload and time bounds, replay protection, checked dispatch, and no-effect
failure results.

See [Jan Protected Synchronization Reference](../jan-protected-synchronization/index.md)
for explicit credential-isolated subtree protection, opaque preservation,
plaintext-save policy, deterministic staging, three-way reconciliation,
no-silent-overwrite application, recovery, cleanup, and retention.

See [Jan Extension Surface Reference](../jan-extension-surface/index.md) for
atomic extension generations, every admitted contribution family, deterministic
ordering, explicit composition, exact invocation, authority and mutation
boundaries, failure containment, cleanup, inspection, and conformance.
