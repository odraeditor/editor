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

fail() {
  printf 'user-guide-exercise-check: %s\n' "$1" >&2
  exit 1
}

for executable in jq sha256sum tar unzstd; do
  command -v "$executable" >/dev/null 2>&1 ||
    fail "required executable is unavailable: $executable"
done

[ -f "$manifest" ] || fail "manifest is unavailable"
jq -e '
  .schemaVersion == 1 and
  .setupFormatVersion == 1 and
  (.exerciseSetVersion == .compatibleOdraVersion) and
  ([.dirs[].id] == ["notes"]) and
  ([.projects[].id] == ["forecast-engine", "report-console"]) and
  ([.workspaces[].id] == ["user-guide"]) and
  (.workspaces[0].projects == ["forecast-engine", "report-console"]) and
  ([.resetGroups[].id] | index("notes") != null) and
  ([.resetGroups[].id] | index("report-console-promotion") != null) and
  ([.resetGroups[].id] | index("workspace-state") != null) and
  ([.resetGroups[].id] | index("all") != null)
' "$manifest" >/dev/null || fail "manifest graph is invalid"

unsafe_path=$(
  jq -r '
    .files[].path,
    .dirs[].root,
    .projects[].root,
    .workspaces[].definition,
    .resetGroups[].workPaths[]?,
    .resetGroups[].configurationPaths[]?,
    .expectedChanges[].path
  ' "$manifest" | rg '(^/|(^|/)\.\.(/|$))' || true
)
[ -z "$unsafe_path" ] || fail "manifest contains an unsafe relative path: $unsafe_path"
[ -z "$(find "$asset_root" -type l -print)" ] || fail "asset source contains a symbolic link"
[ -z "$(find "$asset_root" -type d -name .odra -print)" ] ||
  fail "asset source contains live Project metadata"

diff -u \
  <(find "$asset_root" -type f ! -name manifest.json -printf '%P\n' | sort) \
  <(jq -r '.files[].path' "$manifest" | sort) ||
  fail "manifest payload list differs from the maintained source"

while IFS=$'\t' read -r digest asset_path; do
  printf '%s  %s/%s\n' "$digest" "$asset_root" "$asset_path" |
    sha256sum --check --status || fail "asset digest differs: $asset_path"
done < <(jq -r '.files[] | [.sha256, .path] | @tsv' "$manifest")

workspace_definition="$asset_root/$(jq -r '.workspaces[0].definition' "$manifest")"
manifest_projects=$(jq -c '.workspaces[0].projects' "$manifest")
definition_projects=$(jq -c '[.projects[].id]' "$workspace_definition")
[ "$manifest_projects" = "$definition_projects" ] ||
  fail "Workspace member order differs from the manifest"

"$repository_root/scripts/build-user-guide-exercises.sh" >/dev/null
version=$(jq -r '.exerciseSetVersion' "$manifest")
archive_name="odra-user-guide-$version.tar.zst"
archive="$output_root/$archive_name"
checksum="$archive.sha256"
(cd "$output_root" && sha256sum --check --status "$(basename "$checksum")") ||
  fail "archive checksum differs"

test_root=$(mktemp -d)
cleanup_test_root=true
trap 'if [ "$cleanup_test_root" = true ]; then rm -rf -- "$test_root"; fi' EXIT HUP INT TERM
package_parent="$test_root/package"
mkdir -p "$package_parent"
tar --use-compress-program=unzstd --extract --file "$archive" --directory "$package_parent"
package_root="$package_parent/odra-user-guide-$version"
[ -x "$package_root/bin/odra-guide" ] || fail "packaged setup helper is not executable"

diff -u \
  <(find "$package_root" -type f ! -name manifest.json ! -name SHA256SUMS -printf '%P\n' | sort) \
  <(jq -r '.files[].path' "$manifest" | sort) ||
  fail "archive payload differs from the manifest"
(cd "$package_root" && sha256sum --check --status SHA256SUMS) ||
  fail "archive payload checksum inventory differs"

fake_install="$test_root/odra-$version-linux-x86_64/bin"
command_dir="$test_root/.local/bin"
mkdir -p "$fake_install" "$command_dir"
cp /bin/true "$fake_install/odra"
ln -s "$fake_install/odra" "$command_dir/odra"
helper="$package_root/bin/odra-guide"
guide_root="$test_root/reader one/odra-guide"

env PATH="$command_dir:/usr/bin:/bin" "$helper" setup --root "$guide_root" >/dev/null
first_state=$(
  find "$guide_root/work" "$guide_root/config" -type f -exec sha256sum {} + | sort
)
env PATH="$command_dir:/usr/bin:/bin" "$helper" setup --root "$guide_root" >/dev/null
second_state=$(
  find "$guide_root/work" "$guide_root/config" -type f -exec sha256sum {} + | sort
)
[ "$first_state" = "$second_state" ] || fail "repeated setup changed established state"
[ -d "$guide_root/work/dirs/notes" ] || fail "ordinary Dir was not materialized"
[ -f "$guide_root/work/projects/forecast-engine/main.odin" ] ||
  fail "Forecast Engine was not materialized"
