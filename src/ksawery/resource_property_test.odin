// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

@(private)
commit_revision_sequence_history_output :: proc() -> []u8 {
	return transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00current subject\x00current body\x00" +
		"\x1e" + HISTORY_TEST_SHA1 + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00parent subject\x00parent body\x00",
	))
}

@(private)
commit_revision_sequence_metadata :: proc() -> []u8 {
	return transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 +
		"\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00" +
		"\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00" +
		"\x00current subject\x00current body\n\x00N\x00\x00\n",
	))
}

@(private)
commit_revision_sequence_comparison :: proc() -> []u8 {
	return transmute([]u8)(string(
		":100644 100644 0000000000000000000000000000000000000000 " +
		"1111111111111111111111111111111111111111 M\x00src/example.odin\x00\x00" +
		"diff --git a/src/example.odin b/src/example.odin\n" +
		"index 0000000..1111111 100644\n--- a/src/example.odin\n+++ b/src/example.odin\n" +
		"@@ -0,0 +1 @@\n+package example\n",
	))
}

@(private)
commit_revision_sequence_range_summary :: proc() -> []u8 {
	return transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00current subject\x00\n" +
		"\x1e" + HISTORY_TEST_SHA1 + "\x00parent subject\x00\n",
	))
}

/* Verifies generated Ref, fetch, push, branch, and tag sequences stay bounded across refresh and cleanup. */
@(test)
refs_synchronization_sequences_preserve_bounds_and_cleanup :: proc(t: ^testing.T) {
	branch_outputs := [][]u8{
		transmute([]u8)(string(
			"refs/heads/generated\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n" +
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/heads/topic\x00" + BRANCH_TEST_TOPIC_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n" +
			"refs/heads/topic\x00" + BRANCH_TEST_TOPIC_OBJECT + "\x00commit\x00\x00\x00*\x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/heads/renamed\x00" + BRANCH_TEST_TOPIC_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + BRANCH_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n",
		)),
	}
	branch_heads := []string{
		BRANCH_TEST_MAIN_OBJECT + "\n",
		BRANCH_TEST_TOPIC_OBJECT + "\n",
		BRANCH_TEST_MAIN_OBJECT + "\n",
		BRANCH_TEST_MAIN_OBJECT + "\n",
	}
	tag_outputs := [][]u8{
		transmute([]u8)(string(
			"refs/heads/main\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n" +
			"refs/tags/v0.1.0\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n" +
			"refs/tags/generated\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00 \x00\n",
		)),
		transmute([]u8)(string(
			"refs/heads/main\x00" + TAG_TEST_MAIN_OBJECT + "\x00commit\x00\x00\x00*\x00\n",
		)),
	}
	for sequence in 0 ..< 48 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)

		ref_generation := Ref_Generation(sequence * 10 + 201)
		before, before_opened := push_contracts_test_observation(ref_generation, false, false, allocator)
		testing.expectf(t, before_opened, "generated Ref observation %d failed", sequence)
		if before_opened {
			ref_usage, ref_measured := ref_observation_usage(&before)
			testing.expect(t, ref_measured)
			if ref_measured {
				testing.expect(t, ref_usage.entries <= DEFAULT_REF_LIMITS.entries)
				testing.expect(t, ref_usage.remotes <= DEFAULT_REF_LIMITS.remotes)
				testing.expect(t, ref_usage.metadata_bytes <= DEFAULT_REF_LIMITS.metadata_bytes)
				testing.expect(t, ref_usage.temporary_bytes <= DEFAULT_REF_LIMITS.temporary_bytes)
			}
			ref_count, refs_counted := ref_observation_ref_count(&before)
			remote_count, remotes_counted := ref_observation_remote_count(&before)
			testing.expect(t, refs_counted && remotes_counted && ref_count > 0 && remote_count == 1)
			source, source_found := ref_observation_ref(&before, 0)
			remote, remote_found := ref_observation_remote(&before, 0)
			if source_found && remote_found {
				selection := Ref_Selection{
					generation = ref_generation,
					current = {kind = .Remote, remote = remote},
				}
				configuration, configured := fetch_contracts_test_configuration(remote, u8(sequence + 1))
				testing.expect(t, configured)
				if configured {
					fetch_request, fetch_prepared, fetch_failure := fetch_request_prepare(
						&before,
						selection,
						configuration,
						.Normal,
						Fetch_Operation_ID(sequence + 201),
					)
					testing.expectf(t, fetch_prepared, "generated fetch %d failed with %v", sequence, fetch_failure)
					if fetch_prepared {
						fetch_result, fetch_opened, fetch_result_failure := fetch_result_open(
							fetch_request,
							true,
							0,
							transmute([]u8)(string("generated fetch output")),
							transmute([]u8)(string("generated fetch diagnostic")),
							.None,
							allocator,
						)
						testing.expectf(t, fetch_opened, "generated fetch result %d failed with %v", sequence, fetch_result_failure)
						if fetch_opened {
							usage, measured := fetch_result_usage(&fetch_result)
							testing.expect(t, measured)
							if measured {
								testing.expect(t, usage.output_bytes <= fetch_request.limits.stdout_bytes)
								testing.expect(t, usage.diagnostic_bytes <= fetch_request.limits.diagnostic_bytes)
							}
							fetch_result_close(&fetch_result)
						}
					}
				}

				push_request, push_prepared := push_contracts_test_request(
					&before,
					Push_Operation_ID(sequence + 201),
				)
				testing.expect(t, push_prepared)
				if push_prepared {
					push_result, push_opened, push_failure := push_result_open(
						push_request,
						true,
						0,
						transmute([]u8)(string("generated push output")),
						transmute([]u8)(string("generated push diagnostic")),
						.None,
						allocator,
					)
					testing.expectf(t, push_opened, "generated push result %d failed with %v", sequence, push_failure)
					fresh, fresh_opened := push_contracts_test_observation(
						ref_generation + 1,
						true,
						false,
						allocator,
					)
					testing.expect(t, fresh_opened)
					if push_opened && fresh_opened {
						verified, verify_failure := push_result_verify(&push_result, &fresh)
						testing.expectf(t, verified, "generated push verification %d failed with %v", sequence, verify_failure)
						descriptor, described := push_result_descriptor(&push_result)
						testing.expect(t, described && descriptor.verified && descriptor.succeeded)
						usage, measured := push_result_usage(&push_result)
						testing.expect(t, measured)
						if measured {
							testing.expect(t, usage.output_bytes <= push_request.limits.stdout_bytes)
							testing.expect(t, usage.diagnostic_bytes <= push_request.limits.diagnostic_bytes)
						}
						old_selection := Ref_Selection{
							generation = ref_generation,
							current = {kind = .Ref, reference = source},
						}
						reconciled, reconciled_ok, reconcile_failure := ref_selection_reconcile(
							&before,
							&fresh,
							old_selection,
						)
						testing.expectf(t, reconciled_ok, "generated Ref reconciliation %d failed with %v", sequence, reconcile_failure)
						if reconciled_ok do testing.expect_value(t, reconciled.generation, ref_generation + 1)
					}
					if fresh.state != nil do ref_observation_close(&fresh)
					if push_result.state != nil do push_result_close(&push_result)
				}
			}
			ref_observation_close(&before)
		}

		branch_generation := Ref_Generation(sequence * 10 + 401)
		branch_status, branch_status_opened := branch_contracts_test_status(
			Observation_Generation(sequence * 10 + 401),
			nil,
			allocator,
		)
		branch_before, branch_before_opened := branch_contracts_test_before_refs(branch_generation, allocator)
		testing.expect(t, branch_status_opened && branch_before_opened)
		if branch_status_opened && branch_before_opened {
			topic, topic_found := branch_contracts_test_ref(&branch_before, "refs/heads/topic")
			created: Local_Branch_Name
			renamed: Local_Branch_Name
			names_ready := local_branch_name_assign(&created, "generated") &&
			               local_branch_name_assign(&renamed, "renamed")
			testing.expect(t, topic_found && names_ready)
			if topic_found && names_ready {
				intent := Branch_Intent{operation = .Create, name = created}
				operation_index := sequence % 4
				switch operation_index {
				case 1:
					intent = {operation = .Switch, selected = topic}
				case 2:
					intent = {operation = .Rename, selected = topic, name = renamed}
				case 3:
					intent = {operation = .Delete, selected = topic, require_merged_to_head = true}
				case 0:
				}
				request, prepared, failure := branch_contracts_test_request(
					&branch_status,
					&branch_before,
					intent,
					Branch_Operation_ID(sequence + 401),
				)
				testing.expectf(t, prepared, "generated branch %d failed with %v", sequence, failure)
				if prepared {
					result, opened, result_failure := branch_result_open(
						request,
						true,
						0,
						transmute([]u8)(string("generated branch output")),
						transmute([]u8)(string("generated branch diagnostic")),
						.None,
						allocator,
					)
					testing.expectf(t, opened, "generated branch result %d failed with %v", sequence, result_failure)
					fresh_status, fresh_status_opened := branch_contracts_test_status(
						Observation_Generation(sequence * 10 + 402),
						nil,
						allocator,
						"topic" if intent.operation == .Switch else "main",
					)
					fresh_refs, fresh_refs_opened := branch_contracts_test_refs(
						branch_generation + 1,
						branch_outputs[operation_index],
						branch_heads[operation_index],
						allocator,
					)
					if opened && fresh_status_opened && fresh_refs_opened {
						verified, verify_failure := branch_result_verify(&result, &fresh_status, &fresh_refs)
						testing.expectf(t, verified, "generated branch verification %d failed with %v", sequence, verify_failure)
						descriptor, described := branch_result_descriptor(&result)
						testing.expect(t, described && descriptor.verified && descriptor.succeeded)
						usage, measured := branch_result_usage(&result)
						testing.expect(t, measured)
						if measured {
							testing.expect(t, usage.output_bytes <= request.limits.stdout_bytes)
							testing.expect(t, usage.diagnostic_bytes <= request.limits.diagnostic_bytes)
						}
					}
					if fresh_status.state != nil do status_observation_close(&fresh_status)
					if fresh_refs.state != nil do ref_observation_close(&fresh_refs)
					if result.state != nil do branch_result_close(&result)
				}
			}
		}
		if branch_status.state != nil do status_observation_close(&branch_status)
		if branch_before.state != nil do ref_observation_close(&branch_before)

		tag_generation := Ref_Generation(sequence * 10 + 601)
		tag_status, tag_status_opened := tag_contracts_test_status(
			Observation_Generation(sequence * 10 + 601),
			allocator,
		)
		tag_before, tag_before_opened := tag_contracts_test_before_refs(tag_generation, allocator)
		testing.expect(t, tag_status_opened && tag_before_opened)
		if tag_status_opened && tag_before_opened {
			main, main_found := tag_contracts_test_ref(&tag_before, "refs/heads/main")
			existing, existing_found := tag_contracts_test_ref(&tag_before, "refs/tags/v0.1.0")
			created: Local_Tag_Name
			name_ready := local_tag_name_assign(&created, "generated")
			testing.expect(t, main_found && existing_found && name_ready)
			if main_found && existing_found && name_ready {
				operation_index := sequence % 2
				intent := Tag_Intent{operation = .Create, target = main, name = created}
				if operation_index == 1 do intent = {operation = .Delete, target = existing}
				request, prepared, failure := tag_contracts_test_request(
					&tag_status,
					&tag_before,
					intent,
					Tag_Operation_ID(sequence + 601),
				)
				testing.expectf(t, prepared, "generated tag %d failed with %v", sequence, failure)
				if prepared {
					result, opened, result_failure := tag_result_open(
						request,
						true,
						0,
						transmute([]u8)(string("generated tag output")),
						transmute([]u8)(string("generated tag diagnostic")),
						.None,
						allocator,
					)
					testing.expectf(t, opened, "generated tag result %d failed with %v", sequence, result_failure)
					fresh, fresh_opened := tag_contracts_test_refs(
						tag_generation + 1,
						tag_outputs[operation_index],
						allocator,
					)
					if opened && fresh_opened {
						verified, verify_failure := tag_result_verify(&result, &fresh)
						testing.expectf(t, verified, "generated tag verification %d failed with %v", sequence, verify_failure)
						descriptor, described := tag_result_descriptor(&result)
						testing.expect(t, described && descriptor.verified && descriptor.succeeded)
						usage, measured := tag_result_usage(&result)
						testing.expect(t, measured)
						if measured {
							testing.expect(t, usage.output_bytes <= request.limits.stdout_bytes)
							testing.expect(t, usage.diagnostic_bytes <= request.limits.diagnostic_bytes)
						}
					}
					if fresh.state != nil do ref_observation_close(&fresh)
					if result.state != nil do tag_result_close(&result)
				}
			}
		}
		if tag_status.state != nil do status_observation_close(&tag_status)
		if tag_before.state != nil do ref_observation_close(&tag_before)

		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies generated commit and revision owners remain bounded across refresh and cleanup. */
