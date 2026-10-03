<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Go language service setup

Odra provides Go syntax without an external process. Language intelligence
requires `gopls` v0.23.0 from the selected Go toolchain:

```sh
go install golang.org/x/tools/gopls@v0.23.0
gopls version
```

Odra starts `gopls serve` and resolves the nearest `go.work` or `go.mod`,
falling back to the trusted Project root. If `gopls` is unavailable, local
syntax remains active and service commands report the missing executable.