[ -f "$guide_root/work/projects/report-console/main.rkt" ] ||
  fail "Report Console was not materialized"
[ -f "$guide_root/config/odra/workspaces/user-guide.rkt" ] ||
  fail "User Guide Workspace was not materialized"
[ -z "$(rg -l '\.setup\.[0-9]+' "$guide_root/work" "$guide_root/config" || true)" ] ||
  fail "materialized records retain a staging path"

racket "$repository_root/scripts/setup-user-guide-workspace.rkt" \
  --configuration-root "$guide_root/config/odra" \
  --workspace-root "$guide_root/work/projects" \
  --name 'User Guide' >/dev/null

printf 'changed\n' > "$guide_root/work/dirs/notes/review.md"
printf 'created\n' > "$guide_root/work/dirs/notes/session-notes.txt"
printf 'preserve\n' > "$guide_root/work/dirs/notes/undeclared.txt"
"$helper" reset notes --root "$guide_root" >/dev/null
expected_review_digest=$(
  jq -r '.files[] | select(.path == "dirs/notes/review.md") | .sha256' "$manifest"
)
printf '%s  %s\n' "$expected_review_digest" "$guide_root/work/dirs/notes/review.md" |
  sha256sum --check --status || fail "notes reset did not restore supplied content"
[ ! -e "$guide_root/work/dirs/notes/session-notes.txt" ] ||
  fail "notes reset retained a declared created file"
[ -f "$guide_root/work/dirs/notes/undeclared.txt" ] ||
  fail "notes reset removed an undeclared file"

report_record_before=$(
  sha256sum "$guide_root/work/projects/report-console/.odra/project.rkt" | cut -d ' ' -f 1
)
printf 'changed report\n' > "$guide_root/work/projects/report-console/main.rkt"
"$helper" reset forecast-engine --root "$guide_root" >/dev/null
report_record_after=$(
  sha256sum "$guide_root/work/projects/report-console/.odra/project.rkt" | cut -d ' ' -f 1
)
[ "$report_record_before" = "$report_record_after" ] ||
  fail "Forecast Engine reset changed Report Console state"
[ "$(sed -n '1p' "$guide_root/work/projects/report-console/main.rkt")" = 'changed report' ] ||
  fail "Forecast Engine reset changed Report Console content"
"$helper" reset report-console --root "$guide_root" >/dev/null

"$helper" reset report-console-promotion --root "$guide_root" >/dev/null
[ ! -e "$guide_root/work/projects/report-console/.odra/project.rkt" ] ||
  fail "promotion reset retained the local Project record"
[ ! -e "$guide_root/config/odra/projects/report-console.rkt" ] ||
  fail "promotion reset retained Project discovery"
[ ! -e "$guide_root/config/odra/workspaces/user-guide.rkt" ] ||
  fail "promotion reset retained the dependent Workspace"
"$helper" reset workspace-state --root "$guide_root" >/dev/null
[ -f "$guide_root/work/projects/report-console/.odra/project.rkt" ] ||
  fail "Workspace reset did not restore local Project state"
[ -f "$guide_root/config/odra/workspaces/user-guide.rkt" ] ||
  fail "Workspace reset did not restore the Workspace"

conflict_root="$test_root/conflict-root"
mkdir -p "$conflict_root"
printf 'preserve\n' > "$conflict_root/unrelated.txt"
if env PATH="$command_dir:/usr/bin:/bin" "$helper" setup --root "$conflict_root" >/dev/null 2>&1; then
  fail "setup accepted a conflicting existing root"
fi
[ -f "$conflict_root/unrelated.txt" ] || fail "failed setup changed a conflicting root"

printf 'preserve outside cleanup\n' > "$test_root/unrelated.txt"
if "$helper" cleanup --root "$guide_root" --confirm "$test_root/wrong" >/dev/null 2>&1; then
  fail "cleanup accepted a mismatched confirmation"
fi
[ -d "$guide_root" ] || fail "rejected cleanup removed the guide root"
"$helper" cleanup --root "$guide_root" --confirm "$guide_root" >/dev/null
[ ! -e "$guide_root" ] || fail "confirmed cleanup retained the guide root"
[ -f "$test_root/unrelated.txt" ] || fail "cleanup changed a file outside the guide root"

test -z "$(rg -l 'scripts/setup-user-guide-workspace\.rkt' \
  "$repository_root/docs/tutorials/user-guide" || true)" ||
  fail "User Guide still exposes repository-only Workspace setup"
rg -q 'odra-guide" setup' \
  "$repository_root/docs/tutorials/user-guide/getting-started/prepare-exercises.md" ||
  fail "User Guide does not document installed setup"
rg -q 'odra-guide" reset notes' \
  "$repository_root/docs/tutorials/user-guide/getting-started/prepare-exercises.md" ||
  fail "User Guide does not document reset"
rg -q 'cleanup --confirm' \
  "$repository_root/docs/tutorials/user-guide/getting-started/prepare-exercises.md" ||
  fail "User Guide does not document bounded cleanup"

cleanup_test_root=false
rm -rf -- "$test_root"
trap - EXIT HUP INT TERM
printf 'Checked User Guide source, archive, setup, relocation, reset, and cleanup.\n'
