<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan External Protocols Reference

Jan external protocols admit link, media, capture, and source-location requests
without transferring filesystem, network, credential, command, or navigation
ownership into `jan_output`. The package validates copied provider observations
and request values, then returns a bounded effect plan to the established
Resource, command, and remote-access owners.

## Provider contract

A protocol provider descriptor carries a stable identity, exact generation,
closed capability set, availability, admission decision, and authentication
generation. The supported capabilities are:

- follow a link;
- store a link;
- search links;
- preview a link;
- intake media;
- start capture; and
- open a source location.

Selection requires exactly one matching identity and generation. A stale
generation, duplicate descriptor, unavailable provider, missing capability,
failed admission, or mismatched authentication generation rejects before an
effect plan exists. Provider declarations never grant filesystem, transport,
credential, or editor authority by themselves.

## Link and media operations

`prepare_link_effect` accepts one explicit request and produces a checked
owner handoff:

| Action | Required input | Planned owners |
| --- | --- | --- |
| Follow | bounded locator | Resource read and navigation |
| Store | exact source Resource and revision | Resource read |
| Search | bounded query and result limit | Resource read |
| Preview | bounded locator and byte limit | Resource read and preview |
| Media intake | bounded locator plus exact destination Resource revision | Resource read and write |

Every request binds an operation, provider generation, authentication
generation, byte and result limits, and only the fields valid for its action.
Extra or ambiguous Resource fields reject instead of being ignored.

The plan retains exact source and destination versions, locators or queries,
and required owner classes, but performs no lookup, fetch, write, preview, or
navigation. Completed provider results must match the operation and provider
generation and remain within the planned limits. Failed and cancelled results
are valid only when they report no resource, bytes, results, or completion.

## External request envelope

External tools use schema version 1. Every envelope carries:

- an explicit operation and bounded encoded payload size;
- an exact provider and provider generation;
- caller identity, caller instance, and caller generation;
- issue, expiry, and observation times;
- independent nonce and payload digests;
- verified authentication and its exact generation; and
- one typed action payload.

The validity window is at most 15 minutes. A request observed before issue or
after expiry is stale. Authentication contents and credentials remain with the
selected provider; Jan retains only the verified generation boundary.

Decoded initial values use a closed, non-executable vocabulary: URL, title,
body, selection, and annotation. Values are unique by kind and their aggregate
text must fit inside the already bounded encoded payload. They cannot inject a
template, Racket configuration, command name, provider definition, or effect
authority.

## Entrypoints

Three external actions are admitted:

- `store-link` accepts a locator plus optional title and annotation values and
  plans one link-state change;
- `start-capture` selects an already confirmed template generation, accepts
  bounded initial values and an optional exact target Resource, and plans one
  document change; and
- `open-source` identifies an exact Resource revision plus a source-block or
  structural-node location and plans navigation only.

The dispatch plan records schema, caller, provider, authentication, nonce, and
payload-digest generations without retaining initial-value text. The original
admitted request remains caller-owned for the immediate command handoff.

## Replay boundary

Admission creates a replay reservation containing caller identity and
generation, operation identity, nonce digest, expiry, and `reserved` state.
Another request from the same caller generation with the same operation or
nonce rejects. Every terminal completed, failed, or cancelled outcome consumes
the reservation, preventing a failed request from being replayed as new work.

Retention of replay records belongs to the external-access owner. Removing an
expired record is an explicit retention action, not an admission side effect.

## Result and no-effect rules

A completed dispatch result must match the planned effect exactly:

- store-link reports only link-state change;
- capture reports only document change; and
- open-source reports only navigation.

Failed and cancelled dispatches are accepted only with all effect flags false.
Malformed, oversized, unauthenticated, stale, replayed, unavailable,
unsupported, and cancelled requests return attributable failures before editor
state changes.

## Focused validation

Use:

```sh
make jan-output-focused-test
```

The target checks deterministic provider fixtures, all link and media plans,
versioned external entrypoints, authentication, expiry, replay, payload bounds,
provider availability, cancellation, terminal outcomes, and strict
`src/jan_output` tests. It does not open a Resource, contact a provider, read a
credential, dispatch an editor command, build `src/odra`, or run a
repository-wide gate.
