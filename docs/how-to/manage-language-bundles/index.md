<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Language Bundles

Use the factory-owned language-bundle commands to inspect, install, activate,
update, roll back, disable, and remove bundles. Installed extension code does
not own these recovery operations.

## Inspect Available and Installed Bundles

Run `M-x language-bundle-list` to list Factory and installed bundles with their
exact lifecycle states. Run `M-x language-bundle-search` to search configured,
confirmed catalog snapshots. Select a bundle with
`M-x describe-language-bundle` to inspect its identity, version, origin,
authorities, artifacts, dependencies, contribution generation, and failures.

Refresh configured catalogs with `M-x language-bundle-refresh-catalogs`. This
updates confirmed catalog data without changing installed or active state.

## Install and Enable a Bundle

1. Run `M-x language-bundle-search` and select one exact version.
2. Run `M-x language-bundle-install` for that candidate.
3. Review the publisher, signature evidence, platform, Odra API range,
   dependencies, artifact digests, and requested authorities.
4. Confirm installation. Odra acquires and verifies content before publishing
   installed state.
5. Run `M-x language-bundle-enable`.
6. Review any authority delta, then confirm activation.
7. Restart Odra when the command reports that the prepared activation becomes
   effective on restart.
8. Open a matching file and verify it with `M-x describe-language-support`.

An installation may remain `installed-disabled` when authority has not been
granted. Enabling is the explicit step that prepares contributions for atomic
activation.

## Update and Roll Back

Run `M-x language-bundle-update`, select the compatible candidate, review its
version and authority changes, and confirm. Odra retains the prior confirmed
version as the rollback target.

If the update is unsuitable, run `M-x language-bundle-rollback`, select the
bundle, review the retained predecessor, and confirm. Restart when instructed,
then inspect both bundle and document support. Rollback restores a retained
confirmed version; it does not search a catalog for an arbitrary older build.

## Disable or Remove

Run `M-x language-bundle-disable` to deactivate contributions while preserving
the installed artifacts for inspection or later re-enablement.

To remove a bundle safely:

1. Inspect it with `M-x describe-language-bundle`.
2. Confirm no active bundle depends on it.
3. Disable it if it is active.
4. Run `M-x language-bundle-remove` and confirm the exact identity and version.
5. Restart when instructed and run `M-x language-bundle-list`.

Removal drops the installed record and makes unreferenced managed content
eligible for cleanup. It does not delete Project files, personal
configuration, or external language-server installations.

## Recover an Interrupted Operation

Run `M-x language-support-doctor`, follow only the recovery attached to the
reported generation, and inspect the bundle again. Staging failures do not
replace installed state. Activation failures preserve the last confirmed lock.
Use rollback, disablement, catalog refresh, or removal explicitly; Odra does
not silently delete user-owned data.

See the [Language Bundle Reference](../../reference/language-bundles/index.md)
for lifecycle states, trust, durable records, commands, and failure rules.
