<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Linux Preview Package Reference

## Identity

| Field | Contract |
| --- | --- |
| Tag | Annotated `vMAJOR.MINOR.PATCH` tag on the exact current `main` commit |
| Package owner | `adrianpk` |
| Package name | `odra-preview` |
| Package version | `MAJOR.MINOR.PATCH` without the leading `v` |
| Platform | `linux-x86_64` |
| Registry base | `https://forge.adrianpk.com/api/packages/odra/generic/odra-preview/<version>` |

Publication also requires a successful Nightly Verification run for the exact
tagged `main` commit and an explicit manual dispatch from `main`.

## Public Files

For version `<version>`, let `<stem>` be
`odra-<version>-linux-x86_64`.

| File | Purpose |
| --- | --- |
| `<stem>.tar.zst` | Single-directory relocatable preview bundle |
| `<stem>.tar.zst.sha256` | SHA-256 record for the exact archive |
| `<stem>-PREVIEW_TERMS.md` | Product preview terms available before download |
| `<stem>-THIRD_PARTY_NOTICES.md` | Public component attribution and source references |

The archive also contains `PREVIEW_TERMS.md`, `THIRD_PARTY_NOTICES.md`,
`manifest.json`, complete selected license texts under `LICENSES/`, the Odra
executable under `bin/`, and its bundled Racket runtime resources.

The archive does not contain the Odra repository or Odra source files. The
preview executable is stripped of private debug information, the static symbol
table, and repository source paths before publication.
Required dynamic symbols remain available. Racket runtime sources remain
third-party runtime material governed by the bundled Racket licenses.

## Runtime Baseline

The initial preview supports Linux x86-64 with the ELF interpreter
`/lib64/ld-linux-x86-64.so.2`. The host provides these dynamic libraries:

| System component | Required libraries |
| --- | --- |
| glibc | `ld-linux-x86-64.so.2`, `libc.so.6`, `libm.so.6` |
| GCC runtime | `libgcc_s.so.1` |
| LZ4 | `liblz4.so.1` |
| ncurses | `libncursesw.so.6` |
| zlib | `libz.so.1` |

Racket does not need to be installed on the host. macOS, Windows, Linux ARM64,
package-manager installation, graphical installers, and automatic updates are
outside the initial preview contract.

## Verification

The checksum file contains one lowercase SHA-256 digest followed by two spaces
and the exact archive filename. Verify it from the directory containing both
files:

```sh
VERSION=0.1.0
sha256sum --check "odra-$VERSION-linux-x86_64.tar.zst.sha256"
```

Replace `0.1.0` with the selected published version. The archive contains one
top-level directory named `odra-<version>-linux-x86_64`. Extract it with a
Zstandard-capable `tar` and run `bin/odra` from that directory.

## Immutability and Failure

One package version is immutable after complete publication. A second dispatch
with identical remote digests performs no upload. A conflicting file fails
publication rather than overwriting it.

A partial upload is not a published preview. The workflow records uploaded
filenames, preserves the failed run as evidence, and performs no deletion. Only
an explicit maintainer recovery may remove an incomplete version before a new
dispatch. A complete version is never deleted or replaced by this workflow.

The publication secret is unavailable to build and smoke jobs. Only the final
upload step receives it, and workflow summaries contain no credential.
