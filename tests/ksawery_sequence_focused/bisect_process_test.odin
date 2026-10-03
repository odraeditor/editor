// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#+build linux
package ksawery_sequence_focused

import ksawery "../../src/ksawery"
import "core:fmt"
import "core:os"
import "core:testing"

/* Verifies checked start and reset execute a manual bisect and restore the exact symbolic origin. */
@(test)
bisect_process_starts_and_resets_exact_manual_session :: proc(t: ^testing.T) {
	directory, repository, bad, good, ready := bisect_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	testing.expect(t, ready)
	if !ready do return
	boundaries, boundaries_opened, boundaries_failure := ksawery.bisect_boundary_set_open(bad, []ksawery.Revision_Identity{good})
	testing.expectf(t, boundaries_opened, "bisect boundaries failed with %v", boundaries_failure)
	if !boundaries_opened do return
	defer ksawery.bisect_boundary_set_close(&boundaries)
	sequence, sequence_opened, sequence_failure := sequence_process_observe(repository, 821)
	testing.expectf(t, sequence_opened, "pre-bisect sequence failed with %v", sequence_failure)
	if !sequence_opened do return
	start, start_prepared := bisect_process_precondition(
		t, repository, &sequence, &boundaries, .Start, {}, {}, 822,
	)
	testing.expect(t, start_prepared)
	if !start_prepared {
		ksawery.sequence_observation_close(&sequence)
		return
	}
	request, requested := bisect_process_request(t, start, 823)
	if !requested {
		ksawery.sequence_observation_close(&sequence)
		return
	}
	process, started, start_failure := ksawery.repository_process_start_bisect(
		&sequence, start, &boundaries, request, 1,
	)
	ksawery.sequence_observation_close(&sequence)
	testing.expectf(t, started, "manual bisect failed to start with %v", start_failure)
	if !started do return
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Completed)
	result, retained, result_failure := ksawery.repository_process_take_bisect(&process)
	testing.expectf(t, retained, "manual bisect result failed with %v", result_failure)
	ksawery.repository_process_close(&process)
	if !retained do return
	refs, refs_opened := rebase_process_observe_refs(repository, 825)
	active, active_opened, active_failure := sequence_process_observe(repository, 826)
	testing.expectf(
		t,
		refs_opened && active_opened,
		"active bisect observations failed: refs=%v sequence=%v failure=%v",
		refs_opened,
		active_opened,
		active_failure,
	)
	if !refs_opened || !active_opened {
		if refs_opened do ksawery.ref_observation_close(&refs)
		if active_opened do ksawery.sequence_observation_close(&active)
		ksawery.bisect_result_close(&result)
		return
	}
	verified, verify_failure := ksawery.bisect_result_verify(&result, &refs, &active)
	testing.expectf(t, verified, "manual bisect result failed verification with %v", verify_failure)
	descriptor, described := ksawery.bisect_result_descriptor(&result)
	testing.expect(t, described && descriptor.outcome == .Started)
	ksawery.bisect_result_close(&result)
	ksawery.ref_observation_close(&refs)
	if !described {
		ksawery.sequence_observation_close(&active)
		return
	}
	reset, reset_prepared := bisect_process_precondition(
		t, repository, &active, &boundaries, .Reset, start, descriptor.progress, 827,
	)
	testing.expect(t, reset_prepared)
	if !reset_prepared {
		ksawery.sequence_observation_close(&active)
		return
	}
	reset_request, reset_requested := bisect_process_request(t, reset, 828)
	if !reset_requested {
		ksawery.sequence_observation_close(&active)
		return
	}
	reset_process, reset_started, reset_failure := ksawery.repository_process_start_bisect(
		&active, reset, &boundaries, reset_request, 1,
	)
	ksawery.sequence_observation_close(&active)
	testing.expectf(t, reset_started, "manual bisect reset failed to start with %v", reset_failure)
	if !reset_started do return
	reset_poll := sequence_process_wait(&reset_process, 2)
	testing.expect_value(t, reset_poll.state, ksawery.Repository_Process_State.Completed)
	reset_result, reset_retained, reset_result_failure := ksawery.repository_process_take_bisect(&reset_process)
	testing.expectf(t, reset_retained, "manual bisect reset result failed with %v", reset_result_failure)
	ksawery.repository_process_close(&reset_process)
	if !reset_retained do return
	refs, refs_opened = rebase_process_observe_refs(repository, 830)
	inactive, inactive_opened, _ := sequence_process_observe(repository, 831)
	if refs_opened && inactive_opened {
		reset_verified, reset_verify_failure := ksawery.bisect_result_verify(&reset_result, &refs, &inactive)
		testing.expectf(t, reset_verified, "manual bisect reset failed verification with %v", reset_verify_failure)
		reset_descriptor, reset_described := ksawery.bisect_result_descriptor(&reset_result)
		testing.expectf(
			t,
			reset_described && reset_descriptor.outcome == .Reset,
			"reset descriptor: described=%v outcome=%v failure=%v",
			reset_described,
			reset_descriptor.outcome,
			reset_descriptor.failure,
		)
	}
	if refs_opened do ksawery.ref_observation_close(&refs)
	if inactive_opened do ksawery.sequence_observation_close(&inactive)
	ksawery.bisect_result_close(&reset_result)
}

