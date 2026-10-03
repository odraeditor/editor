// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:testing"

@(private)
revision_contracts_test_observation :: proc(
	generation: History_Generation = History_Generation(31),
) -> (History_Observation, bool) {
	repository: Repository_Context
	if !repository_context_assign(&repository, "/work/revision-contracts") do return {}, false
	output := transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA1 + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00root\x00root body\x00" +
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00child\x00child body\x00",
	))
	observation, opened, _ := history_observation_open(
		repository,
		generation,
		output,
		{limits = DEFAULT_HISTORY_LIMITS},
		context.allocator,
	)
	return observation, opened
}

@(private)
revision_contracts_test_detail_request :: proc(
	generation: History_Generation = History_Generation(31),
) -> (Revision_Detail_Request, bool) {
	revision, assigned := history_test_identity(HISTORY_TEST_SHA256)
	parent, parent_assigned := history_test_identity(HISTORY_TEST_SHA1)
	if !assigned || !parent_assigned do return {}, false
	return Revision_Detail_Request {
		target = {generation = generation, revision = revision},
		parent = {kind = .Parent, parent = parent},
		limits = DEFAULT_REVISION_DETAIL_LIMITS,
	}, true
}

@(private)
revision_contracts_test_range_request :: proc(
	generation: History_Generation = History_Generation(31),
) -> (Revision_Range_Request, bool) {
	base, base_assigned := history_test_identity(HISTORY_TEST_SHA1)
	target, target_assigned := history_test_identity(HISTORY_TEST_SHA256)
	if !base_assigned || !target_assigned do return {}, false
	return Revision_Range_Request {
		range = {
			base = {generation = generation, revision = base},
			target = {generation = generation, revision = target},
		},
		limits = DEFAULT_REVISION_RANGE_LIMITS,
	}, true
}

/* Verifies detail limits bound every retained metadata, path, diff, and temporary allocation class. */
@(test)
revision_detail_limits_bind_complete_retained_payload :: proc(t: ^testing.T) {
	testing.expect(t, revision_detail_limits_are_valid(DEFAULT_REVISION_DETAIL_LIMITS))
	too_many_parents := DEFAULT_REVISION_DETAIL_LIMITS
	too_many_parents.parents = MAX_REVISION_DETAIL_PARENTS + 1
	testing.expect(t, !revision_detail_limits_are_valid(too_many_parents))

	too_large_signature := DEFAULT_REVISION_DETAIL_LIMITS
	too_large_signature.signature_bytes = too_large_signature.metadata_bytes
	testing.expect(t, !revision_detail_limits_are_valid(too_large_signature))

	too_small_temporary := DEFAULT_REVISION_DETAIL_LIMITS
	too_small_temporary.temporary_bytes = too_small_temporary.metadata_bytes +
	                                    too_small_temporary.changed_path_bytes +
	                                    too_small_temporary.diff_bytes - 1
	testing.expect(t, !revision_detail_limits_are_valid(too_small_temporary))
}

/* Verifies detail requests require one exact parent choice and reject stale History generations. */
@(test)
revision_detail_requests_bind_parent_choice_to_current_history :: proc(t: ^testing.T) {
	observation, opened := revision_contracts_test_observation()
	testing.expect(t, opened)
	if !opened do return
	defer history_observation_close(&observation)

	request, prepared := revision_contracts_test_detail_request()
	testing.expect(t, prepared && revision_detail_request_is_valid(request))
	if !prepared do return
	entry, current, failure := revision_detail_request_revalidate(&observation, request)
	testing.expectf(t, current, "detail request rejected with %v", failure)
	if current do testing.expect_value(t, entry.parent_count, u8(1))

	request.parent = {kind = .Empty_Tree}
	_, current, failure = revision_detail_request_revalidate(&observation, request)
	testing.expect(t, !current && failure == .Revision_Unavailable)

	request, prepared = revision_contracts_test_detail_request(History_Generation(32))
	testing.expect(t, prepared)
	_, current, failure = revision_detail_request_revalidate(&observation, request)
	testing.expect(t, !current && failure == .Stale_Observation)
}

