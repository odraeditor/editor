<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure and Diagnose Language Completion

Use this guide to request completion, adjust the factory policy, and identify
why candidates are unavailable.

## Confirm the provider

Open a supported source file through a trusted Project. Run:

```text
M-x describe-language-service
```

Confirm that the session is active, the document is synchronized, and the
server negotiated completion. Correct Project trust, executable discovery, or
server failure before changing completion policy.

## Request and use candidates

Place the cursor after an identifier prefix and press `C-M-i`. Use `C-n` and
`C-p`, or Down and Up, to move through candidates. Press `M-?` for available
detail, Enter or Tab to accept, and `C-g` to cancel.

Typing while the list is visible continues editing the source and narrows the
compatible generation. Accepted primary and additional edits form one undo
unit.

## Configure invocation and filtering

Add a complete export to
`${XDG_CONFIG_HOME:-$HOME/.config}/odra/init.rkt`:

```racket
#lang racket/base

(require odra/completion)

(provide odra-completion-configuration)

(define odra-completion-configuration
  (completion-configuration
   #:identifier? #t
   #:minimum-prefix 3
   #:trigger-character? #t
   #:case-sensitive-prefix? #t
   #:case-insensitive-prefix? #t
   #:subsequence? #f))
```

Run `M-x reload-personal-commands`. The complete candidate replaces the active
policy atomically. Invalid values preserve the last valid generation.

Use `#:enabled? #f` to disable both automatic and explicit factory completion.
Identifier-triggered requests are disabled by default; use `#:identifier? #t`
to enable them. Use `#:trigger-character? #f` to ignore server-advertised
trigger characters.

## Diagnose an unavailable request

Run:

```text
M-x describe-completion-state
M-x describe-language-service
```

Check, in order:

1. completion is enabled and explicit requests are admitted;
2. the active file has a selected language;
3. the file belongs to the trusted active Project;
4. the language-service session and document binding are active;
5. the transmitted revision matches the editor revision; and
6. the server advertised completion support.

After correcting a failed server, use `M-x restart-language-service` when the
service inspection reports that the bounded restart is available. Restarting
or replacing the provider cancels any active completion generation.

See the [Language Completion Reference](../../reference/language-completion/index.md)
for every command, binding, default, limit, and lifecycle rule.
