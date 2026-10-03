// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../history"
import "../hosting"
import "../interaction"
import "../recovery"
import terminal "../terminal"
import edit_transaction "../transaction"
import "../ui"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:time"

@(private)
Recovery_Observed_Buffer :: struct {
	live:                   bool,
	seen:                   bool,
	entry:                  editor_session.Entry_Handle,
	editor_buffer_id:       editor.Buffer_ID,
	recovery_buffer_id:     recovery.Buffer_ID,
	last_revision:          u64,
	last_modified:          bool,
	checkpoint_revision:    u64,
}

@(private)
Recovery_Workflow_State :: struct {
	store:             recovery.Store,
	scheduler:         recovery.Scheduler,
	discovery:         recovery.Startup_Discovery,
	handled:           []bool,
	launch_matches:    []bool,
	launch_only:       bool,
	return_target:     editor_session.Visible_Target,
	observed:          [editor_session.MAX_LIVE_BUFFERS]Recovery_Observed_Buffer,
	policy:            recovery.Policy,
	clock_start:       time.Tick,
	next_buffer_id:    u64,
	next_record_id:    u64,
	position:          ui.List_View_Position,
	model_generation:  u64,
	initialized:       bool,
	active:            bool,
}

/* RECOVERY_UI_OWNER_ID identifies the startup recovery projection owner. */
RECOVERY_UI_OWNER_ID :: ui.Owner_ID(10_010)
/* RECOVERY_UI_MODEL_ID identifies the startup recovery list model. */
RECOVERY_UI_MODEL_ID :: ui.Model_ID(10_010)
/* RECOVERY_UI_TARGET_GENERATION identifies the recovery target contract. */
RECOVERY_UI_TARGET_GENERATION :: u64(1)
/* RECOVERY_UI_ROW_BYTES bounds text copied for one recovery row. */
RECOVERY_UI_ROW_BYTES :: 512

@(private)
recovery_visible_target :: proc() -> editor_session.Visible_Target {
	return editor_session.Visible_Target {
		kind = .UI_Root,
		ui = {
			owner_id = u64(RECOVERY_UI_OWNER_ID),
			model_id = u64(RECOVERY_UI_MODEL_ID),
			generation = RECOVERY_UI_TARGET_GENERATION,
		},
	}
}

@(private)
recovery_workflow_init :: proc(
	state: ^Recovery_Workflow_State,
	commands: ^Command_Context,
	platform_roots: hosting.Platform_Roots,
	policy: recovery.Policy,
) -> bool {
	if state == nil || commands == nil || state.initialized do return false
	state.policy = policy
	state.clock_start = time.tick_now()
	seed := u64(max(time.to_unix_nanoseconds(time.now()), i64(1)))
	state.next_buffer_id = seed
	state.next_record_id = seed
	state.initialized = true
	if !policy.enabled do return true
	root_path, path_error := os.join_path({platform_roots.state, "recovery", "v1"}, commands.persistent_allocator)
	if path_error != nil do return true
	defer delete(root_path, commands.persistent_allocator)
	platform := recovery.Platform.Invalid
	switch platform_roots.platform {
	case .Linux: platform = .Linux
	case .Darwin: platform = .Darwin
	case .Windows: platform = .Windows
	case .Invalid: return true
	}
	root := recovery.Root {
		platform = platform,
		state_root = platform_roots.state,
		recovery_root = root_path,
		private_directory_mode = recovery.PRIVATE_DIRECTORY_MODE if platform != .Windows else 0,
		private_file_mode = recovery.PRIVATE_FILE_MODE if platform != .Windows else 0,
	}
	store_ready, _ := recovery.store_init(&state.store, root, policy, commands.persistent_allocator)
	if !store_ready do return true
	scheduler_ready, _ := recovery.scheduler_init(
		&state.scheduler,
		policy,
		commands.persistent_allocator,
	)
	if !scheduler_ready {
		recovery.store_close(&state.store)
		return true
	}
	discovery, discovered, _ := recovery.store_discover_startup_candidates(
		&state.store,
		commands.persistent_allocator,
	)
	if discovered {
		state.discovery = discovery
		state.model_generation = 1
		if len(discovery.candidates) > 0 {
			handled, allocation_error := make(
				[]bool,
				len(discovery.candidates),
				commands.persistent_allocator,
			)
			if allocation_error != nil {
				recovery.startup_discovery_close(&state.discovery)
				recovery.scheduler_close(&state.scheduler)
				recovery.store_close(&state.store)
				return false
			}
			state.handled = handled
			matches, matches_error := make([]bool, len(discovery.candidates), commands.persistent_allocator)
			if matches_error != nil {
				recovery_workflow_close(state, commands.persistent_allocator)
				return false
			}
			state.launch_matches = matches
		}
	}
	state.active = true
	return true
}

