<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# JavaScript language-service setup

Odra uses `typescript-language-server` 6.0.0 with TypeScript 6.0.3 for
JavaScript and JSX language intelligence. Install both packages in the same
Node.js environment and confirm the executable is available:

```sh
npm install --global typescript-language-server@6.0.0 typescript@6.0.3
typescript-language-server --version
```

Odra starts the server with `--stdio` and selects the nearest `tsconfig.json`,
`jsconfig.json`, or `package.json`, falling back to the trusted Project root.
Syntax highlighting remains available when the server is absent.
