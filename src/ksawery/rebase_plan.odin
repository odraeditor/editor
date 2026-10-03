// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:crypto/sha2"
import "core:strings"

/* Rebase_Plan_State distinguishes usable semantic plans from bounded rejection states. */
Rebase_Plan_State :: enum u8 {
	Invalid,
	Available,
	Ambiguous,
	Unsupported,
	Truncated,
}

/* Rebase_Plan_Text_Ref identifies copied subject text owned by one preview. */
Rebase_Plan_Text_Ref :: struct {
	offset: u32,
	length: u32,
}

/* Rebase_Plan_Commit is one borrowed exact commit identity and single-line subject input. */
Rebase_Plan_Commit :: struct {
	revision: Revision_Identity,
	subject:  string,
}

/* Rebase_Plan_Step is one immutable semantic replay instruction with an exact target. */
Rebase_Plan_Step :: struct {
	position: u32,
	total:    u32,
	action:   Rebase_Replay_Action,
	revision: Revision_Identity,
	target:   Revision_Identity,
	subject:  Rebase_Plan_Text_Ref,
}

/* Rebase_Plan_Descriptor reports one bounded immutable autosquash projection. */
Rebase_Plan_Descriptor :: struct {
	state:          Rebase_Plan_State,
	old_tip:        Revision_Identity,
	upstream:       Revision_Identity,
	fingerprint:    Rebase_Plan_Fingerprint,
	step_count:     u32,
	observed_steps: u32,
	fixups:         u32,
	squashes:       u32,
	subject_bytes:  u64,
	problem_step:   u32,
}

/* Rebase_Plan_Usage reports exact retained semantic preview ownership. */
Rebase_Plan_Usage :: struct {
	steps:            u32,
	observed_steps:   u32,
	subject_bytes:    u64,
	allocation_bytes: u64,
}

/* Rebase_Plan owns one bounded semantic autosquash projection. */
Rebase_Plan :: struct {
	state: rawptr,
}

@(private)
Rebase_Plan_Data :: struct {
	descriptor: Rebase_Plan_Descriptor,
	steps:      [dynamic]Rebase_Plan_Step,
	storage:    [dynamic]u8,
	limits:     Rebase_Plan_Limits,
	allocator:  runtime.Allocator,
}

