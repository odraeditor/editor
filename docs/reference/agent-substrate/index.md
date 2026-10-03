<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Agent Substrate Reference

The agent substrate lets an active package contribute inert agent and
capability metadata through the restricted package runtime. A trusted host
layer owns explicit authority and durable task continuity. Definition
activation alone does not grant authority, start an agent driver, create a
task, or invoke a capability handler.

The public Racket module is `odra/agents`. Compatibility version 1 exposes:

- `make-agent` and `agent?`;
- `make-agent-capability` and `agent-capability?`;
- bounded agent and capability resource-limit constructors;
- the default resource-limit values;
- capability execution-context inspection and cooperative cancellation;
- `agent-capability-invoke-operation!` for one host-resolved public package
  operation;
- `make-agent-capability-owner-result` and
  `agent-capability-owner-result?`;
- `agent-schema?`; and
- `agent-substrate-api-version`.

Package code does not import the registry, package runtime, persistence, or
owner implementation modules.

The [Agent Package Authoring Reference](authoring.md) specifies package roles,
compatibility, migration, security, the conformance fixture, and diagnostics.

## Manifest Contributions

An agent package declares the `racket-extension` authority and exports
`odra-package-contributions` from a `#lang racket/base` module. The entrypoint
may require `odra/agents`, `odra/commands`, or both.

The manifest uses these contribution facets:

| Facet | Requirements | Effects |
| --- | --- | --- |
| `agent` | required provider-role identities | requested capability identities |
| `agent-capability` | required authority identities | declared effect classes |
| `command` | command requirements | command effects |

Every exported value must match the manifest identity, facet, requirements,
and effects. A count mismatch, unknown value, or unsupported facet rejects the
complete candidate.

```racket
#lang racket/base

(require odra/agents)

(provide odra-package-contributions)

(define odra-package-contributions
  (list
   (make-agent
    'example.agent.canary
    #:display-name "Example canary"
    #:interaction-kinds '(progress request result)
    #:provider-requirements '(odra.agent-driver)
    #:requested-capabilities '(example.text.observe))
   (make-agent-capability
    'example.text.observe
    'example.text
    (lambda (_context)
      (error 'example.text.observe "not executable during registration"))
    #:purpose "Observe one bounded text target."
    #:input-schema
    '(record (target required (owner-reference example.text.target 1)))
    #:result-schema
    '(record (observed required boolean))
    #:target-kinds '(example.text.target)
    #:effects '(observe)
    #:required-authorities '(example.text.read))))
```

The handler is retained for a later admitted capability attempt. Definition
preparation, activation, and inspection never invoke it.

## Agent Definitions

An agent definition contains a semantic identity, display metadata,
interaction kinds, provider requirements, requested capability identities, a
resource profile, continuation policy, compatibility version, and safe source
metadata. Identities are lowercase dotted or hyphenated values with at most
128 UTF-8 bytes.

Interaction kinds are a canonical subset of `acknowledgement`, `cancellation`,
`decision`, `failure`, `progress`, `proposal`, `question`, `request`, and
`result`. Provider and capability sets are bounded, unique, and sorted.

An agent resource profile contains:

| Resource | Default | Hard maximum |
| --- | ---: | ---: |
| Turn deadline | 60 seconds | 15 minutes |
| Resolved context | 256 KiB | 1 MiB |
| Driver output | 64 KiB | 256 KiB |
| Provider events | 1,024 | 4,096 |

These values describe requested limits. They do not create provider access or
runtime authority.

## Capability Definitions

A capability definition contains a semantic identity, owner namespace,
purpose, input and result schemas, target kinds, effect classes, required
authorities, default and hard limits, approval and replay classifications,
verification behavior, retirement policy, compatibility version, safe source
metadata, and one handler.

The effect set is a canonical nonempty subset of `credential-use`,
`external-commit`, `filesystem-read`, `filesystem-write`,
`mutate-editor-state`, `mutate-owned-state`, `network-access`, `observe`,
`process-execution`, and `propose`.

Capability limits use these maxima:

| Resource | Default | Hard maximum |
| --- | ---: | ---: |
| Attempt deadline | 30 seconds | 5 minutes |
| Structured input | 16 KiB | 64 KiB |
| Structured result | 16 KiB | 64 KiB |
| Target references | 8 | 32 |

The selected defaults must remain within the definition's hard limits. Later
request admission can reduce them further.

## Schema Format

Schema format 1 is canonical Racket-readable data. It admits:

