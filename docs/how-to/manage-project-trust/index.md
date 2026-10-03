<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Project Trust and Refresh

Project trust belongs to one exact local Project identity, generation, and root.
It controls executable Project capabilities, not ordinary file access.

## Inspect current trust

Open the Project root and invoke `describe-project`. The inspection reports the
current local identity, generation, exact root, and `trusted` or `untrusted`
state.

The authoritative record is `<project-dir>/.odra/project.rkt`. A global
discovery reference cannot grant trust or override the local value.

## Change trust through the checked storage boundary

Until a dedicated interactive trust command is connected to the one-root
lifecycle, use the target record API from the repository root:

```racket
(require "src/project/lifecycle-persistence.rkt"
         "src/project/lifecycle-records.rkt")

(define project-root "/absolute/path/to/project")

(define current
  (local-project-record-module-load
   (local-project-record-path project-root)))

(define replacement
  (local-project-record
   #:format-version current-local-project-format-version
   #:id (odra-local-project-record-id current)
   #:generation (add1 (odra-local-project-record-generation current))
   #:name (odra-local-project-record-name current)
   #:root (odra-local-project-record-root current)
   #:trust 'trusted))

(local-project-record-persist project-root replacement)
```

Use `'untrusted` as the replacement value to revoke trust. The writer requires
an exact next generation, validates the complete record, publishes atomically,
and rejects unsafe paths or permissions.

Reopen the Project after changing the durable record so the editor admits the
new generation. A Workspace does not transfer trust between member Projects.

## Refresh the root

Invoke `project-refresh` to reconcile the active Project root. Missing or
unreadable state is reported without removing identity, changing trust, or
closing buffers. Cancellation or failure preserves the last confirmed
observation generation.
