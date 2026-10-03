<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Install and Launch a Linux Preview

This chapter downloads one immutable Odra preview, reviews its terms and
third-party notices, verifies its checksum, installs it below `~/.local/`, and
exposes the editor as `odra` without a source checkout or an installed Racket
runtime.

## Before You Begin

Use a Linux x86-64 system with a UTF-8 terminal. The supported system runtime
provides glibc, the GCC runtime, LZ4, ncursesw, and zlib. Install `curl`,
`sha256sum`, `tar`, and `unzstd` before continuing.

The commands below use version `0.2.0` as an example. Replace it with the
published version you were given.

## Review the Preview Terms and Notices

Define the package names and create user-owned download and installation
directories:

```sh
VERSION=0.2.0
PLATFORM=linux-x86_64
PACKAGE_BASE="https://forge.adrianpk.com/api/packages/odra/generic/odra-preview/$VERSION"
STEM="odra-$VERSION-$PLATFORM"
DOWNLOAD_DIR="$HOME/Downloads/$STEM"
INSTALL_PARENT="$HOME/.local/opt/odra"
COMMAND_DIR="$HOME/.local/bin"
mkdir -p "$DOWNLOAD_DIR" "$INSTALL_PARENT" "$COMMAND_DIR"
cd "$DOWNLOAD_DIR"
```

Download the public terms and third-party notices before downloading the
binary archive:

```sh
curl --fail --location --remote-name "$PACKAGE_BASE/$STEM-PREVIEW_TERMS.md"
curl --fail --location --remote-name "$PACKAGE_BASE/$STEM-THIRD_PARTY_NOTICES.md"
less "$STEM-PREVIEW_TERMS.md"
less "$STEM-THIRD_PARTY_NOTICES.md"
```

Continue only if the preview terms are acceptable for the intended evaluation.
Complete third-party license texts are also included inside the archive under
`LICENSES/`.

## Download and Verify the Preview

Download the archive and its checksum:

```sh
ARCHIVE="$STEM.tar.zst"
CHECKSUM="$ARCHIVE.sha256"
curl --fail --location --remote-name "$PACKAGE_BASE/$ARCHIVE"
curl --fail --location --remote-name "$PACKAGE_BASE/$CHECKSUM"
sha256sum --check "$CHECKSUM"
```

The checksum command must print the archive name followed by `OK`. Do not
extract or run an archive that fails this check.

## Install Odra

Confirm that the selected version and command locations are unused, then
extract the single versioned directory and create the stable command link:

```sh
test ! -e "$INSTALL_PARENT/$STEM"
test ! -e "$COMMAND_DIR/odra" && test ! -L "$COMMAND_DIR/odra"
tar --use-compress-program=unzstd --extract --file "$ARCHIVE" \
  --directory "$INSTALL_PARENT"
ln --symbolic "$INSTALL_PARENT/$STEM/bin/odra" "$COMMAND_DIR/odra"
```

If either `test` command fails, stop and inspect the existing path. Do not
replace an existing installation or command until you know who owns it.

Add the command directory to the current shell:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Add the same line once to the startup file used by your login shell so future
terminal sessions inherit it. Common locations are `~/.bashrc` for Bash and
`~/.zshrc` for Zsh.

## Verify the Installed Command

Confirm that the shell resolves the installed command:

```sh
command -v odra
```

The output is the user-owned command path:

```text
/home/your-name/.local/bin/odra
```

Launch the editor through that command:

```sh
odra
```

Odra opens the Startup screen. The bundle resolves its embedded Racket runtime
relative to the installed executable; no `racket` command or source repository
is required. Press `Control-X`, then `Control-C` to exit cleanly.

## Recover from Installation Problems

If a download returns `404`, confirm that the version is published and that
the complete package URL is unchanged. Do not substitute a development branch
name for the numeric package version.

If checksum verification fails, remove the archive and checksum and download
both again. A published version is immutable; a different checksum for the
same filename is not an accepted update.

If `command -v odra` produces no output, export `~/.local/bin` into `PATH` in
the current shell and confirm that `~/.local/bin/odra` is the symbolic link
created above. Do not continue to later chapters until `command -v odra`
resolves that link.

If the executable reports a missing shared library, install the named baseline
runtime component through the system package manager. If it reports a missing
bundled resource, preserve the extracted directory and diagnostic output when
reporting the failure; do not copy resources from a source checkout or a local
Racket installation.

## Verify the Result

You have completed this chapter when the public terms and notices are readable,
`sha256sum` reports `OK`, `command -v odra` resolves the user-owned command,
and `odra` opens the Startup screen without an installed Racket executable.

For the exact package layout, filenames, baseline, and immutability rules, see
the [Linux Preview Package Reference](../../../reference/linux-preview-package/index.md).

Continue with
[Prepare the User Guide Exercises](prepare-exercises.md).

---

[Previous: Choose an Installation Method](install-odra.md) ·
[User Guide](../index.md) ·
[Next: Prepare the User Guide Exercises](prepare-exercises.md)
