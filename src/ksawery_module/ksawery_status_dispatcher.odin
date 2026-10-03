// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import command "../command"
import interaction "../interaction"
import ksawery "../ksawery"
import ui "../ui"
import "base:runtime"
import "core:fmt"

Ksawery_Status_Command_Family :: enum u8 {
	Invalid,
	Overview,
	Diff,
	Rebase,
	Merge,
	Remote,
	Clone,
	Ignore,
	Init,
	Submodule,
	Subtree,
	Notes,
	Apply_Patches,
	Format_Patches,
	Sparse_Checkout,
	Stash,
	Worktree,
	Log,
	Blame,
	Targets,
}

@(private)
ksawery_status_command_family_input :: proc(
	input: interaction.Input,
) -> (Ksawery_Status_Command_Family, bool) {
	if input.kind != .Key || input.stroke.kind != .Unicode_Scalar ||
	   input.stroke.modifiers != {} {
		return .Invalid, false
	}
	switch input.stroke.scalar {
	case '?': return .Overview, true
	case 'd': return .Diff, true
	case 'r': return .Rebase, true
	case 'm': return .Merge, true
	case 'M': return .Remote, true
	case 'C': return .Clone, true
	case 'i': return .Ignore, true
	case 'I': return .Init, true
	case 'o': return .Submodule, true
	case 'O': return .Subtree, true
	case 'T': return .Notes, true
	case 'w': return .Apply_Patches, true
	case 'W': return .Format_Patches, true
	case '>': return .Sparse_Checkout, true
	case 'z': return .Stash, true
	case 'Z': return .Worktree, true
	case 'l': return .Log, true
	case 'B': return .Blame, true
	case 'x': return .Targets, true
	}
	return .Invalid, false
}

@(private)
ksawery_status_command_dispatcher_open :: proc(
	state: ^Ksawery_Workflow_State,
	family: Ksawery_Status_Command_Family,
) -> bool {
	if state == nil || family == .Invalid do return false
	if ksawery_status_command_family_is_advanced(family) && state.view_mode != .Status {
		return false
	}
	if family != .Overview && state.view_mode != .Status && state.view_mode != .Refs {
		return false
	}
	switch state.view_mode {
	case .Status, .Refs, .History, .Sequence, .Conflict, .Process, .Provider_Inspection,
	     .Revision_Detail, .Revision_Range:
	case .Inspection_Workflow, .Inspection_Input, .Inspection_Confirmation,
	     .Resource, .Commit_Message, .Raw_Command_Input, .Raw_Command_Confirmation,
	     .Amend_Confirmation, .Push_Confirmation, .Branch_Name, .Branch_Confirmation,
	     .Tag_Name, .Tag_Confirmation, .Merge_Confirmation, .Rebase_Confirmation,
	     .Revision_Sequence_Confirmation, .Bisect_Confirmation, .Conflict_Confirmation,
	     .Extension_Command, .Status_Command_Dispatcher:
		return false
	}
	state.status_command_family = family
	state.status_command_return_mode = state.view_mode
	state.status_command_return_position = state.position
	state.view_mode = .Status_Command_Dispatcher
	state.position = {}
	return true
}

@(private)
ksawery_status_command_family_is_advanced :: proc(
	family: Ksawery_Status_Command_Family,
) -> bool {
	switch family {
	case .Clone, .Ignore, .Init, .Submodule, .Subtree, .Notes,
	     .Apply_Patches, .Format_Patches, .Sparse_Checkout:
		return true
	case .Invalid, .Overview, .Diff, .Rebase, .Merge, .Remote,
	     .Stash, .Worktree, .Log, .Blame, .Targets:
		return false
	}
	return false
}

@(private)
ksawery_status_command_dispatcher_restore :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Status_Command_Dispatcher do return false
	state.view_mode = state.status_command_return_mode
	state.position = state.status_command_return_position
	state.status_command_family = .Invalid
	state.status_command_return_mode = .Status
	state.status_command_return_position = {}
	return true
}

