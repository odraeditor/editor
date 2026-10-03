// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import ksawery "../ksawery"
import interaction "../interaction"
import ui "../ui"
import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

@(private)
ksawery_inspection_operation_kind :: proc(
	family: ksawery.Inspection_Family,
) -> ksawery.Repository_Operation_Kind {
	switch family {
	case .Stash:    return .Stash
	case .Worktree: return .Worktree
	case .Blame:    return .Blame
	case .Reflog:   return .Reflog
	case .Invalid:  return .Invalid
	}
	return .Invalid
}

@(private)
ksawery_inspection_family_label :: proc(family: ksawery.Inspection_Family) -> string {
	switch family {
	case .Stash:    return "Stashes"
	case .Worktree: return "Worktrees"
	case .Blame:    return "Blame"
	case .Reflog:   return "Reflog"
	case .Invalid:  return "Repository inspection"
	}
	return "Repository inspection"
}

@(private)
ksawery_workflow_start_inspection :: proc(
	commands: ^Command_Context,
	family: ksawery.Inspection_Family,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil || family == .Invalid do return false
	state := commands.ksawery_workflow
	if !state.active || state.view_mode != .Status || state.process.state != nil ||
	   state.observation.state == nil {
		return false
	}
	descriptor, described := ksawery.status_observation_descriptor(&state.observation)
	if !described do return false
	request := ksawery.Inspection_Request {
		repository = descriptor.repository,
		observation_generation = descriptor.generation,
		family = family,
		action = .List,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	target_kind := ksawery.Process_Target_Kind.Repository
	target := ksawery.repository_context_string(&descriptor.repository)
	if family == .Blame {
		_, path, selected, _ := ksawery_workflow_selected_path(state)
		if !selected || !ksawery.inspection_text_assign(&request.target, string(path)) {
			state.failure = .Action_Unavailable
			return false
		}
		request.action = .Inspect
		target_kind = .Path
		target = string(path)
	}
	process, started, failure := ksawery.repository_process_start_inspection_workflow(
		&state.observation,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		return false
	}
	kind := ksawery_inspection_operation_kind(family)
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		descriptor.generation,
		{
			kind = kind,
			target_kind = target_kind,
			title = ksawery_inspection_family_label(family),
			target = target,
			phase_detail = fmt.tprintf("Reading repository %s", ksawery_inspection_family_label(family)),
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return false
	}
	if state.inspection_workflow.state != nil {
		previous, previous_described := ksawery.inspection_observation_descriptor(&state.inspection_workflow)
		if !previous_described || previous.family != family {
			ksawery.inspection_observation_close(&state.inspection_workflow)
		}
	}
	next_generation := state.inspection_generation + 1
	if next_generation == ksawery.Inspection_Generation(0) {
		ksawery.repository_process_close(&process)
		state.failure = .Output_Limit
		return false
	}
	state.process = process
	state.pending = .Inspection_Workflow
	state.inspection_generation = next_generation
	state.inspection_family = family
	state.inspection_selection = 0
	state.inspection_detail_open = false
	state.view_mode = .Inspection_Workflow
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_start_inspection_request :: proc(
	commands: ^Command_Context,
	request: ksawery.Inspection_Request,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.process.state != nil || !ksawery.inspection_request_is_valid(request) do return false
	owned_request := request
	mutating := ksawery.inspection_action_is_mutating(request.action)
	next_generation := state.inspection_generation
	if !mutating {
		next_generation += 1
		if next_generation == ksawery.Inspection_Generation(0) {
			state.failure = .Output_Limit
			return false
		}
	}
	process, started, failure := ksawery.repository_process_start_inspection_workflow(
		&state.observation,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
		&state.inspection_workflow,
	)
	if !started {
		state.failure = failure
		return false
	}
	target := ksawery.repository_context_string(&owned_request.repository)
	target_kind := ksawery.Process_Target_Kind.Repository
	if request.target != {} {
		target = ksawery.inspection_text_string(&owned_request.target)
		if request.family == .Blame do target_kind = .Path
		if request.action == .Visit &&
		   (request.family == .Blame || request.family == .Reflog) {
			target_kind = .Revision
		}
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		request.observation_generation,
		{
			kind = ksawery_inspection_operation_kind(request.family),
			target_kind = target_kind,
			title = fmt.tprintf("%s %v", ksawery_inspection_family_label(request.family), request.action),
			target = target,
			phase_detail = fmt.tprintf("Running checked %s action", ksawery_inspection_family_label(request.family)),
			checking = !mutating,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return false
	}
	state.process = process
	state.pending = .Inspection_Workflow
	state.inspection_request = request
	state.inspection_generation = next_generation
	state.view_mode = .Inspection_Workflow
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_selected_inspection_item :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Inspection_Item, bool) {
	if state == nil || state.inspection_workflow.state == nil do return {}, false
	return ksawery.inspection_observation_item(
		&state.inspection_workflow,
		state.inspection_selection,
	)
}

@(private)
ksawery_workflow_begin_inspection_action :: proc(
	commands: ^Command_Context,
	action: ksawery.Inspection_Action,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.view_mode != .Inspection_Workflow || state.process.state != nil ||
	   state.observation.state == nil || state.inspection_family == .Invalid {
		return false
	}
	descriptor, described := ksawery.status_observation_descriptor(&state.observation)
	if !described do return false
	family_descriptor, family_described := ksawery.inspection_observation_descriptor(&state.inspection_workflow)
	if !family_described || family_descriptor.repository != descriptor.repository ||
	   family_descriptor.status_generation != descriptor.generation ||
	   family_descriptor.family != state.inspection_family {
		state.failure = .Stale_Observation
		return false
	}
	request := ksawery.Inspection_Request {
		repository = descriptor.repository,
		observation_generation = descriptor.generation,
		family_generation = family_descriptor.generation,
		family = state.inspection_family,
		action = action,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	requires_selection := action == .Inspect || action == .Apply || action == .Pop ||
	                      action == .Branch || action == .Drop || action == .Visit ||
	                      action == .Lock || action == .Unlock || action == .Remove
	if requires_selection {
		item, selected := ksawery_workflow_selected_inspection_item(state)
		if !selected {
			state.failure = .Action_Unavailable
			return false
		}
		request.target = item.identity
		if request.family == .Stash || request.family == .Worktree do request.evidence = item.secondary
	}
	if action == .Create || action == .Branch {
		state.inspection_request = request
		state.inspection_input_secondary = action == .Branch
		state.view_mode = .Inspection_Input
		state.position = {}
		return true
	}
	if ksawery.inspection_action_is_mutating(action) {
		state.inspection_request = request
		state.view_mode = .Inspection_Confirmation
		state.position = {}
		return true
	}
	return ksawery_workflow_start_inspection_request(commands, request)
}

@(private)
ksawery_inspection_input_text :: proc(state: ^Ksawery_Workflow_State) -> ^ksawery.Inspection_Text {
	if state == nil do return nil
	if state.inspection_input_secondary do return &state.inspection_request.secondary
	return &state.inspection_request.target
}

@(private)
ksawery_workflow_inspection_input_append :: proc(
	state: ^Ksawery_Workflow_State,
	text: string,
) -> bool {
	value := ksawery_inspection_input_text(state)
	if state == nil || value == nil || state.view_mode != .Inspection_Input || len(text) == 0 ||
	   !utf8.valid_string(text) || int(value.length) + len(text) > len(value.bytes) {
		return false
	}
	for byte in transmute([]u8)text {
		if byte == 0 || byte == '\n' || byte == '\r' || byte == 0x1b || byte == 0x7f do return false
	}
	start := int(value.length)
	copy(value.bytes[start:], transmute([]u8)text)
	value.length += u32(len(text))
	return true
}

@(private)
ksawery_workflow_inspection_input_delete :: proc(state: ^Ksawery_Workflow_State) -> bool {
	value := ksawery_inspection_input_text(state)
	if value == nil || value.length == 0 do return false
	start := int(value.length) - 1
	for start > 0 && value.bytes[start] & 0xc0 == 0x80 do start -= 1
	for index in start ..< int(value.length) do value.bytes[index] = 0
	value.length = u32(start)
	return true
}

@(private)
ksawery_workflow_inspection_input_accept :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Inspection_Input do return false
	value := ksawery_inspection_input_text(state)
	if value == nil || value.length == 0 do return false
	if state.inspection_request.family == .Worktree && state.inspection_request.action == .Create &&
	   !state.inspection_input_secondary {
		state.inspection_input_secondary = true
		return true
	}
	state.view_mode = .Inspection_Confirmation
	state.position = {}
	return true
}

@(private)
ksawery_workflow_confirm_inspection_action :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Inspection_Confirmation do return false
	request := state.inspection_request
	request.confirmed = true
	if !ksawery.inspection_request_is_valid(request) {
		state.failure = .Invalid_Request
		return false
	}
	state.inspection_request = {}
	state.inspection_input_secondary = false
	return ksawery_workflow_start_inspection_request(commands, request)
}

@(private)
ksawery_workflow_cancel_inspection_action :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || (state.view_mode != .Inspection_Input && state.view_mode != .Inspection_Confirmation) {
		return false
	}
	state.inspection_request = {}
	state.inspection_input_secondary = false
	state.view_mode = .Inspection_Workflow
	state.position = {}
	return true
}

@(private)
ksawery_workflow_complete_inspection :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if state.pending != .Inspection_Workflow || state.process.state == nil do return {}, false
	request := state.inspection_request
	if request == {} {
		request = ksawery.Inspection_Request {
			repository = state.repository,
			observation_generation = state.process_coordinator.confirmed_observation,
			family = state.inspection_family,
			action = .List,
			limits = ksawery.DEFAULT_PROCESS_LIMITS,
		}
		if request.family == .Blame do request.action = .Inspect
	}
	if ksawery.inspection_action_is_mutating(request.action) {
		state.inspection_request = {}
		state.inspection_input_secondary = false
		state.inspection_refresh_family = request.family
		verification := Ksawery_Repository_Verification_State.Known_Failure
		if poll.state == .Completed && poll.exit_status == 0 do verification = .Verified
		return ksawery_workflow_prepare_index_refresh_outcome(
			commands,
			.Inspection,
			verification,
			"Refreshing repository evidence after checked action",
			"Repository inspection action could not be verified",
		)
	}
	observation: ksawery.Inspection_Observation
	opened := false
	failure := poll.failure
	if poll.state == .Completed {
		observation, opened, failure = ksawery.repository_process_take_inspection_observation(
			&state.process,
			state.inspection_generation,
			commands.persistent_allocator,
		)
	}
	recorded, record_failure := ksawery_process_observation_finish(
		&state.process_coordinator,
		&state.process,
		opened,
		"Repository inspection available" if opened else "Repository inspection failed",
		ksawery_workflow_now(commands),
	)
	if !recorded do state.process_failure = record_failure
	if opened {
		if state.inspection_workflow.state != nil {
			ksawery.inspection_observation_close(&state.inspection_workflow)
		}
		state.inspection_workflow = observation
		state.inspection_selection = 0
		state.position = {}
		state.failure = .None
	} else {
		state.failure = failure
	}
	state.inspection_request = {}
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = .None,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if !opened else .Preserve,
		diagnostic = "Repository inspection failed" if !opened else "",
	}, true
}

