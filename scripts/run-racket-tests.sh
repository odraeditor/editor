#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.


set -euo pipefail

if [[ $# -lt 2 ]]; then
  printf '%s\n' 'racket test: expected the raco command and build directory' >&2
  exit 2
fi

raco_command=$1
build_directory=$2
shift 2

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $build_directory = /* ]]; then
  timings_directory=$build_directory/timings
else
  timings_directory=$repository_root/$build_directory/timings
fi

timings_log=${ODRA_RACKET_TIMINGS_LOG:-$timings_directory/racket-tests.log}
mkdir -p "$(dirname -- "$timings_log")"
started_milliseconds=$(date +%s%3N)
set +e
"$raco_command" test --make "$@"
result=$?
set -e
finished_milliseconds=$(date +%s%3N)
elapsed_milliseconds=$((finished_milliseconds - started_milliseconds))
printf 'racket-test elapsed-ms=%d status=%d modules=%d\n' \
  "$elapsed_milliseconds" "$result" "$#" | tee -a "$timings_log"
exit "$result"
