<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Service Contract Reference

This reference describes the language-independent process and protocol owner
implemented by `src/language_service`. Provider registration and document
synchronization build on these contracts. Revision-bound diagnostic
publication and navigation commands use the same session and document owners.

## Ownership

`Process_Session` is the opaque native owner for one external server process.
It copies the admitted command, environment, and working directory; owns the
child process and its three standard streams; retains one inbound frame
decoder, one outbound byte queue, and one bounded standard-error tail; and
releases them through `process_session_close`.

The caller owns the opaque `Process_Session` value and must close it exactly
once. `process_session_take_frame` returns a copied `Frame`; the caller owns
that body until `frame_close`. Protocol messages returned by `message_decode`
are copied and remain owned until `message_close`. Inspection records are
pointer-free values and never expose process, stream, allocator, or JSON parser
objects.

## Identities and Generations

Registry, definition, provider, session, process, transport, request,
document-binding, synchronization, and inspection identities are distinct
pointer-free types. Zero identifiers and zero generations are invalid.

One successful process restart increments the session generation.
`process_session_validate_handle` accepts only the complete current
`Session_Handle`; an older process generation or a handle from another
provider returns `Stale_Generation`.

## Protocol Profile

The selected wire profile is JSON-RPC 2.0 using LSP `Content-Length` framing
over standard input and output. A frame contains:

```text
Content-Length: <decimal UTF-8 body length>\r\n
\r\n
<JSON body>
```

Headers are ASCII, header lines use CRLF, exactly one valid `Content-Length`
is required, and the body must fit the selected message and buffered-stream
limits. Input may arrive in arbitrary fragments. A complete body is copied out
before the decoder advances to retained trailing bytes.

`message_decode` admits strict JSON-RPC requests, notifications, responses,
and error responses. Integer, text, and null request identifiers are copied
into bounded records. Malformed JSON, excessive nesting, invalid envelopes,
unsupported capability values, duplicate frame lengths, decimal overflow, and
unknown messages remain contained failures. Unknown requests require a
method-not-found response; unknown notifications are ignored.

## Positions

Canonical editor positions remain UTF-8 byte offsets. The protocol adapter
converts positions against the exact supplied UTF-8 text using the negotiated
UTF-8, UTF-16, or UTF-32 unit. A position inside a multibyte code point or UTF-16
surrogate pair is invalid. Line and character overflow, an absent line, an
invalid encoding, and invalid UTF-8 reject without changing owner state.

## Process Lifecycle

The implemented lifecycle is:

```text
start -> initializing -> active
                        |-> cancelling -> active
                        |-> shutting down -> terminating -> stopped
                        |-> failed -> restarting -> initializing
```

Process creation uses an argument vector directly through the Linux platform
adapter; it does not invoke a shell. Parent pipe endpoints are nonblocking.
Each poll performs at most one selected work quantum for standard output,
standard error, and standard input, then polls process exit and deadlines.

Initialization, cancellation, graceful shutdown, and forced termination have
explicit monotonic deadlines. Expired initialization or cancellation marks the
session failed and requests termination. Expired graceful shutdown requests
termination. A child that remains live through the forced interval is killed.
Every child is reaped before its process storage and streams are released.

One automatic restart is admitted after a failed child has been reaped. The
restart copies no new ambient state, increments the exact session generation,
clears negotiated capabilities, and returns to initialization. A second
automatic restart returns `Restart_Exhausted`.

## Selected Limits

The selected topology admits 64 definitions, 64 providers, 32 simultaneous
sessions, 256 documents per session, and 4,096 documents in total. Principal
per-session limits are:

| Resource | Limit |
| --- | ---: |
| Frame headers | 8 KiB |
| JSON nesting | 64 levels |
| Message body | 16 MiB |
| Buffered stream | 32 MiB |
| Outstanding requests | 1,024 |
| Retained notifications | 4,096 |
| Queue depth | 4,096 |
| Queue bytes | 64 MiB |
| Standard-error tail | 1 MiB |
| Work per poll | 256 KiB |
| Automatic restarts | 1 |

The selected deadlines are 500 ms for discovery, 10 s for initialization, 5 s
for an ordinary request, 1 s for cancellation, 3 s for graceful shutdown, and
1 s for forced termination. The complete selected policy and reproducible
ordinary, demanding, and stress evidence are recorded in the
[dependency and resource study](../../../ops/default/report/studies/language-service-dependency-and-resources.md).

## Failures and Cleanup

Failures are stable `Failure_Context` values. They distinguish invalid and
stale identities, resource limits, arithmetic overflow, executable and process
failures, pipes, framing, malformed JSON, protocol violations, unsupported
capabilities, unknown methods, timeouts, cancellation, process exit, restart
exhaustion, shutdown, termination, reaping, allocation, and closed owners.

Standard output is protocol-only. Standard error is never decoded as protocol
and retains only its bounded tail. Allocation failures leave no partially
published session. `process_session_close` kills a live child, waits for reap,
closes every stream, closes the decoder, deletes copied launch data and queues,
and invalidates the opaque owner. Repeated close attempts reject.

## Provider and Workflow Seam

The package now owns a generic provider registry, controlled executable
discovery, Project-scoped document synchronization, and factory OLS data. The
same registry and synchronization contracts admit a data-only non-Odin
fixture. See the [Programmable Language Service Reference](../programmable-language-services/index.md)
for those contracts.

Revision-bound diagnostic publication, candidate navigation, semantic UI
projection, and copied command routes are described in the
[Language Diagnostics Reference](../language-diagnostics/index.md).
The application coordinator selects eligible `.odin` buffers inside trusted
active-Project memberships, owns one service workflow across buffers and
panes, forwards document lifecycle events, consumes diagnostic publications,
and closes every session during editor shutdown. `M-g n` and `M-g p` are
factory direct-profile bindings; process and transport ownership remain in
this package.

## Focused Validation

```sh
make language-service-reference-test
make language-service-resource-study
make language-service-containment-test
make docs-check
```

The containment target runs the native contract, generated framing, position,
external fixture, process lifecycle, stale-generation, allocation-fault,
accounting, and exact-cleanup tests with one Odin test thread.