@(private)
ksawery_workflow_return_from_inspection :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Inspection_Workflow do return false
	state.view_mode = .Status
	state.position = {}
	state.inspection_detail_open = false
	return true
}

@(private)
ksawery_workflow_inspection_move :: proc(
	state: ^Ksawery_Workflow_State,
	direction: i32,
) -> bool {
	if state == nil || state.view_mode != .Inspection_Workflow || state.inspection_workflow.state == nil {
		return false
	}
	descriptor, described := ksawery.inspection_observation_descriptor(&state.inspection_workflow)
	if !described || descriptor.item_count == 0 do return false
	current := i32(state.inspection_selection)
	next := current + direction
	if next < 0 do next = i32(descriptor.item_count) - 1
	if next >= i32(descriptor.item_count) do next = 0
	state.inspection_selection = u32(next)
	state.inspection_detail_open = false
	return true
}

@(private)
ksawery_workflow_inspection_toggle_detail :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Inspection_Workflow || state.inspection_workflow.state == nil {
		return false
	}
	_, found := ksawery.inspection_observation_item(
		&state.inspection_workflow,
		state.inspection_selection,
	)
	if !found do return false
	state.inspection_detail_open = !state.inspection_detail_open
	return true
}

@(private)
ksawery_inspection_append_detail_rows :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	detail: []u8,
) {
	offset := 0
	ordinal: u64
	for offset < len(detail) && ordinal < 32 && write^ < len(rows) {
		end := offset
		limit := min(len(detail), offset + KSAWERY_LIST_ROW_BYTES - 10)
		for end < limit && detail[end] != '\n' do end += 1
		if !ksawery_append_presented_label(
			rows, storage, write, ui.List_Item_ID(0xCE20_0000_0000_0000 | ordinal + 1),
			fmt.tprintf("    %s", string(detail[offset:end])), true,
			{surface = .Status, subject = .Operation},
		) {
			return
		}
		ordinal += 1
		offset = end + 1 if end < len(detail) && detail[end] == '\n' else end
	}
}