- `boolean`;
- `(integer minimum maximum)`;
- `(string maximum-bytes)` and `(bytes maximum-bytes)`;
- `(enum value ...)`;
- `(optional schema)`;
- `(list maximum-items schema)`;
- `(map maximum-items key-schema value-schema)`;
- `(record (field required|optional schema) ...)`; and
- `(owner-reference kind compatibility-version)`.

Records use unique fields in semantic sort order. Schemas are limited to 8
levels, 64 record fields, 256 collection items, and 64 KiB string or byte
values. Procedures, module paths, predicates, reader extensions, and evaluator
directives are invalid.

## Generations and Inspection

Preparation creates one unpublished candidate containing copied safe
projections. Agent projections omit handlers. Capability projections omit
handlers and retain only inert schema and inspection metadata.

Activation composes command, agent, and capability catalogs before changing
the active package map. Duplicate agent identities, duplicate capability
identities, stale contribution generations, or incompatible definitions reject
the candidate and preserve the current catalogs. Replacement publishes the new
catalogs together, then retires the previous package namespace. Deactivation
removes the complete package contribution set before teardown.

The active catalog admits at most 64 agent definitions and 256 capability
definitions. Catalog ordering is deterministic by package and semantic
identity. Inspection returns copied projections containing exact package
identity, package version, contribution generation, definition generation, and
safe definition fields.

Definition discovery is not authority. No active definition can execute its
handler until later authority, admission, and execution stages accept one
exact request.

## Capability Discovery

Discovery starts from one active agent definition and returns only active
capabilities named by that agent's requested-capability set. Each copied row
contains the capability identity and definition generation, owner namespace,
purpose, inert schemas, target kinds, effects, required authorities, visible
limits, approval class, availability, and the requesting agent's grant state.

Discovery never returns a handler, module path, capability token, credential,
policy implementation, target identity, or another agent's grants. An unknown
agent receives an empty result. A visible capability remains unusable until an
explicit grant and a later request-admission stage accept it.

## Deny-by-Default Authority

The initial local authority policy admits no effects or underlying authority.
Package installation, package activation, agent registration, and discovery do
not change that policy.

An explicit grant request binds:

- one stable grant identity;
- the exact agent identity and definition generation;
- one exact capability identity or a bounded final-segment `.*` pattern;
- the exact capability definition generation;
- one typed owner scope;
- requested effects and resource ceilings;
- an optional task restriction;
- bounded delegation depth;
- attributable origin;
- `valid-from`; and
- optional `valid-until`.

Patterns resolve only inside the requesting agent's declared capability set.
Zero matches reject as absent and multiple matches reject as ambiguous. Pattern
order never selects authority.

## Typed Scopes

A target scope contains an owner namespace, target kind, schema compatibility
version, and bounded inert selector. The capability owner namespace and one of
its declared target kinds must match exactly. The substrate does not interpret
a selector as a filesystem prefix or another universal containment rule.

Selectors admit bounded strings, bytes, semantic symbols, exact integers, and
nonempty nested lists. They are limited to 4 levels, 32 items per list, and
4 KiB strings or byte strings. Procedures, ports, paths, module values, and
mutable owner objects reject.

## Effective Grants

Grant creation evaluates the intersection of:

- the explicit requested effects and limits;
- capability effect and hard-limit declarations;
- the active package generation's admitted manifest authorities;
- the local policy's admitted effects, underlying authorities, limits,
  validity, and delegation depth; and
- substrate hard maxima enforced by the public constructors.

A broader policy never enlarges the explicit request. A narrower policy
reduces the published effects, resources, validity, or delegation depth.
Empty effective effects, missing package authority, missing policy authority,
invalid scope, stale definitions, duplicate grant identity, expired validity,
or exhausted grant capacity reject without changing the confirmed grant set.

The first delivery retains at most 1,024 nonexpired grants. The resource study
publishes all 1,024 and verifies that the next grant rejects atomically.

## Expiry, Revocation, and Inspection

Inspection returns copied grant projections, optionally restricted to one
agent. It computes `pending`, `active`, `expired`, or `revoked` at the supplied
observation time. Expiry does not reactivate. A definition-generation change
makes an otherwise active grant ineffective until a new compatible grant is
created.

Revocation requires the exact current grant generation. Successful revocation
increments that generation and makes the grant ineffective for new admission
immediately. A stale or repeated revocation does not change authority.
Publication failure during grant creation or revocation preserves the last
confirmed grant set.

