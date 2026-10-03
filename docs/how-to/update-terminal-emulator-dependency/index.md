<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Update the Terminal Emulator Dependency

Treat a `libghostty-vt` update as a new dependency admission, not as an
in-place replacement of the existing archive.

1. Create a new directory under `third_party/libghostty-vt/` named with the
   full upstream commit.
2. Record the upstream repository, commit, source and vendor archive hashes,
   MIT license, exact Zig version and archive hash, package-cache inputs, ABI
   schema, SIMD policy, required headers, symbols, and features in `MANIFEST`.
3. Add every admitted file and archive hash to `SHA256SUMS`. Preserve the
   corresponding license and public C headers.
4. Point `TERMINAL_VENDOR_DIR` in `makefiles/internal.mk` at the new immutable
   directory. Keep application code behind `src/terminal_emulator/adapter.c`;
   do not expose new upstream layouts or pointers to Odin callers.
5. Run `make terminal-dependency-check`. Resolve manifest, checksum, license,
   header, symbol, ABI, or toolchain failures before compiling.
6. Run `make terminal-vendor-clean-build` and `make terminal-emulator-test`.
   The clean build must use only the admitted offline inputs.
7. Run the focused terminal-session and presentation checks affected by API or
   behavior changes. Leave the previous admitted directory intact until the
   replacement is reviewed and integrated.

Document behavioral, ABI, resource, or licensing changes in the delivery
report. An upstream version label alone is insufficient evidence: the commit,
archives, hashes, toolchain, and adapter surface define the reproducible input.