/* Verifies a confirmed candidate action rejects HEAD drift before Git mutation. */
@(test)
bisect_process_rejects_stale_candidate_before_classification :: proc(t: ^testing.T) {
	directory, repository, bad, good, ready := bisect_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	boundaries, opened, _ := ksawery.bisect_boundary_set_open(bad, []ksawery.Revision_Identity{good})
	if !opened do return
	defer ksawery.bisect_boundary_set_close(&boundaries)
	sequence, observed, _ := sequence_process_observe(repository, 841)
	if !observed do return
	start, prepared := bisect_process_precondition(t, repository, &sequence, &boundaries, .Start, {}, {}, 842)
	if !prepared {
		ksawery.sequence_observation_close(&sequence)
		return
	}
	request, requested := bisect_process_request(t, start, 843)
	if !requested {
		ksawery.sequence_observation_close(&sequence)
		return
	}
	process, started, _ := ksawery.repository_process_start_bisect(&sequence, start, &boundaries, request, 1)
	ksawery.sequence_observation_close(&sequence)
	if !started do return
	_ = sequence_process_wait(&process, 2)
	result, retained, _ := ksawery.repository_process_take_bisect(&process)
	ksawery.repository_process_close(&process)
	if !retained do return
	refs, refs_opened := rebase_process_observe_refs(repository, 845)
	active, active_opened, _ := sequence_process_observe(repository, 846)
	if !refs_opened || !active_opened {
		if refs_opened do ksawery.ref_observation_close(&refs)
		if active_opened do ksawery.sequence_observation_close(&active)
		ksawery.bisect_result_close(&result)
		return
	}
	_, _ = ksawery.bisect_result_verify(&result, &refs, &active)
	descriptor, described := ksawery.bisect_result_descriptor(&result)
	ksawery.bisect_result_close(&result)
	ksawery.ref_observation_close(&refs)
	if !described {
		ksawery.sequence_observation_close(&active)
		return
	}
	good_precondition, good_prepared := bisect_process_precondition(
		t, repository, &active, &boundaries, .Good, start, descriptor.progress, 847,
	)
	ksawery.sequence_observation_close(&active)
	if !good_prepared do return
	good_request, good_requested := bisect_process_request(t, good_precondition, 848)
	if !good_requested do return
	bad_copy := bad
	testing.expect(t, sequence_process_run(
		directory,
		"git",
		"checkout",
		"--detach",
		"-q",
		ksawery.revision_identity_string(&bad_copy),
	))
	active, active_opened, _ = sequence_process_observe(repository, 849)
	if !active_opened do return
	stale_process, stale_started, stale_failure := ksawery.repository_process_start_bisect(
		&active, good_precondition, &boundaries, good_request, 1,
	)
	ksawery.sequence_observation_close(&active)
	testing.expect(t, !stale_started && stale_failure == .Stale_Observation)
	if stale_started do ksawery.repository_process_close(&stale_process)
	_ = sequence_process_run(directory, "git", "bisect", "reset")
}