Common rejection codes are `absent-agent`, `absent-capability`,
`ambiguous-capability`, `stale-agent`, `stale-capability`, `invalid-scope`,
`package-authority`, `policy-authority`, `duplicate-grant`, `expired`,
`grant-limit`, `stale-grant`, `revoked`, and `publication-failure`.

## Durable Task Store

The trusted Racket substrate owns one SQLite database named
`agent-substrate.sqlite3` beneath its assigned package data root. Schema
version 1 persists tasks, participants, interactions, delegations, capability
requests, decisions, driver-session summaries, and turns. Schema creation and
every multi-record state change run in a database transaction. A failed
transaction leaves the last confirmed generation intact.

Restricted packages never receive the database connection, path, SQL API, or
table access. They receive deliberate substrate operations in later runtime
composition. Active definitions remain rebuildable from package generations;
task continuity is operational state and survives process restart.

The hard limits currently enforced by this layer are:

| Resource | Limit |
| --- | ---: |
| Nonterminal tasks | 128 |
| Participants per task | 16 |
| Task ancestry depth | 8 |
| Typed references per record | 32 |
| Inline task objective | 16 KiB |
| Inline interaction payload | 64 KiB |
| Retained interactions | 10,000 |
| Retained delegations | 10,000 |

Queries use deterministic timestamps and stable identities and never return
more than the retained family limit.

## Tasks and Participants

A task has an identity that remains stable across participants, retries,
surfaces, process restarts, and future provider sessions. Provider session and
conversation identifiers are not task identity. Each state transition checks
the exact current task generation and active acting participant.

The initial lifecycle is:

```text
created -> ready -> running -> waiting
                        |        |
                        |        -> running
                        -> blocked
                        -> succeeded
                        -> failed
                        -> cancelled
```

Waiting and blocked work can return to `running`. Failed, succeeded, and
cancelled tasks are terminal. A transition to `succeeded` requires at least
one typed result or evidence reference; an agent assertion alone is not
success.

Creating an owned task publishes the task and its owner participant in the
same transaction. A task has at most one owner. Additional participants use
the `delegate`, `observer`, or `reviewer` role and carry their own generation,
visibility, join time, and optional departure reason. The current owner cannot
leave through the ordinary participant-removal operation.

Parent tasks must already exist. A task cannot name itself or a descendant as
its parent, and ancestry cannot exceed eight levels.

## Typed Owner References

A typed owner reference records an owner namespace, reference kind,
compatibility version, opaque identity, and owner generation. Tasks,
interactions, and delegations retain these references without decoding the
identity or copying the owned object. The owner remains responsible for
validity, current generation, visibility, and canonical state.

Owner identities use bounded inert values only. Procedures, ports, paths,
mutable objects, module paths, reader extensions, and evaluator directives do
not enter the persisted record.

## Interaction Envelopes

An interaction is an immutable attributed record. It identifies sender,
optional acting agent, recipient, task and parent task, optional owner
namespace, interaction kind, bounded payload, context references, visibility,
correlation and idempotency identities, validity, and provenance.

The admitted kinds are `request`, `question`, `decision`, `progress`,
`proposal`, `result`, `failure`, `cancellation`, and `acknowledgement`. Inline
payloads are inert values limited to 64 KiB. Context references remain typed
and opaque. Agent-originated interactions require an active participant, and
the provenance actor must match the sender.

Interaction identity is unique and immutable. Recording another envelope with
changed content requires a new identity. Interaction text cannot grant
authority, prove an external effect, or replace a checked owner result.

## Delegation

A delegation relates one parent task, distinct sender and recipient agents, a
bounded requested outcome, optional child task, context references, an
authority ceiling, state, deadline, and terminal result reference. Both agents
must already be active task participants. The sender must be an owner or
delegate, and the recipient must have the delegate role.

The authority ceiling contains capability identities, not grant tokens. At
creation and again before acceptance or execution, the substrate consults the
current authority store. For every capability:

- the sender must hold an effective grant that permits delegation;
- the recipient must independently hold an effective grant; and
- task restrictions and current definition generations must still match.

Revocation or expiry therefore prevents a pending delegation from advancing.
Delegation never copies a sender grant to the recipient. Later capability
admission rechecks the recipient's own authority.

The delegation lifecycle is `proposed`, `accepted`, `running`, followed by
`completed`, `failed`, or `cancelled`; a proposal may also be rejected. Only
the recipient can accept, reject, run, complete, or fail delegated work.
Either participant can cancel it. Completion requires a typed result
reference.

