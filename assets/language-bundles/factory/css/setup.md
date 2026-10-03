<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# CSS language-service setup

Odra uses the CSS server from `vscode-langservers-extracted` 4.10.0:

```sh
npm install --global vscode-langservers-extracted@4.10.0
vscode-css-language-server --version
```

Odra starts `vscode-css-language-server --stdio` and selects the nearest
`package.json`, falling back to the trusted Project root. Syntax highlighting
remains available when the server is absent.