@(private)
ksawery_status_command_dispatcher_input :: proc(
	state: ^Ksawery_Workflow_State,
	input: interaction.Input,
) -> (route: command.Contextual_Route, handled, changed: bool) {
	if state == nil || state.view_mode != .Status_Command_Dispatcher do return .Invalid, false, false
	if input.kind == .Key &&
	   ((input.stroke.kind == .Unicode_Scalar && input.stroke.scalar == 'g' &&
	     input.stroke.modifiers == {.Control}) ||
	    (input.stroke.kind == .Escape && input.stroke.modifiers == {})) {
		return .Invalid, true, ksawery_status_command_dispatcher_restore(state)
	}
	if input.kind != .Key || input.stroke.kind != .Unicode_Scalar || input.stroke.modifiers != {} {
		return .Invalid, true, false
	}
	key := input.stroke.scalar
	if key == 'q' {
		return .Invalid, true, ksawery_status_command_dispatcher_restore(state)
	}
	if key == 'g' {
		_ = ksawery_status_command_dispatcher_restore(state)
		return .Result_Refresh, true, true
	}
	family, family_input := ksawery_status_command_family_input(input)
	switch state.status_command_family {
	case .Diff:
		if key == 'd' do route = .Component_Complete_Current
	case .Rebase:
		switch key {
		case 'r': route = .Ksawery_Rebase
		case 'a': route = .Ksawery_Rebase_Autosquash
		case 'c': route = .Ksawery_Rebase_Continue
		case 's': route = .Ksawery_Rebase_Skip
		case 'A': route = .Ksawery_Rebase_Abort
		}
	case .Merge:
		switch key {
		case 'f': route = .Ksawery_Merge_Fast_Forward
		case 'm': route = .Ksawery_Merge
		case 'n': route = .Ksawery_Merge_No_Fast_Forward
		case 'c': route = .Ksawery_Merge_Continue
		case 'a': route = .Ksawery_Merge_Abort
		}
	case .Remote:
		switch key {
		case 'b': route = .Ksawery_Refs
		case 'f': route = .Ksawery_Fetch
		case 'p': route = .Ksawery_Push
		}
	case .Targets:
		switch key {
		case 'm': route = .Ksawery_Mark
		case 'u': route = .Ksawery_Unmark
		case 'c': route = .Ksawery_Clear_Marks
		case 'd': route = .Ksawery_Discard
		}
	case .Stash:
		if key == 'l' || key == 'z' do route = .Ksawery_Stashes
	case .Worktree:
		if key == 'l' || key == 'Z' do route = .Ksawery_Worktrees
	case .Log:
		if key == 'r' do route = .Ksawery_Reflog
	case .Blame:
		if key == 'b' || key == 'B' do route = .Ksawery_Blame
	case .Clone:
		switch key {
		case 'C': state.advanced_workflow = .Clone
		case 's': state.advanced_workflow = .Clone_Shallow
		case 'b': state.advanced_workflow = .Clone_Bare
		case 'm': state.advanced_workflow = .Clone_Mirror
		}
	case .Ignore:
		switch key {
		case 't': state.advanced_workflow = .Ignore_Shared
		case 'p': state.advanced_workflow = .Ignore_Private
		}
	case .Init:
		if key == 'I' do state.advanced_workflow = .Init
	case .Submodule:
		switch key {
		case 'a': state.advanced_workflow = .Submodule_Add
		case 'l': state.advanced_workflow = .Submodule_List
		case 'u': state.advanced_workflow = .Submodule_Update
		case 's': state.advanced_workflow = .Submodule_Sync
		case 'd': state.advanced_workflow = .Submodule_Deinit
		}
	case .Subtree:
		switch key {
		case 'a': state.advanced_workflow = .Subtree_Add
		case 'm': state.advanced_workflow = .Subtree_Merge
		case 'f': state.advanced_workflow = .Subtree_Pull
		case 'p': state.advanced_workflow = .Subtree_Push
		case 's': state.advanced_workflow = .Subtree_Split
		}
	case .Notes:
		switch key {
		case 'a': state.advanced_workflow = .Notes_Add
		case 'r': state.advanced_workflow = .Notes_Remove
		case 'p': state.advanced_workflow = .Notes_Prune
		}
	case .Apply_Patches:
		switch key {
		case 'a': state.advanced_workflow = .Mail_Apply
		case 'p': state.advanced_workflow = .Patch_Apply
		}
	case .Format_Patches:
		switch key {
		case 'c': state.advanced_workflow = .Patch_Create
		case 's': state.advanced_workflow = .Patch_Save
		case 'r': state.advanced_workflow = .Request_Pull
		}
	case .Sparse_Checkout:
		switch key {
		case 'e': state.advanced_workflow = .Sparse_Enable
		case 'd': state.advanced_workflow = .Sparse_Disable
		case 'r': state.advanced_workflow = .Sparse_Reapply
		case 's': state.advanced_workflow = .Sparse_Set
		case 'a': state.advanced_workflow = .Sparse_Add
		}
	case .Overview, .Invalid:
	}
	if state.advanced_workflow != .Invalid {
		route = .Ksawery_Raw_Command
	}
	if route == .Invalid && family_input && family != state.status_command_family {
		state.status_command_family = family
		state.position = {}
		return .Invalid, true, true
	}
	if route == .Invalid do return .Invalid, true, false
	_ = ksawery_status_command_dispatcher_restore(state)
	return route, true, true
}