## Recovery and Failure Behavior

Closing and reopening the store reconstructs the same task, participant,
interaction, and delegation records. Generations prevent stale callers from
overwriting later state. SQLite foreign keys preserve record relationships,
and compare-and-swap updates prevent stale publication inside a transaction.

If task creation fails after staging its owner participant, the complete
transaction rolls back. If authority is reduced after a delegation is
accepted, the delegation remains inspectable at its last confirmed state and
cannot advance to `running`.

## Capability Requests

A capability request is an immutable proposal. Recording it does not admit or
execute the capability. Compatibility version 1 binds each request to:

- exact task and task generation;
- exact agent identity and definition generation;
- the active agent registration reference;
- exact capability identity and definition generation;
- package identity, version, and contribution generation;
- input schema identity and compatibility version;
- bounded structured input and explicit typed targets;
- requested effects and capability limits;
- exact grant identities and generations;
- optional human-decision, correlation, and idempotency references; and
- creation and expiry times.

The first compatibility version uses an exact active registration reference.
Provider binding remains separate from semantic agent identity and from the
task that survives provider replacement.

Requests persist in `agent-substrate.sqlite3`. A repeated request identity is
rejected; changed input, targets, effects, limits, grants, or generations
require a new identity. At most 10,000 request records are retained by this
compatibility version.

## Schema and Target Validation

Admission validates the inert schema declared by the active capability.
Booleans, integer ranges, bounded strings and bytes, enums, optional values,
lists, maps, closed records, and typed owner references follow the same schema
format used by capability definitions. Unknown record fields, absent required
fields, oversized values, or type mismatches reject before admission.

Every owner reference found through the input schema must appear in the
request's explicit target list in the same order. This prevents hidden targets
inside structured input. The target count and encoded input must remain within
the request limits.

Target owners register a versioned target kind with two bounded callbacks:

- validation reports `valid`, `stale`, or `unavailable`;
- containment reports `valid`, `outside-scope`, `stale`, or `unavailable` for
  one target and grant scope.

The substrate routes copied references and scopes to those callbacks. It does
not interpret filesystem paths, buffer identities, project membership, or any
other owner-specific target semantics. Missing definitions, callback failures,
stale targets, and scope escape reject closed.

## Admission Order

One admission evaluation uses the persisted request and checks, in order:

1. request validity time;
2. current nonterminal task generation and active participant;
3. active agent definition and registration generation;
4. capability visibility, definition generation, and package generation;
5. input schema reference and value;
6. explicit target equality, owner validation, and scope containment;
7. effect, input, target, and resource limits;
8. required idempotency identity;
9. exact current grant generations and complete-request authority; and
10. local admission policy and any required human decision.

The resulting admission decision is immutable and has one of three states:
`admitted`, `rejected`, or `needs-human-decision`. Repeating evaluation with
the same decision identity returns the confirmed decision. Another decision
identity for the same request rejects.

An admitted decision records only the effects, limits, and current grants that
validated the complete request. It still does not call the capability handler,
publish owner state, create an operation attempt, or claim success.

## Human Decisions

The local admission policy names admitted effects, effects requiring a human,
admitted human actors, request-validity limits, and an exact policy generation.
Capability approval classes `always` and `ask-once` also require a human
decision.

A human decision records exactly one request, task, actor, value, request scope,
captured generations, creation time, validity, and consumption state. Its value
is `approve-once`, `reject`, or `cancel-task`. The captured scope includes the
request's input, targets, effects, limits, grants, and generations. A decision
for one request cannot authorize another request with otherwise identical
content.

`approve-once`, `reject`, and `cancel-task` are consumed in the same SQLite
transaction that publishes the final admission decision. Consumption advances
the human-decision generation and records the consuming admission identity.
Approval creates no reusable grant. A broader or persistent authorization must
use the explicit grant workflow.

Callers that know a human decision is required may record it before requesting
the one final admission decision. Without one, the final state is
`needs-human-decision`; admission decisions are not edited in place.

## Admission Diagnostics

Stable rejection codes distinguish `expired-request`, `absent-task`,
`stale-task`, `terminal-task`, `absent-participant`, `absent-agent`,
`stale-agent`, `stale-registration`, `absent-capability`,
`invisible-capability`, `stale-capability`, `stale-package`, `stale-schema`,
`schema-mismatch`, `target-mismatch`, `target-escape`, `effect-escape`,
`limit-escape`, `input-limit`, `target-limit`, `missing-idempotency`,
`stale-grant`, `inactive-grant`, `authority-denied`, `policy-validity`,
`policy-effect`, and invalid or rejected human decisions.