@(private)
recovery_workflow_present_startup :: proc(
	state: ^Recovery_Workflow_State,
	commands: ^Command_Context,
	global_review := false,
) -> bool {
	if state == nil || commands == nil || !state.active do return false
	state.launch_only = !global_review
	if recovery_workflow_item_count(state) == 0 do return false
	previous, previous_ok, _ := editor_session.session_visible_target(commands.session_owner, commands.session_handle)
	if !previous_ok do return false
	state.return_target = previous
	state.position = {}
	target := recovery_visible_target()
	_, _, presented, _ := editor_session.session_present_ui(
		commands.session_owner,
		commands.session_handle,
		target.ui,
	)
	if presented {
		command_context_set_channel_diagnostic(commands, .Recovery, "Unsaved work: Enter applies the selected action; C-g returns without changes")
	}
	return presented
}

@(private)
recovery_workflow_close :: proc(
	state: ^Recovery_Workflow_State,
	allocator := context.allocator,
) {
	if state == nil || !state.initialized do return
	if state.handled != nil do delete(state.handled, allocator)
	if state.launch_matches != nil do delete(state.launch_matches, allocator)
	recovery.startup_discovery_close(&state.discovery)
	recovery.scheduler_close(&state.scheduler)
	recovery.store_close(&state.store)
	state^ = {}
}

@(private)
recovery_workflow_pending_count :: proc(state: ^Recovery_Workflow_State) -> int {
	if state == nil || !state.active do return 0
	count := 0
	for _, index in state.discovery.candidates {
		if index >= len(state.handled) || !state.handled[index] do count += 1
	}
	return count
}

@(private)
recovery_workflow_startup_context :: proc(
	state: ^Recovery_Workflow_State,
	commands: ^Command_Context,
	arguments: []string,
	startup_directory: bool,
) {
	if state == nil || !state.active || commands == nil do return
	normalized: document.Normalized_Path
	exact_file := ""
	if len(arguments) == 1 && !startup_directory {
		if normalized_ok, _ := document.path_normalize(arguments[0], &normalized, commands.temporary_allocator); normalized_ok {
			exact_file = document.normalized_path_text(&normalized)
		}
	}
	roots, roots_ok, _ := editor_session.session_roots(commands.session_owner, commands.session_handle)
	defer if roots_ok do editor_session.root_batch_close(&roots)
	paths, paths_error := make([]string, len(roots.descriptors), commands.temporary_allocator)
	if paths_error != nil do return
	defer delete(paths, commands.temporary_allocator)
	for descriptor, index in roots.descriptors do paths[index] = descriptor.path
	for observation, index in state.discovery.candidates {
		state.launch_matches[index] = recovery.startup_source_matches(observation.source_identity, exact_file, paths)
		if state.launch_matches[index] && state.policy.startup == .Restore_Matching && observation.candidate.state == .Restorable {
			_ = recovery_workflow_apply_candidate(state, commands, index, .Restore)
		}
	}
	hidden := 0
	for _, index in state.discovery.candidates {
		if !state.handled[index] && !state.launch_matches[index] do hidden += 1
	}
	if hidden > 0 {
		command_context_set_channel_diagnostic(
			commands,
			.Recovery,
			"Other unsaved work is available; M-x recover-unsaved-work to review",
		)
	}
	_ = recovery_workflow_present_startup(state, commands)
}

@(private)
recovery_workflow_candidate_visible :: proc(state: ^Recovery_Workflow_State, index: int) -> bool {
	if state == nil || !state.active || index < 0 || index >= len(state.discovery.candidates) do return false
	if index >= len(state.handled) || state.handled[index] do return false
	return !state.launch_only || (index < len(state.launch_matches) && state.launch_matches[index])
}

