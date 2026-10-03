<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Respond to Package Advisories

Use advisories to constrain acquisition or activation of exact affected
content without treating the advisory issuer as a package curator.

## Inspect Effective Advice

Run `M-x package-advisory-list`. For each entry inspect:

- issuer identity and catalog identity;
- advisory generation, state, classification, severity, and evidence state;
- affected package identities, release identities, and artifact digests;
- recommended actions and the effective local response;
- superseded generation and signature status.

## Apply the Local Response

Confirmed malicious content may block acquisition or activation, deactivate
active content, quarantine it, roll back, or warn according to local policy.
Suspected, disputed, vulnerability, and general policy-risk evidence may have
different actions. The exact local response policy is authoritative.

For a language bundle, inspect its lifecycle after the response. Quarantine
must not corrupt unrelated bundles or erase the retained confirmed rollback
target.

## Handle Corrections and Overrides

Refresh the advisory source and verify the next signed generation. A corrected,
superseded, or withdrawn advisory preserves history rather than rewriting the
old record.

Use a local override only when policy permits it. Bind the override to the
issuer, advisory identity and generation, exact artifact digest, acquisition
or activation phase, accountable authorizer, rationale, and expiry. An
override does not change the advisory or catalog.

## Recover from Failure

Run `M-x package-catalog-doctor` for invalid signatures, unknown issuers,
history gaps, stale generations, selector limits, or unavailable endpoints.
Failed advisory refresh preserves prior confirmed policy state and does not
grant activation.

See the [Package Advisory Reference](../../reference/package-advisories/index.md)
for classifications, actions, records, and limits.