Diagnostics contain bounded safe text. They do not expose handler values,
credentials, policy implementation, target internals, or database handles.

## Agent Drivers

The trusted host-facing driver contract is provider neutral. Compatibility
version 1 uses the role `odra.agent-driver`; the deterministic reference
implementation uses the identity `odra.agent-driver.deterministic`. A driver
registration declares one semantic identity, monotonically increasing
generation, complete compatibility feature set, safe source description, and
four one-argument callbacks for open, turn, cancel, and close.

The required feature set is:

- `session-open` and `turn`;
- `continuation`;
- `interaction-output` and `request-proposal-output`;
- `usage` and `safe-failure`; and
- `cancel` and `close`.

A registration with a missing feature, malformed callback, or stale generation
is rejected. Replacing a driver definition does not silently migrate an open
session. The substrate requires an explicit session rebind to the newer driver
generation.

Driver callbacks receive copied records. They never receive a capability
handler, executable grant token, database connection, another provider's
credentials, or a private owner module. Deterministic, model-backed, and hybrid
adapters implement the same callback contract and produce the same output
records.

## Driver Sessions

Opening a session binds one exact agent registration, task generation, agent
definition generation, driver identity and generation, and effective resource
profile. The persisted session lifecycle is `opening`, `available`, `busy`,
`cancelling`, `closed`, `failed`, or `reconciling`.

The provider may return bounded opaque provider-session and continuation
identities. Those identities cannot contain credentials and are not the agent
or task identity. Closing a session calls the bound driver generation and
releases its provider-owned resources. A process restart preserves the session
summary; later recovery work decides whether a nonterminal provider session is
still owned by a live runtime.

The first compatibility version retains at most 128 driver sessions. Session
updates are generation checked, so stale close, replacement, or turn calls
cannot overwrite a newer state.

## Bounded Turns

Preparing a turn checks an available exact-generation session, current task
and agent generations, active task participation, the current capability
catalog generation, and the per-task turn limit. It copies only selected
task interactions, typed owner references, and safe capability discovery
projections into the invocation context.

The initial hard limits are:

| Resource | Limit |
| --- | ---: |
| Turns per task | 8 |
| Input interaction references | 32 |
| Typed context references | 32 |
| Driver output items | 64 |
| Input or output token observation | 1,000,000 |
| Observed cost | 100,000,000 micros |

The agent definition's resource profile supplies the smaller effective
deadline, context-byte, output-byte, and provider-event ceilings. Preparing a
turn makes its session busy atomically and captures one deadline. Invocation
uses that copied context and exact visible-capability generation. It does not
resolve handlers or execute a capability.

Cancellation invokes the bound driver's cancellation callback when it remains
available, marks the turn terminal, and releases the session. Output arriving
after cancellation is stale and cannot publish. A deadline that expires before
invocation fails the turn and releases the session. Provider exceptions become
bounded safe failures without exposing provider diagnostics.

## Output Validation and Publication

A driver can emit `question`, `progress`, `proposal`, `request`, `terminal`,
and `failure` items. The substrate treats the complete output as untrusted.
Before publication it checks:

- output kinds, inert payload shape, encoded size, and event count;
- observed input, output, token, and cost usage;
- the agent's declared continuation policy;
- interaction, request, and retained-record bounds;
- request-draft capability visibility, input schema, explicit typed targets,
  effects, hard limits, exact grants, and validity; and
- stable identity collisions.

Validated non-request items become attributed interaction envelopes. A request
draft becomes an immutable Capability Request bound to the active package,
schema, task, registration, agent, capability, and grant generations. It then
uses the ordinary admission path; the driver cannot admit or execute it.

Interactions, request proposals, the terminal turn, and the released session
publish in one SQLite transaction. Malformed or partially valid output
publishes none of its proposed records. A completed turn reports only driver
output and observed usage. It cannot claim that an owner effect succeeded.

## Driver Authoring Sequence

A deterministic or model-backed host adapter follows this sequence:

1. construct a driver definition with the complete compatibility feature set;
2. register its exact generation in the trusted driver registry;
3. open a session for one active registration and task;
4. prepare a turn from explicitly selected interactions and context
   references;