@(private)
recovery_workflow_step :: proc(state: ^Recovery_Workflow_State, commands: ^Command_Context) {
	if state == nil || commands == nil || !state.active do return
	for &observed in state.observed do observed.seen = false
	descriptors, copied, _ := editor_session.session_descriptors(
		commands.session_owner,
		commands.session_handle,
		commands.temporary_allocator,
	)
	if !copied do return
	defer editor_session.descriptor_batch_close(&descriptors)
	now := recovery_workflow_elapsed_milliseconds(state)
	for descriptor in descriptors.descriptors {
		if descriptor.kind != .Text do continue
		access, access_ok, _ := editor_session.session_entry_access(
			commands.session_owner,
			descriptor.graph.entry,
		)
		if !access_ok do continue
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !borrowed do continue
		stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
		if !stats_ok do continue
		observed := recovery_workflow_observed_for_editor(state, stats.buffer_id)
		if observed == nil {
			observed = recovery_workflow_free_observed(state)
			if observed == nil do continue
			observed^ = Recovery_Observed_Buffer {
				live = true,
				entry = descriptor.graph.entry,
				editor_buffer_id = stats.buffer_id,
				recovery_buffer_id = recovery.Buffer_ID(recovery_workflow_next_buffer_id(state)),
				last_revision = u64(stats.revision),
				last_modified = descriptor.modified,
			}
			if descriptor.modified && u64(stats.revision) > 0 {
				_, _ = recovery.scheduler_mark_commit(
					&state.scheduler,
					observed.recovery_buffer_id,
					u64(stats.revision),
					now,
				)
			}
		}
		observed.seen = true
		observed.entry = descriptor.graph.entry
		if !descriptor.modified && observed.last_modified {
			recovery_workflow_retire_observed(state, observed)
			_, _, _ = recovery.scheduler_confirm_saved(
				&state.scheduler,
				observed.recovery_buffer_id,
				u64(stats.revision),
			)
		}
		if descriptor.modified && u64(stats.revision) > observed.last_revision {
			_, _ = recovery.scheduler_mark_commit(
				&state.scheduler,
				observed.recovery_buffer_id,
				u64(stats.revision),
				now,
			)
		}
		observed.last_revision = u64(stats.revision)
		observed.last_modified = descriptor.modified
	}
	for &observed in state.observed {
		if !observed.live || observed.seen do continue
		recovery_workflow_retire_observed(state, &observed)
		_, _ = recovery.scheduler_forget_buffer(&state.scheduler, observed.recovery_buffer_id)
		observed = {}
	}
	recovery_workflow_publish_one_due(state, commands, now)
}

@(private)
recovery_workflow_publish_one_due :: proc(
	state: ^Recovery_Workflow_State,
	commands: ^Command_Context,
	now_milliseconds: u64,
) {
	claim, due, _ := recovery.scheduler_claim_due(&state.scheduler, now_milliseconds)
	if !due do return
	observed := recovery_workflow_observed_for_recovery(state, claim.buffer_id)
	if observed == nil {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, true)
		return
	}
	access, access_ok, _ := editor_session.session_entry_access(commands.session_owner, observed.entry)
	if !access_ok {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, true)
		return
	}
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, true)
		return
	}
	snapshot: editor.Buffer_Snapshot
	snapshot_ok, _ := editor.buffer_snapshot_open(entry.buffer, &snapshot)
	if !snapshot_ok {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, false)
		return
	}
	defer editor.buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	if !stats_ok || u64(stats.revision) != claim.revision ||
	   stats.text_bytes > state.policy.storage.record_payload_bytes ||
	   stats.text_bytes > u64(max(int)) {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, false)
		return
	}
	payload, allocation_error := make([]u8, int(stats.text_bytes), commands.temporary_allocator)
	if allocation_error != nil {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, false)
		return
	}
	defer delete(payload, commands.temporary_allocator)
	copied, payload_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, payload)
	if !payload_ok || copied != stats.text_bytes {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, false)
		return
	}
	record := recovery.Record {
		record_id = recovery.Record_ID(recovery_workflow_next_record_id(state)),
		buffer_id = claim.buffer_id,
		saved_revision = 0,
		recovered_revision = claim.revision,
		encoding = .UTF_8,
		line_ending = recovery_workflow_line_ending(payload),
		payload_digest = recovery.checkpoint_payload_digest(payload),
		payload_bytes = stats.text_bytes,
		created_at_seconds = u64(max(time.to_unix_seconds(time.now()), i64(1))),
		policy_generation = state.policy.generation,
		format_version = recovery.RECOVERY_FORMAT_VERSION,
	}
	if entry.has_document {
		status, status_ok, _ := document.document_status(entry.document)
		if status_ok && status.has_target {
			record.source_present = true
			record.source_identity = status.target_path
			if status.has_saved_revision do record.saved_revision = u64(status.saved_revision)
			record.source_fingerprint = recovery_workflow_source_digest(
				status.target_path,
				state.policy.storage.store_storage_bytes,
			)
		}
	}
	if record.recovered_revision <= record.saved_revision {
		_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, true)
		return
	}
	published, _ := recovery.store_publish(&state.store, record, payload)
	_, _ = recovery.scheduler_resolve_claim(&state.scheduler, claim, published)
	if published do observed.checkpoint_revision = claim.revision
}

