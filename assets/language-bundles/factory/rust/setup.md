<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Rust language service setup

Odra provides Rust syntax without an external process. Language intelligence
requires `rust-analyzer` and the Rust standard-library sources that match the
selected toolchain:

```sh
rustup component add rust-analyzer rust-src
rust-analyzer --version
```

Odra starts `rust-analyzer` directly and resolves the nearest `Cargo.toml`,
falling back to the trusted Project root. Maintained acceptance uses the
official `2026-09-14` rust-analyzer release. If the executable is unavailable,
local syntax remains active and service commands report the missing
prerequisite.