5. return bounded output items plus observed usage from the turn callback;
6. let the substrate validate and atomically publish the output; and
7. cancel, close, or explicitly replace the session when provider ownership
   changes.

Model adapters own authentication, provider event decoding, continuation
handles, and provider-specific cancellation. The substrate owns task
continuity, request construction, limits, attribution, and durable state.

## Capability Execution

An admitted request does not execute by itself. The substrate prepares one
operation attempt with a unique identity, exact admission decision, opaque
lease identity, hard deadline, and revocable invocation-context generation.
Compatibility version 1 permits one attempt for a request. Later retry policy
can add another attempt only after checking the capability's idempotency and
current authority again.

The attempt lifecycle is `starting`, `running`, `cancelling`, `reconciling`,
then `completed` or `failed`. Each transition checks the current attempt
generation. A late callback holding an older generation cannot revise a
cancelled or terminal attempt.

The initial retained limits are 10,000 attempts, 10,000 results, 32 owner
evidence references, 32 external evidence references, and 4 KiB safe result
summaries. The admitted capability limits provide the smaller execution
deadline and result-byte ceiling.

## Owner Invocation Context

The substrate resolves the handler from the exact active capability package,
version, contribution generation, semantic identity, and definition
generation captured by the request. Missing or replaced owner generations
fail closed.

The handler receives a copied `agent-capability-execution-context?` through
the public `odra/agents` module. Package code can inspect:

- attempt, request, task, agent, and capability identities;
- copied structured input and typed target references;
- admitted effects and effective limits;
- the hard deadline; and
- cooperative cancellation through
  `agent-capability-cancellation-requested?`.

The context contains no database connection, admission-policy implementation,
other agent state, capability registry, executable grant, provider credential,
or private substrate module. The cancellation predicate becomes true when the
attempt is cancelled, expires, loses runtime ownership, or advances to another
invocation-context generation.

`agent-capability-invoke-operation!` accepts the execution context and one
semantic operation identity. The trusted host resolves that identity against
the active package generation and supplies the already checked owner context.
Cancellation is checked before invocation. The operation must return a
bounded capability owner result; a missing operation or malformed result
fails without exposing package internals.

This operation boundary lets an integration reuse a package's public domain
operation. It does not grant cross-package module imports, direct registry
access, or ambient command execution.

A capability handler returns a value created with
`make-agent-capability-owner-result`. Example:

```racket
(make-agent-capability
 'example.text.observe
 'example.text
 (lambda (context)
   (if (agent-capability-cancellation-requested? context)
       (make-agent-capability-owner-result
        'cancelled
        #:safe-summary "Observation was cancelled before completion.")
       (make-agent-capability-owner-result
        'succeeded
        #:result '((observed #t))
        #:confirmed-effects '(observe)
        #:safe-summary "The current target was observed.")))
 #:input-schema
 '(record (target required (owner-reference example.text.target 1)))
 #:result-schema
 '(record (observed required boolean))
 #:target-kinds '(example.text.target)
 #:effects '(observe))
```

Owner result states are `succeeded`, `rejected`, `cancelled`, `timed-out`,
`failed`, `outcome-unknown`, and `revoked`. The result also carries bounded
owner evidence, external evidence, confirmed effects, and a safe summary.

## ROT13 Vertical Canary

The reference path uses these identities:

| Role | Identity | Dependency or contribution |
| --- | --- | --- |
| Deterministic agent package | `odra.rot13-canary-agent` | contributes `odra.rot13-canary` |
| Driver | `odra.agent-driver.deterministic` | satisfies `odra.agent-driver` |
| Integration package | `odra.rot13-agent-integration` | depends on `odra.agent-substrate` and `odra.rot13` |
| Capability | `odra.rot13.region` | targets one active buffer and non-empty region |
| Public package operation | `rot13-region` | owned by `odra.rot13` |

The agent requests `observe` and `mutate-editor-state` with a 5-second
deadline, 4 KiB input and result ceilings, and at most two target references.
The capability uses `ask-once`, `non-idempotent`, `immediate`, and `cancel` for
approval, replay, verification, and retirement.

The integration handler contains no ROT13 implementation:

```racket
(lambda (context)
  (agent-capability-invoke-operation! context 'rot13-region))
```

The host resolves the active command, runs it with the checked editor context,
and publishes one transaction. Removing the integration withdraws the
capability. Removing the canary agent withdraws the agent definition. Neither
change alters direct `rot13-region` use.

## Checked Results

