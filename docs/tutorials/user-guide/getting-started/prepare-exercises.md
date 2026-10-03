<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Prepare the User Guide Exercises

This chapter downloads the exercise kit that matches the installed Odra
version, verifies it, and initializes one disposable guide area below
`~/odra-guide/`. Complete it once before starting the editing exercises.

## Before You Begin

Complete [Install and Launch a Linux Preview](install-linux-preview.md).
Confirm that the installed command still resolves before preparing exercise
state:

```sh
command -v odra
```

The commands below use version `0.2.0` as an example. Replace it only when both
Odra and the User Guide exercise package have been published with another
matching version.

## Download and Verify the Exercise Kit

Create a user-owned download directory and define the package names:

```sh
VERSION=0.2.0
STEM="odra-user-guide-$VERSION"
PACKAGE_BASE="https://forge.adrianpk.com/api/packages/adrianpk/generic/odra-user-guide/$VERSION"
DOWNLOAD_DIR="$HOME/Downloads/$STEM"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"
```

Download the archive and checksum, then verify them before extraction:

```sh
curl --fail --location --remote-name "$PACKAGE_BASE/$STEM.tar.zst?version=$VERSION"
curl --fail --location --remote-name "$PACKAGE_BASE/$STEM.tar.zst.sha256?version=$VERSION"
sha256sum --check "$STEM.tar.zst.sha256"
```

The checksum command must print the archive name followed by `OK`. Do not
extract or initialize a kit that fails verification.

## Initialize the Guide Area

Extract the archive and run its versioned setup helper:

```sh
tar --use-compress-program=unzstd --extract --file "$STEM.tar.zst"
"$PWD/$STEM/bin/odra-guide" setup
```

The helper verifies the kit and installed Odra version before creating this
layout:

```text
~/odra-guide/
  kit/
  work/
    dirs/
      notes/
    projects/
      forecast-engine/
      report-console/
  config/
```

`kit/` remains the verified source. Exercise changes belong under `work/`, and
the guide's isolated Odra state belongs under `config/`. Repeating the same
setup command against a complete matching area reports that it is already
available; it does not replace exercise work.

## Activate the Guide Session

Set the isolated configuration location once in each terminal session used for
the guide:

```sh
export XDG_CONFIG_HOME="$HOME/odra-guide/config"
```

This variable keeps guide Projects, Workspaces, and personal examples separate
from normal Odra configuration. It does not replace the `odra` command. Later
chapters launch the editor as `odra` or `odra <path>` in this activated shell.

## Reset Exercise State

Run the packaged helper with one reset group when a chapter asks for its
starting state. For example, restore the supplied notes and remove only the
note file declared as chapter-created:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset notes
```

The available groups are:

| Group | Restored boundary |
| --- | --- |
| `notes` | Supplied note files and declared note outputs |
| `forecast-engine` | Forecast Engine content, declared practice trees, and guide Project state |
| `report-console` | Report Console content and guide Project state |
| `working-context-demos` | The two disposable Dir and Project demonstration roots |
| `configuration-examples` | Guide-created personal modules and settings only |
| `report-console-promotion` | The ordinary-Dir starting state used by the Project promotion chapter |
| `workspace-state` | Both maintained Project identities and the original ordered Workspace |
| `all` | Every declared reset group while preserving undeclared files |

A reset verifies the unchanged kit first. It restores only supplied files and
removes only paths declared as exercise-created; it does not remove an
undeclared file elsewhere under the guide root.

## Remove the Complete Guide Area

Cleanup is optional. It removes the verified kit, every exercise edit, and all
isolated guide configuration below `~/odra-guide/`. It does not touch normal
Odra configuration or files outside that directory.

Close Odra, then confirm the exact cleanup boundary:

```sh
GUIDE_ROOT="$HOME/odra-guide"
"$GUIDE_ROOT/kit/bin/odra-guide" cleanup --confirm "$GUIDE_ROOT"
```

The helper refuses a missing, unverified, symbolic-link, mismatched-version,
or differently confirmed root. Repeat setup from the downloaded archive when
you want a new guide area.

## Verify the Result

Confirm the supplied Dir, both Project roots, and the isolated Workspace
record:

```sh
test -d "$HOME/odra-guide/work/dirs/notes"
test -f "$HOME/odra-guide/work/projects/forecast-engine/main.odin"
test -f "$HOME/odra-guide/work/projects/report-console/main.rkt"
test -f "$HOME/odra-guide/config/odra/workspaces/user-guide.rkt"
```

You have completed this chapter when every command succeeds and the setup
helper reports the exact guide version and root.

If a download returns `404`, stop and confirm that the matching exercise
package was published for the installed Odra version. Do not substitute a
source checkout or a kit from another version.

Continue with
[Complete the First Editing Session](first-editing-session.md).

---

[Previous: Install and Launch a Linux Preview](install-linux-preview.md) ·
[User Guide](../index.md) ·
[Next: Complete the First Editing Session](first-editing-session.md)
