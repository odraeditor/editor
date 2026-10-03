#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

vendor_dir=${1:-third_party/libghostty-vt/7b47213f94058c3715205ce8fa73f7ae581a652c}
manifest="$vendor_dir/MANIFEST"

fail() {
  printf 'terminal dependency check: %s\n' "$1" >&2
  exit 1
}

manifest_value() {
  local key=$1
  local count
  count=$(awk -F= -v key="$key" '$1 == key { count += 1 } END { print count + 0 }' "$manifest")
  [ "$count" -eq 1 ] || fail "manifest key must occur exactly once: $key"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }' "$manifest"
}

require_value() {
  local key=$1
  local expected=$2
  local actual
  actual=$(manifest_value "$key")
  [ "$actual" = "$expected" ] || fail "$key mismatch"
}

[ -f "$manifest" ] || fail "MANIFEST is unavailable"
[ -f "$vendor_dir/LICENSE" ] || fail "MIT license is unavailable"
[ -f "$vendor_dir/SHA256SUMS" ] || fail "header checksums are unavailable"

require_value name libghostty-vt
require_value upstream_repository https://github.com/ghostty-org/ghostty
require_value upstream_commit 7b47213f94058c3715205ce8fa73f7ae581a652c
require_value upstream_version 0.1.0-dev
require_value upstream_source_sha256 5e0fb665aac3f1835bd0271ecc9a3da9f673112653e8bb85c48bc7ca1f07c4df
require_value vendor_source_sha256 1df5d73c5f52ac39a7466177b9fd21bc363cbf1ca1bac7b67dbdab1c20876003
require_value license MIT
require_value zig_version 0.16.0
require_value zig_sha256 70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
require_value abi_schema 1
require_value simd false

(
  cd "$vendor_dir"
  sha256sum --check SHA256SUMS >/dev/null
) || fail "license or public header checksum mismatch"

for header in $(manifest_value required_headers); do
  [ -f "$vendor_dir/include/$header" ] || fail "required header is unavailable: $header"
done

for symbol in $(manifest_value required_symbols); do
  grep -R -Fq "$symbol" "$vendor_dir/include/ghostty/vt" || \
    fail "required C symbol is unavailable: $symbol"
done

source_archive=$(manifest_value vendor_source_archive)
zig_archive=$(manifest_value zig_archive)
[ -f "$vendor_dir/source/$source_archive" ] || \
  fail "vendor source archive is unavailable"
[ -f "$vendor_dir/toolchain/$zig_archive" ] || \
  fail "Zig toolchain archive is unavailable"

for package in $(manifest_value package_archives); do
  [ -f "$vendor_dir/packages/$package" ] || \
    fail "Zig package archive is unavailable: $package"
done

grep -Fq '"schema": 1' "$vendor_dir/include/ghostty/vt/types.h" || \
  fail "C ABI schema documentation is incompatible"

printf '%s\n' \
  'terminal_dependency=valid' \
  'upstream_commit=7b47213f94058c3715205ce8fa73f7ae581a652c library_version=0.1.0-dev' \
  'zig_version=0.16.0 abi_schema=1 simd=false'
