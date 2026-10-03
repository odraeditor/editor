<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Agent Package Authoring Reference

This reference covers agent definitions, capability integrations, compatibility,
security, and the conformance fixture for agent packages. The stable package
module is `odra/agents`. Compatibility version 1 is the current public
contract.

Provider drivers are trusted host adapters. An ordinary package may declare a
required provider role, but it does not register a driver or receive provider
credentials.

## Package Roles

The substrate recognizes two package-owned roles.

| Role | Public constructor | Manifest facet | Runtime responsibility |
| --- | --- | --- | --- |
| Agent definition | `make-agent` | `agent` | Declares interaction kinds, provider roles, requested capabilities, and limits. |
| Capability integration | `make-agent-capability` | `agent-capability` | Owns schemas, targets, effects, limits, admission metadata, and one bounded handler. |

An agent definition and a capability integration may live in separate
packages. This is the preferred layout when the capability belongs to an
existing package. The integration package can invoke a public operation of
that package through `agent-capability-invoke-operation!`.

## Public Module

`odra/agents` exports:

- `agent-substrate-api-version`;
- `make-agent` and `agent?`;
- `make-agent-resource-profile`, `agent-resource-profile?`, and the default
  profile;
- `make-agent-capability` and `agent-capability?`;
- `make-agent-capability-limits`, `agent-capability-limits?`, and the default
  limits;
- `agent-schema?`;
- execution-context predicates and copied-field accessors;
- `agent-capability-cancellation-requested?`;
- `agent-capability-invoke-operation!`; and
- `make-agent-capability-owner-result` plus its predicate.

Package entrypoints must not import registry, admission, persistence,
inspection, package-runtime, or hosting modules. Those modules belong to the
trusted host.

## Agent Definition

```racket
#lang racket/base

(require odra/agents)

(provide odra-package-contributions)

(define odra-package-contributions
  (list
   (make-agent
    'example.notes.agent
    #:display-name "Notes Agent"
    #:description "Works with explicitly selected note targets."
    #:interaction-kinds '(progress request result)
    #:provider-requirements '(odra.agent-driver)
    #:requested-capabilities '(example.notes.normalize)
    #:continuation-policy 'bounded
    #:source "example.notes-agent")))
```

The manifest contribution repeats the semantic identity. Its requirements are
the provider roles, and its effects are the requested capability identities.
The runtime rejects disagreement between the manifest and exported value.

An agent definition contains no provider token, prompt transcript, capability
handler, grant, or executable authority.

## Capability Integration

```racket
#lang racket/base

(require odra/agents)

(provide odra-package-contributions)

(define limits
  (make-agent-capability-limits
   #:deadline-milliseconds 5000
   #:input-bytes 4096
   #:result-bytes 4096
   #:target-references 1))

(define odra-package-contributions
  (list
   (make-agent-capability
    'example.notes.normalize
    'example.notes
    (lambda (context)
      (agent-capability-invoke-operation! context 'normalize-note))
    #:purpose "Normalize one exact note selected by the user."
    #:input-schema
    '(record
      (note required (owner-reference example.notes.note 1)))
    #:result-schema
    '(record (revision required (integer 1 9223372036854775807)))
    #:target-kinds '(example.notes.note)
    #:effects '(mutate-owned-state)
    #:required-authorities '(racket-extension)
    #:default-limits limits
    #:hard-limits limits
    #:approval-class 'ask-once
    #:idempotency-class 'non-idempotent
    #:verification-class 'immediate
    #:retirement-policy 'cancel
    #:source "example.notes-agent-integration")))
```

The handler receives a copied execution context only after discovery, grant,
request validation, policy, human decision when required, and attempt
admission have succeeded. It may inspect the declared context fields, check
cancellation, call an admitted public owner operation, and return one bounded
owner result.

The handler cannot access the substrate database, resolve another capability,
change its grant, or publish its own canonical success.

## Result Contract

Use `make-agent-capability-owner-result` for every handler outcome. A success
must match the declared result schema and list only admitted effects. Evidence
uses typed owner references; raw provider responses, credentials, and private
objects are invalid.

Check `agent-capability-cancellation-requested?` before expensive work and at
useful interruption boundaries. A consequential operation that may have
committed before ownership was lost must report or preserve
`outcome-unknown`. Do not retry it automatically.

## Manifest Alignment

The package manifest must declare `racket-extension` authority and a
`racket-module` entrypoint. Contribution facets align as follows:

| Exported value | Facet identity | Requirements | Effects |
| --- | --- | --- | --- |
| Agent definition | Agent identity | Provider roles | Requested capability identities |
| Capability definition | Capability identity | Required package authorities | Declared effect classes |

Dependencies name packages, not private modules. An integration that delegates
to another package's public operation declares both `odra.agent-substrate` and
the owner package as dependencies.

## Compatibility Policy

`agent-substrate-api-version` identifies the public constructor and execution
context contract. Compatibility version 1 follows these rules:

- adding optional descriptive metadata is compatible;
- increasing a package or contribution generation does not change semantic
  compatibility by itself;
- changing an input schema, result schema, target kind, effect class,
  idempotency class, or owner semantics requires an explicit compatibility
  decision;
- an incompatible capability should use a new semantic identity or a later
  compatibility version;
- a replacement keeps the semantic identity only when current callers can
  satisfy the same contract; and
- retained requests and attempts stay bound to the exact package and
  definition generations captured at admission.

Package SemVer describes the package release. Contribution generation orders
runtime activation. Definition compatibility describes the public agent or
capability contract. These values solve different problems and must remain
explicit.

## Migration

For a compatible implementation replacement:

1. keep the semantic identity and compatibility version;
2. increment the package release and contribution generation;
3. preserve schemas, targets, effects, and result meaning;
4. activate the replacement as one complete package generation; and
5. let lifecycle reconciliation retire the prior generation and revoke stale
   grants.

For an incompatible capability change:

1. publish a new capability identity or compatibility version;
2. update agent definitions to request the new identity;
3. keep the old definition available only while its exact package generation
   remains supported;
4. require new grants and requests; and
5. remove the old definition through ordinary package lifecycle handling.

The substrate database is host-owned. Package migrations never rewrite its
tables. Package-owned canonical state remains in the owner package and is
referenced through typed owner references.

## Security Requirements

- Treat driver output and capability input as untrusted.
- Declare every target kind and effect.
- Use the smallest default and hard limits that support the operation.
- Keep credentials in the provider or owner boundary that owns them.
- Never place secrets in source descriptions, summaries, evidence, audit
  payloads, continuation references, or provider-session references.
- Resolve owner operations through the public host boundary.
- Check cancellation before commitment and during long work.
- Return current typed evidence for external or owned effects.
- Preserve uncertain outcomes when success or rollback cannot be proven.
- Release files, processes, network sessions, and other owned resources on
  every terminal path.

Activation grants no capability authority. Discovery grants no capability
authority. Only the explicit grant and admission path can create an executable
attempt.

## Conformance Fixture

Run the repository-owned conformance runner against a fixture module:

```sh
racket scripts/check-agent-substrate-conformance.rkt \
  --fixture path/to/conformance-fixture.rkt
```

The fixture exports:

| Export | Contract |
| --- | --- |
| `package-id` | Package identity string |
| `package-version` | SemVer string |
| `contribution-generation` | Positive exact integer |
| `package-authorities` | Canonical authority symbols |
| `agent-definition` | One value from `make-agent` |
| `capability-definition` | One value from `make-agent-capability` |
| `driver-definition` | Deterministic test driver implementing the trusted driver contract |
| `target-reference` | One typed owner reference |
| `target-registry` | Test owner validation and containment registry |
| `request-input` | Schema-valid inert request input |

The deterministic driver and target registry are test harness adapters. They
do not become package contributions.

The runner proves six cases: agent definition, driver, capability owner,
admission, execution, and durable reload. The canonical example is
`tests/agent_substrate/conformance_fixture.rkt`. The complete focused target is:

```sh
make agent-substrate-conformance-test
```

## Troubleshooting

| Failure | Check |
| --- | --- |
| Definition did not enter the catalog | Manifest identity, contribution facet, package authority, and generation |
| Agent does not request the capability | Exact semantic identity and canonical requested-capability list |
| Driver session rejected | Provider role, driver generation, active task participant, and complete driver features |
| Grant rejected | Target scope, effects, authorities, hard limits, task restriction, and validity |
| Admission rejected | Schema value, typed targets, owner containment, exact generations, current grant, and policy |
| Owner invocation rejected | Active capability generation, attempt lease, deadline, cancellation, and package lifecycle |
| Owner output failed conformance | Result schema, encoded size, confirmed effects, evidence, and safe summary |
| Reload case failed | SQLite path, transaction completion, exact record identity, and store ownership |

Use the [Agent Substrate Reference](index.md) for record fields, limits, and
lifecycle states. Use the
[local-agent operations guide](../../how-to/operate-local-agents/index.md) for
runtime inspection and recovery.