Owner output is untrusted until the substrate verifies it. A successful result
must come from the exact invoked handler generation, match the declared result
schema, stay within the admitted result-byte limit, report only admitted
effects, and contain bounded typed evidence. Raw values, process exit codes,
provider text, and schema-invalid success claims become failed results.

Result publication writes one immutable Operation Result and the terminal
attempt generation in the same SQLite transaction. A failed publication leaves
the attempt running and exposes no partial result. Repeated or late callbacks
cannot create another result for the same attempt.

The persisted result records:

- request and attempt identities;
- terminal state;
- exact result schema reference when structured success exists;
- checked structured result;
- owner and external evidence references;
- confirmed effects;
- bounded safe summary; and
- completion time.

`succeeded` means that the capability owner returned schema-valid checked
output. It does not allow the agent driver to assert success and does not let
the substrate reconstruct canonical owner state from prose.

## Cancellation, Deadlines, and Uncertainty

Cancellation increments the invocation-context generation before settlement.
An owner that is still running observes the cancellation predicate and should
release its resources promptly. Output arriving after cancellation is stale.
The substrate settles a cancelled attempt with one terminal result; it never
claims that already confirmed effects were rolled back.

An attempt that expires before handler invocation becomes `timed-out` and does
not call the owner. A late read-only callback also becomes `timed-out`. When a
late callback or in-flight cancellation may have committed a consequential
effect such as a filesystem write, process execution, network operation,
credential use, editor mutation, owned-state mutation, or external commit, the
result is `outcome-unknown`.

`outcome-unknown` is terminal local knowledge, not proof of success or failure.
The capability owner remains responsible for a separate verification operation
and current external evidence. Automatic replay is prohibited until current
authority, idempotency, and verification policy establish that retry is safe.

Capability owners are responsible for checking cancellation at useful
boundaries, enforcing owner-specific resource limits, returning current typed
evidence, distinguishing preparation from commitment for external effects,
and releasing files, processes, network sessions, and other resources on every
terminal path.

## Audit History

The substrate stores append-only audit events in the continuity database. Each
event has a stable identity, one database-wide sequence, occurrence time,
event kind, actor identity, optional task identity, causal subject and evidence
references, captured generations, effect class, outcome, visibility, and
redaction class. Inspection is ordered by sequence and limited to 1,024 events
per query.

Audit outcomes contain bounded inert data. One event is limited to 16 KiB and
32 references in each reference family. Raw prompts, provider transcripts,
credentials, executable values, and database handles are not audit data. The
initial store retains at most 100,000 events. A duplicate event identity and a
write beyond the retained limit reject without changing the confirmed log.

Visibility is `administrator`, `local-user`, `participants`, or `public-safe`.
Redaction is `identity-only`, `safe-summary`, or `none`. These fields govern
later presentation; they do not make the event replayable and do not grant
authority.

## Restart Reconciliation

At startup, the trusted host queries durable records whose state still implies
live runtime ownership. Driver sessions in `opening`, `available`, `busy`, or
`cancelling`; turns in `prepared`, `running`, or `waiting`; and attempts in
`starting`, `running`, or `cancelling` move to `reconciling`. Each transition:

1. checks the exact stored generation;
2. increments that generation and invalidates the invocation context where
   applicable;
3. records a bounded `runtime-ownership-lost` failure;
4. writes a generational reconciliation marker; and
5. appends an identity-only startup audit event.

Terminal records and records already in `reconciling` remain unchanged. A
second startup pass therefore does not replay work or duplicate a transition.
The marker identifies the record kind, identity, prior generation, prior
state, marker generation, and observation time. It contains no provider
session, handler, prompt, or owner payload.

Reconciliation does not infer an operation result. A running or cancelling
attempt is marked outcome-uncertain until its owner supplies fresh bounded
evidence. Tasks, immutable requests, decisions, and terminal results remain
available for inspection; their mere presence never causes automatic replay.

## Package Lifecycle

The lifecycle reconciler compares the previously confirmed agent catalog with
the newly active catalog. A missing definition or a changed definition
generation retires the old projection. The transition then:

- writes one bounded tombstone for the retired generation;
- revokes active grants that name the retired agent or capability generation;
- moves affected nonterminal sessions, turns, and attempts to
  `reconciling`;
- rebuilds SQLite indexes from confirmed records; and
- appends a lifecycle audit event with aggregate counts.

Requests stay bound to their original package identity, version, contribution
generation, capability generation, and schemas. Lifecycle reconciliation does
not migrate them to a replacement package. Compatible replacement can retain
semantic identities, but new work needs authority and admission against the
new generations.

