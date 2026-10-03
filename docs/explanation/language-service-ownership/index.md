<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Language Services Use a Native Process Owner

Language servers are useful because they are separate programs, but that
separation introduces resources and failure modes that ordinary editor
commands do not own: processes, pipes, partial frames, request identities,
timeouts, cancellation, stderr, restarts, and shutdown. Odra keeps those
mechanics in one language-independent native owner so an external service can
fail without becoming an editor-state owner.

## The Server Is Advisory

Canonical document text, revisions, positions, transactions, history,
Projects, views, and UI roots already have native owners. A language server
observes copied revision-bound document state and later returns derived data.
It never owns text and cannot publish an edit, diagnostic, candidate, or UI
change merely by writing a protocol message.

This boundary matters even when the first maintained server is OLS. The core
process and protocol implementation knows only a data-only command vector,
bounded policy, JSON-RPC framing, negotiated capabilities, and checked
generations. Language-specific executable names, selectors, options, and
result interpretation remain outside it.

## One Owner Contains the Whole Process Lifetime

Splitting the child process, streams, decoder, queues, and timers across
callers would make partial failure difficult to unwind. `Process_Session`
instead owns the complete lifetime. Construction either publishes a complete
opaque session or releases every allocation made so far. Closing that session
terminates and reaps any live child before it frees process-associated state.

The same owner bounds work. Standard streams are nonblocking and one poll
touches no more than the configured work quantum. Large messages therefore
advance across turns instead of allowing one server to monopolize the editor
loop. Message, stream, queue, stderr, retained, and temporary storage have
independent ceilings because limiting only the largest frame would still leave
aggregate growth unbounded.

## Generations Separate Replacement from Mutation

A restarted process is not the old process made healthy again. It is a new
session generation with cleared negotiated capabilities and fresh protocol
state. Consumers must validate the full session handle before using derived
state. Late output from an earlier generation is stale even when stable service
and provider identities are unchanged.

The automatic restart budget is deliberately one. It contains one transient
process failure without turning repeated failure into an invisible restart
loop. A further restart requires later explicit operator-facing coordination.

## Framing Is Separate from Meaning

The streaming decoder decides only where one bounded message body begins and
ends. The JSON-RPC decoder then validates and copies the message envelope.
Later protocol owners decide whether a known response matches an outstanding
request, whether a notification belongs to an exact document generation, and
whether its contents can be published.

Keeping these stages separate makes containment explicit. A malformed header
cannot enter the JSON parser; malformed JSON cannot become a protocol record;
and a valid but unknown notification cannot acquire editor authority.

## Positions Are Converted at the Boundary

Odra's canonical position is a UTF-8 byte offset. LSP peers may count UTF-8
bytes, UTF-16 code units, or UTF-32 code points. Converting at the protocol
boundary preserves one internal coordinate system and forces every conversion
to use the exact bound text. A conversion that lands inside an encoded scalar
rejects instead of rounding onto another character.

## Programmability Supplies Data, Not Ownership

The Racket capability composes bounded service definitions and policy as copied
records. It never receives the child process, ports, frame decoder, mutable
queue, allocator, timer, or borrowed editor state. Native code validates and
copies a proposed definition before it can start a process.

This keeps adding another conforming language service a data and adapter task,
while process containment, protocol limits, generation checks, and cleanup
remain shared invariants.

## Coordination Belongs Above the Generic Owner

The application must connect Project trust, eligible buffers, document events,
diagnostic redraw, navigation, and shutdown, but it does not need to absorb any
of their owners. The session coordinator therefore keeps only checked handles
and bindings. It asks the Project owner whether the one-root projection is current, the
language owner whether a buffer is eligible, the service owner to synchronize
and inspect, and the candidate and UI owners to present copied results.

That separation is what makes Odin a factory case instead of an architectural
special case. The `.odin` selector, `ols` executable name, and preferred
protocol data live in the factory definition. A second conforming language can
enter through another admitted definition without changing process,
synchronization, diagnostic, candidate, or UI control flow.

## Failure Preserves the Editor

Missing discovery, initialization failure, malformed output, process exit,
restart exhaustion, and trust revocation affect only derived service state.
They are visible through copied health and bounded stderr, but they never own
the buffer or block editing. Explicit restart is limited to a failed and reaped
session so recovery cannot become a hidden infinite loop.

Orderly editor shutdown follows the opposite ownership order: stop document
publication, request protocol shutdown, terminate when deadlines require it,
reap the process, release service storage, and only then close the remaining
editor session owners. Terminal restoration does not depend on server
cooperation.
