<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Odra

Odra is a terminal-first programmable text editor. Its native Odin core owns
text, buffers, views, commands, and editor state. An embedded Racket environment
provides configuration and extensions while keeping core editing rules in one
place.

The editor supports ordinary file editing, multiple buffers and panes,
integrated terminals, Projects and Workspaces, syntax presentation, language
services, direct and modal interaction profiles, and installable packages. Its
first-party modules add structured-document, filesystem, project-tree, and
repository workflows without changing the basic editor model.

## Status

**Release: v0.2.0**

Odra is under active development. It is currently useful for smaller edits and
focused evaluation cycles. Broader daily use still needs refinement, and some
workflows and interfaces may evolve between releases.

Every published source snapshot records its exact `vMAJOR.MINOR.PATCH` version
above. The publication workflow rejects an `unreleased` value or a version that
does not match the release request. Public snapshots contain the source for
that release; the development repository can contain newer work.

## Build and run

From the repository root:

```sh
make odra
.build/odra
```

To open an existing file or start a new file-backed buffer:

```sh
.build/odra path/to/file
```

Run the complete repository validation with:

```sh
make verify
```

## Documentation

Start with the [documentation index](docs/index.md) for tutorials, task guides,
reference material, and design explanations. See the [changelog](CHANGELOG.md)
for the current unreleased product capabilities.

## License

Odra is copyright 2026 Adrian PK and is distributed under the
[GNU General Public License version 3 only](COPYING). Third-party components
retain their own copyright and license notices.