@(private)
recovery_workflow_apply_candidate :: proc(
	state: ^Recovery_Workflow_State,
	commands: ^Command_Context,
	index: int,
	action: recovery.Candidate_Action,
) -> bool {
	if state == nil || commands == nil || !state.active || index < 0 ||
	   index >= len(state.discovery.candidates) || index >= len(state.handled) ||
	   state.handled[index] {
		return false
	}
	observation := state.discovery.candidates[index]
	request := recovery.Candidate_Action_Request {
		record_id = observation.candidate.record_id,
		buffer_id = observation.candidate.buffer_id,
		recovered_revision = observation.candidate.recovered_revision,
		action = action,
	}
	result, applied, _ := recovery.store_apply_candidate_action(
		&state.store,
		request,
		commands.temporary_allocator,
	)
	if !applied do return false
	defer recovery.candidate_action_result_close(&result)
	switch action {
	case .Restore:
		entry, restored := recovery_workflow_restore_checkpoint(state, commands, &result)
		if !restored do return false
		state.handled[index] = true
		_ = entry
		return true
	case .Inspect:
		label := fmt.tprintf("Recovered buffer %d", u64(result.candidate.buffer_id))
		_, created, _ := editor_session.session_create_buffer(
			commands.session_owner,
			{
				session = commands.session_handle,
				name = label,
				initial_contents = string(result.checkpoint.payload),
				configuration = commands.entry_configuration,
			},
		)
		return created
	case .Compare:
		comparison := recovery_workflow_comparison_text(
			result.checkpoint.payload,
			result.current_source,
			commands.temporary_allocator,
		)
		if comparison == nil do return false
		defer delete(comparison, commands.temporary_allocator)
		label := fmt.tprintf("Recovery comparison %d", u64(result.candidate.buffer_id))
		_, created, _ := editor_session.session_create_buffer(
			commands.session_owner,
			{
				session = commands.session_handle,
				name = label,
				initial_contents = string(comparison),
				configuration = commands.entry_configuration,
			},
		)
		return created
	case .Discard:
		state.handled[index] = true
		return true
	case .Invalid:
		return false
	}
	return false
}

@(private)
recovery_workflow_restore_checkpoint :: proc(
	state: ^Recovery_Workflow_State,
	commands: ^Command_Context,
	result: ^recovery.Candidate_Action_Result,
) -> (editor_session.Entry_Handle, bool) {
	record := result.checkpoint.record
	admission: editor_session.Admission_Result
	admitted := false
	if record.source_present &&
	   (result.candidate.state == .Restorable || result.candidate.state == .Conflict) {
		admission, admitted, _ = editor_session.session_open_path(
			commands.session_owner,
			{
				session = commands.session_handle,
				path = record.source_identity,
				encoding = .UTF8,
				configuration = commands.entry_configuration,
			},
		)
	}
	if !admitted {
		label := fmt.tprintf("Recovered buffer %d", u64(record.buffer_id))
		admission, admitted, _ = editor_session.session_create_buffer(
			commands.session_owner,
			{
				session = commands.session_handle,
				name = label,
				initial_contents = "",
				configuration = commands.entry_configuration,
			},
		)
	}
	if !admitted do return {}, false
	revision, replaced := recovery_workflow_replace_entry(
		commands,
		admission.entry,
		result.checkpoint.payload,
	)
	if !replaced do return {}, false
	access, access_ok, _ := editor_session.session_entry_access(commands.session_owner, admission.entry)
	if !access_ok do return {}, false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return {}, false
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok do return {}, false
	observed := recovery_workflow_observed_for_editor(state, stats.buffer_id)
	if observed == nil do observed = recovery_workflow_free_observed(state)
	if observed == nil do return {}, false
	observed^ = Recovery_Observed_Buffer {
		live = true,
		seen = true,
		entry = admission.entry,
		editor_buffer_id = stats.buffer_id,
		recovery_buffer_id = record.buffer_id,
		last_revision = revision,
		last_modified = true,
		checkpoint_revision = record.recovered_revision,
	}
	return admission.entry, true
}