@(private)
dispatch_ksawery_inspection_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ksawery_workflow == nil do return {}, {}
	state := commands.ksawery_workflow
	if state.view_mode != .Inspection_Workflow || input.kind != .Key ||
	   input.stroke.modifiers != {} {
		return {}, {}
	}
	if input.stroke.kind == .Escape {
		return {changed = ksawery_workflow_return_from_inspection(state)}, {}
	}
	if input.stroke.kind == .Enter {
		return {changed = ksawery_workflow_inspection_toggle_detail(state)}, {}
	}
	if input.stroke.kind != .Unicode_Scalar do return {}, {}
	switch input.stroke.scalar {
	case 'q':
		return {changed = ksawery_workflow_return_from_inspection(state)}, {}
	case 'n':
		return {changed = ksawery_workflow_inspection_move(state, 1)}, {}
	case 'p':
		if state.inspection_family == .Stash {
			return {changed = ksawery_workflow_begin_inspection_action(commands, .Pop)}, {}
		}
		return {changed = ksawery_workflow_inspection_move(state, -1)}, {}
	case 'g':
		if state.process.state != nil do return {}, {}
		family := state.inspection_family
		state.view_mode = .Status
		started := ksawery_workflow_start_inspection(commands, family)
		if !started do state.view_mode = .Inspection_Workflow
		return {changed = started}, {}
	case 'c':
		if state.inspection_family == .Stash || state.inspection_family == .Worktree {
			return {changed = ksawery_workflow_begin_inspection_action(commands, .Create)}, {}
		}
	case 'v':
		action := ksawery.Inspection_Action.Inspect
		if state.inspection_family == .Worktree do action = .Visit
		if state.inspection_family == .Blame || state.inspection_family == .Reflog do action = .Visit
		return {changed = ksawery_workflow_begin_inspection_action(commands, action)}, {}
	case 'a':
		if state.inspection_family == .Stash {
			return {changed = ksawery_workflow_begin_inspection_action(commands, .Apply)}, {}
		}
	case 'P':
		if state.inspection_family == .Worktree {
			return {changed = ksawery_workflow_begin_inspection_action(commands, .Prune)}, {}
		}
	case 'b':
		if state.inspection_family == .Stash {
			return {changed = ksawery_workflow_begin_inspection_action(commands, .Branch)}, {}
		}
	case 'k':
		action := ksawery.Inspection_Action.Drop
		if state.inspection_family == .Worktree do action = .Remove
		return {changed = ksawery_workflow_begin_inspection_action(commands, action)}, {}
	case 'L':
		if state.inspection_family == .Worktree {
			return {changed = ksawery_workflow_begin_inspection_action(commands, .Lock)}, {}
		}
	case 'U':
		if state.inspection_family == .Worktree {
			return {changed = ksawery_workflow_begin_inspection_action(commands, .Unlock)}, {}
		}
	}
	return {}, {}
}