@(private)
ksawery_status_command_family_label :: proc(family: Ksawery_Status_Command_Family) -> string {
	switch family {
	case .Overview: return "Commands"
	case .Diff:     return "Diff"
	case .Rebase:   return "Rebase"
	case .Merge:    return "Merge"
	case .Remote:   return "Remote"
	case .Clone:    return "Clone"
	case .Ignore:   return "Ignore"
	case .Init:     return "Init"
	case .Submodule: return "Submodule"
	case .Subtree:  return "Subtree"
	case .Notes:    return "Notes"
	case .Apply_Patches: return "Apply patches"
	case .Format_Patches: return "Format patches"
	case .Sparse_Checkout: return "Sparse checkout"
	case .Stash:    return "Stash"
	case .Worktree: return "Worktree"
	case .Log:      return "Log"
	case .Blame:    return "Blame"
	case .Targets:  return "Target actions"
	case .Invalid:  return "Commands"
	}
	return "Commands"
}

@(private)
ksawery_status_command_availability :: proc(
	state: ^Ksawery_Workflow_State,
	family: Ksawery_Status_Command_Family,
) -> bool {
	if state == nil || state.process.state != nil do return false
	switch family {
	case .Overview:
		return true
	case .Diff, .Targets, .Blame:
		if state.status_command_return_mode != .Status || state.observation.state == nil do return false
		_, selected, _ := ksawery.status_selection_path_target(&state.observation, state.selection)
		return selected
	case .Rebase:
		if state.status_command_return_mode == .Sequence do return true
		if state.status_command_return_mode != .Refs || state.refs.state == nil do return false
		_, selected := ksawery_workflow_selected_rebase_base(state)
		return selected
	case .Merge:
		if state.status_command_return_mode == .Sequence do return true
		if state.status_command_return_mode != .Refs || state.refs.state == nil do return false
		_, selected := ksawery_workflow_selected_merge_source(state)
		return selected
	case .Remote:
		return state.status_command_return_mode == .Refs && state.refs.state != nil &&
		       ksawery.ref_selection_is_current(&state.refs, state.ref_selection) &&
		       state.ref_selection.current.kind == .Remote
	case .Clone, .Ignore, .Init, .Submodule, .Subtree, .Notes,
	     .Apply_Patches, .Format_Patches, .Sparse_Checkout,
	     .Stash, .Worktree, .Log:
		return state.status_command_return_mode == .Status && state.observation.state != nil
	case .Invalid:
		return false
	}
	return false
}

@(private)
ksawery_status_command_append_row :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	id: ui.List_Item_ID,
	label: string,
	passive := false,
) -> bool {
	return ksawery_append_presented_label(
		rows,
		storage,
		write,
		id,
		label,
		passive,
		{surface = .Status, subject = .Operation},
	)
}