@(private)
recovery_workflow_replace_entry :: proc(
	commands: ^Command_Context,
	entry_handle: editor_session.Entry_Handle,
	payload: []u8,
) -> (u64, bool) {
	access, access_ok, _ := editor_session.session_entry_access(commands.session_owner, entry_handle)
	if !access_ok do return 0, false
	entry, borrowed, _ := editor_session.entry_access_borrow(access)
	if !borrowed do return 0, false
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if !stats_ok do return 0, false
	start, start_ok, _ := editor.buffer_position(entry.buffer, 0)
	end, end_ok, _ := editor.buffer_position(entry.buffer, editor.Byte_Offset(stats.text_bytes))
	if !start_ok || !end_ok do return 0, false
	transaction: edit_transaction.Transaction
	transaction_id := edit_transaction.Transaction_ID(commands.next_transaction_id)
	undo_unit_id := edit_transaction.Undo_Unit_ID(commands.next_undo_unit_id)
	commands.next_transaction_id += 1
	commands.next_undo_unit_id += 1
	started, _ := edit_transaction.transaction_begin(
		&transaction,
		transaction_id,
		undo_unit_id,
		entry.buffer,
		{kind = .Built_In, descriptor = "recovery"},
		"restore-recovered-buffer",
		{persistent = commands.persistent_allocator, temporary = commands.temporary_allocator},
	)
	if !started do return 0, false
	defer if edit_transaction.transaction_is_valid(&transaction) {
		edit_transaction.transaction_close(&transaction)
	}
	applied, _ := edit_transaction.transaction_apply_batch(
		&transaction,
		[]edit_transaction.Base_Splice{{start = start, end = end, replacement = string(payload)}},
	)
	if !applied do return 0, false
	tracked, _ := edit_transaction.transaction_track_history(
		&transaction,
		entry.history_store,
		history.Grouping_Context{kind = .Independent},
	)
	if !tracked do return 0, false
	validated, _ := edit_transaction.transaction_validate(&transaction)
	if !validated do return 0, false
	commit, committed, _ := edit_transaction.transaction_commit(&transaction)
	if !committed do return 0, false
	return u64(commit.result_revision), true
}

@(private)
recovery_workflow_clean_shutdown :: proc(state: ^Recovery_Workflow_State) {
	if state == nil || !state.active do return
	for &observed in state.observed {
		if !observed.live do continue
		recovery_workflow_retire_observed(state, &observed)
		_, _ = recovery.scheduler_forget_buffer(&state.scheduler, observed.recovery_buffer_id)
	}
}

@(private)
recovery_workflow_retire_observed :: proc(
	state: ^Recovery_Workflow_State,
	observed: ^Recovery_Observed_Buffer,
) {
	if observed == nil || observed.checkpoint_revision == 0 do return
	retired, _ := recovery.store_retire_current(
		&state.store,
		observed.recovery_buffer_id,
		observed.checkpoint_revision,
	)
	if retired do observed.checkpoint_revision = 0
}

@(private)
recovery_workflow_observed_for_editor :: proc(
	state: ^Recovery_Workflow_State,
	buffer_id: editor.Buffer_ID,
) -> ^Recovery_Observed_Buffer {
	for &observed in state.observed {
		if observed.live && observed.editor_buffer_id == buffer_id do return &observed
	}
	return nil
}

@(private)
recovery_workflow_observed_for_recovery :: proc(
	state: ^Recovery_Workflow_State,
	buffer_id: recovery.Buffer_ID,
) -> ^Recovery_Observed_Buffer {
	for &observed in state.observed {
		if observed.live && observed.recovery_buffer_id == buffer_id do return &observed
	}
	return nil
}

@(private)
recovery_workflow_free_observed :: proc(state: ^Recovery_Workflow_State) -> ^Recovery_Observed_Buffer {
	for &observed in state.observed do if !observed.live do return &observed
	return nil
}

@(private)
recovery_workflow_elapsed_milliseconds :: proc(state: ^Recovery_Workflow_State) -> u64 {
	nanoseconds := time.duration_nanoseconds(time.tick_since(state.clock_start))
	return u64(max(nanoseconds, i64(0)) / i64(time.Millisecond))
}

@(private)
recovery_workflow_next_buffer_id :: proc(state: ^Recovery_Workflow_State) -> u64 {
	state.next_buffer_id += 1
	if state.next_buffer_id == 0 do state.next_buffer_id = 1
	return state.next_buffer_id
}

@(private)
recovery_workflow_next_record_id :: proc(state: ^Recovery_Workflow_State) -> u64 {
	state.next_record_id += 1
	if state.next_record_id == 0 do state.next_record_id = 1
	return state.next_record_id
}