/* rebase_plan_project resolves fixup and squash subjects only to unique earlier exact commits. */
rebase_plan_project :: proc(
	commits: []Rebase_Plan_Commit,
	old_tip: Revision_Identity,
	upstream: Revision_Identity,
	limits := DEFAULT_REBASE_PLAN_LIMITS,
	allocator := context.allocator,
) -> (Rebase_Plan, bool, Failure_Code) {
	if allocator.procedure == nil || !rebase_plan_limits_are_valid(limits) || len(commits) == 0 ||
	   !revision_identity_is_valid(old_tip) || !revision_identity_is_valid(upstream) || old_tip == upstream {
		return {}, false, .Invalid_Request
	}
	state, allocation_error := new(Rebase_Plan_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.limits = limits
	state.descriptor.old_tip = old_tip
	state.descriptor.upstream = upstream
	state.descriptor.observed_steps = u32(len(commits))
	state.steps, allocation_error = make([dynamic]Rebase_Plan_Step, 0, int(min(limits.steps, 64)), allocator)
	if allocation_error == nil {
		state.storage, allocation_error = make(
			[dynamic]u8,
			0,
			int(min(limits.subject_bytes, 16 * KIBIBYTE)),
			allocator,
		)
	}
	if allocation_error != nil {
		rebase_plan_data_destroy(state)
		return {}, false, .Allocation
	}
	if u32(len(commits)) > limits.steps {
		state.descriptor.state = .Truncated
		return Rebase_Plan{state = state}, true, .None
	}
	total_subject_bytes: u64
	for commit, index in commits {
		if !rebase_plan_commit_is_valid(commit) || rebase_plan_revision_precedes(commits, index, commit.revision) {
			rebase_plan_data_destroy(state)
			return {}, false, .Invalid_Request
		}
		if total_subject_bytes > max(u64) - u64(len(commit.subject)) {
			rebase_plan_data_destroy(state)
			return {}, false, .Invalid_Limits
		}
		total_subject_bytes += u64(len(commit.subject))
	}
	if total_subject_bytes > limits.subject_bytes {
		state.descriptor.state = .Truncated
		state.descriptor.subject_bytes = total_subject_bytes
		return Rebase_Plan{state = state}, true, .None
	}
	if commits[len(commits) - 1].revision != old_tip {
		rebase_plan_data_destroy(state)
		return {}, false, .Stale_Observation
	}
	for commit, index in commits {
		action, wanted, classified := rebase_plan_subject_classify(commit.subject)
		if !classified {
			state.descriptor.state = .Unsupported
			state.descriptor.problem_step = u32(index + 1)
			rebase_plan_finish_rejection(state)
			return Rebase_Plan{state = state}, true, .None
		}
		target: Revision_Identity
		if action == .Fixup || action == .Squash {
			target, classified = rebase_plan_target_resolve(commits[:index], wanted)
			if !classified {
				state.descriptor.state = .Ambiguous
				state.descriptor.problem_step = u32(index + 1)
				rebase_plan_finish_rejection(state)
				return Rebase_Plan{state = state}, true, .None
			}
		}
		step := Rebase_Plan_Step {
			position = u32(index + 1),
			total = u32(len(commits)),
			action = action,
			revision = commit.revision,
			target = target,
			subject = {offset = u32(len(state.storage)), length = u32(len(commit.subject))},
		}
		if _, append_error := append(&state.storage, ..transmute([]u8)commit.subject); append_error != nil {
			rebase_plan_data_destroy(state)
			return {}, false, .Allocation
		}
		if _, append_error := append(&state.steps, step); append_error != nil {
			rebase_plan_data_destroy(state)
			return {}, false, .Allocation
		}
		if action == .Fixup do state.descriptor.fixups += 1
		if action == .Squash do state.descriptor.squashes += 1
	}
	state.descriptor.state = .Available
	state.descriptor.step_count = u32(len(state.steps))
	state.descriptor.subject_bytes = u64(len(state.storage))
	state.descriptor.fingerprint = rebase_plan_fingerprint(state)
	if !rebase_plan_descriptor_is_valid(state.descriptor, limits) {
		rebase_plan_data_destroy(state)
		return {}, false, .Parse
	}
	return Rebase_Plan{state = state}, true, .None
}

/* rebase_plan_descriptor returns copied immutable semantic preview metadata. */
rebase_plan_descriptor :: proc(plan: ^Rebase_Plan) -> (Rebase_Plan_Descriptor, bool) {
	state := rebase_plan_data(plan)
	if state == nil do return {}, false
	return state.descriptor, rebase_plan_descriptor_is_valid(state.descriptor, state.limits)
}

/* rebase_plan_step returns one copied semantic step in replay order. */
rebase_plan_step :: proc(plan: ^Rebase_Plan, ordinal: u32) -> (Rebase_Plan_Step, bool) {
	state := rebase_plan_data(plan)
	if state == nil || ordinal >= u32(len(state.steps)) do return {}, false
	return state.steps[ordinal], true
}

/* rebase_plan_subject returns borrowed copied subject text for one preview step. */
rebase_plan_subject :: proc(plan: ^Rebase_Plan, reference: Rebase_Plan_Text_Ref) -> (string, bool) {
	state := rebase_plan_data(plan)
	if state == nil || reference.length == 0 ||
	   u64(reference.offset) + u64(reference.length) > u64(len(state.storage)) {
		return "", false
	}
	end := int(reference.offset + reference.length)
	return string(state.storage[int(reference.offset):end]), true
}

/* rebase_plan_accept produces one exact accepted plan identity only from a complete projection. */
rebase_plan_accept :: proc(plan: ^Rebase_Plan) -> (Rebase_Reviewed_Plan, bool, Failure_Code) {
	state := rebase_plan_data(plan)
	if state == nil do return {}, false, .Invalid_Request
	if state.descriptor.state != .Available do return {}, false, .Action_Unavailable
	return {
		fingerprint = state.descriptor.fingerprint,
		old_tip = state.descriptor.old_tip,
		upstream = state.descriptor.upstream,
		steps = state.descriptor.step_count,
		fixups = state.descriptor.fixups,
		squashes = state.descriptor.squashes,
		accepted = true,
	}, true, .None
}

/* rebase_plan_usage reports exact retained steps, subject text, and allocation capacity. */
rebase_plan_usage :: proc(plan: ^Rebase_Plan) -> (Rebase_Plan_Usage, bool) {
	state := rebase_plan_data(plan)
	if state == nil do return {}, false
	return {
		steps = u32(len(state.steps)),
		observed_steps = state.descriptor.observed_steps,
		subject_bytes = u64(len(state.storage)),
		allocation_bytes = u64(size_of(Rebase_Plan_Data)) +
		                   u64(cap(state.steps)) * u64(size_of(Rebase_Plan_Step)) + u64(cap(state.storage)),
	}, true
}

/* rebase_plan_close releases all copied semantic preview ownership. */
rebase_plan_close :: proc(plan: ^Rebase_Plan) {
	state := rebase_plan_data(plan)
	if state == nil do return
	rebase_plan_data_destroy(state)
	plan^ = {}
}

@(private)
rebase_plan_commit_is_valid :: proc(commit: Rebase_Plan_Commit) -> bool {
	if !revision_identity_is_valid(commit.revision) || len(commit.subject) == 0 do return false
	for byte in transmute([]u8)commit.subject {
		if byte == 0 || byte == '\n' || byte == '\r' do return false
	}
	return true
}

@(private)
rebase_plan_revision_precedes :: proc(
	commits: []Rebase_Plan_Commit,
	index: int,
	revision: Revision_Identity,
) -> bool {
	for prior in commits[:index] {
		if prior.revision == revision do return true
	}
	return false
}

@(private)
rebase_plan_subject_classify :: proc(subject: string) -> (Rebase_Replay_Action, string, bool) {
	fixup_prefix :: "fixup! "
	squash_prefix :: "squash! "
	if strings.has_prefix(subject, fixup_prefix) {
		wanted := subject[len(fixup_prefix):]
		return .Fixup, wanted, len(wanted) > 0 && strings.trim_space(wanted) == wanted
	}
	if strings.has_prefix(subject, squash_prefix) {
		wanted := subject[len(squash_prefix):]
		return .Squash, wanted, len(wanted) > 0 && strings.trim_space(wanted) == wanted
	}
	if strings.has_prefix(subject, "fixup!") || strings.has_prefix(subject, "squash!") ||
	   strings.has_prefix(subject, "amend!") || strings.has_prefix(subject, "reword!") {
		return .Invalid, "", false
	}
	return .Pick, "", true
}

@(private)
rebase_plan_finish_rejection :: proc(state: ^Rebase_Plan_Data) {
	if state == nil do return
	state.descriptor.step_count = u32(len(state.steps))
	state.descriptor.subject_bytes = u64(len(state.storage))
}

@(private)
rebase_plan_target_resolve :: proc(
	commits: []Rebase_Plan_Commit,
	wanted: string,
) -> (Revision_Identity, bool) {
	exact: Revision_Identity
	exact_count := 0
	for commit in commits {
		if commit.subject == wanted {
			exact = commit.revision
			exact_count += 1
		}
	}
	if exact_count == 1 do return exact, true
	if exact_count > 1 do return {}, false
	matched: Revision_Identity
	matches := 0
	for commit in commits {
		if strings.has_prefix(commit.subject, wanted) {
			matched = commit.revision
			matches += 1
		}
	}
	return matched, matches == 1
}

@(private)
rebase_plan_fingerprint :: proc(state: ^Rebase_Plan_Data) -> Rebase_Plan_Fingerprint {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	old_tip := state.descriptor.old_tip
	upstream := state.descriptor.upstream
	sha2.update(&ctx, old_tip.bytes[:old_tip.length])
	sha2.update(&ctx, upstream.bytes[:upstream.length])
	for step in state.steps {
		action := [1]u8{u8(step.action)}
		sha2.update(&ctx, action[:])
		revision := step.revision
		target := step.target
		sha2.update(&ctx, revision.bytes[:revision.length])
		sha2.update(&ctx, target.bytes[:target.length])
		end := int(step.subject.offset + step.subject.length)
		sha2.update(&ctx, state.storage[int(step.subject.offset):end])
	}
	fingerprint: Rebase_Plan_Fingerprint
	sha2.final(&ctx, fingerprint.bytes[:])
	return fingerprint
}

@(private)
rebase_plan_descriptor_is_valid :: proc(
	descriptor: Rebase_Plan_Descriptor,
	limits: Rebase_Plan_Limits,
) -> bool {
	if !rebase_plan_limits_are_valid(limits) || !revision_identity_is_valid(descriptor.old_tip) ||
	   !revision_identity_is_valid(descriptor.upstream) || descriptor.old_tip == descriptor.upstream ||
	   descriptor.observed_steps == 0 {
		return false
	}
	if descriptor.state == .Truncated {
		return descriptor.step_count == 0 && descriptor.problem_step == 0 &&
		       (descriptor.observed_steps > limits.steps || descriptor.subject_bytes > limits.subject_bytes)
	}
	if descriptor.state == .Ambiguous || descriptor.state == .Unsupported {
		return descriptor.problem_step > 0 && descriptor.problem_step <= descriptor.observed_steps &&
		       descriptor.step_count < descriptor.observed_steps &&
		       descriptor.subject_bytes <= limits.subject_bytes && descriptor.fingerprint == {}
	}
	if descriptor.state != .Available do return false
	return descriptor.step_count == descriptor.observed_steps && descriptor.step_count <= limits.steps &&
	       descriptor.fixups <= descriptor.step_count &&
	       descriptor.squashes <= descriptor.step_count - descriptor.fixups &&
	       descriptor.subject_bytes <= limits.subject_bytes && descriptor.problem_step == 0 &&
	       rebase_plan_fingerprint_is_valid(descriptor.fingerprint)
}

@(private)
rebase_plan_data :: proc(plan: ^Rebase_Plan) -> ^Rebase_Plan_Data {
	if plan == nil || plan.state == nil do return nil
	return cast(^Rebase_Plan_Data)plan.state
}

@(private)
rebase_plan_data_destroy :: proc(state: ^Rebase_Plan_Data) {
	if state == nil do return
	allocator := state.allocator
	delete(state.steps)
	delete(state.storage)
	free(state, allocator)
}