A tombstone records the semantic identity, final definition generation,
definition kind, package identity and version, contribution generation,
compatibility version, safe display and owner identities, target and effect
classes, retirement reason and time, and a digest of the safe projection. It
does not retain package code, handlers, credentials, prompts, provider state,
unrestricted payloads, or canonical owner objects. The initial store admits
at most 10,000 tombstones.

## Disablement, Retention, and Repair

Substrate disablement writes tombstones for the confirmed definition catalog
and an attributable audit event. It leaves tasks, interactions, delegations,
requests, decisions, sessions, turns, attempts, results, audit events, typed
owner references, and tombstones in the continuity database. It does not open,
rewrite, or delete the external state named by an owner reference.

Retention cleanup is explicit and bounded. The current cleanup operation
removes at most 1,024 expired reconciliation markers per call and records the
count in a new audit event. Tombstones and operational history are not removed
by that operation. Product policy retains terminal operational summaries for
90 days, audit events for 365 days, and tombstones while retained history
references them and for 365 days after the final reference expires; later
cleanup stages must preserve those reference conditions.

SQLite indexes contain no unique canonical state. The trusted host may run the
index rebuild operation after restart, package replacement, or index damage.
The tables remain authoritative during that rebuild. A failed audit,
tombstone, marker, or state transition rolls back its database transaction and
leaves the last confirmed generation inspectable.

## Local Interaction Commands

The substrate package defines these stable semantic command identities:

| Command | Result |
| --- | --- |
| `agent-list` | Lists discoverable agents and current availability. |
| `agent-describe` | Shows one agent, provider requirements, requested capabilities, grants, limits, and provenance. |
| `agent-task-start` | Selects an available agent and creates one bounded task. |
| `agent-task-list` | Lists visible tasks and pending attention. |
| `agent-task-open` | Opens one selected task and its ordered interactions. |
| `agent-send` | Adds one inert user interaction to a selected task. |
| `agent-request-list` | Lists pending and recent capability requests. |
| `agent-request-decide` | Approves once, rejects, or cancels the task for one exact pending request. |
| `agent-grant` | Creates one explicit bounded capability grant. |
| `agent-revoke` | Revokes one exact current grant generation. |
| `agent-cancel` | Requests cancellation of one selected task, turn, or attempt. |
| `agent-inspect` | Opens a safe projection of a visible substrate record. |
| `agent-audit` | Lists bounded attributable audit history. |

Commands that need an object use filtered candidates. They do not require a
raw internal identity. Filtering matches safe labels, identities, and summaries
incrementally. A candidate retains its semantic identity and generation; every
state-changing action validates both again before mutation.

## Inspection Projections

One inspection projection contains a record kind, semantic identity,
generation, human-readable label, state, safe summary, attention marker,
bounded detail fields, and safe relations to other projections. The supported
kinds are `agent`, `capability`, `driver`, `driver-session`, `grant`, `task`,
`interaction`, `request`, `decision`, `turn`, `attempt`, `result`, `audit`, and
`reconciliation`.

Inspection returns at most 1,024 projections. Candidate flows return at most
256 items. Results have deterministic kind, label, and identity ordering.
Identity-only audit events remain visibly redacted, and inspection never
returns handlers, credentials, provider-private values, database connections,
or executable authority.

## Presentation Contract

The local presentation model supports widths of 24 columns or more and at most
256 visible rows. It removes control characters from visible text, truncates
long content to the current width, leads with human-readable labels and state,
and keeps exact identities available in detail.

Candidate, task, detail, empty-state, and diagnostic surfaces use the same
safe projections. Empty surfaces name the next useful action. Diagnostics
distinguish stale selection, missing records, denied authority, and exhausted
limits. A stale candidate cannot act on a replacement generation.

Starting a local task requires an available current agent candidate, a bounded
objective, an attributable local actor, and optional typed context references.
Sending text requires one current nonterminal task candidate. The resulting
text is an interaction payload only; it is not evaluated as Racket, shell,
Odin, JavaScript, a command identity, or a capability request.

Grant, human-decision, revocation, cancellation, and uncertainty actions call
the canonical substrate operations. `approve-once` creates no reusable grant.
Revocation blocks new admission immediately. Cancellation preserves pending
and reconciliation states when owner settlement is not yet known.
Acknowledging `outcome-unknown` records an attributable audit event and leaves
the result uncertain.