@(private)
recovery_workflow_source_digest :: proc(path: string, maximum_bytes: u64) -> recovery.Digest {
	info, stat_error := os.stat(path, context.temp_allocator)
	if stat_error == nil {
		defer os.file_info_delete(info, context.temp_allocator)
		if info.type == .Regular && info.size >= 0 && u64(info.size) <= maximum_bytes {
			contents, read_error := os.read_entire_file(path, context.temp_allocator)
			if read_error == nil {
				defer delete(contents, context.temp_allocator)
				return recovery.checkpoint_payload_digest(contents)
			}
		}
	}
	return recovery.checkpoint_payload_digest(transmute([]u8)path)
}

@(private)
recovery_workflow_line_ending :: proc(payload: []u8) -> recovery.Line_Ending {
	for value, index in payload {
		if value != '\n' do continue
		if index > 0 && payload[index - 1] == '\r' do return .CRLF
		return .LF
	}
	return .LF
}

@(private)
recovery_workflow_comparison_text :: proc(
	recovered, current: []u8,
	allocator: runtime.Allocator,
) -> []u8 {
	header := "Recovered content\n=================\n"
	middle := "\nCurrent source\n==============\n"
	total := len(header) + len(recovered) + len(middle) + len(current)
	text, allocation_error := make([]u8, total, allocator)
	if allocation_error != nil do return nil
	offset := copy(text, transmute([]u8)header)
	offset += copy(text[offset:], recovered)
	offset += copy(text[offset:], transmute([]u8)middle)
	copy(text[offset:], current)
	return text
}

@(private)
recovery_workflow_item_count :: proc(state: ^Recovery_Workflow_State) -> int {
	if state == nil do return 0
	count := 0
	for observation, index in state.discovery.candidates {
		if !recovery_workflow_candidate_visible(state, index) do continue
		count += int(observation.candidate.action_count)
		if count >= ui.MAX_LIST_ITEMS do return ui.MAX_LIST_ITEMS
	}
	return count
}

@(private)
recovery_workflow_row :: proc(
	state: ^Recovery_Workflow_State,
	row: int,
) -> (candidate_index: int, action: recovery.Candidate_Action, ok: bool) {
	if state == nil || row < 0 do return 0, .Invalid, false
	cursor := 0
	for observation, index in state.discovery.candidates {
		if !recovery_workflow_candidate_visible(state, index) do continue
		for action_index in 0 ..< int(observation.candidate.action_count) {
			if cursor == row {
				return index, observation.candidate.actions[action_index], true
			}
			cursor += 1
			if cursor >= ui.MAX_LIST_ITEMS do return 0, .Invalid, false
		}
	}
	return 0, .Invalid, false
}

