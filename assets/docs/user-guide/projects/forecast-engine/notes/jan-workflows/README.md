<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Workflow Exercises

This directory supplies safe, bounded examples for the Structured Documents
part of the User Guide.

- `00-start-here.org` and `00-start-here.jan` are byte-identical parity files.
- `planning/tasks.org` contains tasks, metadata, time, and agenda inputs.
- `computation/report.jan` contains a table formula and one inert Racket block.
- `publishing/site.org` contains native export and publication inputs.
- `references/library.json` contains a small local bibliography.

Opening, parsing, saving, exporting, or publishing these files must not execute
source code. Execute the Racket block only through an explicit Jan command and
after reviewing its deny-first authority request. Native text, HTML, Markdown,
and normalized Jan/Org output need no external converter. PDF, ODT, Gnuplot,
citation-processor, remote-publication, encryption, and synchronization
examples can report `unavailable` when their optional tool or provider is not
configured.

Expected outcomes are described in each file and in the User Guide. Rejected,
stale, unavailable, cancelled, or limited operations preserve source.