@(test)
commit_revision_workflow_sequences_preserve_bounds_and_cleanup :: proc(t: ^testing.T) {
	for sequence in 0 ..< 64 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		repository: Repository_Context
		repository_ready := repository_context_assign(&repository, "/work/generated-commit-revision")
		testing.expectf(t, repository_ready, "generated commit revision repository %d failed", sequence)
		if !repository_ready {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}

		generation := History_Generation(sequence + 101)
		history, history_opened, history_failure := history_observation_open(
			repository,
			generation,
			commit_revision_sequence_history_output(),
			{limits = DEFAULT_HISTORY_LIMITS},
			allocator,
		)
		testing.expectf(t, history_opened, "generated commit revision history %d failed with %v", sequence, history_failure)
		if !history_opened {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}

		history_usage, history_measured := history_observation_usage(&history)
		testing.expect(t, history_measured)
		if history_measured {
			testing.expect_value(t, history_usage.revisions, u32(2))
			testing.expect(t, history_usage.metadata_bytes <= DEFAULT_HISTORY_LIMITS.metadata_bytes)
			testing.expect(t, history_usage.temporary_bytes <= DEFAULT_HISTORY_LIMITS.temporary_bytes)
		}
		selection, selected := history_selection_begin(&history)
		testing.expect(t, selected && history_selection_is_current(&history, selection))
		current, current_found := history_observation_revision(&history, 0)
		parent, parent_found := history_observation_revision(&history, 1)
		testing.expect(t, current_found && parent_found)
		if !selected || !current_found || !parent_found {
			history_observation_close(&history)
			testing.expect_value(t, tracking.current_memory_allocated, i64(0))
			mem.tracking_allocator_destroy(&tracking)
			continue
		}

		presentation := Presentation_State {
			surface = .History,
			subject = .Revision,
			current = sequence % 4 == 0,
			marked = sequence % 4 == 1,
			head = sequence % 4 == 2,
			destructive = sequence % 4 == 3,
		}
		role, composed := presentation_role_compose(presentation)
		testing.expect(t, composed && presentation_role_is_valid(role))

		detail_request := Revision_Detail_Request {
			target = {generation = generation, revision = current.identity},
			parent = {kind = .Parent, parent = parent.identity},
			limits = DEFAULT_REVISION_DETAIL_LIMITS,
		}
		detail, detail_opened, detail_failure := revision_detail_open(
			repository,
			detail_request,
			commit_revision_sequence_metadata(),
			commit_revision_sequence_comparison(),
			false,
			allocator,
		)
		testing.expectf(t, detail_opened, "generated revision detail %d failed with %v", sequence, detail_failure)
		if detail_opened {
			detail_usage, detail_measured := revision_detail_usage(&detail)
			testing.expect(t, detail_measured)
			if detail_measured {
				inspection := Revision_Inspection_Request{kind = .Detail, detail = detail_request}
				testing.expect(t, revision_inspection_usage_is_valid(detail_usage, inspection))
			}
		}

		range_request := Revision_Range_Request {
			range = {
				base = {generation = generation, revision = parent.identity},
				target = {generation = generation, revision = current.identity},
			},
			limits = DEFAULT_REVISION_RANGE_LIMITS,
		}
		range, range_opened, range_failure := revision_range_observation_open(
			repository,
			range_request,
			commit_revision_sequence_range_summary(),
			commit_revision_sequence_comparison(),
			false,
			allocator,
		)
		testing.expectf(t, range_opened, "generated revision range %d failed with %v", sequence, range_failure)
		if range_opened {
			range_usage, range_measured := revision_range_observation_usage(&range)
			testing.expect(t, range_measured)
			if range_measured {
				inspection := Revision_Inspection_Request{kind = .Range, range = range_request}
				testing.expect(t, revision_inspection_usage_is_valid(range_usage, inspection))
			}
		}

		precondition, precondition_ready := commit_contracts_test_precondition(Commit_Generation(sequence + 101))
		testing.expect(t, precondition_ready)
		if precondition_ready do precondition.repository = repository
		message: Commit_Message
		message_ready := commit_message_assign(&message, "generated commit revision")
		testing.expect(t, message_ready)
		request: Commit_Request
		request_prepared := false
		request_failure := Failure_Code.None
		if precondition_ready && message_ready {
			switch sequence % 3 {
			case 0:
				request, request_prepared, request_failure = commit_request_prepare(
					precondition, message, Commit_Operation_ID(sequence + 101),
				)
			case 1:
				confirmation, confirmation_prepared, confirmation_failure := amend_confirmation_prepare(
					precondition, &history, message, Commit_Confirmation_ID(sequence + 101),
				)
				testing.expectf(t, confirmation_prepared, "generated amend confirmation %d failed with %v", sequence, confirmation_failure)
				if confirmation_prepared {
					confirmed, confirm_failure := amend_confirmation_confirm(&confirmation, Commit_Confirmation_ID(sequence + 101))
					testing.expectf(t, confirmed, "generated amend confirmation %d rejected with %v", sequence, confirm_failure)
					if confirmed {
						request, request_prepared, request_failure = amend_request_prepare(
							precondition, message, Commit_Operation_ID(sequence + 101), &confirmation,
						)
					}
				}
			case 2:
				request, request_prepared, request_failure = fixup_request_prepare(
					precondition,
					&history,
					{generation = generation, revision = parent.identity},
					Commit_Operation_ID(sequence + 101),
				)
			}
		}
		testing.expectf(t, request_prepared, "generated commit request %d failed with %v", sequence, request_failure)
		result: Commit_Result
		result_opened := false
		result_failure := Failure_Code.None
		if request_prepared {
			request_usage, request_measured := commit_request_usage(request)
			testing.expect(t, request_measured && request_usage.message_bytes > 0)
			if request.mode != .Normal do testing.expect(t, request_usage.target_subject_bytes > 0)
			result, result_opened, result_failure = commit_result_open(
				request,
				parent.identity,
				0,
				transmute([]u8)(string("generated output")),
				transmute([]u8)(string("generated diagnostic")),
				.None,
				allocator,
			)
			testing.expectf(t, result_opened, "generated commit result %d failed with %v", sequence, result_failure)
			if result_opened {
				result_usage, result_measured := commit_result_usage(&result)
				testing.expect(t, result_measured)
				if result_measured {
					testing.expect(t, result_usage.output_bytes <= request.limits.stdout_bytes)
					testing.expect(t, result_usage.diagnostic_bytes <= request.limits.diagnostic_bytes)
				}
			}
		}

		refreshed, refreshed_opened, refresh_failure := history_observation_open(
			repository,
			generation + 1,
			commit_revision_sequence_history_output(),
			{limits = DEFAULT_HISTORY_LIMITS},
			allocator,
		)
		testing.expectf(t, refreshed_opened, "generated history refresh %d failed with %v", sequence, refresh_failure)
		if refreshed_opened {
			testing.expect(t, !history_selection_is_current(&refreshed, selection))
			if detail_opened do testing.expect(t, !revision_detail_is_current(&detail, &refreshed))
			if range_opened do testing.expect(t, !revision_range_observation_is_current(&range, &refreshed))
			refreshed_selection, refreshed_selected := history_selection_begin(&refreshed)
			testing.expect(t, refreshed_selected && history_selection_is_current(&refreshed, refreshed_selection))
			history_observation_close(&refreshed)
		}
		if result_opened do commit_result_close(&result)
		if range_opened do revision_range_observation_close(&range)
		if detail_opened do revision_detail_close(&detail)
		history_observation_close(&history)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies generated amend and fixup contracts remain bounded and release all retained outcomes. */
@(test)
commit_revision_sequences_preserve_bounds_and_cleanup :: proc(t: ^testing.T) {
	history_output := transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00current subject\x00current body\x00" +
		"\x1e" + HISTORY_TEST_SHA1 + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00parent subject\x00parent body\x00",
	))
	for sequence in 0 ..< 96 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		precondition, ready := commit_contracts_test_precondition(Commit_Generation(sequence + 1))
		testing.expectf(t, ready, "generated commit precondition %d failed", sequence)
		if !ready {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		generation := History_Generation(sequence + 1)
		history, opened, history_failure := history_observation_open(
			precondition.repository, generation, history_output, {limits = DEFAULT_HISTORY_LIMITS}, allocator,
		)
		testing.expectf(t, opened, "generated commit history %d failed with %v", sequence, history_failure)
		if !opened {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		message: Commit_Message
		testing.expect(t, commit_message_assign(&message, "generated replacement"))
		request: Commit_Request
		prepared := false
		prepare_failure := Failure_Code.None
		if sequence % 3 == 0 {
			confirmation, confirmation_prepared, confirmation_failure := amend_confirmation_prepare(
				precondition, &history, message, Commit_Confirmation_ID(sequence + 1),
			)
			testing.expectf(t, confirmation_prepared, "generated amend confirmation %d failed with %v", sequence, confirmation_failure)
			if confirmation_prepared {
				confirmed, confirm_failure := amend_confirmation_confirm(&confirmation, Commit_Confirmation_ID(sequence + 1))
				testing.expectf(t, confirmed, "generated amend confirmation acceptance %d failed with %v", sequence, confirm_failure)
				if confirmed {
					request, prepared, prepare_failure = amend_request_prepare(
						precondition, message, Commit_Operation_ID(sequence + 1), &confirmation,
					)
				}
			}
		} else {
			target := History_Target{generation = generation, revision = precondition.head.revision}
			if sequence % 3 == 2 {
				parent, parent_assigned := history_test_identity(HISTORY_TEST_SHA1)
				testing.expect(t, parent_assigned)
				if parent_assigned do target.revision = parent
			}
			request, prepared, prepare_failure = fixup_request_prepare(
				precondition, &history, target, Commit_Operation_ID(sequence + 1),
			)
		}
		testing.expectf(t, prepared, "generated commit request %d failed with %v", sequence, prepare_failure)
		if prepared {
			resulting, result_assigned := history_test_identity(HISTORY_TEST_SHA1)
			testing.expect(t, result_assigned)
			if result_assigned {
				result, result_opened, result_failure := commit_result_open(
					request,
					resulting,
					0,
					transmute([]u8)(string("generated output")),
					transmute([]u8)(string("generated diagnostic")),
					.None,
					allocator,
				)
				testing.expectf(t, result_opened, "generated commit result %d failed with %v", sequence, result_failure)
				if result_opened {
					descriptor, described := commit_result_descriptor(&result)
					testing.expect(t, described && descriptor.succeeded)
					if described {
						testing.expect_value(t, descriptor.lineage.resulting, resulting)
						if request.mode == .Amend {
							testing.expect_value(t, descriptor.lineage.replaced, precondition.head.revision)
						} else {
							testing.expect_value(t, descriptor.lineage.fixup_target, request.arguments.target.observation.revision)
						}
					}
					usage, measured := commit_result_usage(&result)
					testing.expect(t, measured)
					if measured {
						testing.expect(t, usage.message_bytes > 0)
						testing.expect(t, usage.output_bytes <= request.limits.stdout_bytes)
						testing.expect(t, usage.diagnostic_bytes <= request.limits.diagnostic_bytes)
					}
					commit_result_close(&result)
				}
			}
		}
		history_observation_close(&history)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies generated repository-state sequences remain bounded and release every owner. */
@(test)
repository_state_sequences_preserve_bounds_and_cleanup :: proc(t: ^testing.T) {
	outputs := [4]string {
		"# branch.head main\x00? new.txt\x00",
		"# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb edited.txt\x00",
		"# branch.head main\x001 M. N... 100644 100644 100644 aaa bbb staged.txt\x00",
		"# branch.head main\x00u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt\x00",
	}
	repository: Repository_Context
	testing.expect(t, repository_context_assign(&repository, "/work/generated"))
	for sequence in 0 ..< 128 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		generation := Observation_Generation(sequence * 2 + 1)
		output := outputs[sequence % len(outputs)]
		observation, opened, failure := status_observation_open(
			repository,
			generation,
			transmute([]u8)output,
			transmute([]u8)(string("bounded diagnostic")),
			DEFAULT_PROCESS_LIMITS,
			allocator,
		)
		testing.expectf(t, opened, "generated observation %d failed with %v", sequence, failure)
		if !opened {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		selection, selected := status_selection_begin(&observation)
		if selected do selection, selected, _ = status_selection_move(&observation, selection, .Next)
		testing.expect(t, selected && selection.current.kind == .Path)
		target, targeted, _ := status_selection_path_target(&observation, selection)
		detail: Path_Detail
		if targeted {
			detail, opened, failure = path_detail_open(
				&observation,
				target,
				transmute([]u8)(string("generated detail")),
				false,
				DEFAULT_PROCESS_LIMITS,
				allocator,
			)
			testing.expectf(t, opened, "generated detail %d failed with %v", sequence, failure)
		}
		result: Index_Action_Result
		action := Index_Action.Stage
		if sequence % len(outputs) == 2 do action = .Unstage
		if sequence % len(outputs) != 3 && targeted {
			request, prepared, prepare_failure := index_action_prepare(
				&observation,
				selection,
				action,
				Index_Operation_ID(sequence + 1),
			)
			testing.expectf(t, prepared, "generated action %d failed with %v", sequence, prepare_failure)
			if prepared {
				result, opened, failure = index_action_result_open(
					request,
					0,
					transmute([]u8)(string("ok")),
					nil,
					.None,
					allocator,
				)
				testing.expectf(t, opened, "generated result %d failed with %v", sequence, failure)
				if opened do testing.expect(t, index_action_result_is_current(&result, &observation))
			}
		}
		refreshed, refreshed_ok, refresh_failure := status_observation_open(
			repository,
			generation + 1,
			transmute([]u8)output,
			nil,
			DEFAULT_PROCESS_LIMITS,
			allocator,
		)
		testing.expectf(t, refreshed_ok, "generated refresh %d failed with %v", sequence, refresh_failure)
		if refreshed_ok {
			reconciled, reconciled_ok, reconcile_failure := status_selection_reconcile(
				&observation,
				&refreshed,
				selection,
			)
			testing.expectf(t, reconciled_ok, "generated reconciliation %d failed with %v", sequence, reconcile_failure)
			if reconciled_ok do testing.expect_value(t, reconciled.generation, generation + 1)
			if detail.state != nil do testing.expect(t, !path_detail_is_current(&detail, &refreshed))
			if result.state != nil do testing.expect(t, !index_action_result_is_current(&result, &refreshed))
			status_observation_close(&refreshed)
		}
		if result.state != nil do index_action_result_close(&result)
		if detail.state != nil do path_detail_close(&detail)
		status_observation_close(&observation)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

/* Verifies generated change-management owners stay bounded across refresh and cleanup. */
@(test)
change_management_sequences_preserve_bounds_and_cleanup :: proc(t: ^testing.T) {
	for sequence in 0 ..< 64 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		group := Change_Group.Unstaged
		action := Index_Action.Stage
		output := "# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb src/main.odin\x00"
		if sequence % 2 == 1 {
			group = .Staged
			action = .Unstage
			output = "# branch.head main\x001 M. N... 100644 100644 100644 aaa bbb src/main.odin\x00"
		}
		observation, detail, document, selection, ready := partial_index_action_test_state(group, allocator)
		testing.expectf(t, ready, "generated change state %d failed", sequence)
		if !ready {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}

		diff_usage, diff_measured := diff_document_usage(&document)
		testing.expect(t, diff_measured)
		if diff_measured {
			testing.expect_value(t, diff_usage.units, u32(2))
			testing.expect(t, diff_usage.patch_bytes <= DEFAULT_DIFF_LIMITS.patch_bytes)
		}
		partial, partial_prepared, partial_failure := partial_index_action_prepare(
			&observation,
			&document,
			selection,
			action,
			Index_Operation_ID(sequence + 1),
			DEFAULT_PROCESS_LIMITS,
			allocator,
		)
		testing.expectf(t, partial_prepared, "generated partial action %d failed with %v", sequence, partial_failure)
		if partial_prepared {
			partial_usage, measured := partial_index_action_request_usage(&partial)
			testing.expect(t, measured && partial_usage.input_bytes > 0)
			testing.expect(t, partial_usage.input_bytes <= DEFAULT_PROCESS_LIMITS.diff_bytes)
			partial_index_action_request_close(&partial)
		}

		grouped, grouped_opened, grouped_failure := grouped_selection_open(
			&observation,
			DEFAULT_GROUPED_SELECTION_LIMITS,
			allocator,
		)
		testing.expectf(t, grouped_opened, "generated target set %d failed with %v", sequence, grouped_failure)
		if grouped_opened {
			first_marked, first_failure := grouped_selection_mark(
				&observation,
				&document,
				selection,
				&grouped,
			)
			selection, _, _ = status_selection_move(&observation, selection, .Next, &document)
			second_marked, second_failure := grouped_selection_mark(
				&observation,
				&document,
				selection,
				&grouped,
			)
			testing.expectf(t, first_marked, "generated first mark %d failed with %v", sequence, first_failure)
			testing.expectf(t, second_marked, "generated second mark %d failed with %v", sequence, second_failure)
			grouped_usage, measured := grouped_selection_usage(&grouped)
			testing.expect(t, measured && grouped_usage.targets == 2)
			request, prepared, prepare_failure := grouped_index_action_prepare(
				&observation,
				&document,
				&grouped,
				Index_Operation_ID(sequence + 101),
				DEFAULT_PROCESS_LIMITS,
				allocator,
			)
			testing.expectf(t, prepared, "generated grouped action %d failed with %v", sequence, prepare_failure)
			if prepared {
				request_usage, request_measured := grouped_index_action_request_usage(&request)
				testing.expect(t, request_measured && request_usage.input_bytes > 0)
				testing.expect(t, request_usage.input_bytes <= DEFAULT_PROCESS_LIMITS.diff_bytes)
				grouped_index_action_request_close(&request)
			}
		}

		path_selection := selection
		path_selection.current.kind = .Path
		path_selection.current.source = {}
		path_selection.current.unit = {}
		if group == .Unstaged {
			discard, prepared, prepare_failure := discard_action_prepare(
				&observation,
				path_selection,
				Index_Operation_ID(sequence + 201),
				Discard_Confirmation_ID(sequence + 301),
				false,
			)
			testing.expectf(t, prepared, "generated discard %d failed with %v", sequence, prepare_failure)
			if prepared {
				confirmed, confirmation_failure := discard_action_confirm(
					&discard,
					Discard_Confirmation_ID(sequence + 301),
				)
				testing.expectf(t, confirmed, "generated confirmation %d failed with %v", sequence, confirmation_failure)
				result, opened, result_failure := discard_action_result_open(
					discard,
					0,
					transmute([]u8)(string("discarded")),
					nil,
					.None,
					allocator,
				)
				testing.expectf(t, opened, "generated discard result %d failed with %v", sequence, result_failure)
				if opened do discard_action_result_close(&result)
			}
		}

		repository: Repository_Context
		testing.expect(t, repository_context_assign(&repository, "/work/example"))
		refreshed, refreshed_ok, refresh_failure := status_observation_open(
			repository,
			Observation_Generation(42),
			transmute([]u8)output,
			nil,
			DEFAULT_PROCESS_LIMITS,
			allocator,
		)
		testing.expectf(t, refreshed_ok, "generated change refresh %d failed with %v", sequence, refresh_failure)
		if refreshed_ok {
			reconciled, reconciled_ok, reconcile_failure := status_selection_reconcile(
				&observation,
				&refreshed,
				selection,
				&document,
			)
			testing.expectf(t, reconciled_ok, "generated change reconciliation %d failed with %v", sequence, reconcile_failure)
			if reconciled_ok do testing.expect_value(t, reconciled.current.kind, Status_Item_Kind.Path)
			if grouped_opened {
				removed, group_reconciled, group_failure := grouped_selection_reconcile(&grouped, &refreshed)
				testing.expectf(t, group_reconciled, "generated group refresh %d failed with %v", sequence, group_failure)
				testing.expect_value(t, removed, u32(2))
			}
			status_observation_close(&refreshed)
		}
		if grouped_opened do grouped_selection_close(&grouped)
		partial_index_action_test_close(&observation, &detail, &document)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}
