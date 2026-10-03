// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:testing"

/* Verifies the resource-study defaults stay within the complete process envelope. */
@(test)
default_process_limits_are_admitted :: proc(t: ^testing.T) {
	testing.expect(t, process_limits_are_valid(DEFAULT_PROCESS_LIMITS))
	testing.expect_value(t, DEFAULT_PROCESS_LIMITS.status_paths, DEFAULT_STATUS_PATHS)
	testing.expect_value(t, DEFAULT_PROCESS_LIMITS.status_path_bytes, DEFAULT_STATUS_PATH_BYTES)
	testing.expect_value(t, DEFAULT_PROCESS_LIMITS.stdout_bytes, DEFAULT_PROCESS_OUTPUT_BYTES)
	testing.expect_value(t, DEFAULT_PROCESS_LIMITS.diagnostic_bytes, DEFAULT_DIAGNOSTIC_BYTES)
	testing.expect_value(t, DEFAULT_PROCESS_LIMITS.diff_bytes, DEFAULT_DIFF_BYTES)
}

/* Verifies invalid resource envelopes reject range and cross-field violations. */
@(test)
process_limits_reject_invalid_ranges_and_relationships :: proc(t: ^testing.T) {
	too_many_paths := DEFAULT_PROCESS_LIMITS
	too_many_paths.status_paths = MAX_STATUS_PATHS + 1
	testing.expect(t, !process_limits_are_valid(too_many_paths))

	too_much_diagnostic := DEFAULT_PROCESS_LIMITS
	too_much_diagnostic.diagnostic_bytes = too_much_diagnostic.stdout_bytes + 1
	testing.expect(t, !process_limits_are_valid(too_much_diagnostic))

	invalid_grace := DEFAULT_PROCESS_LIMITS
	invalid_grace.cancellation_grace_ns = invalid_grace.timeout_nanoseconds
	testing.expect(t, !process_limits_are_valid(invalid_grace))
}

/* Verifies a repository context is copied and rejects nonlocal or malformed paths. */
@(test)
repository_context_requires_a_copied_absolute_path :: proc(t: ^testing.T) {
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, "/work/example"))
	testing.expect(t, repository_context_is_valid(repository))
	testing.expect_value(t, repository_context_string(&repository), "/work/example")

	testing.expect(t, !repository_context_assign(&repository, "relative/path"))
	testing.expect(t, !repository_context_is_valid(repository))
	testing.expect(t, !repository_context_assign(&repository, "/work/\x00invalid"))
	testing.expect(t, !repository_context_is_valid(repository))
}

/* Verifies process request shape keeps Status observation separate from path actions. */
@(test)
process_requests_require_checked_context_and_targets :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example")
	testing.expect(t, ready)
	if !ready do return

	observe := Process_Request {
		kind = .Observe_Status,
		repository = repository,
		limits = DEFAULT_PROCESS_LIMITS,
	}
	testing.expect(t, process_request_is_valid(observe))

	inspect := observe
	inspect.kind = .Inspect_Path
	testing.expect(t, !process_request_is_valid(inspect))
	inspect.target = {generation = Observation_Generation(7), path = Path_ID(3)}
	testing.expect(t, process_request_is_valid(inspect))

	observe.target = inspect.target
	testing.expect(t, !process_request_is_valid(observe))

	history := Process_Request {
		kind = .Observe_History,
		repository = repository,
		history = {limits = DEFAULT_HISTORY_LIMITS},
		limits = DEFAULT_PROCESS_LIMITS,
	}
	testing.expect(t, process_request_is_valid(history))
	history.target = inspect.target
	testing.expect(t, !process_request_is_valid(history))
}

/* Verifies immutable Status descriptors cannot exceed their checked budgets. */
@(test)
observation_descriptors_require_checked_metadata :: proc(t: ^testing.T) {
	repository: Repository_Context
	branch: Branch_Label
	ready := repository_context_assign(&repository, "/work/example") &&
	         branch_label_assign(&branch, "main")
	testing.expect(t, ready)
	if !ready do return

	descriptor := Observation_Descriptor {
		repository = repository,
		generation = Observation_Generation(1),
		branch = branch,
		operation = .Normal,
		path_count = 3,
		path_bytes = 96,
	}
	testing.expect(t, observation_descriptor_is_valid(descriptor, DEFAULT_PROCESS_LIMITS))

	descriptor.path_count = DEFAULT_PROCESS_LIMITS.status_paths + 1
	testing.expect(t, !observation_descriptor_is_valid(descriptor, DEFAULT_PROCESS_LIMITS))
}
