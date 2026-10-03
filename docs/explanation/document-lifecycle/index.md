<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Documents Are Separate from Buffers

A buffer is canonical editable text. A file is an external filesystem object.
A document records the controlled relationship between them. Keeping these
concepts separate lets Odra represent useful states that a single "open file"
object would hide: text without a target, a named target that does not exist,
an exact saved revision, and a target that changed outside the editor.

## Association is not publication

When a new in-memory buffer is first named, Odra validates and privately owns
the candidate path before changing observable document state. Cancellation or
a pre-publication failure can therefore release the candidate and return to the
exact unassociated state. The association becomes public only after the target
has actually been replaced.

This is the same prepare-and-publish shape used by canonical buffer edits. It
prevents the UI from claiming that a document exists at a path when no file was
successfully written there.

## Saving uses an immutable revision

A save retains one immutable rope snapshot and streams its UTF-8 leaves. It
does not build a second whole-document output string. The snapshot records the
buffer identity and revision that the operation is authorized to publish.

If editing creates a newer revision while that snapshot is live, publication
still saves the captured revision truthfully. The newer live revision remains
modified. This separates filesystem latency from canonical editor mutation and
avoids holding mutable text across I/O.

## Atomic replacement has two success boundaries

On Linux, Odra writes a same-directory temporary file, syncs it, renames it over
the target, and then syncs the parent directory. Rename establishes target
publication. Parent-directory sync establishes confirmed directory durability.

Those boundaries cannot be collapsed honestly. If rename succeeds but the
directory sync fails, the new target is visible but durability is uncertain.
Odra reports that state instead of claiming either that nothing changed or that
durability was confirmed.

## External observation is information, not authority

The document records bounded file identity, size, modification time, mode, and
existence. A later observation can reveal that another program replaced the
target. It cannot mutate the buffer or veto an explicit save.

This first lifecycle treats Save as the user's current authoritative request.
Automatic reload, content merging, and file watching require separate policy
because they introduce background authority over visible text.

## Exit is a checked transition

An exit command is a request, not immediate process termination. Odra compares
the document state and saved revision with the live buffer revision. Clean work
can shut down directly. Unassociated, unmaterialized, or modified work requires
an explicit Save or Discard decision; Cancel returns to editing.

The path prompt is reused when Save has no target. A canceled or failed save
cannot fall through into shutdown. This makes data loss depend on one visible
user decision rather than on incidental command routing.

## Language and frontend boundaries

Odin owns canonical text, document state, paths, file descriptors, publication,
and cleanup. Racket defines the active command map and selects named lifecycle
requests. The terminal renders prompts and decodes input but does not decide
whether work is clean or whether publication succeeded.

This boundary keeps later programmable interaction possible without lending
filesystem authority or mutable editor memory across the native interface.