@(private)
dispatch_ksawery_inspection_action_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ksawery_workflow == nil do return {}, {}
	state := commands.ksawery_workflow
	if state.view_mode != .Inspection_Input && state.view_mode != .Inspection_Confirmation {
		return {}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control} {
		return {changed = ksawery_workflow_cancel_inspection_action(state)}, {}
	}
	if state.view_mode == .Inspection_Confirmation {
		if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
		   input.stroke.modifiers == {} {
			switch input.stroke.scalar {
			case 'y': return {changed = ksawery_workflow_confirm_inspection_action(commands)}, {}
			case 'n', 'q': return {changed = ksawery_workflow_cancel_inspection_action(state)}, {}
			}
		}
		return {}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {} {
		return {changed = ksawery_workflow_inspection_input_accept(commands)}, {}
	}
	if input.kind == .Key && (input.stroke.kind == .Backspace || input.stroke.kind == .Delete) {
		return {changed = ksawery_workflow_inspection_input_delete(state)}, {}
	}
	if (input.kind == .Text_Commit || input.kind == .Key) && len(input.text) > 0 &&
	   input.stroke.modifiers == {} {
		return {changed = ksawery_workflow_inspection_input_append(state, input.text)}, {}
	}
	return {}, {}
}

@(private)
ksawery_inspection_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || state.view_mode != .Inspection_Workflow || viewport_items == 0 ||
	   allocator.procedure == nil {
		return nil, nil, false
	}
	row_capacity := 8
	if state.inspection_workflow.state != nil {
		if descriptor, described := ksawery.inspection_observation_descriptor(&state.inspection_workflow); described {
			row_capacity += int(descriptor.item_count) * 2 + 32
		}
	}
	row_capacity = min(row_capacity, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, row_capacity, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xCE00_0000_0000_0001,
		fmt.tprintf("Ksawery %s", ksawery_inspection_family_label(state.inspection_family)), true,
		{surface = .Status, subject = .Operation},
	)
	if state.process.state != nil && state.pending == .Inspection_Workflow {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCE00_0000_0000_0002,
			"Reading checked repository evidence...", true,
			{surface = .Status, subject = .Operation},
		)
	} else if state.inspection_workflow.state != nil {
		descriptor, described := ksawery.inspection_observation_descriptor(&state.inspection_workflow)
		if described && descriptor.item_count == 0 {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xCE00_0000_0000_0003,
				"No entries", true, {surface = .Status, subject = .Operation},
			)
		}
		if described {
			for index in 0 ..< descriptor.item_count {
				item, found := ksawery.inspection_observation_item(&state.inspection_workflow, index)
				if !found do break
				identity := ksawery.inspection_text_string(&item.identity)
				summary := ksawery.inspection_text_string(&item.summary)
				label := identity
				if len(summary) > 0 do label = fmt.tprintf("%s  %s", identity, summary)
				current := index == state.inspection_selection
				row_index := write
				if !ksawery_append_presented_label(
					rows, storage, &write, ui.List_Item_ID(0xCE10_0000_0000_0000 + u64(index)), label, false,
					{surface = .Status, subject = .Operation, current = current},
				) {
					break
				}
				if current do state.position.current_item = i32(row_index)
				if current && state.inspection_detail_open {
					secondary := ksawery.inspection_text_string(&item.secondary)
					if len(secondary) > 0 {
						_ = ksawery_append_presented_label(
							rows, storage, &write, ui.List_Item_ID(0xCE20_0000_0000_0000 + u64(index)),
							secondary, true, {surface = .Status, subject = .Operation},
						)
					}
					if detail, available := ksawery.inspection_observation_detail(&state.inspection_workflow); available {
						ksawery_inspection_append_detail_rows(rows, storage, &write, detail)
					}
				}
			}
		}
	}
	if state.process.state == nil {
		actions := "n/p move; Enter detail; g refresh; q return"
		if state.inspection_family == .Stash {
			actions = "n move; c create; v inspect; a apply; p pop; b branch; k drop; g refresh; q return"
		} else if state.inspection_family == .Worktree {
			actions = "n/p move; c create; v visit; L lock; U unlock; P prune; k remove; g refresh; q return"
		} else if state.inspection_family == .Blame || state.inspection_family == .Reflog {
			actions = "n/p move; Enter detail; v inspect revision; g refresh; q return"
		}
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCE00_0000_0000_00ff,
			fmt.tprintf("Actions: %s", actions), true,
			{surface = .Status, subject = .Operation},
		)
	}
	state.position.presentation_generation = 1
	state.position.selection_owner = .View
	state.position.viewport_items = min(viewport_items, u32(write))
	return rows[:write], storage, true
}

