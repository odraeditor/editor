#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.


set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)
asset_root="$repository_root/assets/docs/user-guide"
manifest="$asset_root/manifest.json"
output_root="$repository_root/.build/docs/user-guide"

for executable in jq sha256sum tar zstd; do
  command -v "$executable" >/dev/null 2>&1 || {
    printf 'user-guide-exercises: required executable is unavailable: %s\n' "$executable" >&2
    exit 1
  }
done

[ -f "$manifest" ] || {
  printf 'user-guide-exercises: manifest is unavailable: %s\n' "$manifest" >&2
  exit 1
}

version=$(jq -er '.exerciseSetVersion' "$manifest")
compatible_version=$(jq -er '.compatibleOdraVersion' "$manifest")
[ "$version" = "$compatible_version" ] || {
  printf 'user-guide-exercises: exercise and Odra versions differ\n' >&2
  exit 1
}

archive_stem="odra-user-guide-$version"
archive_name="$archive_stem.tar.zst"
checksum_name="$archive_name.sha256"
mkdir -p "$output_root"
staging_root=$(mktemp -d "$output_root/.exercise-package.XXXXXX")
cleanup_staging=true
trap 'if [ "$cleanup_staging" = true ]; then rm -rf -- "$staging_root"; fi' EXIT HUP INT TERM
package_root="$staging_root/$archive_stem"
mkdir -p "$package_root"

while IFS=$'\t' read -r digest asset_path; do
  case "$asset_path" in
    /*|..|../*|*/../*|*/..)
      printf 'user-guide-exercises: unsafe manifest path: %s\n' "$asset_path" >&2
      exit 1
      ;;
  esac
  source_path="$asset_root/$asset_path"
  [ -f "$source_path" ] && [ ! -L "$source_path" ] || {
    printf 'user-guide-exercises: payload is not a regular owned file: %s\n' "$asset_path" >&2
    exit 1
  }
  printf '%s  %s\n' "$digest" "$source_path" | sha256sum --check --status || {
    printf 'user-guide-exercises: payload digest differs: %s\n' "$asset_path" >&2
    exit 1
  }
  destination="$package_root/$asset_path"
  mkdir -p "$(dirname "$destination")"
  cp "$source_path" "$destination"
done < <(jq -r '.files[] | [.sha256, .path] | @tsv' "$manifest")

cp "$manifest" "$package_root/manifest.json"
jq -r '.files[] | "\(.sha256)  \(.path)"' "$manifest" > "$package_root/SHA256SUMS"
chmod 755 "$package_root/bin/odra-guide"

temporary_tar="$staging_root/$archive_stem.tar"
temporary_archive="$staging_root/$archive_name"
temporary_checksum="$staging_root/$checksum_name"
tar \
  --sort=name \
  --format=ustar \
  --mtime='@0' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --mode='u+rwX,go+rX,go-w' \
  --create \
  --file "$temporary_tar" \
  --directory "$staging_root" \
  "$archive_stem"
zstd --quiet --threads=1 -19 "$temporary_tar" -o "$temporary_archive"
archive_digest=$(sha256sum "$temporary_archive" | cut -d ' ' -f 1)
printf '%s  %s\n' "$archive_digest" "$archive_name" > "$temporary_checksum"

mv --force "$temporary_archive" "$output_root/$archive_name"
mv --force "$temporary_checksum" "$output_root/$checksum_name"
cleanup_staging=false
rm -rf -- "$staging_root"
trap - EXIT HUP INT TERM

printf 'user_guide_archive=%s\n' "$output_root/$archive_name"
printf 'user_guide_checksum=%s\n' "$output_root/$checksum_name"
printf 'sha256=%s\n' "$archive_digest"
