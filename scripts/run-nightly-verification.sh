#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.


set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
result_directory=${ODRA_NIGHTLY_RESULT_DIRECTORY:-$repository_root/.build/nightly}
verification_log="$result_directory/verify.log"
stage_records="$result_directory/stages.tsv"
summary_json="$result_directory/summary.json"
summary_markdown="$result_directory/summary.md"
timeout_limit=${ODRA_NIGHTLY_TIMEOUT:-6h}
make_command=${ODRA_NIGHTLY_MAKE:-make}

duration_seconds() {
  local value=$1
  case $value in
    *s) printf '%d\n' "${value%s}" ;;
    *m) printf '%d\n' "$(( ${value%m} * 60 ))" ;;
    *h) printf '%d\n' "$(( ${value%h} * 60 * 60 ))" ;;
    *d) printf '%d\n' "$(( ${value%d} * 24 * 60 * 60 ))" ;;
    *) printf '%d\n' "$value" ;;
  esac
}

timeout_seconds=$(duration_seconds "$timeout_limit")
if [[ $timeout_seconds -le 0 ]]; then
  printf 'nightly verification: invalid timeout: %s\n' "$timeout_limit" >&2
  exit 2
fi

stages=(
  'source-hygiene|source-hygiene-check'
  'compile-checks|check'
  'ui-migration|ui-migration-check'
  'test-suite|internal-test'
  'hosting|hosting-test'
  'documentation|docs-check'
)

mkdir -p "$result_directory"
result_directory=$(cd -- "$result_directory" && pwd)
# Native compilation must not consume a host's quota-limited temporary filesystem.
temporary_directory=$(mktemp -d "$result_directory/tmp.XXXXXX")
cleanup() {
  case "$temporary_directory" in
    "$result_directory"/tmp.*)
      chmod -R u+w -- "$temporary_directory"
      rm -rf -- "$temporary_directory"
      ;;
    *)
      printf 'refusing to remove unexpected nightly temporary directory: %s\n' \
        "$temporary_directory" >&2
      return 1
      ;;
  esac
}
trap cleanup EXIT
export TMPDIR="$temporary_directory"
: >"$verification_log"
: >"$stage_records"

commit=$(git -C "$repository_root" rev-parse HEAD)
started_at=$(date --utc '+%Y-%m-%dT%H:%M:%SZ')
started_epoch=$(date '+%s')
deadline_epoch=$((started_epoch + timeout_seconds))
aggregate_exit=0
timed_out=false
timeout_stage=''

for stage_specification in "${stages[@]}"; do
  stage_name=${stage_specification%%|*}
  stage_target=${stage_specification#*|}
  current_epoch=$(date '+%s')
  remaining_seconds=$((deadline_epoch - current_epoch))
  if [[ $timed_out == true || $remaining_seconds -le 0 ]]; then
    if [[ -z $timeout_stage ]]; then
      timed_out=true
      timeout_stage=global-deadline
      aggregate_exit=124
    fi
    printf '%s\t%s\tskipped\t-\t0\n' "$stage_name" "$stage_target" >>"$stage_records"
    printf 'ODRA_NIGHTLY_STAGE name=%s target=%s status=skipped reason=global-deadline\n' \
      "$stage_name" "$stage_target" | tee -a "$verification_log"
    if [[ -n ${ODRA_EVIDENCE_DIRECTORY:-} ]]; then
      racket "$repository_root/scripts/evidence/producer.rkt" \
        --directory "$ODRA_EVIDENCE_DIRECTORY" --stage "$stage_name" skip >/dev/null 2>&1 ||
        printf '%s\n' 'native-evidence: skipped phase observation unavailable'
    fi
    continue
  fi

  stage_started_epoch=$current_epoch
  printf 'ODRA_NIGHTLY_STAGE_BEGIN name=%s target=%s remaining_seconds=%s\n' \
    "$stage_name" "$stage_target" "$remaining_seconds" | tee -a "$verification_log"
  set +e
  (
    cd "$repository_root"
    bash scripts/evidence/run-stage.sh "$stage_name" -- \
      timeout --foreground --signal=TERM --kill-after=30s \
      "${remaining_seconds}s" "$make_command" "$stage_target"
  ) 2>&1 | tee -a "$verification_log"
  stage_exit=${PIPESTATUS[0]}
  set -e
  stage_finished_epoch=$(date '+%s')
  stage_duration=$((stage_finished_epoch - stage_started_epoch))

  if [[ $stage_exit -eq 0 ]]; then
    stage_status=passed
  elif [[ $stage_exit -eq 124 || $stage_finished_epoch -ge $deadline_epoch ]]; then
    stage_status=timed-out
    timed_out=true
    timeout_stage=$stage_name
    aggregate_exit=124
  else
    stage_status=failed
    if [[ $aggregate_exit -eq 0 ]]; then
      aggregate_exit=1
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$stage_name" "$stage_target" "$stage_status" "$stage_exit" "$stage_duration" \
    >>"$stage_records"
  printf 'ODRA_NIGHTLY_STAGE_END name=%s target=%s status=%s exit_code=%s duration_seconds=%s\n' \
    "$stage_name" "$stage_target" "$stage_status" "$stage_exit" "$stage_duration" \
    | tee -a "$verification_log"
done

finished_at=$(date --utc '+%Y-%m-%dT%H:%M:%SZ')
finished_epoch=$(date '+%s')
total_duration=$((finished_epoch - started_epoch))
status=success
if [[ $aggregate_exit -ne 0 ]]; then
  status=failure
fi

racket "$repository_root/scripts/write-nightly-summary.rkt" \
  --stages "$stage_records" \
  --json "$summary_json" \
  --markdown "$summary_markdown" \
  --status "$status" \
  --exit-code "$aggregate_exit" \
  --timed-out "$timed_out" \
  --timeout-stage "${timeout_stage:-none}" \
  --commit "$commit" \
  --started-at "$started_at" \
  --finished-at "$finished_at" \
  --duration-seconds "$total_duration"

printf '%s\n' \
  'ODRA_NIGHTLY_SUMMARY_BEGIN' \
  "status=$status" \
  "exit_code=$aggregate_exit" \
  "timed_out=$timed_out" \
  "timeout_stage=${timeout_stage:-none}" \
  "commit=$commit" \
  "duration_seconds=$total_duration" \
  'ODRA_NIGHTLY_SUMMARY_END'

exit "$aggregate_exit"