@(private)
ksawery_inspection_action_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || (state.view_mode != .Inspection_Input &&
	   state.view_mode != .Inspection_Confirmation) || viewport_items == 0 ||
	   allocator.procedure == nil {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 6, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, 6 * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	request := &state.inspection_request
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xCE30_0000_0000_0001,
		fmt.tprintf("%s %v", ksawery_inspection_family_label(request.family), request.action), true,
		{surface = .Status, subject = .Operation},
	)
	if state.view_mode == .Inspection_Input {
		label := "Value"
		if request.family == .Stash && request.action == .Create do label = "Stash message"
		if request.family == .Stash && request.action == .Branch do label = "Branch name"
		if request.family == .Worktree && request.action == .Create {
			label = "Worktree path" if !state.inspection_input_secondary else "Revision or branch"
		}
		value := ksawery_inspection_input_text(state)
		value_text := ""
		if value != nil && value.length > 0 do value_text = ksawery.inspection_text_string(value)
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCE30_0000_0000_0002,
			fmt.tprintf("%s: %s", label, value_text), true,
			{surface = .Status, subject = .Operation},
		)
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCE30_0000_0000_0003,
			"Enter continue; C-g cancel", true,
			{surface = .Status, subject = .Operation},
		)
	} else {
		target := ksawery.inspection_text_string(&request.target)
		secondary := ksawery.inspection_text_string(&request.secondary)
		if len(target) > 0 {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xCE30_0000_0000_0004,
				fmt.tprintf("Target: %s", target), true,
				{surface = .Status, subject = .Operation},
			)
		}
		if len(secondary) > 0 {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xCE30_0000_0000_0005,
				fmt.tprintf("Secondary: %s", secondary), true,
				{surface = .Status, subject = .Operation},
			)
		}
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCE30_0000_0000_0006,
			"Confirm checked repository mutation? [y]es [n]o", true,
			{surface = .Status, subject = .Operation, destructive = true},
		)
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = -1,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return rows[:write], storage, true
}
