#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
environment_manifest="$repository_root/release/linux-x86_64/build-environment.json"
containerfile="$repository_root/release/linux-x86_64/Containerfile.build"
prepared_image=odra-preview-build:20260831
tag=
commit=
adapter_commit=
source_date_epoch=
output_root=

fail() {
  printf 'preview reproduction: %s\n' "$1" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --tag) tag=${2:-}; shift 2 ;;
    --commit) commit=${2:-}; shift 2 ;;
    --adapter-commit) adapter_commit=${2:-}; shift 2 ;;
    --source-date-epoch) source_date_epoch=${2:-}; shift 2 ;;
    --output) output_root=${2:-}; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ $tag =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
  fail 'tag must use canonical vMAJOR.MINOR.PATCH form'
[[ $commit =~ ^[0-9a-f]{40}$ ]] || fail 'commit must be a full lowercase Git identity'
[[ $adapter_commit =~ ^[0-9a-f]{40}$ ]] || \
  fail 'adapter commit must be a full lowercase Git identity'
[[ $source_date_epoch =~ ^[0-9]+$ ]] || fail 'source date epoch must be numeric'
[ -n "$output_root" ] || fail 'output directory is required'
git -C "$repository_root" cat-file -e "$commit^{commit}" 2>/dev/null || \
  fail 'commit is unavailable'
git -C "$repository_root" cat-file -e "$adapter_commit^{commit}" 2>/dev/null || \
  fail 'adapter commit is unavailable'
[ "$(git -C "$repository_root" rev-parse HEAD)" = "$adapter_commit" ] || \
  fail 'checked-out publication adapter differs from the requested commit'
git -C "$repository_root" diff --quiet "$adapter_commit" -- \
  scripts/release/build-racket-runtime-module.rkt \
  scripts/release/reproduce-preview.sh || \
  fail 'publication adapter files differ from the requested commit'

if [ -e "$output_root" ]; then
  [ -d "$output_root" ] || fail 'output path must be a directory'
  [ -z "$(find "$output_root" -mindepth 1 -print -quit)" ] || \
    fail 'output directory must be empty'
fi

version=${tag#v}
artifact_stem="odra-$version-linux-x86_64"
build_environment=$(racket -e \
  '(require json) (define e (call-with-input-file (vector-ref (current-command-line-arguments) 0) read-json)) (display (hash-ref (hash-ref (hash-ref e (quote images)) (quote build)) (quote digest)))' \
  "$environment_manifest")

mkdir -p "$output_root"
output_root=$(cd "$output_root" && pwd)
evidence_directory="$output_root/evidence"
mkdir -p "$evidence_directory"

racket "$repository_root/scripts/release/check-build-environment.rkt"
docker build --quiet --tag "$prepared_image" --file "$containerfile" \
  "$repository_root/release/linux-x86_64" > "$evidence_directory/prepared-image.id"
docker run --rm --network none --cpus 4 --memory 6g --pids-limit 512 \
  "$prepared_image" bash -lc \
  'test "$(odin version)" = "odin version dev-2026-07:301c287de" && test "$(racket --version)" = "Welcome to Racket v9.2 [cs]."'

workspace="$output_root/workspace"
mkdir -p "$workspace"
git -C "$repository_root" archive "$commit" | tar -x -C "$workspace"
log="$evidence_directory/build.log"
printf 'preview_provenance_commit=%s adapter_commit=%s workspace=%s\n' \
  "$commit" "$adapter_commit" "$workspace" | tee "$log"
runtime_module_builder="$repository_root/scripts/release/build-racket-runtime-module.rkt"
timeout 7200 docker run --rm \
  --network none \
  --cpus 4 \
  --memory 6g \
  --pids-limit 512 \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp/odra-home \
  --env SOURCE_DATE_EPOCH="$source_date_epoch" \
  --tmpfs /tmp:rw,nosuid,nodev,size=1073741824,mode=1777 \
  --mount "type=bind,src=$workspace,dst=/workspace" \
  --mount "type=bind,src=$runtime_module_builder,dst=/release-adapter/build-racket-runtime-module.rkt,readonly" \
  --workdir /workspace \
  "$prepared_image" \
  bash -lc \
    "racket /release-adapter/build-racket-runtime-module.rkt --source-root /workspace/src --entry hosting/runtime-boundary.rkt --output /workspace/.build/hosting/runtime_module.c && make preview-tree PREVIEW_TAG='$tag' PREVIEW_COMMIT='$commit' PREVIEW_BUILD_ENVIRONMENT='$build_environment' ODRA_PREVIEW_THREAD_COUNT=1 && make preview-archive PREVIEW_TAG='$tag' PREVIEW_COMMIT='$commit' PREVIEW_TREE='.build/release/linux-x86_64/$artifact_stem'" \
  2>&1 | tee -a "$log"

tree="$workspace/.build/release/linux-x86_64/$artifact_stem"
archive="$workspace/.build/release/linux-x86_64/$artifact_stem.tar.zst"
checksum="$archive.sha256"

racket "$repository_root/scripts/release/record-preview-provenance.rkt" \
  --tree "$tree" \
  --archive "$archive" \
  --checksum "$checksum" \
  --tag "$tag" \
  --commit "$commit" \
  --adapter-commit "$adapter_commit" \
  --source-date-epoch "$source_date_epoch" \
  --build-environment "$build_environment" \
  --evidence "$evidence_directory"