/* Verifies range endpoints stay distinct, ordered, and bound to one current History generation. */
@(test)
revision_ranges_reject_duplicate_or_stale_endpoints :: proc(t: ^testing.T) {
	observation, opened := revision_contracts_test_observation()
	testing.expect(t, opened)
	if !opened do return
	defer history_observation_close(&observation)

	request, prepared := revision_contracts_test_range_request()
	testing.expect(t, prepared && revision_range_request_is_valid(request))
	if !prepared do return
	current, failure := revision_range_request_revalidate(&observation, request)
	testing.expectf(t, current, "range request rejected with %v", failure)

	request.range.target = request.range.base
	testing.expect(t, !revision_range_request_is_valid(request))

	request, prepared = revision_contracts_test_range_request(History_Generation(32))
	testing.expect(t, prepared)
	current, failure = revision_range_request_revalidate(&observation, request)
	testing.expect(t, !current && failure == .Stale_Observation)
}

/* Verifies detail descriptors retain an explicit diff base and bounded immutable text references. */
@(test)
revision_detail_descriptors_require_matching_parent_and_bounded_text :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/revision-contracts")
	testing.expect(t, ready)
	request, prepared := revision_contracts_test_detail_request()
	testing.expect(t, prepared)
	if !ready || !prepared do return
	parents: [MAX_REVISION_DETAIL_PARENTS]Revision_Identity
	parents[0] = request.parent.parent
	descriptor := Revision_Detail_Descriptor {
		repository = repository,
		target = request.target,
		parent = request.parent,
		parents = parents,
		parent_count = 1,
		author_name = {offset = 0, length = 3},
		author_email = {offset = 3, length = 19},
		authored_at = {offset = 22, length = 25},
		committer_name = {offset = 47, length = 3},
		committer_email = {offset = 50, length = 19},
		committed_at = {offset = 69, length = 25},
		subject = {offset = 94, length = 5},
		message = {offset = 99, length = 10},
		signature_status = .Unavailable,
		metadata_bytes = 109,
		message_bytes = 10,
		changed_paths = 1,
		changed_path_bytes = 24,
		diff_bytes = 32,
		temporary_bytes = 165,
	}
	testing.expect(t, revision_detail_descriptor_is_valid(descriptor))

	descriptor.parent = {kind = .Empty_Tree}
	testing.expect(t, !revision_detail_descriptor_is_valid(descriptor))
	descriptor.parent = request.parent
	descriptor.message_bytes = 9
	testing.expect(t, !revision_detail_descriptor_is_valid(descriptor))
}

/* Verifies changed-path summaries preserve source-path requirements for copies and renames. */
@(test)
revision_changed_paths_require_explicit_source_only_when_needed :: proc(t: ^testing.T) {
	renamed := Revision_Changed_Path {
		kind = .Renamed,
		path = {offset = 0, length = 8},
		original_path = {offset = 8, length = 8},
	}
	testing.expect(t, revision_changed_path_is_valid(renamed, 16))
	renamed.original_path = {}
	testing.expect(t, !revision_changed_path_is_valid(renamed, 16))

	modified := Revision_Changed_Path {kind = .Modified, path = {offset = 0, length = 8}}
	testing.expect(t, revision_changed_path_is_valid(modified, 8))
	modified.original_path = {offset = 0, length = 1}
	testing.expect(t, !revision_changed_path_is_valid(modified, 8))
}

/* Verifies inspection results preserve their closed request family, bounded usage, and truncation state. */
@(test)
revision_inspection_results_retain_closed_bounded_outcomes :: proc(t: ^testing.T) {
	detail, prepared := revision_contracts_test_detail_request()
	testing.expect(t, prepared)
	if !prepared do return
	request := Revision_Inspection_Request {kind = .Detail, detail = detail}
	usage := Revision_Inspection_Usage {
		parents = 1,
		metadata_bytes = 128,
		message_bytes = 16,
		changed_paths = 1,
		changed_path_bytes = 24,
		diff_bytes = 32,
		temporary_bytes = 184,
		allocation_bytes = 184,
	}
	result := Revision_Inspection_Result_Descriptor {
		request = request,
		state = .Available,
		usage = usage,
	}
	testing.expect(t, revision_inspection_result_descriptor_is_valid(result))

	result.state = .Truncated
	result.failure = .Output_Limit
	testing.expect(t, revision_inspection_result_descriptor_is_valid(result))
	result.failure = .None
	testing.expect(t, !revision_inspection_result_descriptor_is_valid(result))
}
