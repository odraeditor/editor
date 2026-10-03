<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# HTML language-service setup

Odra uses the HTML server from `vscode-langservers-extracted` 4.10.0:

```sh
npm install --global vscode-langservers-extracted@4.10.0
vscode-html-language-server --version
```

Odra starts `vscode-html-language-server --stdio` and selects the nearest
`package.json`, falling back to the trusted Project root. HTML syntax and its
embedded JavaScript and CSS regions remain available when the server is absent.
