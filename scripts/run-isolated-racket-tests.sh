#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  printf '%s\n' 'usage: run-isolated-racket-tests.sh COMMAND [ARGUMENT ...]' >&2
  exit 2
fi

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary_parent=${TMPDIR:-$repository_root/.build/test-isolation}
mkdir -p "$temporary_parent"
temporary_parent=$(cd -- "$temporary_parent" && pwd)
isolated_root=$(mktemp -d "$temporary_parent/odra-isolated-racket-tests.XXXXXX")
isolated_home="$isolated_root/home"
isolated_config="$isolated_root/config"
isolated_state="$isolated_root/state"
isolated_cache="$isolated_root/cache"
isolated_data="$isolated_root/data"
isolated_temporary="$isolated_root/tmp"

cleanup() {
  case "$isolated_root" in
    "$temporary_parent"/odra-isolated-racket-tests.*)
      # Go module downloads can leave read-only directories inside this owned tree.
      chmod -R u+w -- "$isolated_root"
      rm -rf -- "$isolated_root"
      ;;
    *)
      printf 'refusing to remove unexpected isolated root: %s\n' "$isolated_root" >&2
      return 1
      ;;
  esac
}
trap cleanup EXIT

mkdir -p \
  "$isolated_home" \
  "$isolated_config" \
  "$isolated_state" \
  "$isolated_cache" \
  "$isolated_data" \
  "$isolated_temporary"

env \
  HOME="$isolated_home" \
  XDG_CONFIG_HOME="$isolated_config" \
  XDG_STATE_HOME="$isolated_state" \
  XDG_CACHE_HOME="$isolated_cache" \
  XDG_DATA_HOME="$isolated_data" \
  TMPDIR="$isolated_temporary" \
  "$@"