@(private)
ksawery_status_command_dispatcher_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || state.view_mode != .Status_Command_Dispatcher ||
	   viewport_items == 0 || allocator.procedure == nil {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 24, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, 24 * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	family := state.status_command_family
	if family == .Invalid do family = .Overview
	available := ksawery_status_command_availability(state, family)
	availability := "unavailable"
	if available do availability = "available"
	if !ksawery_status_command_append_row(
		rows,
		storage,
		&write,
		0xCD00_0000_0000_0001,
		fmt.tprintf("Ksawery %s", ksawery_status_command_family_label(family)),
		true,
	) || !ksawery_status_command_append_row(
		rows,
		storage,
		&write,
		0xCD00_0000_0000_0002,
		fmt.tprintf("State: %s; ? index; q return", availability),
		true,
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	switch family {
	case .Overview:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0010, "g Refresh — available on repository surfaces; effect: replace the checked observation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0011, "d Diff — requires a selected Status change; effect: inspect only")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0012, "r Rebase — requires a selected commit-backed ref; effect: checked repository mutation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0013, "m Merge — requires a selected commit-backed ref; effect: checked repository mutation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0014, "M Remote — requires Refs and a selected remote; effect: checked network operation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0015, "C Clone — checked clone variants with an explicit source and destination")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0016, "x Target actions — requires a selected Status change; destructive actions confirm")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0017, "z Stash — list, inspect, and checked stash actions")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0018, "Z Worktree — list, visit, and checked worktree actions")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0019, "l Log — history and reflog inspection")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_001a, "B Blame — requires a selected Status path; effect: bounded attribution")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_001b, "i/I Ignore and Init — edit repository ignore policy or initialize an explicit destination")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_001c, "o/O Submodule and Subtree — reviewed structure operations; subtree requires Git support")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_001d, "T Notes — add, remove, or prune Git notes through reviewed arguments")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_001e, "w/W Patches — apply mail or patches, create patches, save diffs, or request pull")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_001f, "> Sparse checkout — enable, disable, reapply, set, or add directories")
	case .Diff:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0020, "d Inspect selected change — requires Status selection; effect: open or close bounded detail")
	case .Rebase:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0030, "r Rebase — selected ref; preview and confirmation precede mutation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0031, "a Autosquash — selected ref and complete History; reviewed plan precedes mutation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0032, "c Continue — active checked rebase sequence; effect: continue")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0033, "s Skip — active checked rebase sequence; effect: skip current commit")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0034, "A Abort — active checked rebase sequence; confirmation precedes mutation")
	case .Merge:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0040, "f Fast-forward only — selected ref; confirmation precedes mutation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0041, "m Merge — selected ref; merge commit permitted after confirmation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0042, "n No fast-forward — selected ref; merge commit required after confirmation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0043, "c Continue — active checked merge sequence; effect: continue")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0044, "a Abort — active checked merge sequence; confirmation precedes mutation")
	case .Remote:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0050, "b Browse remotes — effect: open checked Refs observation")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0051, "f Fetch — selected remote; effect: checked network update")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0052, "p Push — selected remote and marked local branch; confirmation precedes network mutation")
	case .Clone:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0060, "C Regular; s shallow; b bare; m mirror — enter source and explicit destination, then review")
	case .Ignore:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0061, "t Open the repository .gitignore; p open .git/info/exclude")
	case .Init:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0062, "I Initialize — enter an explicit destination path, then review")
	case .Submodule:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0063, "a Add; l list; u update; s synchronize; d deinitialize")
	case .Subtree:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0064, "a Add; m merge; f pull; p push; s split — requires git-subtree availability")
	case .Notes:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0065, "a Add with message; r remove; p prune — enter remaining arguments, then review")
	case .Apply_Patches:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0066, "a Apply mail with git am; p apply a plain patch — enter a local path")
	case .Format_Patches:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0067, "c Create format-patch output; s save diff; r create request-pull text")
	case .Sparse_Checkout:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0068, "e Enable cone mode; d disable; r reapply; s set; a add directories")
	case .Targets:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0070, "m Mark selected target — effect: update the checked target set")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0071, "u Unmark selected target — effect: update the checked target set")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0072, "c Clear marks — effect: empty the checked target set")
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0073, "d Discard selected tracked change — destructive; preview and confirmation required")
	case .Stash:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0080, "l List stashes — checked bounded repository observation")
	case .Worktree:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_0090, "l List worktrees — checked bounded repository observation")
	case .Log:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_00a0, "r Reflog — checked bounded repository history")
	case .Blame:
		_ = ksawery_status_command_append_row(rows, storage, &write, 0xCD00_0000_0000_00b0, "b Blame selected path — bounded exact commit attribution")
	case .Invalid:
	}
	first_visible_item := u32(0)
	if viewport_items <= 2 do first_visible_item = 2
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = 2,
		first_visible_item = first_visible_item,
		viewport_items = min(viewport_items, u32(write)),
	}
	return rows[:write], storage, true
}
