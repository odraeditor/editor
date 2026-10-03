#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.


set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_commit=$(git -C "$repository_root" ls-remote origin refs/heads/main |
  awk '{print $1}')
status_output=$(racket "$repository_root/scripts/nightly-status.rkt" \
  --source-commit "$source_commit")
printf '%s\n' "$status_output"
case $status_output in
  nightly:\ status=missing\ * | *\ admission=retryable\ *) ;;
  *)
    printf '%s\n' 'nightly dispatch: skipped because an active run or a successful run for the same source owns the local date'
    exit 0
    ;;
esac

origin_url=$(git -C "$repository_root" remote get-url origin)
repository_path=${origin_url%.git}
repository_slug=$(printf '%s\n' "$repository_path" |
  sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#')

if [[ -z $repository_slug || $repository_slug == "$repository_path" ]]; then
  printf '%s\n' 'nightly dispatch: unable to derive the repository slug' >&2
  exit 1
fi

arguments=(
  actions workflows dispatch nightly.yml
  --ref main
  --repo "$repository_slug"
)
if [[ -n ${ODRA_TEA_LOGIN:-} ]]; then
  arguments+=(--login "$ODRA_TEA_LOGIN")
fi

tea "${arguments[@]}"
