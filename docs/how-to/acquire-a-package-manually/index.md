<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Acquire a Package Manually

Use manual acquisition when a package is not in a configured catalog or when
you need to inspect one exact development input. Manual acquisition never
implies curation or activation.

## Choose an Exact Source

Run `M-x package-manual-acquire` and select one source kind:

- development directory: an absolute local directory;
- local artifact: an absolute archive path;
- Git: an absolute local repository or a credential-free HTTPS or SSH URL,
  resolved to one exact 40- or 64-character revision.

Branch names and moving tags are discovery inputs only. Confirm the resolved
revision before continuing.

## Verify the Candidate

Review the package identity, version, publisher, source, source revision,
manifest digest, artifact digests and sizes, target, dependencies,
compatibility, capabilities, and contributions. Odra rejects mismatched
manifests, artifacts, source references, unsafe archive paths, size limits, and
non-exact Git state before installation.

The result remains `manual-uncurated`. If confirmed catalog state contains an
exact matching assertion, Odra lists every matching assertion and curator but
does not rewrite the manual provenance.

## Install and Activate Separately

Confirm installation for the package family. A language bundle enters
`installed-disabled`; inspect it with `M-x describe-language-bundle`, review
its requested authorities, and use `M-x language-bundle-enable` separately.

Manual dependencies do not add catalogs or recursively acquire sources. Enroll
or acquire each missing dependency explicitly.

## Update or Remove

Repeat manual acquisition to create a new explicit generation. There is no
implicit tracking of a directory, branch, URL, or artifact path. Removal uses
the package family's normal lifecycle and does not delete the original local
directory or repository.

See [Package Curation Reference](../../reference/package-curation/index.md) for
the exact distinction between manual provenance and curation assertions.
