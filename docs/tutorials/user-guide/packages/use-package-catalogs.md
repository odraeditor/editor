<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Package Catalogs

This chapter refreshes the signed official catalog, installs and activates the
ROT13 canary, invokes its contributed command through `M-x`, and exercises its
local lifecycle. Refreshing retrieves signed metadata, installation adds a
selected artifact, activation exposes its commands, and local policy controls
execution.

Odra contains the official catalog identity, endpoint, and public verification
keys. The catalog is available without credentials and needs no manual
registration.

## Refresh the Official Catalog

1. Start Odra and run `M-x package-catalog-refresh`.
2. Select `odra-official` when the catalog selector opens.
3. Wait for the signed snapshot and assertion set to verify.
4. Run `M-x package-catalog-doctor` if the endpoint is unavailable or the
   publication fails verification.

Refresh failure is recoverable. It does not authorize a replacement trust root
or an unsigned snapshot. Private catalogs can use separately configured opaque
credential references; those credentials do not apply to the official catalog.

## Inspect the Default

1. Start Odra and run `M-x package-catalog-list`.
2. Read the registration identifiers in the command result.
3. Run `M-x package-catalog-describe`, enter `odra-official`, and inspect its
   catalog identity, `official` designation, refresh
   state, and confirmed snapshot.

The word “official,” the display name, and the endpoint host are presentation.
Only the catalog and root identities compiled into Odra grant the official
designation.

## Add an Independent Catalog

1. Obtain a KASPER-compatible publication directory through an authenticated
   channel. It must contain `catalog.rktd`, `snapshot.rktd`, and
   `assertions.rktd` from the same publication.
2. Run `M-x package-catalog-add` and enter the publication directory. `~` at
   the beginning of the path expands to the current home directory.
3. Review the catalog display name, generated local registration identifier,
   snapshot identifier, and assertion count shown by Odra.
4. Confirm the registration. Odra verifies and refreshes the publication
   before reporting success.
5. Run `M-x package-catalog-list` and verify that the built-in and independent
   registrations remain separate entries.

An independent catalog does not need Odra project approval. Local
configuration decides whether to enroll it and what precedence it receives.

## Refresh and Search

1. Run `M-x package-catalog-refresh` and select the local registration reported
   by `package-catalog-list`. Refresh begins immediately.
2. When refresh completes, run `M-x package-catalog-search` and enter a package
   identity or search text.
3. Read each result's package identity, version, catalog attribution, curator,
   source revision, artifact digest, and curation state.
4. Run `M-x package-catalog-describe` with the registration identifier to
   inspect its identity, designation, refresh state, and confirmed snapshot.
5. If two catalogs publish incompatible content for the same release, stop at
   the reported integrity conflict. Precedence never hides an exact-content
   disagreement.

## Install and Run the Canary

1. Run `M-x package-discover`. On first use, Odra refreshes the configured
   catalogs and then shows confirmed releases. Type `odra.rot13` in the visible
   search field to filter the list incrementally.
2. Select `odra.rot13@0.1.1`. Selection verifies and installs that exact
   release without evaluating package code, then presents its requested
   authorities.
3. Confirm the authority transition once to enable the selected release. You
   do not need to re-enter its name or version.
4. Open a text buffer containing `Hello from Odra`, select that text, and run
   `M-x rot13-region`. The selection becomes `Uryyb sebz Bqen`.
5. Run `rot13-region` again to restore the original. Undo and redo each
   invocation; one invocation is one undo unit.

With no active non-empty selection, `rot13-region` reports an actionable
message and leaves the buffer unchanged. ASCII letters rotate while other
Unicode scalars are preserved.

## Disable, Re-enable, and Remove

1. Restart Odra without network access. `rot13-region` remains available from
   verified installed content; restart does not redownload or reauthorize it.
2. Run `M-x package-disable` with `odra.rot13`. The command disappears from
   `M-x`, while verified releases remain installed.
3. Run `M-x package-enable` with `odra.rot13@0.1.1`. Confirm the authority
   transition and verify that `rot13-region` returns.
4. Run `M-x package-remove` with `odra.rot13@0.1.1`, then run
   `M-x package-cleanup`. Cleanup deletes only content no longer reachable from
   installed, active, rollback, pinned, or quarantined state.

`package-update` and `package-rollback` use the same verified lifecycle when a
catalog publishes a compatible successor. The initial official catalog exposes
one exact ROT13 release, so there is no earlier official version to select.

The complete command and state contracts are in the
[Installable Package Reference](../../../reference/installable-packages/index.md).

## Inspect Advisories and Recover

The semantic command `package-advisory-list` is reserved but is not connected
to the runtime service in this development build. Run
`M-x package-catalog-doctor` when refresh, verification, or resolution fails.

If the network is unavailable, Odra keeps the last confirmed unexpired
snapshot and reports `offline`. A failed refresh does not replace that state.
If no confirmed snapshot exists, wait for the endpoint or fix the exact
configuration; do not bypass signature or identity checks.

---

[Previous: Packages and Catalogs](index.md) ·
[User Guide](../index.md) ·
[Next: Work with Local Agents](use-local-agents.md)