/* Verifies good and skip advance exact candidates with distinct retained classifications. */
@(test)
bisect_process_advances_good_and_skipped_candidates :: proc(t: ^testing.T) {
	actions := [?]ksawery.Bisect_Action{.Good, .Skip}
	for action, index in actions {
		directory, repository, bad, good, ready := bisect_process_repository(t)
		if len(directory) == 0 do return
		if !ready {
			os.remove_all(directory)
			delete(directory)
			return
		}
		boundaries, lineage, progress, sequence, begun := bisect_process_begin_session(
			t, repository, bad, good, u64(860 + index * 20),
		)
		testing.expect(t, begun)
		if begun {
			advanced, outcome, applied := bisect_process_apply_action(
				t, repository, &sequence, &boundaries, lineage, progress, action,
				u64(870 + index * 20),
			)
			testing.expect(t, applied)
			if applied {
				testing.expect_value(t, outcome, ksawery.Bisect_Outcome.Advanced)
				testing.expect_value(t, advanced.classifications, u32(1))
				testing.expect_value(t, advanced.skipped, action == .Skip ? u32(1) : u32(0))
			}
			ksawery.sequence_observation_close(&sequence)
			ksawery.bisect_boundary_set_close(&boundaries)
			_ = sequence_process_run(directory, "git", "bisect", "reset")
		}
		os.remove_all(directory)
		delete(directory)
	}
}

/* Verifies repeated bad classifications find one exact answer and reset remains available. */
@(test)
bisect_process_finds_first_bad_and_resets_completed_session :: proc(t: ^testing.T) {
	directory, repository, bad, good, ready := bisect_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	boundaries, lineage, progress, sequence, begun := bisect_process_begin_session(
		t, repository, bad, good, 920,
	)
	testing.expect(t, begun)
	if !begun do return
	defer ksawery.bisect_boundary_set_close(&boundaries)
	defer ksawery.sequence_observation_close(&sequence)
	found := false
	for step in 0 ..< 8 {
		outcome: ksawery.Bisect_Outcome
		applied: bool
		progress, outcome, applied = bisect_process_apply_action(
			t, repository, &sequence, &boundaries, lineage, progress, .Bad, u64(930 + step * 10),
		)
		testing.expect(t, applied)
		if !applied do return
		testing.expect(t, outcome == .Advanced || outcome == .Found_First_Bad)
		if outcome == .Found_First_Bad {
			found = true
			break
		}
	}
	testing.expect(t, found)
	testing.expect(t, progress.complete && progress.remaining == 0)
	testing.expect(t, ksawery.revision_identity_is_valid(progress.first_bad))
	if !found do return
	reset_progress, reset_outcome, reset := bisect_process_apply_action(
		t, repository, &sequence, &boundaries, lineage, progress, .Reset, 1_020,
	)
	testing.expect(t, reset)
	testing.expect_value(t, reset_outcome, ksawery.Bisect_Outcome.Reset)
	testing.expect_value(t, reset_progress, ksawery.Bisect_Progress{})
}

