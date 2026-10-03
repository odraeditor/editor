<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Package Advisory Reference

A package advisory is a separately trusted signed statement about affected
content and a recommended local response. It neither admits nor removes a
package from a catalog.

## Advisory Record

An advisory records issuer and catalog identity, generation, state,
classification, severity, evidence state, exact package/release/artifact
selectors, recommended actions, rationale, issue time, predecessor reference,
and Ed25519 signatures.

States are `draft`, `active`, `corrected`, `superseded`, and `withdrawn`.
Classifications are `compromised`, `malicious`, `policy-risk`, and
`vulnerability`. Evidence is `confirmed`, `disputed`, or `suspected`;
severities are `critical`, `high`, `medium`, `low`, and `none`.

Recommended and local actions are:

- `block-acquisition`;
- `block-activation`;
- `deactivate`;
- `quarantine`;
- `rollback`;
- `warn`.

Drafts may be unsigned. Every non-draft generation requires signatures from
the configured advisory issuer. Generation one has no predecessor; later
generations reference the exact prior advisory and digest.

## Local Response Policy

The local policy maps suspected, confirmed-malicious, confirmed-other, and
disputed evidence to ordered action sets. It may permit bounded local
overrides. An override binds issuer, advisory and generation, artifact digest,
acquisition or activation phase, authorizer, rationale, and expiry.

Overrides do not change advisory history, catalog membership, or curation.
Unknown issuers, invalid signatures, stale generations, mismatched selectors,
or expired overrides fail closed and preserve previous confirmed state.

## Limits

One advisory admits at most 4,096 combined selectors, 4,096 UTF-8 bytes of
rationale, and 16 signatures. Selector lists and action lists are canonical,
unique, and bounded. Diagnostics are redacted and bounded.

Use `M-x package-advisory-list` for inspection and
`M-x package-catalog-doctor` for recovery.
