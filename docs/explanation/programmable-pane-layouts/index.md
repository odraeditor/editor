<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Programmable Pane Layouts Use Copied Authority

Layout customization needs to observe and request structural changes without
becoming a second owner of panes, views, geometry, or buffer lifetimes. Odra
therefore gives Racket copied values and short-lived checked authority while the
Odin layout registry remains the only publication owner.

## A copied snapshot separates observation from ownership

A layout snapshot contains identities, generations, topology, geometry, focus,
MRU rank, pane buffer identity, dedication, and history accounting. It contains
no native pointers and lends no registry storage.

Racket can retain that snapshot as historical data, but its handles authorize
nothing by themselves. Every mutation request must return through the scoped
capability with the exact owner, layout generation, pane identity, slot, and slot
generation that were granted for the current turn.

This separation allows useful inspection without making garbage collection,
continuation escape, or a retained Racket value part of native resource
lifetime.

## Authority lasts for one host turn

The host creates one operation set and one exact layout scope, invokes the
Racket composition, and revokes the capability when that dynamic extent ends.
The capability cannot be reused from another thread, after continuation escape,
or after its native generation has closed.

A successful structural operation returns a new copied scope because the
publication advances layout generation. Subsequent operations in the same turn
must use that new scope. This prevents a convenient Racket wrapper from hiding
optimistic concurrency: old authority becomes stale as soon as another layout
generation is published.

## Hooks observe commits rather than intermediate state

Each native publication completes topology, geometry, focus, view effects,
accounting, and generation validation before notification begins. All hooks in
one notification round receive the same immutable snapshot of that committed
generation.

Rolling a callback exception back through the publication would make already
visible native state depend on observer success. Odra instead contains the
exception, records a callback failure, and keeps the committed generation.
Other registered hooks can still observe that generation.

## Callback mutations are deferred transactions

Allowing a hook to mutate the registry while notification is iterating would
invalidate the snapshot and make later hook order observable as partial native
state. Mutation from a callback is therefore copied into a bounded FIFO queue:

```text
validate and publish
        |
        v
notify every hook with one snapshot
        |
        v
revalidate queued requests in FIFO order
        |
        v
publish each accepted request as an ordinary transaction
```

Inspection can remain synchronous because it changes no state. A deferred
request is optimistic: an earlier queued publication may make a later request
stale. That failure is recorded with its deferred sequence and does not undo the
earlier accepted publication.

## Bounds make observation part of the runtime contract

Hook slots, queued requests, snapshot nodes and bytes, prepared transaction
memory, geometry work, and diagnostics all have explicit ceilings. Registration
or queue overflow rejects the new request without evicting existing observers
or queued work. Teardown and hook mutation reject while notification or deferred
processing is active.

The result is programmable composition without a second mutable layout model:
Racket decides what to request, while Odin decides whether the complete request
is current, admissible, and safe to publish.

See [Pane Layout Reference](../../reference/pane-layout/index.md) for procedure,
record, limit, and failure details, and [Validate Pane Layouts](../../how-to/validate-pane-layouts/index.md)
for the focused and integrated gates.