/* Verifies reset restores the exact detached revision captured before bisect start. */
@(test)
bisect_process_reset_restores_detached_origin :: proc(t: ^testing.T) {
	directory, repository, bad, good, ready := bisect_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	bad_copy := bad
	testing.expect(t, sequence_process_run(
		directory, "git", "checkout", "--detach", "-q", ksawery.revision_identity_string(&bad_copy),
	))
	boundaries, lineage, progress, sequence, begun := bisect_process_begin_session(
		t, repository, bad, good, 1_030,
	)
	testing.expect(t, begun)
	if !begun do return
	defer ksawery.bisect_boundary_set_close(&boundaries)
	defer ksawery.sequence_observation_close(&sequence)
	_, outcome, reset := bisect_process_apply_action(
		t, repository, &sequence, &boundaries, lineage, progress, .Reset, 1_040,
	)
	testing.expect(t, reset)
	testing.expect_value(t, outcome, ksawery.Bisect_Outcome.Reset)
	refs, observed := rebase_process_observe_refs(repository, 1_044)
	testing.expect(t, observed)
	if observed {
		descriptor, described := ksawery.ref_observation_descriptor(&refs)
		testing.expect(t, described)
		testing.expect_value(t, descriptor.head.state, ksawery.Head_State.Detached)
		testing.expect_value(t, descriptor.head.object, bad)
		ksawery.ref_observation_close(&refs)
	}
}

