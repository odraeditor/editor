<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Racket language service setup

Odra provides Racket syntax without an external process. Language intelligence
requires Racket and the maintained `racket-langserver` package:

```sh
raco pkg install --auto racket-langserver
```

Confirm the same Racket installation can resolve the server module:

```sh
racket -l racket-langserver
```

Odra starts the server with that argument vector and resolves the nearest
`info.rkt`, falling back to the trusted Project root. If the executable or
module is unavailable, local syntax remains active and service commands report
the unavailable prerequisite.