@(private)
recovery_workflow_prepare_ui :: proc(
	state: ^Recovery_Workflow_State,
	viewport_items: u32,
) -> (bool, ui.Failure) {
	item_count := recovery_workflow_item_count(state)
	if state == nil || item_count == 0 || viewport_items == 0 || viewport_items > ui.MAX_LIST_ITEMS {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	if state.position.presentation_generation == 0 {
		state.position = {
			presentation_generation = 1,
			selection_owner = .View,
			viewport_items = min(viewport_items, u32(item_count)),
		}
		return true, {}
	}
	state.position.viewport_items = min(viewport_items, u32(item_count))
	state.position.current_item = min(state.position.current_item, i32(item_count - 1))
	state.position.first_visible_item = min(
		state.position.first_visible_item,
		u32(item_count - 1),
	)
	return true, {}
}

@(private)
recovery_workflow_move_ui :: proc(
	state: ^Recovery_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(
		{
			present = true,
			item_count = u32(recovery_workflow_item_count(state)),
			position = state.position,
		},
		delta,
	)
	if ok do state.position = next.position
	return
}

@(private)
recovery_workflow_action_name :: proc(action: recovery.Candidate_Action) -> string {
	switch action {
	case .Restore: return "Restore (open modified buffer)"
	case .Inspect: return "Inspect (open review copy)"
	case .Compare: return "Compare (recovered and saved text)"
	case .Discard: return "Discard (remove checkpoint, keep source)"
	case .Invalid: return "Unavailable"
	}
	return "Unavailable"
}

@(private)
recovery_workflow_state_label :: proc(state: recovery.Candidate_State) -> string {
	switch state {
	case .Restorable: return "saved file unchanged"
	case .Conflict: return "saved file changed"
	case .Pathless: return "untitled buffer"
	case .Missing_Source: return "source file missing"
	case .Inaccessible: return "source file unavailable"
	case .Quarantined: return "checkpoint unavailable"
	case .Invalid: return "unavailable"
	}
	return "unavailable"
}

@(private)
recovery_workflow_age_label :: proc(seconds: u64) -> string {
	if seconds < 60 do return "less than a minute ago"
	if seconds < 3_600 do return fmt.tprintf("%d min ago", seconds / 60)
	if seconds < 86_400 do return fmt.tprintf("%d hr ago", seconds / 3_600)
	return fmt.tprintf("%d days ago", seconds / 86_400)
}

@(private)
recovery_workflow_definitions :: proc(
	state: ^Recovery_Workflow_State,
	allocator: runtime.Allocator,
) -> (items: []ui.List_Item_Definition, storage: []u8, ok: bool) {
	count := recovery_workflow_item_count(state)
	if count == 0 || allocator.procedure == nil do return nil, nil, false
	items_error: runtime.Allocator_Error
	items, items_error = make([]ui.List_Item_Definition, count, allocator)
	if items_error != nil do return nil, nil, false
	storage_error: runtime.Allocator_Error
	storage, storage_error = make([]u8, count * RECOVERY_UI_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(items, allocator)
		return nil, nil, false
	}
	for row in 0 ..< count {
		candidate_index, action, row_ok := recovery_workflow_row(state, row)
		if !row_ok {
			delete(storage, allocator)
			delete(items, allocator)
			return nil, nil, false
		}
		observation := state.discovery.candidates[candidate_index]
		source := observation.source_identity
		if len(source) == 0 do source = "Untitled buffer"
		now_seconds := u64(max(time.to_unix_seconds(time.now()), i64(1)))
		age_seconds := u64(0)
		if now_seconds > observation.created_at_seconds {
			age_seconds = now_seconds - observation.created_at_seconds
		}
		row_storage := storage[row * RECOVERY_UI_ROW_BYTES:(row + 1) * RECOVERY_UI_ROW_BYTES]
		text := fmt.bprintf(
			row_storage,
			"%s — %s [%s; %s] — %s",
			filepath.base(source),
			recovery_workflow_action_name(action),
			recovery_workflow_state_label(observation.candidate.state),
			recovery_workflow_age_label(age_seconds),
			source,
		)
		items[row] = {
			id = ui.List_Item_ID(row + 1),
			text = text,
			action = {
				owner_id = RECOVERY_UI_OWNER_ID,
				action_id = ui.List_Action_ID(row + 1),
				generation = state.model_generation,
			},
		}
	}
	return items, storage, true
}

@(private)
present_recovery_ui :: proc(
	commands: ^Command_Context,
	session: ^terminal.Session,
	renderer: ^terminal.Renderer,
	constraints: display.Viewport_Constraints,
) -> App_Failure {
	state := commands.recovery_workflow
	if state == nil || constraints.width_cells == 0 || constraints.height_rows == 0 {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_List_View}}
	}
	content_rows, rows_ok := transient_input_content_rows(commands, constraints)
	if !rows_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	if prepared, prepare_failure := recovery_workflow_prepare_ui(state, content_rows); !prepared {
		return App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Startup); map_failure.stage != .None {
		return map_failure
	}
	registry, registry_ok, registry_failure := command_context_ui_registry(commands)
	if !registry_ok do return registry_failure
	profile, profile_ok := terminal.renderer_ui_profile(renderer)
	if !profile_ok do return App_Failure{stage = .Presentation, terminal = {code = .Invalid_Renderer}}
	definitions, text_storage, definitions_ok := recovery_workflow_definitions(
		state,
		commands.temporary_allocator,
	)
	if !definitions_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
	defer delete(definitions, commands.temporary_allocator)
	defer delete(text_storage, commands.temporary_allocator)
	proposal, proposal_ok, proposal_failure := ui.proposal_begin(registry, commands.ui_root)
	if !proposal_ok do return App_Failure{stage = .UI, ui = proposal_failure}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok, styles_failure := proposal_resolve_session_theme(&proposal, commands)
	if !styles_ok do return styles_failure
	view, projected, projection_failure := ui.proposal_project_list_view(
		&proposal,
		{
			model = {
				owner_id = RECOVERY_UI_OWNER_ID,
				model_id = RECOVERY_UI_MODEL_ID,
				generation = ui.Model_Generation(state.model_generation),
			},
			position = state.position,
			read_only = true,
		},
		definitions,
	)
	if !projected do return App_Failure{stage = .UI, ui = projection_failure}
	surface, surface_ok, surface_failure := ui.proposal_add_surface(
		&proposal,
		{
			owner_id = RECOVERY_UI_OWNER_ID,
			view = view,
			focusable = true,
			visible = true,
			input_context = 3_010,
			keymap_context = 4_010,
			required_profile = profile.id,
			geometry = {height = i32(content_rows), width = i32(constraints.width_cells)},
		},
	)
	if !surface_ok do return App_Failure{stage = .UI, ui = surface_failure}
	node, node_ok, node_failure := ui.proposal_add_surface_node(&proposal, surface)
	if !node_ok do return App_Failure{stage = .UI, ui = node_failure}
	if transient_feedback_projects_root_edge(commands) {
		if composed, compose_failure := proposal_compose_command_feedback(
			&proposal, commands, node, surface, constraints,
		); !composed do return App_Failure{stage = .UI, ui = compose_failure}
	} else if root_ok, root_failure := ui.proposal_set_root(&proposal, node, surface); !root_ok {
		return App_Failure{stage = .UI, ui = root_failure}
	}
	root, published, publish_failure := ui.proposal_publish(registry, &proposal, profile)
	if !published do return App_Failure{stage = .UI, ui = publish_failure}
	commands.ui_root = root
	snapshot, snapped, snapshot_failure := ui.registry_snapshot(registry, root, profile)
	if !snapped do return App_Failure{stage = .UI, ui = snapshot_failure}
	defer ui.snapshot_close(&snapshot)
	presented, presentation_failure := terminal.renderer_present_ui(
		renderer,
		session,
		{root = &snapshot},
	)
	if !presented do return App_Failure{stage = .Presentation, terminal = presentation_failure}
	return {}
}

