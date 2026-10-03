<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Author and Validate an Agent Package

Use this procedure from an Odra checkout while developing an agent definition
or capability integration package.

## Define the Package Role

1. Choose whether the package contributes an agent definition, a capability
   integration, or both.
2. Give each contribution a stable lowercase semantic identity.
3. Import only `odra/agents` and deliberate public owner-package modules.
4. Export the values through `odra-package-contributions`.
5. Repeat each identity, provider role, required authority, and effect in the
   package manifest.

Keep an integration separate from the owner package when it only adapts an
existing public operation. Declare the owner package as a dependency and call
the operation with `agent-capability-invoke-operation!`.

## Declare the Capability Boundary

1. Write inert input and result schemas.
2. Declare exact target kinds and effect classes.
3. Choose default and hard limits.
4. Choose approval, idempotency, verification, and retirement classes.
5. Check cancellation inside the handler.
6. Return a typed owner result with a safe summary and current evidence.

Do not put database handles, procedures, credentials, raw provider output, or
private owner values in schemas or results.

## Create a Conformance Fixture

Start from `tests/agent_substrate/conformance_fixture.rkt`. Replace its agent
and capability definitions with the package contributions. Keep the driver and
target registry deterministic; they are test adapters.

Set the fixture exports to the exact package identity, version, contribution
generation, authorities, target reference, and schema-valid request input.

## Run Conformance

```sh
racket scripts/check-agent-substrate-conformance.rkt \
  --fixture path/to/conformance-fixture.rkt
```

A passing run reports six cases: agent definition, driver, capability owner,
admission, execution, and reload.

For changes inside the Odra repository, run:

```sh
make agent-substrate-conformance-test
```

## Test Lifecycle Failures

Exercise these states before publishing the package:

1. no grant;
2. stale or revoked grant;
3. invalid target generation or scope;
4. cancellation before commitment;
5. deadline before and after owner invocation;
6. provider or package replacement;
7. package disablement and removal;
8. process restart with live work; and
9. uncertain consequential effect.

Use `make agent-substrate-recovery-acceptance` for the repository-owned
recovery cases.

## Prepare a Compatible Update

Keep the identity and compatibility version only when existing schemas,
targets, effects, and result meaning remain valid. Increment the package
release and contribution generation. An incompatible contract needs a new
identity or compatibility version and new grants.

See the [Agent Package Authoring Reference](../../reference/agent-substrate/authoring.md)
for the complete API, migration, security, fixture, and diagnostic contracts.
