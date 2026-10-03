#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -u
set +e

stage=$1
shift
if [[ ${1:-} != -- ]]; then
  printf '%s\n' 'native-evidence: command separator is required' >&2
  exit 2
fi
shift
session=${ODRA_EVIDENCE_DIRECTORY:-}
producer=$(dirname -- "${BASH_SOURCE[0]}")/producer.rkt

# Evidence failure must not suppress or retry the product command.
if [[ -z $session || ! -f "$session/session.json" ]] ||
   ! racket "$producer" --directory "$session" --stage "$stage" prepare >/dev/null 2>&1; then
  exec "$@"
fi

if [[ -x /usr/bin/time ]] && { exec 3>"$session/$stage.time"; } 2>/dev/null; then
  /usr/bin/time -q -f '%U %S %M' -o /dev/fd/3 -- "$@"
else
  "$@"
fi
result=$?
exec 3>&-
finished_ms=$(date +%s%3N)
racket "$producer" --directory "$session" --stage "$stage" \
  --exit-code "$result" --finished-ms "$finished_ms" \
  --metrics "$session/$stage.time" observe >/dev/null 2>&1 ||
  printf '%s\n' 'native-evidence: phase observation unavailable' >&2
exit "$result"
