#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.


set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$workspace_root/assets/docs/user-guide/manifest.json"
artifact_root="$workspace_root/.build/docs/user-guide"
server_url=${FORGEJO_SERVER_URL:-}
owner=${PACKAGE_OWNER:-}
token=${ODRA_USER_GUIDE_PACKAGE_TOKEN:-}

if [[ ! "$server_url" =~ ^https://[^/]+$ ]]; then
  printf '%s\n' 'FORGEJO_SERVER_URL must be one fixed HTTPS origin' >&2
  exit 2
fi
if [[ ! "$owner" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf '%s\n' 'PACKAGE_OWNER must be one safe package owner' >&2
  exit 2
fi
if [[ -z "$token" || "$token" == *$'\n'* || "$token" == *$'\r'* ]]; then
  printf '%s\n' 'ODRA_USER_GUIDE_PACKAGE_TOKEN is unavailable or malformed' >&2
  exit 2
fi

version=$(jq -r '.exerciseSetVersion' "$manifest")
compatible_version=$(jq -r '.compatibleOdraVersion' "$manifest")
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ||
      "$version" != "$compatible_version" ]]; then
  printf '%s\n' 'exercise and compatible Odra versions must be one matching SemVer' >&2
  exit 2
fi

stem="odra-user-guide-$version"
archive="$artifact_root/$stem.tar.zst"
checksum="$archive.sha256"
for artifact in "$archive" "$checksum"; do
  if [[ ! -f "$artifact" ]]; then
    printf 'publication artifact is missing: %s\n' "$artifact" >&2
    exit 1
  fi
done
(cd "$artifact_root" && sha256sum --check --strict "$stem.tar.zst.sha256")

temporary_root=$(mktemp -d "$workspace_root/.build/user-guide-publication.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT
header_file="$temporary_root/authorization-header"
umask 077
printf 'Authorization: token %s\n' "$token" > "$header_file"

package_base="$server_url/api/packages/$owner/generic/odra-user-guide/$version"
for artifact in "$archive" "$checksum"; do
  filename=$(basename "$artifact")
  url="$package_base/$filename"
  artifact_sha256=$(sha256sum "$artifact" | awk '{print $1}')
  probe_url="$url?sha256=$artifact_sha256"
  public_copy="$temporary_root/$filename.public"
  http_code=$(curl --location --silent --show-error --output "$public_copy" \
    --write-out '%{http_code}' "$probe_url")
  case "$http_code" in
    200)
      if ! cmp --silent "$artifact" "$public_copy"; then
        printf 'immutable package conflict: %s\n' "$filename" >&2
        exit 1
      fi
      printf 'reused %s\n' "$filename"
      ;;
    404)
      upload_code=$(curl --silent --show-error --output /dev/null \
        --write-out '%{http_code}' --header "@$header_file" \
        --upload-file "$artifact" "$url")
      if [[ "$upload_code" != 201 ]]; then
        printf 'upload failed for %s with HTTP %s\n' "$filename" "$upload_code" >&2
        exit 1
      fi
      printf 'uploaded %s\n' "$filename"
      ;;
    *)
      printf 'public package probe failed for %s with HTTP %s\n' \
        "$filename" "$http_code" >&2
      exit 1
      ;;
  esac
done

verified_root="$temporary_root/verified"
mkdir -p "$verified_root"
for filename in "$stem.tar.zst" "$stem.tar.zst.sha256"; do
  expected_sha256=$(sha256sum "$artifact_root/$filename" | awk '{print $1}')
  curl --fail --location --silent --show-error \
    "$package_base/$filename?sha256=$expected_sha256" \
    --output "$verified_root/$filename"
done
(cd "$verified_root" && sha256sum --check --strict "$stem.tar.zst.sha256")
cmp --silent "$archive" "$verified_root/$stem.tar.zst"
cmp --silent "$checksum" "$verified_root/$stem.tar.zst.sha256"

printf 'published and verified odra-user-guide %s\n' "$version"