/* Verifies a dirty temporary repository is rejected before bisect mutation. */
@(test)
bisect_process_rejects_dirty_start_repository :: proc(t: ^testing.T) {
	directory, repository, bad, good, ready := bisect_process_repository(t)
	if len(directory) == 0 do return
	defer {os.remove_all(directory); delete(directory)}
	if !ready do return
	dirty_path, path_error := os.join_path({directory, "dirty.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(dirty_path)
	testing.expect(t, os.write_entire_file(dirty_path, "dirty\n") == nil)
	boundaries, opened, _ := ksawery.bisect_boundary_set_open(bad, []ksawery.Revision_Identity{good})
	if !opened do return
	defer ksawery.bisect_boundary_set_close(&boundaries)
	sequence, observed, _ := sequence_process_observe(repository, 1_045)
	if !observed do return
	defer ksawery.sequence_observation_close(&sequence)
	status, status_opened := rebase_process_observe_status(repository, 1_046)
	if !status_opened do return
	defer ksawery.status_observation_close(&status)
	history, history_opened := revision_sequence_observe_history(repository, 1_047)
	if !history_opened do return
	defer ksawery.history_observation_close(&history)
	refs, refs_opened := rebase_process_observe_refs(repository, 1_048)
	if !refs_opened do return
	defer ksawery.ref_observation_close(&refs)
	process, started, failure := ksawery.repository_process_start_bisect_precondition(
		&status, &history, &refs, &sequence, &boundaries, .Start, {}, {},
		{repository_resources = 1}, 1,
	)
	testing.expectf(t, started, "dirty bisect precondition failed to start with %v", failure)
	if !started do return
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	testing.expect_value(t, poll.state, ksawery.Repository_Process_State.Failed)
	testing.expect_value(t, poll.failure, ksawery.Failure_Code.Action_Unavailable)
	inactive, inactive_observed, _ := sequence_process_observe(repository, 1_049)
	testing.expect(t, inactive_observed)
	if inactive_observed {
		descriptor, described := ksawery.sequence_observation_descriptor(&inactive)
		testing.expect(t, described && descriptor.state == .Inactive)
		ksawery.sequence_observation_close(&inactive)
	}
}

/* Verifies cancellation and timeout stop before any implicit bisect classification. */
@(test)
bisect_process_termination_does_not_classify_candidate :: proc(t: ^testing.T) {
	for terminate in 0 ..< 2 {
		directory, repository, bad, good, ready := bisect_process_repository(t)
		if len(directory) == 0 do return
		if !ready {
			os.remove_all(directory)
			delete(directory)
			return
		}
		boundaries, lineage, progress, sequence, begun := bisect_process_begin_session(
			t, repository, bad, good, u64(1_050 + terminate * 20),
		)
		if !begun {
			os.remove_all(directory)
			delete(directory)
			return
		}
		precondition, prepared := bisect_process_precondition(
			t, repository, &sequence, &boundaries, .Good, lineage, progress,
			u64(1_060 + terminate * 20),
		)
		request, requested := bisect_process_request(t, precondition, u64(1_061 + terminate * 20))
		if prepared && requested {
			process, started, failure := ksawery.repository_process_start_bisect(
				&sequence, precondition, &boundaries, request, 1,
			)
			testing.expectf(t, started, "terminating bisect failed to start with %v", failure)
			if started {
				if terminate == 0 {
					testing.expect(t, ksawery.repository_process_cancel(&process))
					poll, polled := ksawery.repository_process_poll(&process, 2)
					testing.expect(t, polled && poll.state == .Failed && poll.failure == .Cancelled)
					result, retained, result_failure := ksawery.repository_process_take_bisect(&process)
					testing.expectf(t, retained, "cancelled bisect result failed with %v", result_failure)
					if retained {
						descriptor, described := ksawery.bisect_result_descriptor(&result)
						testing.expect(t, described && descriptor.outcome == .Cancelled_Before_Start)
						ksawery.bisect_result_close(&result)
					}
				} else {
					now := i64(1) + request.limits.timeout_nanoseconds
					poll := sequence_process_wait(&process, now)
					testing.expect(t, poll.state == .Failed && poll.failure == .Timeout)
				}
				ksawery.repository_process_close(&process)
			}
		}
		ksawery.sequence_observation_close(&sequence)
		ksawery.bisect_boundary_set_close(&boundaries)
		_ = sequence_process_run(directory, "git", "bisect", "reset")
		os.remove_all(directory)
		delete(directory)
	}
}

bisect_process_begin_session :: proc(
	t: ^testing.T,
	repository: ksawery.Repository_Context,
	bad: ksawery.Revision_Identity,
	good: ksawery.Revision_Identity,
	generation: u64,
) -> (
	ksawery.Bisect_Boundary_Set,
	ksawery.Bisect_Precondition,
	ksawery.Bisect_Progress,
	ksawery.Sequence_Observation,
	bool,
) {
	boundaries, opened, failure := ksawery.bisect_boundary_set_open(bad, []ksawery.Revision_Identity{good})
	testing.expectf(t, opened, "bisect boundaries failed with %v", failure)
	if !opened do return {}, {}, {}, {}, false
	sequence, observed, observe_failure := sequence_process_observe(
		repository, ksawery.Sequence_Generation(generation),
	)
	if !observed {
		ksawery.bisect_boundary_set_close(&boundaries)
		testing.expectf(t, observed, "initial bisect observation failed with %v", observe_failure)
		return {}, {}, {}, {}, false
	}
	lineage, prepared := bisect_process_precondition(
		t, repository, &sequence, &boundaries, .Start, {}, {}, generation + 1,
	)
	if !prepared {
		ksawery.sequence_observation_close(&sequence)
		ksawery.bisect_boundary_set_close(&boundaries)
		return {}, {}, {}, {}, false
	}
	request, requested := bisect_process_request(t, lineage, generation + 2)
	if !requested {
		ksawery.sequence_observation_close(&sequence)
		ksawery.bisect_boundary_set_close(&boundaries)
		return {}, {}, {}, {}, false
	}
	process, started, start_failure := ksawery.repository_process_start_bisect(
		&sequence, lineage, &boundaries, request, 1,
	)
	ksawery.sequence_observation_close(&sequence)
	if !started {
		ksawery.bisect_boundary_set_close(&boundaries)
		testing.expectf(t, started, "manual bisect failed to start with %v", start_failure)
		return {}, {}, {}, {}, false
	}
	poll := sequence_process_wait(&process, 2)
	result, retained, result_failure := ksawery.repository_process_take_bisect(&process)
	ksawery.repository_process_close(&process)
	if poll.state != .Completed || !retained {
		if retained do ksawery.bisect_result_close(&result)
		ksawery.bisect_boundary_set_close(&boundaries)
		testing.expectf(t, retained, "manual bisect result failed with %v", result_failure)
		return {}, {}, {}, {}, false
	}
	refs, refs_opened := rebase_process_observe_refs(repository, ksawery.Ref_Generation(generation + 3))
	active, active_opened, active_failure := sequence_process_observe(
		repository, ksawery.Sequence_Generation(generation + 4),
	)
	verified := false
	verify_failure: ksawery.Failure_Code
	if refs_opened && active_opened {
		verified, verify_failure = ksawery.bisect_result_verify(&result, &refs, &active)
	}
	descriptor, described := ksawery.bisect_result_descriptor(&result)
	if refs_opened do ksawery.ref_observation_close(&refs)
	ksawery.bisect_result_close(&result)
	if !active_opened || !verified || !described || descriptor.outcome != .Started {
		if active_opened do ksawery.sequence_observation_close(&active)
		ksawery.bisect_boundary_set_close(&boundaries)
		testing.expectf(
			t, false,
			"manual bisect start verification failed: observed=%v verify=%v/%v described=%v outcome=%v source=%v",
			active_opened, verified, verify_failure, described, descriptor.outcome, active_failure,
		)
		return {}, {}, {}, {}, false
	}
	return boundaries, lineage, descriptor.progress, active, true
}

bisect_process_apply_action :: proc(
	t: ^testing.T,
	repository: ksawery.Repository_Context,
	sequence: ^ksawery.Sequence_Observation,
	boundaries: ^ksawery.Bisect_Boundary_Set,
	lineage: ksawery.Bisect_Precondition,
	progress: ksawery.Bisect_Progress,
	action: ksawery.Bisect_Action,
	generation: u64,
) -> (ksawery.Bisect_Progress, ksawery.Bisect_Outcome, bool) {
	precondition, prepared := bisect_process_precondition(
		t, repository, sequence, boundaries, action, lineage, progress, generation,
	)
	if !prepared do return progress, .Invalid, false
	request, requested := bisect_process_request(t, precondition, generation + 1)
	if !requested do return progress, .Invalid, false
	process, started, failure := ksawery.repository_process_start_bisect(
		sequence, precondition, boundaries, request, 1,
	)
	testing.expectf(t, started, "manual bisect action %v failed to start with %v", action, failure)
	if !started do return progress, .Invalid, false
	poll := sequence_process_wait(&process, 2)
	result, retained, result_failure := ksawery.repository_process_take_bisect(&process)
	ksawery.repository_process_close(&process)
	testing.expectf(
		t, poll.state == .Completed && retained,
		"manual bisect action %v failed: state=%v result=%v failure=%v",
		action, poll.state, retained, result_failure,
	)
	if poll.state != .Completed || !retained {
		if retained do ksawery.bisect_result_close(&result)
		return progress, .Invalid, false
	}
	refs, refs_opened := rebase_process_observe_refs(repository, ksawery.Ref_Generation(generation + 2))
	refreshed, refreshed_opened, refresh_failure := sequence_process_observe(
		repository, ksawery.Sequence_Generation(generation + 3),
	)
	verified := false
	verify_failure: ksawery.Failure_Code
	if refs_opened && refreshed_opened {
		verified, verify_failure = ksawery.bisect_result_verify(&result, &refs, &refreshed)
	}
	descriptor, described := ksawery.bisect_result_descriptor(&result)
	if refs_opened do ksawery.ref_observation_close(&refs)
	ksawery.bisect_result_close(&result)
	testing.expectf(
		t, refreshed_opened && verified && described,
		"manual bisect action %v verification failed: observed=%v source=%v verify=%v/%v described=%v",
		action, refreshed_opened, refresh_failure, verified, verify_failure, described,
	)
	if !refreshed_opened || !verified || !described {
		if refreshed_opened do ksawery.sequence_observation_close(&refreshed)
		return progress, .Invalid, false
	}
	ksawery.sequence_observation_close(sequence)
	sequence^ = refreshed
	return descriptor.progress, descriptor.outcome, true
}

bisect_process_precondition :: proc(
	t: ^testing.T,
	repository: ksawery.Repository_Context,
	sequence: ^ksawery.Sequence_Observation,
	boundaries: ^ksawery.Bisect_Boundary_Set,
	action: ksawery.Bisect_Action,
	lineage: ksawery.Bisect_Precondition,
	progress: ksawery.Bisect_Progress,
	generation: u64,
) -> (ksawery.Bisect_Precondition, bool) {
	status, status_opened := rebase_process_observe_status(repository, ksawery.Observation_Generation(generation))
	testing.expectf(t, status_opened, "bisect Status observation %d failed", generation)
	if !status_opened do return {}, false
	defer ksawery.status_observation_close(&status)
	history, history_opened := revision_sequence_observe_history(repository, ksawery.History_Generation(generation + 1))
	testing.expectf(t, history_opened, "bisect History observation %d failed", generation + 1)
	if !history_opened do return {}, false
	defer ksawery.history_observation_close(&history)
	refs, refs_opened := rebase_process_observe_refs(repository, ksawery.Ref_Generation(generation + 2))
	testing.expectf(t, refs_opened, "bisect Ref observation %d failed", generation + 2)
	if !refs_opened do return {}, false
	defer ksawery.ref_observation_close(&refs)
	process, started, failure := ksawery.repository_process_start_bisect_precondition(
		&status,
		&history,
		&refs,
		sequence,
		boundaries,
		action,
		lineage,
		progress,
		{repository_resources = 1},
		1,
	)
	testing.expectf(t, started, "bisect precondition failed to start with %v", failure)
	if !started do return {}, false
	defer ksawery.repository_process_close(&process)
	poll := sequence_process_wait(&process, 2)
	testing.expectf(t, poll.state == .Completed, "bisect precondition process ended as %v with %v", poll.state, poll.failure)
	if poll.state != .Completed do return {}, false
	precondition, prepared, prepare_failure := ksawery.repository_process_take_bisect_precondition(&process)
	testing.expectf(t, prepared, "bisect precondition failed with %v", prepare_failure)
	return precondition, prepared
}

bisect_process_request :: proc(
	t: ^testing.T,
	precondition: ksawery.Bisect_Precondition,
	id: u64,
) -> (ksawery.Bisect_Request, bool) {
	confirmation, prepared, _ := ksawery.bisect_confirmation_prepare(
		precondition,
		ksawery.Bisect_Confirmation_ID(id),
	)
	if !prepared do return {}, false
	confirmed, _ := ksawery.bisect_confirmation_confirm(&confirmation, confirmation.id)
	if !confirmed do return {}, false
	request, requested, failure := ksawery.bisect_request_prepare(
		precondition,
		ksawery.Bisect_Operation_ID(id),
		&confirmation,
	)
	testing.expectf(t, requested, "bisect request failed with %v", failure)
	return request, requested
}

bisect_process_repository :: proc(
	t: ^testing.T,
) -> (string, ksawery.Repository_Context, ksawery.Revision_Identity, ksawery.Revision_Identity, bool) {
	directory, repository, ready := sequence_process_repository(t)
	if len(directory) == 0 || !ready do return directory, repository, {}, {}, false
	good := merge_process_revision(t, directory, "HEAD")
	path, path_error := os.join_path({directory, "bisect.txt"}, context.allocator)
	if path_error != nil do return directory, repository, {}, {}, false
	defer delete(path)
	for index in 1 ..= 5 {
		content := fmt.aprintf("revision %d\n", index)
		write_error := os.write_entire_file(path, content)
		delete(content)
		ready = ready && write_error == nil &&
			sequence_process_run(directory, "git", "add", "bisect.txt")
		message := fmt.aprintf("bisect revision %d", index)
		ready = ready && sequence_process_run(directory, "git", "commit", "-q", "-m", message)
		delete(message)
	}
	bad := merge_process_revision(t, directory, "HEAD")
	return directory, repository, bad, good, ready
}
