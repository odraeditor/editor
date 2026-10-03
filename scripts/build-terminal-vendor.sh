#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

vendor_dir=${1:-third_party/libghostty-vt/7b47213f94058c3715205ce8fa73f7ae581a652c}
build_dir=${2:-.build/terminal-vendor}
mode=${3:-cached}
repository_root=$PWD

fail() {
  printf 'terminal vendor build: %s\n' "$1" >&2
  exit 1
}

manifest_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }' \
    "$vendor_dir/MANIFEST"
}

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) ;;
  *) fail "the admitted Zig toolchain targets Linux x86-64" ;;
esac

bash "$repository_root/scripts/check-terminal-dependency.sh" "$vendor_dir" >/dev/null

vendor_dir=$(cd "$vendor_dir" && pwd)
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)

if [ "$mode" = --clean ]; then
  find "$build_dir" -mindepth 1 -depth -delete
elif [ "$mode" != cached ]; then
  fail "unknown build mode: $mode"
fi

source_archive=$(manifest_value vendor_source_archive)
zig_archive=$(manifest_value zig_archive)
source_root="$build_dir/source/libghostty-vt-1.3.2-main-+7b47213"
zig_root="$build_dir/toolchain/zig-x86_64-linux-0.16.0"
global_cache="$build_dir/zig-global-cache"
local_cache="$build_dir/zig-local-cache"
install_root="$build_dir/install"

if [ ! -x "$zig_root/zig" ]; then
  mkdir -p "$build_dir/toolchain"
  find "$build_dir/toolchain" -mindepth 1 -depth -delete
  tar -xJf "$vendor_dir/toolchain/$zig_archive" -C "$build_dir/toolchain"
fi

[ "$($zig_root/zig version)" = 0.16.0 ] || fail "unexpected Zig version"

if [ ! -f "$source_root/build.zig" ]; then
  mkdir -p "$build_dir/source"
  find "$build_dir/source" -mindepth 1 -depth -delete
  tar -xzf "$vendor_dir/source/$source_archive" -C "$build_dir/source"
fi

mkdir -p "$global_cache/p" "$local_cache" "$install_root"
find "$global_cache/p" -mindepth 1 -depth -delete
cp "$vendor_dir"/packages/*.tar.gz "$global_cache/p/"

(
  cd "$source_root"
  HTTPS_PROXY=http://127.0.0.1:9 \
  HTTP_PROXY=http://127.0.0.1:9 \
  ALL_PROXY=http://127.0.0.1:9 \
  NO_PROXY= \
    "$zig_root/zig" build \
      --cache-dir "$local_cache" \
      --global-cache-dir "$global_cache" \
      --prefix "$install_root" \
      -j2 \
      --maxrss 4294967296 \
      -Demit-lib-vt=true \
      -Doptimize=ReleaseFast \
      -Dsimd=false
)

test -s "$install_root/lib/libghostty-vt.a" || fail "static library is unavailable"
test -s "$install_root/include/ghostty/vt.h" || fail "installed public header is unavailable"

# Zig's static archive carries weak libc compatibility symbols. Localize them
# so linking the emulator into an Odin process cannot preempt Odin's libc
# allocator during runtime initialization.
objcopy --localize-symbol=calloc --localize-symbol=free \
  "$install_root/lib/libghostty-vt.a" 2>/dev/null || \
  fail "unable to isolate static runtime symbols"
if nm -g "$install_root/lib/libghostty-vt.a" | grep -Eq ' [TW] (calloc|free)$'; then
  fail "static runtime symbols remain externally visible"
fi

printf '%s\n' \
  'terminal_vendor=built offline=true' \
  "library=$install_root/lib/libghostty-vt.a" \
  "zig_version=$($zig_root/zig version) simd=false"
