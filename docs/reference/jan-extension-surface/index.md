<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Extension Surface Reference

The Jan extension surface admits bounded Racket contributions through one
generation-checked provider model. It does not load foreign editor objects,
create a second package manager, or permit a callback to mutate canonical
document, Resource, process, credential, network, or publication state.

## Extension generation

One candidate generation declares an exact configuration generation, extension
catalog generation, predecessor generation, catalog digest, definition limit,
and complete provider set. Activation validates the whole candidate and either
replaces the previous generation atomically or preserves it unchanged.

Every definition declares:

- a stable identity and exact provider generation;
- one extension family and its supported operation set;
- factory, package, user, Workspace, or Project provenance;
- explicit order, API version, result boundary, and failure policy;
- requested authorities;
- input-count, input-byte, result-count, output-byte, and temporary-resource
  limits;
- availability and admission; and
- for a derived backend, one exact parent identity and generation.

Definitions are unique by identity and ordered by family, declared order,
source, and identity. Declaration order does not alter execution order.
Derived backend chains must terminate in an export backend, reference exact
generations, and remain acyclic.

## Contribution families

The version 1 surface admits these families:

- lifecycle hooks and structured-document packages;
- property readers and checked property writers;
- bounded document-tree mapping;
- agenda sources, searches, views, and result enrichment;
- capture template and value providers;
- custom link parsing, completion, following, storage, export, and preview;
- export and explicitly composed derived backends;
- output filters and citation processors;
- table translators and dynamic block writers;
- executable-language adapters; and
- publishing and synchronization providers.

Each family has a closed operation vocabulary. A definition that declares an
operation belonging to another family rejects before activation.

## Invocation and authority

An invocation binds an operation to exact configuration, catalog, provider,
Resource, and Resource revision generations. It also declares copied input
counts and bytes, an output ceiling, a temporary-resource ceiling, and the
authority granted for this turn.

The granted authority must be a subset of the provider declaration and always
includes inspection. Available authorities cover copied document and Resource
reads, checked document or Resource proposals, process, network, and credential
access. They never include direct canonical mutation.

Authority is necessary but not sufficient: process, network, credential,
Resource, document, and publication owners still authorize and perform their
own effects. Registering a link scheme, backend, adapter, or provider does not
grant those effects automatically.

## Mutation boundary

Provider results have one declared boundary:

- `read-only` and `result-value` return bounded copied values;
- `document-candidate` returns an unapplied candidate bound to the exact source
  revision; or
- `resource-candidate` returns an unapplied candidate for the exact Resource
  revision.

Property writers and dynamic blocks always return document candidates. A
dynamic block refresh therefore computes a replacement body, after which the
document and transaction owners revalidate the revision and publish one
transaction. Table translators return compatible table values or Resource
candidates without creating another canonical table.

Hooks observe confirmed lifecycle events. A mutating hook must declare checked
document-proposal authority and returns a candidate; it cannot publish during
the callback. Property reads distinguish local, inherited, additive, and
derived values from one confirmed analysis. Property writes remain semantic
Jan command candidates.

Tree mapping declares document, subtree, selection, or agenda scope plus
pruning, archive, comment, restriction, match, stable-order, node, and result
limits. Callbacks receive copied values and cannot retain native syntax nodes.

## Custom links, exporters, and adapters

Custom links declare only the operations they implement. Network, process, or
Resource needs remain visible authorities on each provider and are checked for
every turn.

Exporters consume copied normalized values and return bounded output or checked
Resource candidates. Derived backends compose through explicit parent identity
and generation. Filters, citation processors, table translators, execution
adapters, publishing providers, and synchronization providers use the same
generation, authority, result, failure, and cleanup contracts.

## Failure containment and cleanup

A provider turn completes, fails, is cancelled, or reports unavailable. Every
non-completed result has zero output and no candidate. A completed result must
match the exact operation and provider generation, declared boundary, output
ceiling, expected revision, and result digest.

Providers cannot report direct mutation or retain native bytes. Created
temporary Resources must equal cleaned temporary Resources before any terminal
result is accepted. The provider failure policy explicitly selects continued
execution, operation abort, or a provider-disable candidate; it never mutates
the active catalog during the failed turn. Failure remains attributable to the
provider identity.

Stale generations, duplicate identities, invalid family operations, cyclic or
missing backend parents, undeclared authority, invalid result shape, limit
excess, incomplete cleanup, and retained native state reject without replacing
the confirmed catalog or applying a candidate.

## Inspection and conformance

Inspection reports catalog and provider generations, family, provenance,
order, operations, authorities, result boundary, failure policy, availability,
and active state. It exposes declaration truth only and never invokes a
callback or returns secret data.

The conformance ledger requires every family plus evidence for copied values,
deterministic ordering, stale rejection, authority containment,
candidate-only mutation, failure isolation, limits, cleanup, and inspection.
The deterministic Racket fixture contains one admitted provider for every
family and an exact invocation and result pair.

## Focused validation

Use:

```sh
make jan-output-focused-test
```

The target checks the independent Racket generation and invocation model,
complete family fixture, ordering, replacement, derived-backend composition,
authority, candidates, failure containment, cleanup, inspection, and strict
`src/jan_output` tests. It does not execute a Racket provider, apply a document
or Resource candidate, build `src/odra`, or run a repository-wide gate.
