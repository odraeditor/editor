<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Reuses Buffer and Syntax Ownership

Jan adds a second factory document language, but it does not add a second
editor, view model, or terminal presentation system. Canonical bytes remain in
the editor buffer. Language analysis retains one exact revision, and every view
of that buffer consumes the same checked result.

## Suffixes select semantics, not parsers

`.org` and `.jan` are two factory associations for one Jan language identity.
Treating them as separate languages would create independent provider,
configuration, and generation state for identical bytes. That would make
syntax results depend on the filename spelling rather than the accepted Jan
contract.

The selected association is still retained for inspection. This preserves the
reason for selection without allowing the suffix to alter parsing or
presentation. Explicit Jan selection follows the same rule for documents with
another suffix.

## The buffer is the sharing boundary

A view owns presentation geometry and focus, not language analysis. If every
view retained its own parser, two panes showing one buffer could temporarily
publish different trees for the same revision. Closing a pane could also tear
down analysis still needed by another pane.

The syntax workflow therefore keys Jan ownership by buffer identity. Views ask
for visible spans from that shared confirmed generation. View creation and
closure do not parse, advance generations, or duplicate the Jan tree.

## Configuration and providers invalidate atomically

Configuration changes can alter whether source forms are classified as task
keywords, registered links, entities, blocks, properties, or file-local
settings. Provider changes can alter the parser contract itself. Retaining
syntax produced under an older configuration or provider would mislabel the
same bytes.

Odra invalidates the complete Jan owner and its syntax snapshot before
scheduling replacement analysis. Text remains available as plain editable
content during that interval. Odin uses an independent provider registry, so a
Jan transition cannot invalidate an Odin buffer.

## Presentation remains semantic

Jan produces `Syntax_Role` spans rather than terminal colors. The UI proposal
path checks their revision and ownership, while theme and frontend layers map
roles to physical styling. This keeps terminal output, future frontends, and
theme changes independent from Jan grammar details.

Recovery regions use the same copied span path. They remain visible and
editable source, not a parser-owned overlay that can capture input or alter
bytes.

## Failure returns to text

Analysis is derived state. Editing is canonical state. When Jan parsing,
incremental validation, resource admission, allocation, or publication fails,
Odra discards or withholds the candidate presentation and continues to expose
the buffer as ordinary text.

The last confirmed analysis remains useful for diagnosis, but exact scope
checks prevent it from being reused against a newer revision. This is the same
revision-bound rule already used by Odin syntax presentation, extended without
changing Odin behavior.