@(private)
dispatch_recovery_list_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	state := commands.recovery_workflow
	if state == nil do return {}, App_Failure{stage = .UI}
	if prepared, prepare_failure := recovery_workflow_prepare_ui(state, constraints.height_rows); !prepared {
		return {}, App_Failure{stage = .UI, ui = prepare_failure}
	}
	if map_failure := command_context_sync_list_map(commands, .Startup); map_failure.stage != .None {
		return {}, map_failure
	}
	metadata, resolution, resolved, resolution_failure := command_context_resolve_context_input(commands, input)
	if !resolved do return {}, resolution_failure
	if resolution.kind != .Command do return {}, {}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	if contextual_ok &&
	   (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		delta := i32(1)
		if contextual_route == .Component_Previous_Row do delta = -1
		changed, moved, move_failure := recovery_workflow_move_ui(state, delta)
		if !moved do return {}, App_Failure{stage = .UI, ui = move_failure}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Component_Activate_Current {
		candidate_index, action, row_ok := recovery_workflow_row(state, int(state.position.current_item))
		if !row_ok do return {}, App_Failure{stage = .UI}
		if !recovery_workflow_apply_candidate(state, commands, candidate_index, action) {
			command_context_set_channel_diagnostic(
				commands,
				.Recovery,
				"Recovery action could not be completed",
				.Error,
				attention = .Required,
				retention = .History,
			)
			return Interaction_Result{changed = true}, {}
		}
		state.model_generation += 1
		state.position.presentation_generation += 1
		if action == .Discard && recovery_workflow_item_count(state) > 0 {
			return Interaction_Result{changed = true}, {}
		}
		if action == .Discard {
			return recovery_workflow_leave(state, commands)
		}
		return Interaction_Result{changed = true}, {}
	}
	if contextual_route == .Component_Close || command_metadata_is_native(metadata, .Keyboard_Quit) {
		return recovery_workflow_leave(state, commands)
	}
	return {}, {}
}

@(private)
recovery_workflow_leave :: proc(state: ^Recovery_Workflow_State, commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	switch state.return_target.kind {
	case .Primary_View:
		_, activated, activation_failure := editor_session.session_activate(commands.session_owner, state.return_target.entry)
		if !activated do return {}, App_Failure{stage = .Session_Access, editor_session = activation_failure}
	case .UI_Root:
		_, _, presented, present_failure := editor_session.session_present_ui(commands.session_owner, commands.session_handle, state.return_target.ui)
		if !presented do return {}, App_Failure{stage = .Session_Access, editor_session = present_failure}
	case .None:
		return {}, App_Failure{stage = .Session_Access}
	}
	message := "Retained checkpoint discarded; source file unchanged"
	if recovery_workflow_pending_count(state) > 0 do message = "Unsaved work remains available; M-x recover-unsaved-work to review"
	command_context_set_channel_diagnostic(commands, .Recovery, message)
	return Interaction_Result{changed = true}, {}
}
