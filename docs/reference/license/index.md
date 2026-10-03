<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# License Reference

Odra's first-party source code, documentation, and website material are
copyright 2026 Adrian PK and are distributed under the GNU General Public
License version 3 only. The canonical SPDX expression is `GPL-3.0-only`.

The complete license text is stored in the repository root as
[`COPYING`](../../../COPYING). The public source snapshot preserves this file,
the repository licensing metadata, and source-file notices from the canonical
development sources.

## Source notices

First-party files that safely support comments carry these fields using their
native comment syntax:

```text
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only
```

Files that cannot safely contain comments use repository-level REUSE metadata.
Racket source keeps `#lang` first, executable scripts keep their shebang first,
XML keeps its declaration first, and Markdown keeps frontmatter first.

## Third-party material

Third-party and vendored components retain their original copyright, license,
and attribution notices. Their inclusion does not relicense those components
under Odra's license. Distribution artifacts provide the applicable license
texts and notices for their complete dependency closure.
