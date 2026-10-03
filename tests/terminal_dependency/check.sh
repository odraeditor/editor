#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

repository_root=$(cd "$(dirname "$0")/../.." && pwd)
checker="$repository_root/scripts/check-terminal-dependency.sh"
source_vendor="$repository_root/third_party/libghostty-vt/7b47213f94058c3715205ce8fa73f7ae581a652c"
mkdir -p "$repository_root/.build"
test_root=$(mktemp -d "$repository_root/.build/terminal-dependency.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

expect_rejected() {
  local label=$1
  if "$checker" "$test_root/vendor" >"$test_root/$label.out" 2>&1; then
    printf 'terminal dependency test: expected rejection for %s\n' "$label" >&2
    exit 1
  fi
}

reset_fixture() {
  rm -rf -- "$test_root/vendor"
  cp -al "$source_vendor" "$test_root/vendor"
}

"$checker" "$source_vendor" >/dev/null

reset_fixture
sed -i 's/7b47213f94058c3715205ce8fa73f7ae581a652c/0000000000000000000000000000000000000000/' \
  "$test_root/vendor/MANIFEST"
expect_rejected wrong-commit

reset_fixture
sed -i 's/5e0fb665aac3f1835bd0271ecc9a3da9f673112653e8bb85c48bc7ca1f07c4df/0000000000000000000000000000000000000000000000000000000000000000/' \
  "$test_root/vendor/MANIFEST"
expect_rejected wrong-source-checksum

reset_fixture
sed -i 's/zig_version=0.16.0/zig_version=0.15.2/' "$test_root/vendor/MANIFEST"
expect_rejected wrong-toolchain

reset_fixture
rm "$test_root/vendor/include/ghostty/vt/render.h"
expect_rejected missing-header

reset_fixture
sed -i 's/ghostty_terminal_new/ghostty_terminal_removed/' \
  "$test_root/vendor/include/ghostty/vt/terminal.h"
expect_rejected missing-symbol

reset_fixture
sed -i 's/abi_schema=1/abi_schema=2/' "$test_root/vendor/MANIFEST"
expect_rejected incompatible-abi

printf '%s\n' 'terminal dependency admission tests passed'
