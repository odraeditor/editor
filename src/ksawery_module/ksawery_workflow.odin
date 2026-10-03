// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module

import "../command"
import "../interaction"
import "../ksawery"
import "../ksawery_command"
import "../product_module"
import "../display"
import "../ui"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:time"
import "core:unicode/utf8"

/* KSAWERY_LIST_ROW_BYTES bounds one presentation-safe Status row. */
KSAWERY_LIST_ROW_BYTES :: 320
/* KSAWERY_DIAGNOSTIC_BYTES bounds one module-owned user diagnostic. */
KSAWERY_DIAGNOSTIC_BYTES :: 512
/* KSAWERY_DIAGNOSTIC_LIST_ITEM_ID reserves one cross-surface passive diagnostic row. */
KSAWERY_DIAGNOSTIC_LIST_ITEM_ID :: ui.List_Item_ID(0xFFFF_FFFF_FFFF_FFFE)

/* KSAWERY_UI_OWNER_ID identifies the full-canvas repository-session owner. */
KSAWERY_UI_OWNER_ID :: ui.Owner_ID(10_012)
/* KSAWERY_UI_MODEL_ID identifies the initial repository-status model. */
KSAWERY_UI_MODEL_ID :: ui.Model_ID(10_012)
/* KSAWERY_UI_TARGET_GENERATION identifies the stable Status session target. */
KSAWERY_UI_TARGET_GENERATION :: u64(1)
/* KSAWERY_LIST_SELECT_ACTION identifies semantic Status row selection. */
KSAWERY_LIST_SELECT_ACTION :: ui.List_Action_ID(1)

@(private)
Ksawery_Pending_Operation :: enum u8 {
	None,
	Observe,
	Refresh,
	Sequence_Observe,
	History_Observe,
	History_Refresh,
	History_Next,
	Refs_Observe,
	Refs_Refresh,
	Remote_Configuration,
	Fetch,
	Push_Configuration,
	Push,
	Branch,
	Tag,
	Merge_Precondition,
	Merge,
	Rebase_Precondition,
	Rebase,
	Revision_Sequence_Precondition,
	Revision_Sequence,
	Bisect_Precondition,
	Bisect,
	Conflict_Precondition,
	Conflict_Resolution,
	Conflict_Assistance,
	Extension_Operation,
	Raw_Command,
	Revision_Detail_Metadata,
	Revision_Detail_Comparison,
	Revision_Range_Summary,
	Revision_Range_Comparison,
	Inspection_Workflow,
	Detail,
	Index_Action,
	Partial_Index_Action,
	Grouped_Index_Action,
	Discard_Action,
	Commit_Precondition,
	Commit,
}

@(private)
Ksawery_Pending_Family :: enum u8 {
	Invalid,
	Idle_And_Local,
	Raw_Command,
	Repository_Observation,
	Sequence_Coordination,
	History,
	Refs_And_Synchronization,
	Commit,
	Revision_Inspection,
	Inspection_Workflow,
	Changes_And_Index,
}

@(private)
Ksawery_Workflow_Process_Disposition :: enum u8 {
	Invalid,
	Retain,
	Close,
	Replace,
}

@(private)
Ksawery_Workflow_Resolution_Intent :: enum u8 {
	Invalid,
	Preserve,
	Handler_Published,
	Handler_Cleared,
}

@(private)
Ksawery_Workflow_Refresh_Continuation :: enum u8 {
	Invalid,
	None,
	Continue_After_Status,
	Advance_Raw_Command,
	Complete_Repository_Observation,
	Start_Mutation_Refresh,
	Start_Commit_Refresh,
	Complete_History,
	Complete_Refs,
	Complete_Synchronization,
	Complete_Sequence,
}

@(private)
Ksawery_Workflow_Observation_Result :: enum u8 {
	None,
	Applied,
	Unavailable,
	Process_Failed,
	Grouping_Unavailable,
}

@(private)
Ksawery_Workflow_History_Result :: enum u8 {
	None,
	Applied,
	Unavailable,
	Process_Failed,
}

@(private)
Ksawery_Workflow_Refs_Result :: enum u8 {
	None,
	Applied,
	Unavailable,
	Process_Failed,
}

@(private)
Ksawery_Workflow_Synchronization_Result :: enum u8 {
	None,
	Start_Prepared_Fetch,
	Prepare_Push_Confirmation,
	Finish_Fetch,
	Start_Fetch_Refresh,
	Finish_Push,
	Start_Push_Refresh,
	Finish_Branch,
	Start_Branch_Refresh,
	Finish_Tag,
	Start_Tag_Refresh,
}

@(private)
Ksawery_Workflow_Sequence_Result :: enum u8 {
	None,
	Prepare_Merge_Confirmation,
	Prepare_Rebase_Confirmation,
	Prepare_Revision_Sequence_Confirmation,
	Prepare_Bisect_Confirmation,
	Prepare_Conflict_Confirmation,
	Start_Mutation_Refresh,
	Start_Revision_Sequence_Refresh,
	Start_Bisect_Refresh,
	Observation_Applied,
	Observation_Unavailable,
	Observation_Process_Failed,
}

@(private)
Ksawery_Workflow_Presentation_Intent :: enum u8 {
	Invalid,
	Preserve,
	Handler_Applied,
}

@(private)
Ksawery_Workflow_Diagnostic_Intent :: enum u8 {
	Invalid,
	Preserve,
	Publish,
}

@(private)
Ksawery_Workflow_Completion_Outcome :: struct {
	consumed:             bool,
	changed:              bool,
	next_pending:         Ksawery_Pending_Operation,
	process:              Ksawery_Workflow_Process_Disposition,
	replacement_process:  ksawery.Repository_Process,
	resolution:           Ksawery_Workflow_Resolution_Intent,
	refresh:              Ksawery_Workflow_Refresh_Continuation,
	observation_result:   Ksawery_Workflow_Observation_Result,
	history_result:       Ksawery_Workflow_History_Result,
	refs_result:          Ksawery_Workflow_Refs_Result,
	synchronization_result: Ksawery_Workflow_Synchronization_Result,
	synchronization_failed: bool,
	sequence_result:       Ksawery_Workflow_Sequence_Result,
	mutation_refresh:     Ksawery_Mutation_Refresh,
	presentation:         Ksawery_Workflow_Presentation_Intent,
	diagnostic_intent:    Ksawery_Workflow_Diagnostic_Intent,
	diagnostic:           string,
}

@(private)
ksawery_workflow_completion_outcome_is_valid :: proc(
	outcome: ^Ksawery_Workflow_Completion_Outcome,
	state: ^Ksawery_Workflow_State,
) -> bool {
	if outcome == nil || state == nil do return false
	if !outcome.consumed || !outcome.changed ||
	   outcome.process == .Invalid || outcome.resolution == .Invalid ||
	   outcome.refresh == .Invalid || outcome.presentation == .Invalid ||
	   outcome.diagnostic_intent == .Invalid {
		return false
	}
	if ksawery_pending_operation_family(outcome.next_pending) == .Invalid do return false
	if outcome.process == .Replace {
		if outcome.replacement_process.state == nil || outcome.next_pending == .None do return false
	} else if outcome.replacement_process.state != nil {
		return false
	}
	if outcome.process == .Close && outcome.next_pending != .None do return false
	if outcome.diagnostic_intent == .Publish {
		if len(outcome.diagnostic) == 0 do return false
	} else if len(outcome.diagnostic) != 0 {
		return false
	}
	if outcome.refresh != .None && outcome.next_pending != .None do return false
	if outcome.refresh == .Complete_Repository_Observation {
		if outcome.observation_result == .None do return false
	} else if outcome.observation_result != .None {
		return false
	}
	if outcome.refresh == .Start_Mutation_Refresh {
		if outcome.mutation_refresh == .None do return false
	} else if outcome.mutation_refresh != .None {
		return false
	}
	if outcome.refresh == .Complete_History {
		if outcome.history_result == .None do return false
	} else if outcome.history_result != .None {
		return false
	}
	if outcome.refresh == .Complete_Refs {
		if outcome.refs_result == .None do return false
	} else if outcome.refs_result != .None {
		return false
	}
	if outcome.refresh == .Complete_Synchronization {
		if outcome.synchronization_result == .None do return false
	} else if outcome.synchronization_result != .None || outcome.synchronization_failed {
		return false
	}
	if outcome.refresh == .Complete_Sequence {
		if outcome.sequence_result == .None do return false
		#partial switch outcome.sequence_result {
		case .Prepare_Merge_Confirmation:
			if !ksawery.merge_precondition_is_valid(state.merge_precondition) do return false
		case .Prepare_Rebase_Confirmation:
			if !ksawery.rebase_precondition_is_valid(state.rebase_precondition) do return false
		case .Prepare_Revision_Sequence_Confirmation:
			if !ksawery.revision_sequence_precondition_is_valid(
				state.revision_sequence_precondition,
			) {
				return false
			}
		case .Prepare_Bisect_Confirmation:
			if !ksawery.bisect_precondition_is_valid(state.bisect_precondition) do return false
		case .Prepare_Conflict_Confirmation:
			if !ksawery.conflict_resolution_precondition_is_valid(
				state.conflict_precondition,
			) {
				return false
			}
		case .Start_Mutation_Refresh, .Start_Revision_Sequence_Refresh,
		     .Start_Bisect_Refresh, .Observation_Applied, .Observation_Unavailable,
		     .Observation_Process_Failed:
		case .None:
			return false
		}
	} else if outcome.sequence_result != .None {
		return false
	}
	if outcome.synchronization_failed {
		#partial switch outcome.synchronization_result {
		case .Finish_Fetch, .Finish_Push, .Finish_Branch, .Finish_Tag:
		case:
			return false
		}
	}
	return true
}

@(private)
ksawery_pending_operation_family :: proc(
	operation: Ksawery_Pending_Operation,
) -> Ksawery_Pending_Family {
	switch operation {
	case .None, .Conflict_Assistance, .Extension_Operation:
		return .Idle_And_Local
	case .Raw_Command:
		return .Raw_Command
	case .Observe, .Refresh:
		return .Repository_Observation
	case .Sequence_Observe, .Merge_Precondition, .Merge, .Rebase_Precondition, .Rebase,
	     .Revision_Sequence_Precondition, .Revision_Sequence, .Bisect_Precondition, .Bisect,
	     .Conflict_Precondition, .Conflict_Resolution:
		return .Sequence_Coordination
	case .History_Observe, .History_Refresh, .History_Next:
		return .History
	case .Refs_Observe, .Refs_Refresh, .Remote_Configuration, .Fetch, .Push_Configuration,
	     .Push, .Branch, .Tag:
		return .Refs_And_Synchronization
	case .Commit_Precondition, .Commit:
		return .Commit
	case .Revision_Detail_Metadata, .Revision_Detail_Comparison, .Revision_Range_Summary,
	     .Revision_Range_Comparison:
		return .Revision_Inspection
	case .Inspection_Workflow:
		return .Inspection_Workflow
	case .Detail, .Index_Action, .Partial_Index_Action, .Grouped_Index_Action, .Discard_Action:
		return .Changes_And_Index
	}
	return .Invalid
}

@(private)
Ksawery_View_Mode :: enum u8 {
	Status,
	Sequence,
	Conflict,
	History,
	Refs,
	Process,
	Provider_Inspection,
	Revision_Detail,
	Revision_Range,
	Inspection_Workflow,
	Inspection_Input,
	Inspection_Confirmation,
	Resource,
	Commit_Message,
	Raw_Command_Input,
	Raw_Command_Confirmation,
	Amend_Confirmation,
	Push_Confirmation,
	Branch_Name,
	Branch_Confirmation,
	Tag_Name,
	Tag_Confirmation,
	Merge_Confirmation,
	Rebase_Confirmation,
	Revision_Sequence_Confirmation,
	Bisect_Confirmation,
	Conflict_Confirmation,
	Extension_Command,
	Status_Command_Dispatcher,
}

@(private)
Ksawery_Commit_Refresh :: enum u8 {
	None,
	Status,
	History,
}

@(private)
Ksawery_Raw_Command_Refresh :: enum u8 {
	None,
	Status,
	History,
	Refs,
	Sequence,
}

@(private)
Ksawery_Advanced_Workflow :: enum u8 {
	Invalid,
	Clone,
	Clone_Shallow,
	Clone_Bare,
	Clone_Mirror,
	Ignore_Shared,
	Ignore_Private,
	Init,
	Submodule_Add,
	Submodule_List,
	Submodule_Update,
	Submodule_Sync,
	Submodule_Deinit,
	Subtree_Add,
	Subtree_Merge,
	Subtree_Pull,
	Subtree_Push,
	Subtree_Split,
	Notes_Add,
	Notes_Remove,
	Notes_Prune,
	Mail_Apply,
	Patch_Apply,
	Patch_Create,
	Patch_Save,
	Request_Pull,
	Sparse_Enable,
	Sparse_Disable,
	Sparse_Reapply,
	Sparse_Set,
	Sparse_Add,
}

@(private)
Ksawery_Conflict_Assistance_Refresh :: enum u8 {
	None,
	Status,
	Sequence,
}

@(private)
Ksawery_Extension_Operation_Refresh :: enum u8 {
	None,
	Status,
	History,
	Refs,
	Sequence,
}

@(private)
Ksawery_Mutation_Refresh :: enum u8 {
	None,
	Index,
	Partial_Index,
	Grouped_Index,
	Discard,
	Inspection,
}

@(private)
Ksawery_Fetch_Refresh :: enum u8 {
	None,
	Refs,
	Status,
	History,
}

@(private)
Ksawery_Push_Refresh :: enum u8 {
	None,
	Refs,
	Status,
	History,
}

@(private)
Ksawery_Branch_Refresh :: enum u8 {
	None,
	Refs,
	Status,
	History,
}

@(private)
Ksawery_Tag_Refresh :: enum u8 {
	None,
	Refs,
	Status,
	History,
}

@(private)
Ksawery_Revision_Staging :: struct {
	metadata:  [dynamic]u8,
	summary:   [dynamic]u8,
	allocator: runtime.Allocator,
}

@(private)
Ksawery_Revision_Sequence_Selection :: struct {
	targets:   [dynamic]ksawery.Revision_Sequence_Target,
	allocator: runtime.Allocator,
}

@(private)
Ksawery_Workflow_State :: struct {
	active:      bool,
	allocator:   runtime.Allocator,
	extension_registry: Ksawery_Extension_Provider_Registry,
	extension_command_workflow: Ksawery_Extension_Command_Workflow,
	extension_command_family: ^ksawery_command.Ksawery_Command_Family_State,
	extension_command_route: ksawery_command.Ksawery_Extension_Command_Route,
	extension_command_name: [interaction.MAX_COMMAND_NAME_BYTES]u8,
	extension_command_name_length: u16,
	extension_command_return_mode: Ksawery_View_Mode,
	extension_command_completion_mode: Ksawery_View_Mode,
	extension_command_return_position: ui.List_View_Position,
	extension_command_cursor: u16,
	extension_command_text_editing: bool,
	extension_command_text: [ksawery.MAX_EXTENSION_COMMAND_VALUE_BYTES]u8,
	extension_command_text_length: u16,
	status_command_family: Ksawery_Status_Command_Family,
	status_command_return_mode: Ksawery_View_Mode,
	status_command_return_position: ui.List_View_Position,
	advanced_workflow: Ksawery_Advanced_Workflow,
	extension_operation: ^Ksawery_Extension_Operation_Workflow,
	extension_operation_refresh: Ksawery_Extension_Operation_Refresh,
	extension_operation_refresh_completed: ksawery.Extension_Observation_Families,
	extension_operation_return_mode: Ksawery_View_Mode,
	extension_operation_return_position: ui.List_View_Position,
	provider_inspection_return_mode: Ksawery_View_Mode,
	provider_inspection_return_position: ui.List_View_Position,
	next_extension_command_request: ksawery.Extension_Command_Request_ID,
	next_extension_command_confirmation: ksawery.Extension_Command_Confirmation_ID,
	previous:    u64,
	command:     interaction.Command_Handle,
	repository:  ksawery.Repository_Context,
	process:     ksawery.Repository_Process,
	process_coordinator: Ksawery_Process_Coordinator,
	pending:     Ksawery_Pending_Operation,
	observation: ksawery.Status_Observation,
	generation:  ksawery.Observation_Generation,
	sequence:    ksawery.Sequence_Observation,
	sequence_generation: ksawery.Sequence_Generation,
	sequence_failure: ksawery.Failure_Code,
	sequence_process_recorded: bool,
	conflict_selection: ksawery.Conflict_ID,
	conflict_assistance: ^Ksawery_Conflict_Assistance_Workflow,
	conflict_assistance_request: ksawery.Conflict_Assistance_Request_ID,
	conflict_assistance_selection_generation: ksawery.Conflict_Assistance_Selection_Generation,
	conflict_assistance_refresh: Ksawery_Conflict_Assistance_Refresh,
	conflict_assistance_refresh_completed: ksawery.Extension_Observation_Families,
	history:     ksawery.History_Observation,
	history_generation: ksawery.History_Generation,
	refs:        ksawery.Ref_Observation,
	ref_generation: ksawery.Ref_Generation,
	revision_detail: ksawery.Revision_Detail,
	revision_range: ksawery.Revision_Range_Observation,
	revision_detail_request: ksawery.Revision_Detail_Request,
	revision_range_request: ksawery.Revision_Range_Request,
	inspection_workflow: ksawery.Inspection_Observation,
	inspection_generation: ksawery.Inspection_Generation,
	inspection_family: ksawery.Inspection_Family,
	inspection_selection: u32,
	inspection_detail_open: bool,
	inspection_request: ksawery.Inspection_Request,
	inspection_input_secondary: bool,
	inspection_refresh_family: ksawery.Inspection_Family,
	revision_staging: ^Ksawery_Revision_Staging,
	failure:     ksawery.Failure_Code,
	diagnostic: [KSAWERY_DIAGNOSTIC_BYTES]u8,
	diagnostic_length: u16,
	selection:   ksawery.Status_Selection,
	extension_status:           ^ksawery.Extension_Status_Generation,
	extension_status_selection: Ksawery_Extension_Status_Selection,
	extension_annotation_selection: Ksawery_Extension_Annotation_Selection,
	history_selection: ksawery.History_Selection,
	ref_selection:     ksawery.Ref_Selection,
	process_selection: ksawery.Process_Selection,
	process_return_mode: Ksawery_View_Mode,
	process_return_position: ui.List_View_Position,
	process_detail_open: bool,
	process_failure: ksawery.Failure_Code,
	fetch_configuration: ksawery.Remote_Configuration_Identity,
	fetch_request:       ksawery.Fetch_Request,
	fetch_result:        ksawery.Fetch_Result,
	fetch_refresh:       Ksawery_Fetch_Refresh,
	push_configuration:  ksawery.Push_Configuration_Identity,
	push_precondition:   ksawery.Push_Precondition,
	push_confirmation:   ksawery.Push_Confirmation,
	push_request:        ksawery.Push_Request,
	push_result:         ksawery.Push_Result,
	push_refresh:        Ksawery_Push_Refresh,
	branch_intent:       ksawery.Branch_Intent,
	branch_precondition: ksawery.Branch_Precondition,
	branch_confirmation: ksawery.Branch_Confirmation,
	branch_request:      ksawery.Branch_Request,
	branch_result:       ksawery.Branch_Result,
	branch_refresh:      Ksawery_Branch_Refresh,
	branch_draft:        [ksawery.MAX_LOCAL_BRANCH_NAME_BYTES]u8,
	branch_draft_length: u16,
	tag_intent:       ksawery.Tag_Intent,
	tag_precondition: ksawery.Tag_Precondition,
	tag_confirmation: ksawery.Tag_Confirmation,
	tag_request:      ksawery.Tag_Request,
	tag_result:       ksawery.Tag_Result,
	tag_refresh:      Ksawery_Tag_Refresh,
	tag_draft:        [ksawery.MAX_LOCAL_TAG_NAME_BYTES]u8,
	tag_draft_length: u16,
	merge_policy:       ksawery.Merge_Fast_Forward_Policy,
	merge_action:       ksawery.Merge_Action,
	merge_precondition: ksawery.Merge_Precondition,
	merge_confirmation: ksawery.Merge_Confirmation,
	merge_request:      ksawery.Merge_Request,
	merge_result:       ksawery.Merge_Result,
	rebase_mode:        ksawery.Rebase_Mode,
	rebase_action:      ksawery.Rebase_Action,
	rebase_plan:        ksawery.Rebase_Plan,
	rebase_precondition: ksawery.Rebase_Precondition,
	rebase_confirmation: ksawery.Rebase_Confirmation,
	rebase_request:      ksawery.Rebase_Request,
	rebase_result:       ksawery.Rebase_Result,
	revision_sequence_selection: ^Ksawery_Revision_Sequence_Selection,
	revision_sequence_set: ksawery.Revision_Sequence_Set,
	revision_sequence_family: ksawery.Revision_Sequence_Family,
	revision_sequence_action: ksawery.Revision_Sequence_Action,
	revision_sequence_precondition: ksawery.Revision_Sequence_Precondition,
	revision_sequence_confirmation: ksawery.Revision_Sequence_Confirmation,
	revision_sequence_request: ksawery.Revision_Sequence_Request,
	revision_sequence_result: ksawery.Revision_Sequence_Result,
	bisect_good: [ksawery.MAX_BISECT_GOOD_BOUNDARIES]ksawery.Revision_Identity,
	bisect_good_count: u32,
	bisect_bad: ksawery.Revision_Identity,
	bisect_boundaries: ksawery.Bisect_Boundary_Set,
	bisect_action: ksawery.Bisect_Action,
	bisect_precondition: ksawery.Bisect_Precondition,
	bisect_confirmation: ksawery.Bisect_Confirmation,
	bisect_request: ksawery.Bisect_Request,
	bisect_result: ksawery.Bisect_Result,
	bisect_progress: ksawery.Bisect_Progress,
	conflict_action:       ksawery.Conflict_Resolution_Action,
	conflict_precondition: ksawery.Conflict_Resolution_Precondition,
	conflict_confirmation: ksawery.Conflict_Resolution_Confirmation,
	conflict_request:      ksawery.Conflict_Resolution_Request,
	conflict_result:       ksawery.Conflict_Resolution_Result,
	conflict_stage_zero:   ksawery.Conflict_Stage_Zero,
	conflict_path:         [int(ksawery.MAX_REPOSITORY_CONTEXT_BYTES)]u8,
	conflict_path_length:  u32,
	sequence_mutation_refresh: bool,
	sequence_mutation_conflict: bool,
	sequence_mutation_kind: ksawery.Sequence_Kind,
	sequence_mutation_history_refresh: bool,
	grouped:     ksawery.Grouped_Selection,
	detail:      ksawery.Path_Detail,
	diff:         ksawery.Diff_Document,
	diff_failure: ksawery.Failure_Code,
	action:      ksawery.Index_Action_Result,
	partial_action: ksawery.Partial_Index_Action_Result,
	grouped_action: ksawery.Grouped_Index_Action_Result,
	discard_action: ksawery.Discard_Action_Result,
	commit_precondition: ksawery.Commit_Precondition,
	commit_request:     ksawery.Commit_Request,
	commit_result:      ksawery.Commit_Result,
	commit_mode:        ksawery.Commit_Mode,
	commit_target:      ksawery.History_Target,
	amend_confirmation: ksawery.Amend_Confirmation,
	commit_draft:       [ksawery.MAX_COMMIT_MESSAGE_BYTES]u8,
	commit_draft_length: u32,
	commit_refresh:     Ksawery_Commit_Refresh,
	commit_return_to_draft: bool,
	raw_input:             ksawery.Raw_Repository_Command_Input,
	raw_intent:            ksawery.Raw_Repository_Command_Intent,
	raw_confirmation:      ksawery.Raw_Repository_Command_Confirmation,
	raw_request:           ksawery.Raw_Repository_Command_Request,
	raw_failure:           ksawery.Raw_Repository_Command_Failure,
	raw_return_mode:       Ksawery_View_Mode,
	raw_return_position:   ui.List_View_Position,
	raw_terminal:          ksawery.Repository_Process_Lifecycle_View,
	raw_awaiting_refresh:  bool,
	raw_refresh:           Ksawery_Raw_Command_Refresh,
	raw_refresh_completed: ksawery.Extension_Observation_Families,
	raw_result:            ksawery.Raw_Repository_Command_Result,
	mutation_refresh: Ksawery_Mutation_Refresh,
	operation_effect: ksawery.Repository_Process_Lifecycle_View,
	operation_verification: Ksawery_Repository_Verification_State,
	discard_request: ksawery.Discard_Action_Request,
	discard_path: [int(ksawery.MAX_REPOSITORY_CONTEXT_BYTES)]u8,
	discard_path_length: u32,
	discard_label: [int(ksawery.MAX_REPOSITORY_CONTEXT_BYTES) + 64]u8,
	next_action: ksawery.Index_Operation_ID,
	next_commit: ksawery.Commit_Operation_ID,
	next_fetch: ksawery.Fetch_Operation_ID,
	next_push: ksawery.Push_Operation_ID,
	next_branch: ksawery.Branch_Operation_ID,
	next_tag: ksawery.Tag_Operation_ID,
	next_merge: ksawery.Merge_Operation_ID,
	next_rebase: ksawery.Rebase_Operation_ID,
	next_revision_sequence: ksawery.Revision_Sequence_Operation_ID,
	next_bisect: ksawery.Bisect_Operation_ID,
	next_conflict_resolution: ksawery.Conflict_Resolution_Operation_ID,
	next_raw_command: ksawery.Raw_Repository_Command_ID,
	next_raw_confirmation: ksawery.Raw_Repository_Command_Confirmation_ID,
	next_confirmation: ksawery.Commit_Confirmation_ID,
	next_push_confirmation: ksawery.Push_Confirmation_ID,
	next_branch_confirmation: ksawery.Branch_Confirmation_ID,
	next_tag_confirmation: ksawery.Tag_Confirmation_ID,
	next_merge_confirmation: ksawery.Merge_Confirmation_ID,
	next_rebase_confirmation: ksawery.Rebase_Confirmation_ID,
	next_revision_sequence_confirmation: ksawery.Revision_Sequence_Confirmation_ID,
	next_bisect_confirmation: ksawery.Bisect_Confirmation_ID,
	next_conflict_confirmation: ksawery.Conflict_Resolution_Confirmation_ID,
	view_mode:   Ksawery_View_Mode,
	visited:     u64,
	resource_return_mode: Ksawery_View_Mode,
	surface_restore_pending: bool,
	position:    ui.List_View_Position,
}

@(private)
ksawery_raw_refresh_pending_matches :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || !state.raw_awaiting_refresh do return false
	switch state.raw_refresh {
	case .None:
		return state.pending == .None
	case .Status:
		return state.pending == .Observe || state.pending == .Refresh
	case .History:
		return state.pending == .History_Observe || state.pending == .History_Refresh ||
		       state.pending == .History_Next
	case .Refs:
		return state.pending == .Refs_Observe || state.pending == .Refs_Refresh
	case .Sequence:
		return state.pending == .Sequence_Observe
	}
	return false
}

@(private)
ksawery_workflow_pending_family :: proc(
	state: ^Ksawery_Workflow_State,
) -> Ksawery_Pending_Family {
	if state == nil do return .Invalid
	if state.raw_awaiting_refresh {
		if ksawery_raw_refresh_pending_matches(state) do return .Raw_Command
		return .Invalid
	}
	return ksawery_pending_operation_family(state.pending)
}

@(private)
ksawery_workflow_poll_is_terminal :: proc(poll: ksawery.Repository_Process_Poll) -> bool {
	return poll.state == .Completed || poll.state == .Failed
}

@(private)
ksawery_workflow_poll_once :: proc(
	state: ^Ksawery_Workflow_State,
	now: i64,
) -> (ksawery.Repository_Process_Poll, bool) {
	if state == nil || state.process.state == nil do return {}, false
	return ksawery.repository_process_poll(&state.process, now)
}

@(private)
ksawery_workflow_publish_completion :: proc(
	commands: ^Command_Context,
	outcome: ^Ksawery_Workflow_Completion_Outcome,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if !ksawery_workflow_completion_outcome_is_valid(outcome, state) {
		state.failure = .Cleanup
		command_context_set_diagnostic(commands, "Ksawery workflow completion outcome was invalid")
		return true
	}

	switch outcome.process {
	case .Close:
		if state.process.state == nil {
			state.failure = .Cleanup
			command_context_set_diagnostic(commands, "Ksawery workflow process ownership was invalid")
			return true
		}
		ksawery.repository_process_close(&state.process)
	case .Retain:
	case .Replace:
		if state.process.state == nil || outcome.replacement_process.state == nil {
			state.failure = .Cleanup
			command_context_set_diagnostic(commands, "Ksawery workflow process replacement was invalid")
			return true
		}
		ksawery.repository_process_close(&state.process)
		state.process = outcome.replacement_process
	case .Invalid:
		unreachable()
	}

	state.pending = outcome.next_pending
	if outcome.resolution == .Handler_Cleared {
		ksawery_workflow_clear_operation_resolution(state)
	}
	if outcome.diagnostic_intent == .Publish {
		command_context_set_diagnostic(commands, outcome.diagnostic)
	}

	switch outcome.refresh {
	case .None:
		return outcome.changed
	case .Continue_After_Status:
		return ksawery_workflow_continue_after_status(commands) || outcome.changed
	case .Advance_Raw_Command:
		return ksawery_workflow_advance_raw_command_refresh(commands) || outcome.changed
	case .Complete_Repository_Observation:
		return ksawery_workflow_continue_repository_observation(
			commands, outcome.observation_result,
		) || outcome.changed
	case .Start_Mutation_Refresh:
		state.mutation_refresh = outcome.mutation_refresh
		if ksawery_workflow_refresh(commands) do return true
		_ = ksawery_workflow_finish_unverified_operation(
			commands, "Repository mutation outcome is indeterminate",
		)
		return true
	case .Start_Commit_Refresh:
		state.commit_refresh = .Status
		state.view_mode = .Status
		if ksawery_workflow_refresh(commands) do return true
		state.commit_refresh = .None
		_ = ksawery_workflow_finish_unverified_operation(
			commands, "Repository commit outcome is indeterminate",
		)
		command_context_set_diagnostic(commands, "Repository status refresh could not start after commit")
		return true
	case .Complete_History:
		return ksawery_workflow_continue_history_completion(
			commands, outcome.history_result,
		) || outcome.changed
	case .Complete_Refs:
		return ksawery_workflow_continue_refs_completion(
			commands, outcome.refs_result,
		) || outcome.changed
	case .Complete_Synchronization:
		return ksawery_workflow_continue_synchronization_completion(
			commands,
			outcome.synchronization_result,
			outcome.synchronization_failed,
		) || outcome.changed
	case .Complete_Sequence:
		return ksawery_workflow_continue_sequence_completion(
			commands,
			outcome.sequence_result,
		) || outcome.changed
	case .Invalid:
		unreachable()
	}
	return outcome.changed
}

@(private)
Ksawery_Workflow_Usage :: struct {
	fixed_storage_bytes:          u64,
	context_bytes:                u64,
	observation_paths:            u32,
	observation_path_bytes:       u64,
	observation_diagnostic_bytes: u64,
	sequence_conflicts:           u32,
	sequence_allocation_bytes:    u64,
	history_revisions:            u32,
	history_parent_links:         u32,
	history_allocation_bytes:     u64,
	ref_entries:                  u32,
	ref_remotes:                  u32,
	ref_allocation_bytes:         u64,
	revision_detail_allocation_bytes: u64,
	revision_range_allocation_bytes:  u64,
	revision_staging_bytes:       u64,
	detail_bytes:                 u64,
	diff_units:                   u32,
	diff_lines:                   u32,
	diff_presentation_bytes:      u64,
	diff_patch_bytes:             u64,
	diff_allocation_bytes:        u64,
	grouped_targets:              u32,
	grouped_allocation_bytes:     u64,
	commit_output_bytes:          u64,
	commit_diagnostic_bytes:      u64,
	fetch_output_bytes:           u64,
	fetch_diagnostic_bytes:       u64,
	push_output_bytes:            u64,
	push_diagnostic_bytes:        u64,
	branch_output_bytes:          u64,
	branch_diagnostic_bytes:      u64,
	tag_output_bytes:             u64,
	tag_diagnostic_bytes:         u64,
	rebase_plan_allocation_bytes: u64,
	rebase_output_bytes:          u64,
	rebase_diagnostic_bytes:      u64,
	revision_sequence_set_bytes:  u64,
	revision_sequence_output_bytes: u64,
	revision_sequence_diagnostic_bytes: u64,
	bisect_boundary_set_bytes:    u64,
	bisect_output_bytes:          u64,
	bisect_diagnostic_bytes:      u64,
	process_output_bytes:         u64,
	process_input_bytes:          u64,
	process_diagnostic_bytes:     u64,
	process_record_count:         u32,
	process_record_bytes:         u64,
	action_output_bytes:          u64,
	action_diagnostic_bytes:      u64,
	retained_bytes:               u64,
}

@(private)
ksawery_workflow_usage :: proc(state: ^Ksawery_Workflow_State) -> (Ksawery_Workflow_Usage, bool) {
	if state == nil do return {}, false
	usage := Ksawery_Workflow_Usage {
		fixed_storage_bytes = u64(size_of(Ksawery_Workflow_State)),
		context_bytes = u64(state.repository.length),
	}
	if state.observation.state != nil {
		descriptor, described := ksawery.status_observation_descriptor(&state.observation)
		if !described do return {}, false
		usage.observation_paths = descriptor.path_count
		usage.observation_path_bytes = descriptor.path_bytes
		usage.observation_diagnostic_bytes = descriptor.diagnostic_bytes
	}
	if state.sequence.state != nil {
		sequence_usage, described := ksawery.sequence_observation_usage(&state.sequence)
		if !described do return {}, false
		usage.sequence_conflicts = sequence_usage.conflicts
		usage.sequence_allocation_bytes = sequence_usage.allocation_bytes
	}
	if state.history.state != nil {
		history_usage, described := ksawery.history_observation_usage(&state.history)
		if !described do return {}, false
		usage.history_revisions = history_usage.revisions
		usage.history_parent_links = history_usage.parent_links
		usage.history_allocation_bytes = history_usage.allocation_bytes
	}
	if state.refs.state != nil {
		refs_usage, described := ksawery.ref_observation_usage(&state.refs)
		if !described do return {}, false
		usage.ref_entries = refs_usage.entries
		usage.ref_remotes = refs_usage.remotes
		usage.ref_allocation_bytes = refs_usage.allocation_bytes
	}
	if state.revision_detail.state != nil {
		inspection_usage, described := ksawery.revision_detail_usage(&state.revision_detail)
		if !described do return {}, false
		usage.revision_detail_allocation_bytes = inspection_usage.allocation_bytes
	}
	if state.revision_range.state != nil {
		inspection_usage, described := ksawery.revision_range_observation_usage(&state.revision_range)
		if !described do return {}, false
		usage.revision_range_allocation_bytes = inspection_usage.allocation_bytes
	}
	if state.revision_staging != nil {
		usage.revision_staging_bytes = u64(size_of(Ksawery_Revision_Staging)) +
			u64(cap(state.revision_staging.metadata)) + u64(cap(state.revision_staging.summary))
	}
	if state.detail.state != nil {
		descriptor, described := ksawery.path_detail_descriptor(&state.detail)
		if !described do return {}, false
		usage.detail_bytes = descriptor.bytes
	}
	if state.diff.state != nil {
		diff_usage, described := ksawery.diff_document_usage(&state.diff)
		if !described do return {}, false
		usage.diff_units = diff_usage.units
		usage.diff_lines = diff_usage.lines
		usage.diff_presentation_bytes = diff_usage.presentation_bytes
		usage.diff_patch_bytes = diff_usage.patch_bytes
		usage.diff_allocation_bytes = diff_usage.allocation_bytes
	}
	if state.grouped.state != nil {
		grouped_usage, described := ksawery.grouped_selection_usage(&state.grouped)
		if !described do return {}, false
		usage.grouped_targets = grouped_usage.targets
		usage.grouped_allocation_bytes = grouped_usage.allocation_bytes
	}
	if state.commit_result.state != nil {
		descriptor, described := ksawery.commit_result_descriptor(&state.commit_result)
		if !described do return {}, false
		usage.commit_output_bytes = descriptor.output_bytes
		usage.commit_diagnostic_bytes = descriptor.diagnostic_bytes
	}
	if state.fetch_result.state != nil {
		fetch_usage, described := ksawery.fetch_result_usage(&state.fetch_result)
		if !described do return {}, false
		usage.fetch_output_bytes = fetch_usage.output_bytes
		usage.fetch_diagnostic_bytes = fetch_usage.diagnostic_bytes
	}
	if state.push_result.state != nil {
		push_usage, described := ksawery.push_result_usage(&state.push_result)
		if !described do return {}, false
		usage.push_output_bytes = push_usage.output_bytes
		usage.push_diagnostic_bytes = push_usage.diagnostic_bytes
	}
	if state.branch_result.state != nil {
		branch_usage, described := ksawery.branch_result_usage(&state.branch_result)
		if !described do return {}, false
		usage.branch_output_bytes = branch_usage.output_bytes
		usage.branch_diagnostic_bytes = branch_usage.diagnostic_bytes
	}
	if state.tag_result.state != nil {
		tag_usage, described := ksawery.tag_result_usage(&state.tag_result)
		if !described do return {}, false
		usage.tag_output_bytes = tag_usage.output_bytes
		usage.tag_diagnostic_bytes = tag_usage.diagnostic_bytes
	}
	if state.rebase_plan.state != nil {
		plan_usage, described := ksawery.rebase_plan_usage(&state.rebase_plan)
		if !described do return {}, false
		usage.rebase_plan_allocation_bytes = plan_usage.allocation_bytes
	}
	if state.rebase_result.state != nil {
		rebase_usage, described := ksawery.rebase_result_usage(&state.rebase_result)
		if !described do return {}, false
		usage.rebase_output_bytes = rebase_usage.output_bytes
		usage.rebase_diagnostic_bytes = rebase_usage.diagnostic_bytes
	}
	if state.revision_sequence_set.state != nil {
		set_usage, described := ksawery.revision_sequence_set_usage(&state.revision_sequence_set)
		if !described do return {}, false
		usage.revision_sequence_set_bytes = set_usage.allocation_bytes
	}
	if state.revision_sequence_result.state != nil {
		result_usage, described := ksawery.revision_sequence_result_usage(&state.revision_sequence_result)
		if !described do return {}, false
		usage.revision_sequence_output_bytes = result_usage.output_bytes
		usage.revision_sequence_diagnostic_bytes = result_usage.diagnostic_bytes
	}
	if state.bisect_boundaries.state != nil {
		set_usage, described := ksawery.bisect_boundary_set_usage(&state.bisect_boundaries)
		if !described do return {}, false
		usage.bisect_boundary_set_bytes = set_usage.allocation_bytes
	}
	if state.bisect_result.state != nil {
		result_usage, described := ksawery.bisect_result_usage(&state.bisect_result)
		if !described do return {}, false
		usage.bisect_output_bytes = result_usage.output_bytes
		usage.bisect_diagnostic_bytes = result_usage.diagnostic_bytes
	}
	if state.process.state != nil {
		process, described := ksawery.repository_process_usage(&state.process)
		if !described do return {}, false
		usage.process_output_bytes = process.output_bytes
		usage.process_input_bytes = process.input_bytes
		usage.process_diagnostic_bytes = process.diagnostic_bytes
	}
	if state.process_coordinator.allocator.procedure != nil {
		coordinator, described := ksawery_process_coordinator_usage(&state.process_coordinator)
		if !described do return {}, false
		usage.process_record_count = coordinator.records
		usage.process_record_bytes = coordinator.retained_bytes
	}
	if state.action.state != nil {
		descriptor, described := ksawery.index_action_result_descriptor(&state.action)
		if !described do return {}, false
		usage.action_output_bytes = descriptor.output_bytes
		usage.action_diagnostic_bytes = descriptor.diagnostic_bytes
	}
	if state.partial_action.state != nil {
		descriptor, described := ksawery.partial_index_action_result_descriptor(&state.partial_action)
		if !described do return {}, false
		usage.action_output_bytes = descriptor.output_bytes
		usage.action_diagnostic_bytes = descriptor.diagnostic_bytes
	}
	if state.grouped_action.state != nil {
		descriptor, described := ksawery.grouped_index_action_result_descriptor(&state.grouped_action)
		if !described do return {}, false
		usage.action_output_bytes = descriptor.output_bytes
		usage.action_diagnostic_bytes = descriptor.diagnostic_bytes
	}
	if state.discard_action.state != nil {
		descriptor, described := ksawery.discard_action_result_descriptor(&state.discard_action)
		if !described do return {}, false
		usage.action_output_bytes = descriptor.output_bytes
		usage.action_diagnostic_bytes = descriptor.diagnostic_bytes
	}
	usage.retained_bytes = usage.fixed_storage_bytes + usage.observation_path_bytes +
	                       usage.observation_diagnostic_bytes + usage.detail_bytes +
	                       usage.sequence_allocation_bytes +
	                       usage.history_allocation_bytes +
	                       usage.ref_allocation_bytes +
	                       usage.revision_detail_allocation_bytes + usage.revision_range_allocation_bytes +
	                       usage.revision_staging_bytes +
	                       usage.diff_allocation_bytes + usage.grouped_allocation_bytes +
	                       usage.commit_output_bytes + usage.commit_diagnostic_bytes +
	                       usage.fetch_output_bytes + usage.fetch_diagnostic_bytes +
	                       usage.push_output_bytes + usage.push_diagnostic_bytes +
	                       usage.branch_output_bytes + usage.branch_diagnostic_bytes +
	                       usage.tag_output_bytes + usage.tag_diagnostic_bytes +
	                       usage.rebase_plan_allocation_bytes + usage.rebase_output_bytes +
	                       usage.rebase_diagnostic_bytes +
	                       usage.revision_sequence_set_bytes +
	                       ksawery_workflow_revision_sequence_selection_bytes(state) +
	                       usage.revision_sequence_output_bytes + usage.revision_sequence_diagnostic_bytes +
	                       usage.bisect_boundary_set_bytes + usage.bisect_output_bytes +
	                       usage.bisect_diagnostic_bytes +
	                       usage.process_input_bytes + usage.process_output_bytes +
	                       usage.process_diagnostic_bytes +
	                       usage.process_record_bytes +
	                       usage.action_output_bytes + usage.action_diagnostic_bytes
	return usage, true
}

/* command_context_exit_ksawery_status restores the retained editor-visible target. */
command_context_exit_ksawery_status :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.host.call == nil || commands.ksawery_workflow == nil ||
	   !commands.ksawery_workflow.active {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	state := commands.ksawery_workflow
	_, restored := host_session_request(
		&commands.host,
		.Restore_Target,
		state.previous,
		0,
		"",
	)
	if !restored {
		return {}, App_Failure{stage = .Session_Access, host_status = .Failed}
	}
	pointer_text_capture_clear(commands)
	extension_registry := state.extension_registry
	state.extension_registry = {}
	ksawery_workflow_close(state)
	state.allocator = commands.persistent_allocator
	state.extension_registry = extension_registry
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_close :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	if state.extension_command_workflow.active {
		_ = ksawery_extension_command_workflow_abort(&state.extension_command_workflow)
	}
	if state.extension_operation != nil {
		if state.extension_operation.process.state != nil {
			ksawery.repository_process_close(&state.extension_operation.process)
		}
		free(state.extension_operation, state.allocator)
	}
	if state.extension_command_family != nil {
		ksawery_command.ksawery_command_family_close(state.extension_command_family)
		free(state.extension_command_family, state.allocator)
	}
	if state.extension_registry.allocator.procedure != nil && !state.extension_registry.closed {
		_ = ksawery_extension_provider_registry_close(&state.extension_registry)
	}
	if state.observation.state != nil do ksawery.status_observation_close(&state.observation)
	if state.sequence.state != nil do ksawery.sequence_observation_close(&state.sequence)
	if state.history.state != nil do ksawery.history_observation_close(&state.history)
	if state.refs.state != nil do ksawery.ref_observation_close(&state.refs)
	if state.inspection_workflow.state != nil {
		ksawery.inspection_observation_close(&state.inspection_workflow)
	}
	ksawery_workflow_clear_revision_inspection(state)
	if state.grouped.state != nil do ksawery.grouped_selection_close(&state.grouped)
	if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
	if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
	if state.action.state != nil do ksawery.index_action_result_close(&state.action)
	if state.partial_action.state != nil do ksawery.partial_index_action_result_close(&state.partial_action)
	if state.grouped_action.state != nil do ksawery.grouped_index_action_result_close(&state.grouped_action)
	if state.discard_action.state != nil do ksawery.discard_action_result_close(&state.discard_action)
	if state.commit_result.state != nil do ksawery.commit_result_close(&state.commit_result)
	if state.fetch_result.state != nil do ksawery.fetch_result_close(&state.fetch_result)
	if state.push_result.state != nil do ksawery.push_result_close(&state.push_result)
	if state.branch_result.state != nil do ksawery.branch_result_close(&state.branch_result)
	if state.tag_result.state != nil do ksawery.tag_result_close(&state.tag_result)
	if state.merge_result.state != nil do ksawery.merge_result_close(&state.merge_result)
	if state.rebase_plan.state != nil do ksawery.rebase_plan_close(&state.rebase_plan)
	if state.rebase_result.state != nil do ksawery.rebase_result_close(&state.rebase_result)
	if state.revision_sequence_selection != nil {
		selection := state.revision_sequence_selection
		if selection.targets != nil do delete(selection.targets)
		free(selection, selection.allocator)
	}
	if state.revision_sequence_set.state != nil do ksawery.revision_sequence_set_close(&state.revision_sequence_set)
	if state.revision_sequence_result.state != nil do ksawery.revision_sequence_result_close(&state.revision_sequence_result)
	if state.bisect_boundaries.state != nil do ksawery.bisect_boundary_set_close(&state.bisect_boundaries)
	if state.bisect_result.state != nil do ksawery.bisect_result_close(&state.bisect_result)
	if state.conflict_result.state != nil do ksawery.conflict_resolution_result_close(&state.conflict_result)
	if state.conflict_assistance != nil {
		ksawery_conflict_assistance_workflow_close(state.conflict_assistance)
		free(state.conflict_assistance, state.allocator)
	}
	if state.process.state != nil do ksawery.repository_process_close(&state.process)
	if state.process_coordinator.allocator.procedure != nil do ksawery_process_coordinator_close(&state.process_coordinator)
	state^ = {}
}

@(private)
ksawery_workflow_clear_revision_inspection :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	if state.revision_detail.state != nil do ksawery.revision_detail_close(&state.revision_detail)
	if state.revision_range.state != nil do ksawery.revision_range_observation_close(&state.revision_range)
	if state.revision_staging != nil {
		if state.revision_staging.metadata != nil do delete(state.revision_staging.metadata)
		if state.revision_staging.summary != nil do delete(state.revision_staging.summary)
		free(state.revision_staging, state.allocator)
		state.revision_staging = nil
	}
	state.revision_detail_request = {}
	state.revision_range_request = {}
}

@(private)
ksawery_workflow_copy_revision_output :: proc(
	output: []u8,
	allocator: runtime.Allocator,
) -> ([dynamic]u8, bool) {
	if allocator.procedure == nil do return {}, false
	owned, allocation_error := make([dynamic]u8, 0, len(output), allocator)
	if allocation_error != nil do return {}, false
	_, append_error := append(&owned, ..output)
	if append_error != nil {
		delete(owned)
		return {}, false
	}
	return owned, true
}

@(private)
ksawery_workflow_revision_staging_open :: proc(
	allocator: runtime.Allocator,
) -> (^Ksawery_Revision_Staging, bool) {
	if allocator.procedure == nil do return nil, false
	staging, allocation_error := new(Ksawery_Revision_Staging, allocator)
	if allocation_error != nil do return nil, false
	staging.allocator = allocator
	return staging, true
}

@(private)
ksawery_workflow_now :: proc(commands: ^Command_Context) -> i64 {
	if commands == nil do return 0
	return time.duration_nanoseconds(time.tick_since(commands.grouping_started))
}

@(private)
ksawery_workflow_reclaim_canvas :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.host.call == nil || commands.ksawery_workflow == nil ||
	   !commands.ksawery_workflow.active ||
	   !commands.ksawery_workflow.surface_restore_pending {
		return false
	}
	_, presented := host_session_request(
		&commands.host,
		.Present_Surface,
		0,
		0,
		"source-control.status",
	)
	if presented {
		commands.ksawery_workflow.surface_restore_pending = false
		pointer_text_capture_clear(commands)
	}
	return presented
}

@(private)
ksawery_workflow_start_sequence_observation :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || !state.active || state.observation.state == nil || state.process.state != nil do return false
	if u64(state.sequence_generation) == max(u64) {
		state.sequence_failure = .Invalid_Request
		return false
	}
	next_generation := state.sequence_generation + 1
	process, started, failure := ksawery.repository_process_start_sequence_observation(
		state.repository,
		ksawery_workflow_now(commands),
		ksawery.DEFAULT_SEQUENCE_LIMITS,
		commands.persistent_allocator,
	)
	if !started {
		state.sequence_failure = failure
		return false
	}
	state.sequence_process_recorded = false
	if !state.process_coordinator.active {
		generation := state.process_coordinator.confirmed_observation
		recorded, record_failure := ksawery_process_observation_begin(
			&state.process_coordinator,
			&process,
			generation,
			{
				kind = .Sequence,
				target_kind = .Repository,
				title = "Repository Sequence",
				target = ksawery.repository_context_string(&state.repository),
				phase_detail = "Reading repository sequence state",
			},
			ksawery_workflow_now(commands),
		)
		if !recorded {
			ksawery.repository_process_close(&process)
			state.sequence_failure = record_failure
			return false
		}
		state.sequence_process_recorded = true
	}
	state.sequence_generation = next_generation
	state.process = process
	state.pending = .Sequence_Observe
	state.sequence_failure = .None
	return true
}

@(private)
ksawery_workflow_continue_after_status :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil do return false
	if state.fetch_refresh == .Status {
		if state.history.state != nil {
			state.fetch_refresh = .History
			if !ksawery_workflow_start_history(commands, .History_Refresh) {
				ksawery_workflow_finish_fetch_refresh(commands, true)
				return true
			}
			state.view_mode = .Refs
			return true
		}
		ksawery_workflow_finish_fetch_refresh(commands, false)
		return true
	}
	if state.push_refresh == .Status {
		if state.history.state != nil {
			state.push_refresh = .History
			if !ksawery_workflow_start_history(commands, .History_Refresh) {
				ksawery_workflow_finish_push_refresh(commands, true)
				return true
			}
			state.view_mode = .Refs
			return true
		}
		ksawery_workflow_finish_push_refresh(commands, false)
		return true
	}
	if state.branch_refresh == .Status {
		_, _ = ksawery.branch_result_verify(&state.branch_result, &state.observation, &state.refs)
		if state.history.state != nil {
			state.branch_refresh = .History
			if !ksawery_workflow_start_history(commands, .History_Refresh) {
				ksawery_workflow_finish_branch_refresh(commands, true)
				return true
			}
			state.view_mode = .Refs
			return true
		}
		ksawery_workflow_finish_branch_refresh(commands, false)
		return true
	}
	if state.tag_refresh == .Status {
		if state.history.state != nil {
			state.tag_refresh = .History
			if !ksawery_workflow_start_history(commands, .History_Refresh) {
				ksawery_workflow_finish_tag_refresh(commands, true)
				return true
			}
			state.view_mode = .Refs
			return true
		}
		ksawery_workflow_finish_tag_refresh(commands, false)
		return true
	}
	if state.commit_refresh == .Status {
		state.commit_refresh = .History
		if !ksawery_workflow_start_history(commands, .History_Refresh) {
			state.commit_refresh = .None
			_ = ksawery_workflow_finish_unverified_operation(
				commands,
				"Repository commit outcome is indeterminate",
			)
			state.failure = .Process_Failed
			command_context_set_diagnostic(commands, "Repository History refresh could not start after commit")
			return true
		}
		return true
	}
state.failure = .None
	return true
}

@(private)
ksawery_workflow_continue_repository_observation :: proc(
	commands: ^Command_Context,
	result: Ksawery_Workflow_Observation_Result,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	switch result {
	case .Applied:
		if state.inspection_refresh_family != .Invalid {
			family := state.inspection_refresh_family
			state.inspection_refresh_family = .Invalid
			state.view_mode = .Status
			if ksawery_workflow_start_inspection(commands, family) do return true
			command_context_set_diagnostic(commands, "Repository inspection refresh could not start")
			return true
		}
		if state.sequence_mutation_refresh && state.refs.state != nil {
			if ksawery_workflow_start_refs(commands, .Refs_Refresh) do return true
			ksawery_workflow_finish_sequence_mutation_refresh(commands, false)
			return true
		}
		if ksawery_workflow_start_sequence_observation(commands) do return true
		return ksawery_workflow_continue_after_status(commands)
	case .Unavailable:
		state.inspection_refresh_family = .Invalid
		if state.tag_refresh != .None {
			ksawery_workflow_finish_tag_refresh(commands, true)
			return true
		}
		if state.branch_refresh != .None {
			ksawery_workflow_finish_branch_refresh(commands, true)
			return true
		}
		if state.push_refresh != .None {
			ksawery_workflow_finish_push_refresh(commands, true)
			return true
		}
		return true
	case .Process_Failed:
		state.inspection_refresh_family = .Invalid
		if state.fetch_refresh != .None {
			ksawery_workflow_finish_fetch_refresh(commands, true)
			return true
		}
		if state.push_refresh != .None {
			ksawery_workflow_finish_push_refresh(commands, true)
			return true
		}
		if state.branch_refresh != .None {
			ksawery_workflow_finish_branch_refresh(commands, true)
			return true
		}
		if state.tag_refresh != .None {
			ksawery_workflow_finish_tag_refresh(commands, true)
			return true
		}
		if state.commit_refresh != .None {
			state.commit_refresh = .None
			descriptor, described := ksawery.commit_result_descriptor(&state.commit_result)
			if state.commit_return_to_draft {
				state.amend_confirmation = {}
				state.view_mode = .Commit_Message
				state.failure = descriptor.failure if described else .Process_Failed
				command_context_set_diagnostic(
					commands, "Repository post-commit refresh failed; message draft retained",
				)
			} else {
				state.view_mode = .Status
				command_context_set_diagnostic(
					commands, "Repository commit completed; post-commit refresh failed",
				)
			}
		}
		return true
	case .Grouping_Unavailable:
		state.inspection_refresh_family = .Invalid
		if state.commit_refresh == .Status && state.process_coordinator.active {
			state.commit_refresh = .None
			_ = ksawery_workflow_finish_unverified_operation(
				commands, "Repository commit outcome is indeterminate",
			)
		}
		if state.tag_refresh != .None {
			ksawery_workflow_finish_tag_refresh(commands, true)
			return true
		}
		if state.branch_refresh != .None {
			ksawery_workflow_finish_branch_refresh(commands, true)
			return true
		}
		if state.push_refresh != .None {
			ksawery_workflow_finish_push_refresh(commands, true)
			return true
		}
		return true
	case .None:
		return false
	}
	return false
}

@(private)
ksawery_workflow_continue_history_completion :: proc(
	commands: ^Command_Context,
	result: Ksawery_Workflow_History_Result,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if result == .Unavailable {
		if state.sequence_mutation_history_refresh {
			ksawery_workflow_finish_sequence_mutation_refresh(commands, false)
			return true
		}
		if state.tag_refresh != .None {
			ksawery_workflow_finish_tag_refresh(commands, true)
			return true
		}
		if state.branch_refresh != .None {
			ksawery_workflow_finish_branch_refresh(commands, true)
			return true
		}
		if state.push_refresh != .None {
			ksawery_workflow_finish_push_refresh(commands, true)
			return true
		}
		command_context_set_diagnostic(commands, "Repository history observation failed")
		return true
	}
	if result == .Process_Failed {
		if state.fetch_refresh != .None {
			ksawery_workflow_finish_fetch_refresh(commands, true)
			return true
		}
		if state.push_refresh != .None {
			ksawery_workflow_finish_push_refresh(commands, true)
			return true
		}
		if state.branch_refresh != .None {
			ksawery_workflow_finish_branch_refresh(commands, true)
			return true
		}
		if state.tag_refresh != .None {
			ksawery_workflow_finish_tag_refresh(commands, true)
			return true
		}
		if state.commit_refresh != .None {
			state.commit_refresh = .None
			descriptor, described := ksawery.commit_result_descriptor(&state.commit_result)
			if state.commit_return_to_draft {
				state.amend_confirmation = {}
				state.view_mode = .Commit_Message
				state.failure = descriptor.failure if described else .Process_Failed
				command_context_set_diagnostic(
					commands, "Repository post-commit refresh failed; message draft retained",
				)
			} else {
				state.view_mode = .Status
				command_context_set_diagnostic(
					commands, "Repository commit completed; post-commit refresh failed",
				)
			}
		}
		return true
	}
	if result != .Applied do return false
	if state.sequence_mutation_history_refresh {
		ksawery_workflow_finish_sequence_mutation_refresh(commands, true)
		return true
	}
	if state.fetch_refresh == .History {
		ksawery_workflow_finish_fetch_refresh(commands, false)
		return true
	}
	if state.push_refresh == .History {
		ksawery_workflow_finish_push_refresh(commands, false)
		return true
	}
	if state.branch_refresh == .History {
		ksawery_workflow_finish_branch_refresh(commands, false)
		return true
	}
	if state.tag_refresh == .History {
		ksawery_workflow_finish_tag_refresh(commands, false)
		return true
	}
	if state.commit_refresh == .History {
		state.commit_refresh = .None
		descriptor, described := ksawery.commit_result_descriptor(&state.commit_result)
		if described && descriptor.succeeded {
			state.commit_draft = {}
			state.commit_draft_length = 0
			state.commit_precondition = {}
			state.commit_request = {}
			state.commit_mode = .Invalid
			state.commit_target = {}
			state.amend_confirmation = {}
			state.commit_return_to_draft = false
			state.view_mode = .History
			state.failure = .None
			command_context_set_diagnostic(commands, "Repository commit completed")
		} else {
			state.commit_return_to_draft = false
			state.amend_confirmation = {}
			state.view_mode = .Commit_Message
			state.failure = descriptor.failure if described else .Process_Failed
			command_context_set_diagnostic(commands, "Repository commit failed; message draft retained")
		}
		return true
	}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_continue_refs_completion :: proc(
	commands: ^Command_Context,
	result: Ksawery_Workflow_Refs_Result,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if result == .Unavailable {
		if state.sequence_mutation_refresh {
			ksawery_workflow_finish_sequence_mutation_refresh(commands, false)
			return true
		}
		if state.tag_refresh != .None {
			ksawery_workflow_finish_tag_refresh(commands, true)
			return true
		}
		if state.branch_refresh != .None {
			ksawery_workflow_finish_branch_refresh(commands, true)
			return true
		}
		if state.push_refresh != .None {
			ksawery_workflow_finish_push_refresh(commands, true)
			return true
		}
		command_context_set_diagnostic(commands, "Repository ref observation failed")
		return true
	}
	if result == .Process_Failed {
		if state.fetch_refresh != .None {
			ksawery_workflow_finish_fetch_refresh(commands, true)
			return true
		}
		if state.push_refresh != .None {
			ksawery_workflow_finish_push_refresh(commands, true)
			return true
		}
		if state.branch_refresh != .None {
			ksawery_workflow_finish_branch_refresh(commands, true)
			return true
		}
		if state.tag_refresh != .None {
			ksawery_workflow_finish_tag_refresh(commands, true)
			return true
		}
		return true
	}
	if result != .Applied do return false
	if state.sequence_mutation_refresh {
		if !ksawery_workflow_start_sequence_observation(commands) {
			ksawery_workflow_finish_sequence_mutation_refresh(commands, false)
		}
		return true
	}
	if state.fetch_refresh == .Refs {
		state.fetch_refresh = .Status
		if !ksawery_workflow_refresh(commands) {
			ksawery_workflow_finish_fetch_refresh(commands, true)
		}
		return true
	}
	if state.push_refresh == .Refs {
		_, _ = ksawery.push_result_verify(&state.push_result, &state.refs)
		state.push_refresh = .Status
		if !ksawery_workflow_refresh(commands) {
			ksawery_workflow_finish_push_refresh(commands, true)
		}
		return true
	}
	if state.branch_refresh == .Refs {
		state.branch_refresh = .Status
		if !ksawery_workflow_refresh(commands) {
			ksawery_workflow_finish_branch_refresh(commands, true)
		}
		return true
	}
	if state.tag_refresh == .Refs {
		_, _ = ksawery.tag_result_verify(&state.tag_result, &state.refs)
		state.tag_refresh = .Status
		if !ksawery_workflow_refresh(commands) {
			ksawery_workflow_finish_tag_refresh(commands, true)
		}
		return true
	}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_continue_synchronization_completion :: proc(
	commands: ^Command_Context,
	result: Ksawery_Workflow_Synchronization_Result,
	failed: bool,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	switch result {
	case .Start_Prepared_Fetch:
		if !ksawery_workflow_start_prepared_fetch(commands, state.fetch_configuration) {
			_ = ksawery_process_observation_finish_without_child(
				&state.process_coordinator,
				.Failed,
				.Known_Failure,
				"Checked repository remote fetch could not start",
				ksawery_workflow_now(commands),
			)
			command_context_set_diagnostic(commands, "Checked repository remote fetch could not start")
		}
		return true
	case .Prepare_Push_Confirmation:
		status, described := ksawery.status_observation_descriptor(&state.observation)
		if !described {
			_ = ksawery_process_observation_finish_without_child(
				&state.process_coordinator, .Failed, .Known_Failure,
				"Repository status no longer admits push confirmation", ksawery_workflow_now(commands),
			)
			state.failure = .Stale_Observation
			command_context_set_diagnostic(commands, "Repository status no longer admits push confirmation")
			return true
		}
		precondition, prepared, prepare_failure := ksawery.push_precondition_prepare(
			&state.refs,
			state.ref_selection.marked,
			state.push_configuration,
			status.operation,
		)
		if !prepared {
			_ = ksawery_process_observation_finish_without_child(
				&state.process_coordinator, .Failed, .Known_Failure,
				"Marked branch has no safe push destination", ksawery_workflow_now(commands),
			)
			state.failure = prepare_failure
			command_context_set_diagnostic(commands, "Marked branch does not have one safe tracked push destination")
			return true
		}
		confirmation_id := state.next_push_confirmation
		if confirmation_id == ksawery.Push_Confirmation_ID(0) {
			confirmation_id = ksawery.Push_Confirmation_ID(1)
		}
		confirmation, confirmation_ready, confirmation_failure := ksawery.push_confirmation_prepare(
			precondition,
			confirmation_id,
		)
		if !confirmation_ready {
			_ = ksawery_process_observation_finish_without_child(
				&state.process_coordinator, .Failed, .Known_Failure,
				"Repository push confirmation could not be prepared", ksawery_workflow_now(commands),
			)
			state.failure = confirmation_failure
			command_context_set_diagnostic(commands, "Exact repository push confirmation could not be prepared")
			return true
		}
		state.push_precondition = precondition
		state.push_confirmation = confirmation
		state.next_push_confirmation = confirmation_id + 1
		if state.next_push_confirmation == ksawery.Push_Confirmation_ID(0) {
			state.next_push_confirmation = ksawery.Push_Confirmation_ID(1)
		}
		state.view_mode = .Push_Confirmation
		state.position = {}
		state.failure = .None
		published, publish_failure := ksawery_process_operation_publish_phase(
			&state.process_coordinator,
			nil,
			.Checking,
			"Waiting for push confirmation",
			false,
			ksawery_workflow_now(commands),
		)
		if !published {
			state.process_failure = publish_failure
			state.failure = publish_failure
		}
		return true
	case .Finish_Fetch:
		ksawery_workflow_finish_fetch_refresh(commands, failed)
		return true
	case .Start_Fetch_Refresh:
		state.fetch_refresh = .Refs
		if !ksawery_workflow_start_refs(commands, .Refs_Refresh) {
			ksawery_workflow_finish_fetch_refresh(commands, true)
		}
		return true
	case .Finish_Push:
		ksawery_workflow_finish_push_refresh(commands, failed)
		return true
	case .Start_Push_Refresh:
		state.push_refresh = .Refs
		if !ksawery_workflow_start_refs(commands, .Refs_Refresh) {
			ksawery_workflow_finish_push_refresh(commands, true)
		}
		return true
	case .Finish_Branch:
		ksawery_workflow_finish_branch_refresh(commands, failed)
		return true
	case .Start_Branch_Refresh:
		state.branch_refresh = .Refs
		if !ksawery_workflow_start_refs(commands, .Refs_Refresh) {
			ksawery_workflow_finish_branch_refresh(commands, true)
		}
		return true
	case .Finish_Tag:
		ksawery_workflow_finish_tag_refresh(commands, failed)
		return true
	case .Start_Tag_Refresh:
		state.tag_refresh = .Refs
		if !ksawery_workflow_start_refs(commands, .Refs_Refresh) {
			ksawery_workflow_finish_tag_refresh(commands, true)
		}
		return true
	case .None:
		return false
	}
	return false
}

@(private)
ksawery_workflow_sequence_outcome :: proc(
	result: Ksawery_Workflow_Sequence_Result = .None,
	diagnostic: string = "",
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = .Complete_Sequence if result != .None else .None,
		sequence_result = result,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_start_sequence_completion_refresh :: proc(
	commands: ^Command_Context,
	failure_diagnostic: string,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || !state.sequence_mutation_refresh do return false
	if ksawery_workflow_refresh(commands) do return true
	state.sequence_mutation_refresh = false
	_ = ksawery_workflow_finish_unverified_operation(commands, failure_diagnostic)
	state.failure = .Process_Failed
	return true
}

@(private)
ksawery_workflow_continue_sequence_completion :: proc(
	commands: ^Command_Context,
	result: Ksawery_Workflow_Sequence_Result,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	switch result {
	case .Prepare_Merge_Confirmation:
		return ksawery_workflow_prepare_merge_confirmation(commands, state.merge_precondition)
	case .Prepare_Rebase_Confirmation:
		return ksawery_workflow_prepare_rebase_confirmation(commands, state.rebase_precondition)
	case .Prepare_Revision_Sequence_Confirmation:
		id := state.next_revision_sequence_confirmation
		if id == ksawery.Revision_Sequence_Confirmation_ID(0) do id = 1
		confirmation, prepared, failure :=
			ksawery.revision_sequence_confirmation_prepare(state.revision_sequence_precondition, id)
		if !prepared {
			state.failure = failure
			return true
		}
		state.revision_sequence_confirmation = confirmation
		state.next_revision_sequence_confirmation = id + 1
		if state.next_revision_sequence_confirmation == ksawery.Revision_Sequence_Confirmation_ID(0) {
			state.next_revision_sequence_confirmation = 1
		}
		state.view_mode = .Revision_Sequence_Confirmation
		state.position = {}
		state.failure = .None
		return true
	case .Prepare_Bisect_Confirmation:
		id := state.next_bisect_confirmation
		if id == ksawery.Bisect_Confirmation_ID(0) do id = 1
		confirmation, prepared, failure := ksawery.bisect_confirmation_prepare(state.bisect_precondition, id)
		if !prepared {
			state.failure = failure
			return true
		}
		state.bisect_confirmation = confirmation
		state.next_bisect_confirmation = id + 1
		if state.next_bisect_confirmation == ksawery.Bisect_Confirmation_ID(0) {
			state.next_bisect_confirmation = 1
		}
		state.view_mode = .Bisect_Confirmation
		state.position = {}
		state.failure = .None
		return true
	case .Prepare_Conflict_Confirmation:
		return ksawery_workflow_prepare_conflict_confirmation(commands, state.conflict_precondition)
	case .Start_Mutation_Refresh:
		return ksawery_workflow_start_sequence_completion_refresh(
			commands, "Repository sequence mutation outcome is indeterminate",
		)
	case .Start_Revision_Sequence_Refresh:
		return ksawery_workflow_start_sequence_completion_refresh(
			commands, "Sequenced revision mutation outcome is indeterminate",
		)
	case .Start_Bisect_Refresh:
		return ksawery_workflow_start_sequence_completion_refresh(
			commands, "Manual bisect outcome is indeterminate",
		)
	case .Observation_Applied:
		if state.sequence_mutation_refresh {
			if (state.sequence_mutation_kind == .Rebase || state.sequence_mutation_kind == .Cherry_Pick ||
			    state.sequence_mutation_kind == .Revert || state.sequence_mutation_kind == .Bisect) &&
			   state.history.state != nil {
				state.sequence_mutation_history_refresh = true
				if ksawery_workflow_start_history(commands, .History_Refresh) do return true
				ksawery_workflow_finish_sequence_mutation_refresh(commands, false)
				return true
			}
			ksawery_workflow_finish_sequence_mutation_refresh(commands, true)
		}
		return ksawery_workflow_continue_after_status(commands)
	case .Observation_Unavailable, .Observation_Process_Failed:
		if state.sequence_mutation_refresh {
			ksawery_workflow_finish_sequence_mutation_refresh(commands, false)
		}
		return ksawery_workflow_continue_after_status(commands)
	case .None:
		return false
	}
	return false
}

@(private)
ksawery_workflow_complete_sequence_observation :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state == nil || state.pending != .Sequence_Observe || state.process.state == nil do return {}, false
	observation: ksawery.Sequence_Observation
	opened := false
	failure := poll.failure
	if poll.state == .Completed {
		observation, opened, failure = ksawery.repository_process_take_sequence(
			&state.process, state.sequence_generation, commands.persistent_allocator,
		)
	}
	if state.sequence_process_recorded {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			opened,
			"Repository sequence available" if opened else "Repository sequence observation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	state.sequence_process_recorded = false
	if !opened {
		state.sequence_failure = failure
		return ksawery_workflow_sequence_outcome(
			.Observation_Process_Failed if poll.state == .Failed else .Observation_Unavailable,
		), true
	}
	next_conflict := ksawery_workflow_reconcile_conflict_selection(
		&state.sequence, &observation, state.conflict_selection,
	)
	if state.sequence.state != nil do ksawery.sequence_observation_close(&state.sequence)
	state.sequence = observation
	state.sequence_failure = .None
	_ = ksawery_extension_annotations_refresh_sequence(
		&state.extension_registry,
		&commands.host,
		&state.sequence,
		commands.temporary_allocator,
	)
	descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	if !described || descriptor.conflict_count == 0 {
		state.conflict_selection = 0
	} else {
		state.conflict_selection = next_conflict
	}
	if !described || descriptor.state == .Inactive {
		if state.view_mode == .Sequence || state.view_mode == .Conflict do state.view_mode = .Status
	} else if descriptor.conflict_count == 0 && state.view_mode == .Conflict {
		state.view_mode = .Sequence
	}
	return ksawery_workflow_sequence_outcome(.Observation_Applied), true
}

@(private)
ksawery_workflow_complete_sequence :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Sequence_Coordination ||
	   state.process.state == nil {
		return {}, false
	}
	#partial switch state.pending {
	case .Sequence_Observe:
		return ksawery_workflow_complete_sequence_observation(commands, poll)
	case .Merge_Precondition:
		return ksawery_workflow_finish_merge_precondition(commands, poll)
	case .Rebase_Precondition:
		return ksawery_workflow_finish_rebase_precondition(commands, poll)
	case .Revision_Sequence_Precondition:
		return ksawery_workflow_finish_revision_sequence_precondition(commands, poll)
	case .Bisect_Precondition:
		return ksawery_workflow_finish_bisect_precondition(commands, poll)
	case .Conflict_Precondition:
		return ksawery_workflow_finish_conflict_precondition(commands, poll)
	case .Merge, .Rebase, .Conflict_Resolution:
		return ksawery_workflow_finish_sequence_mutation_process(commands)
	case .Revision_Sequence:
		return ksawery_workflow_finish_revision_sequence_process(commands)
	case .Bisect:
		return ksawery_workflow_finish_bisect_process(commands)
	case:
		return {}, false
	}
}

@(private)
ksawery_workflow_complete_raw_command_process :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil do return {}, false
	state := commands.ksawery_workflow
	if state.pending != .Raw_Command || state.process.state == nil do return {}, false
	_, _, view, output, diagnostic, _, viewed :=
		ksawery.repository_process_raw_repository_command_snapshot(&state.process)
	if !viewed || (view.owner_state != .Completed && view.owner_state != .Failed) do return {}, false
	proposal, prepared := ksawery_process_observation_current_proposal(
		&state.process_coordinator, ksawery_workflow_now(commands),
	)
	published := false
	publish_failure := ksawery.Failure_Code.Cleanup
	if prepared {
		proposal.lifecycle = .Running
		proposal.phase = .Refreshing
		proposal.phase_detail = "Preparing full repository refresh after raw command"
		proposal.output = nil
		proposal.diagnostic = nil
		proposal.output_truncated = view.output_truncated || len(output) > 0
		proposal.diagnostic_truncated = view.diagnostic_truncated || len(diagnostic) > 0
		proposal.exit_status = view.child.exit_status
		proposal.exit_status_available = view.child.exit_status_available
		proposal.progress = {
			kind = .Determinate,
			current = u64(len(output)) + u64(len(diagnostic)),
			total = state.raw_request.intent.limits.output_bytes +
				state.raw_request.intent.limits.diagnostic_bytes,
		}
		proposal.actions = {}
		proposal.actions[0] = {kind = .Inspect, available = true}
		proposal.action_count = 1
		published, publish_failure = ksawery_process_coordinator_publish(
			&state.process_coordinator, &state.process, proposal,
		)
	}
	if !published {
		state.process_failure = publish_failure
		command_context_set_diagnostic(commands, "Raw repository command terminal Process evidence could not be recorded")
	}
	_, _, terminal, _, _, _, terminal_viewed :=
		ksawery.repository_process_raw_repository_command_snapshot(&state.process)
	if !terminal_viewed do terminal = view
	state.raw_terminal = terminal
	state.raw_terminal.output_bytes = u64(len(output))
	state.raw_terminal.diagnostic_bytes = u64(len(diagnostic))
	if terminal_viewed {
		detached, detach_failure := ksawery_process_operation_detach_child(
			&state.process_coordinator,
			&state.process,
		)
		if !detached do state.process_failure = detach_failure
	}
	state.raw_awaiting_refresh = true
	state.raw_refresh_completed = {.Process}
	state.raw_refresh = .Status
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Preserve,
		refresh = .Advance_Raw_Command,
		presentation = .Preserve,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = "Refreshing repository truth after raw command",
	}, true
}

@(private)
ksawery_workflow_start_raw_command_refresh :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if !state.raw_awaiting_refresh || state.process.state != nil do return false
	return_mode := state.raw_return_mode
	return_position := state.raw_return_position
	started := false
	switch state.raw_refresh {
	case .Status:
		started = ksawery_workflow_refresh(commands)
	case .History:
		started = ksawery_workflow_start_history(commands, .History_Refresh)
	case .Refs:
		started = ksawery_workflow_start_refs(commands, .Refs_Refresh)
	case .Sequence:
		started = ksawery_workflow_start_sequence_observation(commands)
	case .None:
		return false
	}
	if started {
		if ksawery_workflow_raw_return_mode_is_valid(return_mode) {
			state.view_mode = return_mode
			state.position = return_position
		}
		state.failure = .None
	}
	return started
}

@(private)
ksawery_workflow_advance_raw_command_refresh :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	for state.raw_awaiting_refresh && state.process.state == nil {
		switch state.raw_refresh {
		case .Status:   state.raw_refresh = .History
		case .History:  state.raw_refresh = .Refs
		case .Refs:     state.raw_refresh = .Sequence
		case .Sequence: return ksawery_workflow_finish_raw_command_refresh(commands)
		case .None:     return false
		}
		if ksawery_workflow_start_raw_command_refresh(commands) do return true
	}
	return false
}

@(private)
ksawery_workflow_complete_raw_command_refresh_child :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil do return {}, false
	state := commands.ksawery_workflow
	if !state.raw_awaiting_refresh || state.process.state == nil ||
	   (poll.state != .Completed && poll.state != .Failed) {
		return {}, false
	}
	opened := false
	failure := poll.failure
	switch state.raw_refresh {
	case .Status:
		observation: ksawery.Status_Observation
		if poll.state == .Completed {
			observation, opened, failure = ksawery.repository_process_take_status(
				&state.process, state.generation, commands.persistent_allocator,
			)
		}
		if opened {
			confirmed, confirm_failure := ksawery_process_observation_confirm_refresh(
				&state.process_coordinator, state.generation,
			)
			if !confirmed {
				opened = false
				failure = confirm_failure
				ksawery.status_observation_close(&observation)
			}
		}
		if opened {
			document := &state.diff if state.diff.state != nil else nil
			next_selection, reconciled, _ := ksawery.status_selection_reconcile(
				&state.observation, &observation, state.selection, document,
			)
			if state.observation.state != nil do ksawery.status_observation_close(&state.observation)
			state.observation = observation
			state.selection = next_selection if reconciled else ksawery.Status_Selection{}
			if !reconciled do state.selection, _ = ksawery.status_selection_begin(&state.observation)
			_ = ksawery_extension_status_refresh(
				&state.extension_registry,
				&commands.host,
				&state.observation,
				commands.temporary_allocator,
			)
			state.raw_refresh_completed += {.Status}
		}
	case .History:
		history: ksawery.History_Observation
		if poll.state == .Completed {
			history, opened, failure = ksawery.repository_process_take_history(
				&state.process, state.history_generation, commands.persistent_allocator,
			)
		}
		if opened {
			if state.history.state != nil do ksawery.history_observation_close(&state.history)
			state.history = history
			state.history_selection, _ = ksawery.history_selection_begin(&state.history)
			_ = ksawery_extension_annotations_refresh_history(
				&state.extension_registry, &commands.host, &state.history,
				commands.temporary_allocator,
			)
			state.raw_refresh_completed += {.History}
		}
	case .Refs:
		refs: ksawery.Ref_Observation
		if poll.state == .Completed {
			refs, opened, failure = ksawery.repository_process_take_refs(
				&state.process, state.ref_generation, commands.persistent_allocator,
			)
		}
		if opened {
			if state.refs.state != nil do ksawery.ref_observation_close(&state.refs)
			state.refs = refs
			state.ref_selection, _ = ksawery.ref_selection_begin(&state.refs)
			_ = ksawery_extension_annotations_refresh_refs(
				&state.extension_registry, &commands.host, &state.refs,
				commands.temporary_allocator,
			)
			state.raw_refresh_completed += {.Refs}
		}
	case .Sequence:
		sequence: ksawery.Sequence_Observation
		if poll.state == .Completed {
			sequence, opened, failure = ksawery.repository_process_take_sequence(
				&state.process, state.sequence_generation, commands.persistent_allocator,
			)
		}
		if opened {
			if state.sequence.state != nil do ksawery.sequence_observation_close(&state.sequence)
			state.sequence = sequence
			state.conflict_selection = 0
			_ = ksawery_extension_annotations_refresh_sequence(
				&state.extension_registry, &commands.host, &state.sequence,
				commands.temporary_allocator,
			)
			state.raw_refresh_completed += {.Sequence, .Conflict}
		}
	case .None:
		return {}, false
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator, &state.process,
	)
	if !detached do state.process_failure = detach_failure
	if !opened do state.failure = failure
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Preserve,
		refresh = .Advance_Raw_Command,
		presentation = .Preserve,
		diagnostic_intent = .Preserve,
	}, true
}

@(private)
ksawery_workflow_complete_raw_command :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Raw_Command do return {}, false
	if state.pending == .Raw_Command {
		return ksawery_workflow_complete_raw_command_process(commands)
	}
	return ksawery_workflow_complete_raw_command_refresh_child(commands, poll)
}

@(private)
ksawery_workflow_finish_raw_command_refresh :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if !state.raw_awaiting_refresh || state.process.state != nil ||
	   !ksawery.raw_repository_command_request_is_valid(state.raw_request) {
		return false
	}
	request := state.raw_request
	refreshed_generation := ksawery.Repository_Generation(state.generation)
	if refreshed_generation <= request.intent.repository_generation {
		refreshed_generation = request.intent.repository_generation + 1
	}
	evidence := ksawery.Raw_Repository_Command_Refresh_Evidence {
		repository = state.repository,
		repository_generation = refreshed_generation,
		attempted = ksawery.RAW_REPOSITORY_COMMAND_REFRESH,
		completed = state.raw_refresh_completed,
	}
	if .Status in evidence.completed {
		descriptor, described := ksawery.status_observation_descriptor(&state.observation)
		if described {
			evidence.operation_checked = true
			evidence.operation = descriptor.operation
		}
	}
	refresh_completed, verifier_applied, verifier_agreed, valid :=
		ksawery.raw_repository_command_verifier_apply(request, evidence)
	terminal := state.raw_terminal
	result := ksawery.Raw_Repository_Command_Result {
		command = request.intent.command,
		mode = request.intent.input.mode,
		repository = request.intent.repository,
		process = {association = terminal.association, started = true, detached = true},
		failure = terminal.failure,
		effect_possible = terminal.child.children_started > 0,
		exit_code_present = terminal.child.exit_status_available,
		exit_code = terminal.child.exit_status,
		refresh_completed = refresh_completed,
		verifier_applied = verifier_applied,
		verifier_agreed = verifier_agreed,
		output_bytes = terminal.output_bytes,
		diagnostic_bytes = 0,
		output_truncated = terminal.output_truncated,
		diagnostic_truncated = terminal.diagnostic_truncated,
		diagnostic_omitted = true,
		cleanup = {
			input_cleared = true,
			confirmation_cleared = true,
			child_closed = true,
			association_detached = true,
		},
	}
	resolution := Ksawery_Process_Resolution{}
	message := "Raw repository command outcome is indeterminate"
	if terminal.termination.reason == .Cancellation {
		result.outcome = .Cancelled_After_Possible_Effect
		result.failure = .Cancelled
		resolution = {lifecycle = .Cancelled, outcome = result.outcome, failure = .Cancelled}
		message = "Raw repository command cancelled after possible effect"
	} else if terminal.termination.reason == .Timeout {
		result.outcome = .Timed_Out_After_Possible_Effect
		result.failure = .Timeout
		resolution = {lifecycle = .Timed_Out, outcome = result.outcome, failure = .Timeout}
		message = "Raw repository command timed out after possible effect"
	} else if terminal.owner_state == .Failed ||
	          (terminal.child.exit_status_available && terminal.child.exit_status != 0) {
		result.outcome = .Known_Failure
		if result.failure == .None do result.failure = .Process_Failed
		resolution = {lifecycle = .Failed, outcome = result.outcome, failure = result.failure}
		message = "Raw repository command failed"
	} else if valid && refresh_completed && verifier_applied && verifier_agreed {
		result.outcome = .Verified_Success
		resolution = {lifecycle = .Succeeded, outcome = result.outcome}
		message = "Raw repository command outcome verified"
	} else if valid && refresh_completed && verifier_applied && !verifier_agreed {
		result.outcome = .Verification_Mismatch
		resolution = {lifecycle = .Failed, outcome = result.outcome}
		message = "Raw repository command verification mismatched"
	} else {
		result.outcome = .Indeterminate
		resolution = {lifecycle = .Indeterminate, outcome = result.outcome, failure = result.failure}
	}
	validation_failure := ksawery.raw_repository_command_result_validate(result, request)
	result_failure := ksawery.Raw_Repository_Command_Failure{}
	if !valid || validation_failure.code != .None {
		result_failure = validation_failure
		if !valid do result_failure = {code = .Invalid_Refresh, command = request.intent.command}
		result.outcome = .Indeterminate
		resolution = {lifecycle = .Indeterminate, outcome = .Indeterminate, failure = .Cleanup}
		message = "Raw repository command result evidence was incomplete"
	}
	finished, finish_failure := ksawery_process_operation_finish_resolution(
		&state.process_coordinator, nil, resolution, message, ksawery_workflow_now(commands),
	)
	if !finished do state.process_failure = finish_failure
	return_mode := state.raw_return_mode
	return_position := state.raw_return_position
	ksawery_workflow_clear_raw_command(state)
	state.raw_result = result
	state.raw_failure = result_failure
	state.view_mode = return_mode if ksawery_workflow_raw_return_mode_is_valid(return_mode) else .Status
	state.position = return_position
	state.failure = .None
	command_context_set_diagnostic(commands, message)
	return true
}

@(private)
ksawery_workflow_repository_observation_outcome :: proc(
	result: Ksawery_Workflow_Observation_Result,
	diagnostic: string = "",
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = .Complete_Repository_Observation,
		observation_result = result,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_repository_observation_failure :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil || poll.state != .Failed {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Repository_Observation do return {}, false
	if state.commit_refresh != .None && state.process_coordinator.active {
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator, state.operation_effect, .Unavailable, 0, true,
		)
		if resolved {
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				"Repository commit outcome is indeterminate",
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
	} else if (state.fetch_refresh != .None || state.push_refresh != .None ||
	           state.branch_refresh != .None || state.tag_refresh != .None) &&
	          state.process_coordinator.active {
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator, state.operation_effect, .Unavailable, 0, true,
		)
		if resolved {
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				"Repository synchronization outcome is indeterminate",
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
	} else if state.pending == .Refresh && state.mutation_refresh != .None {
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator, state.operation_effect, .Unavailable, 0, true,
		)
		if resolved {
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				"Repository mutation outcome is indeterminate",
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
	} else if state.process_coordinator.active {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository observation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	if state.pending == .Refresh {
		state.generation = state.process_coordinator.confirmed_observation
	}
	state.failure = poll.failure
	return ksawery_workflow_repository_observation_outcome(
		.Process_Failed, "Repository status observation failed",
	), true
}

@(private)
ksawery_workflow_complete_repository_observation_success :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil do return {}, false
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Repository_Observation ||
	   (state.pending != .Observe && state.pending != .Refresh) ||
	   state.process.state == nil {
		return {}, false
	}
	pending := state.pending
	observation, opened, failure := ksawery.repository_process_take_status(
		&state.process, state.generation, commands.persistent_allocator,
	)
	if opened && pending == .Refresh {
		confirmed, confirm_failure := ksawery_process_observation_confirm_refresh(
			&state.process_coordinator, state.generation,
		)
		if !confirmed {
			opened = false
			failure = confirm_failure
			ksawery.status_observation_close(&observation)
		}
	}
	if state.commit_refresh == .Status && state.process_coordinator.active {
		if opened {
			detached, detach_failure := ksawery_process_operation_detach_child(
				&state.process_coordinator, &state.process,
			)
			if !detached do state.process_failure = detach_failure
		} else {
			resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
				&state.process_coordinator, state.operation_effect, .Unavailable, 0, true,
			)
			if resolved {
				recorded, record_failure := ksawery_process_operation_finish_resolution(
					&state.process_coordinator,
					&state.process,
					resolution,
					"Repository commit outcome is indeterminate",
					ksawery_workflow_now(commands),
				)
				if !recorded do state.process_failure = record_failure
			} else {
				state.process_failure = resolve_failure
			}
			state.commit_refresh = .None
			ksawery_workflow_clear_operation_resolution(state)
		}
	} else if state.sequence_mutation_refresh && state.process_coordinator.active {
		if opened {
			detached, detach_failure := ksawery_process_operation_detach_child(
				&state.process_coordinator, &state.process,
			)
			if !detached do state.process_failure = detach_failure
		}
	} else if (state.fetch_refresh != .None || state.push_refresh != .None ||
	           state.branch_refresh != .None || state.tag_refresh != .None ||
	           state.sequence_mutation_history_refresh) &&
	          state.process_coordinator.active {
		detached, detach_failure := ksawery_process_operation_detach_child(
			&state.process_coordinator, &state.process,
		)
		if !detached do state.process_failure = detach_failure
	} else if state.mutation_refresh != .None {
		verification := state.operation_verification if opened else Ksawery_Repository_Verification_State.Unavailable
		refreshed_generation := state.generation if opened else ksawery.Observation_Generation(0)
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator, state.operation_effect, verification, refreshed_generation, true,
		)
		if resolved {
			message := "Repository mutation verified"
			if resolution.lifecycle == .Failed do message = "Repository mutation failed"
			if resolution.lifecycle == .Cancelled do message = "Repository mutation cancelled"
			if resolution.lifecycle == .Timed_Out do message = "Repository mutation timed out"
			if resolution.lifecycle == .Indeterminate do message = "Repository mutation outcome is indeterminate"
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				message,
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
	} else {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			opened,
			"Repository status available" if opened else "Repository status observation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	if !opened && state.sequence_mutation_refresh {
		ksawery_workflow_finish_sequence_mutation_refresh(commands, false)
	}
	if !opened {
		if pending == .Refresh {
			state.generation = state.process_coordinator.confirmed_observation
		}
		state.failure = failure
		return ksawery_workflow_repository_observation_outcome(
			.Unavailable, "Repository status observation failed",
		), true
	}
	if pending == .Refresh && state.observation.state != nil {
		document := &state.diff if state.diff.state != nil else nil
		next_selection, reconciled, _ := ksawery.status_selection_reconcile(
			&state.observation, &observation, state.selection, document,
		)
		if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
		if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
		if state.grouped.state != nil {
			_, _, _ = ksawery.grouped_selection_reconcile(&state.grouped, &observation)
		}
		state.diff_failure = .None
		ksawery.status_observation_close(&state.observation)
		state.observation = observation
		if reconciled {
			state.selection = next_selection
		} else {
			state.selection, _ = ksawery.status_selection_begin(&state.observation)
		}
	} else {
		state.observation = observation
		state.selection, _ = ksawery.status_selection_begin(&state.observation)
	}
	_ = ksawery_extension_status_refresh(
		&state.extension_registry,
		&commands.host,
		&state.observation,
		commands.temporary_allocator,
	)
	diff := &state.diff if state.diff.state != nil else nil
	_ = ksawery_extension_annotations_refresh_status(
		&state.extension_registry,
		&commands.host,
		&state.observation,
		diff,
		commands.temporary_allocator,
	)
	state.extension_status = ksawery_extension_status_generation(&state.extension_registry)
	if state.grouped.state == nil {
		grouped, grouped_opened, grouped_failure := ksawery.grouped_selection_open(
			&state.observation,
			ksawery.DEFAULT_GROUPED_SELECTION_LIMITS,
			commands.persistent_allocator,
		)
		if grouped_opened {
			state.grouped = grouped
		} else {
			state.failure = grouped_failure
			return ksawery_workflow_repository_observation_outcome(
				.Grouping_Unavailable, "Repository group selection was unavailable",
			), true
		}
	}
	return ksawery_workflow_repository_observation_outcome(.Applied), true
}

@(private)
ksawery_workflow_complete_repository_observation :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if !ksawery_workflow_poll_is_terminal(poll) do return {}, false
	if poll.state == .Failed {
		return ksawery_workflow_complete_repository_observation_failure(commands, poll)
	}
	return ksawery_workflow_complete_repository_observation_success(commands)
}

@(private)
ksawery_workflow_history_outcome :: proc(
	result: Ksawery_Workflow_History_Result,
	diagnostic: string = "",
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = .Complete_History,
		history_result = result,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_history_failure :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if state.commit_refresh != .None && state.process_coordinator.active {
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator, state.operation_effect, .Unavailable, 0, true,
		)
		if resolved {
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				"Repository commit outcome is indeterminate",
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
	} else if (state.fetch_refresh != .None || state.push_refresh != .None ||
	           state.branch_refresh != .None || state.tag_refresh != .None) &&
	          state.process_coordinator.active {
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator, state.operation_effect, .Unavailable, 0, true,
		)
		if resolved {
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				"Repository synchronization outcome is indeterminate",
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
	} else if state.process_coordinator.active {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository history observation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	state.failure = poll.failure
	return ksawery_workflow_history_outcome(
		.Process_Failed, "Repository history observation failed",
	), true
}

@(private)
ksawery_workflow_complete_history_success :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	history, opened, failure := ksawery.repository_process_take_history(
		&state.process, state.history_generation, commands.persistent_allocator,
	)
	if state.commit_refresh == .History && state.process_coordinator.active {
		verification := Ksawery_Repository_Verification_State.Unavailable
		if opened {
			verification = state.operation_verification
			if verification == .Verified {
				result_descriptor, result_described := ksawery.commit_result_descriptor(&state.commit_result)
				history_descriptor, history_described := ksawery.history_observation_descriptor(&history)
				if !result_described || !history_described ||
				   history_descriptor.head != result_descriptor.lineage.resulting {
					verification = .Mismatch
				}
			}
		}
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator,
			state.operation_effect,
			verification,
			state.generation if opened else ksawery.Observation_Generation(0),
			true,
		)
		if resolved {
			message := "Repository commit verified"
			if resolution.lifecycle == .Failed do message = "Repository commit failed"
			if resolution.lifecycle == .Cancelled do message = "Repository commit cancelled"
			if resolution.lifecycle == .Timed_Out do message = "Repository commit timed out"
			if resolution.lifecycle == .Indeterminate do message = "Repository commit outcome is indeterminate"
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				message,
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
		if !opened do state.commit_refresh = .None
	} else if (state.fetch_refresh != .None || state.push_refresh != .None ||
	           state.branch_refresh != .None || state.tag_refresh != .None) &&
	          state.process_coordinator.active {
		detached, detach_failure := ksawery_process_operation_detach_child(
			&state.process_coordinator,
			&state.process,
		)
		if !detached do state.process_failure = detach_failure
	} else {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			opened,
			"Repository history available" if opened else "Repository history observation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	if !opened {
		state.failure = failure
		return ksawery_workflow_history_outcome(.Unavailable), true
	}
	next_history_selection: ksawery.History_Selection
	history_reconciled := false
	if state.sequence_mutation_history_refresh && state.history.state != nil {
		next_history_selection, history_reconciled, _ = ksawery.history_selection_reconcile(
			&state.history, &history, state.history_selection,
		)
	}
	if state.history.state != nil do ksawery.history_observation_close(&state.history)
	state.history = history
	_ = ksawery_extension_annotations_refresh_history(
		&state.extension_registry,
		&commands.host,
		&state.history,
		commands.temporary_allocator,
	)
	if history_reconciled {
		state.history_selection = next_history_selection
	} else {
		state.history_selection, _ = ksawery.history_selection_begin(&state.history)
	}
	state.position = {}
	return ksawery_workflow_history_outcome(.Applied), true
}

@(private)
ksawery_workflow_complete_history :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .History || state.process.state == nil {
		return {}, false
	}
	if poll.state == .Failed do return ksawery_workflow_complete_history_failure(commands, poll)
	return ksawery_workflow_complete_history_success(commands)
}

@(private)
ksawery_workflow_refs_outcome :: proc(
	result: Ksawery_Workflow_Refs_Result,
	diagnostic: string = "",
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = .Complete_Refs,
		refs_result = result,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_refs_failure :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	if (state.fetch_refresh != .None || state.push_refresh != .None ||
	    state.branch_refresh != .None || state.tag_refresh != .None) &&
	   state.process_coordinator.active {
		resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
			&state.process_coordinator, state.operation_effect, .Unavailable, 0, true,
		)
		if resolved {
			recorded, record_failure := ksawery_process_operation_finish_resolution(
				&state.process_coordinator,
				&state.process,
				resolution,
				"Repository synchronization outcome is indeterminate",
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		} else {
			state.process_failure = resolve_failure
		}
		ksawery_workflow_clear_operation_resolution(state)
	} else if state.process_coordinator.active {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository ref observation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	state.failure = poll.failure
	return ksawery_workflow_refs_outcome(
		.Process_Failed, "Repository status observation failed",
	), true
}

@(private)
ksawery_workflow_complete_refs_success :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	pending := state.pending
	refs, opened, failure := ksawery.repository_process_take_refs(
		&state.process, state.ref_generation, commands.persistent_allocator,
	)
	if (state.fetch_refresh != .None || state.push_refresh != .None ||
	    state.branch_refresh != .None || state.tag_refresh != .None ||
	    state.sequence_mutation_refresh) &&
	   state.process_coordinator.active {
		detached, detach_failure := ksawery_process_operation_detach_child(
			&state.process_coordinator,
			&state.process,
		)
		if !detached do state.process_failure = detach_failure
	} else {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			opened,
			"Repository refs available" if opened else "Repository ref observation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	if !opened {
		state.failure = failure
		return ksawery_workflow_refs_outcome(.Unavailable), true
	}
	if pending == .Refs_Refresh && state.refs.state != nil {
		next_selection, reconciled, _ := ksawery.ref_selection_reconcile(
			&state.refs, &refs, state.ref_selection,
		)
		ksawery.ref_observation_close(&state.refs)
		state.refs = refs
		if reconciled {
			state.ref_selection = next_selection
		} else {
			state.ref_selection, _ = ksawery.ref_selection_begin(&state.refs)
		}
	} else {
		if state.refs.state != nil do ksawery.ref_observation_close(&state.refs)
		state.refs = refs
		state.ref_selection, _ = ksawery.ref_selection_begin(&state.refs)
	}
	_ = ksawery_extension_annotations_refresh_refs(
		&state.extension_registry,
		&commands.host,
		&state.refs,
		commands.temporary_allocator,
	)
	state.position = {}
	return ksawery_workflow_refs_outcome(.Applied), true
}

@(private)
ksawery_workflow_complete_refs :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Refs_And_Synchronization ||
	   (state.pending != .Refs_Observe && state.pending != .Refs_Refresh) ||
	   state.process.state == nil {
		return {}, false
	}
	if poll.state == .Failed do return ksawery_workflow_complete_refs_failure(commands, poll)
	return ksawery_workflow_complete_refs_success(commands)
}

@(private)
ksawery_workflow_synchronization_outcome :: proc(
	result: Ksawery_Workflow_Synchronization_Result = .None,
	failed: bool = false,
	diagnostic: string = "",
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = .Complete_Synchronization if result != .None else .None,
		synchronization_result = result,
		synchronization_failed = failed,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_remote_configuration :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	configuration: ksawery.Remote_Configuration_Identity
	opened := false
	failure := poll.failure
	if poll.state == .Completed {
		configuration, opened, failure = ksawery.repository_process_take_remote_configuration(&state.process)
	}
	if !opened {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Selected remote configuration could not be checked", ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = failure
		return ksawery_workflow_synchronization_outcome(
			.None, false, "Selected remote configuration could not be checked",
		), true
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator,
		&state.process,
	)
	if !detached {
		state.process_failure = detach_failure
		state.failure = detach_failure
		return ksawery_workflow_synchronization_outcome(), true
	}
	state.fetch_configuration = configuration
	return ksawery_workflow_synchronization_outcome(.Start_Prepared_Fetch), true
}

@(private)
ksawery_workflow_complete_push_configuration :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	configuration: ksawery.Push_Configuration_Identity
	opened := false
	failure := poll.failure
	if poll.state == .Completed {
		configuration, opened, failure = ksawery.repository_process_take_push_configuration(&state.process)
	}
	if !opened {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Selected remote push destination could not be checked", ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = failure
		return ksawery_workflow_synchronization_outcome(
			.None, false, "Selected remote push destination could not be checked",
		), true
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator,
		&state.process,
	)
	if !detached {
		state.process_failure = detach_failure
		state.failure = detach_failure
		return ksawery_workflow_synchronization_outcome(), true
	}
	state.push_configuration = configuration
	return ksawery_workflow_synchronization_outcome(.Prepare_Push_Confirmation), true
}

@(private)
ksawery_workflow_prepare_synchronization_outcome :: proc(
	commands: ^Command_Context,
	verification: Ksawery_Repository_Verification_State,
	start_result: Ksawery_Workflow_Synchronization_Result,
	finish_result: Ksawery_Workflow_Synchronization_Result,
	failure_message: string,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	effect, prepared, prepare_failure := ksawery_process_operation_prepare_refresh(
		&state.process_coordinator,
		&state.process,
		"Refreshing repository observations",
		ksawery_workflow_now(commands),
	)
	if !prepared {
		state.process_failure = prepare_failure
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			failure_message, ksawery_workflow_now(commands),
		)
		return ksawery_workflow_synchronization_outcome(finish_result, true), true
	}
	state.operation_effect = effect
	state.operation_verification = verification
	return ksawery_workflow_synchronization_outcome(start_result), true
}

@(private)
ksawery_workflow_complete_fetch :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_fetch(
		&state.process, commands.persistent_allocator,
	)
	if !opened {
		state.failure = failure
		state.fetch_configuration = {}
		state.fetch_request = {}
	} else {
		if state.fetch_result.state != nil do ksawery.fetch_result_close(&state.fetch_result)
		state.fetch_result = result
	}
	descriptor, described := ksawery.fetch_result_descriptor(&state.fetch_result)
	if described && !descriptor.refresh_required {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, descriptor.succeeded,
			"Repository remote fetch completed" if descriptor.succeeded else "Repository remote fetch failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		return ksawery_workflow_synchronization_outcome(.Finish_Fetch), true
	}
	verification := Ksawery_Repository_Verification_State.Unavailable
	if described do verification = .Verified if descriptor.succeeded else .Known_Failure
	return ksawery_workflow_prepare_synchronization_outcome(
		commands, verification, .Start_Fetch_Refresh, .Finish_Fetch,
		"Repository remote fetch could not refresh",
	)
}

@(private)
ksawery_workflow_complete_push :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_push(
		&state.process, commands.persistent_allocator,
	)
	if !opened {
		state.failure = failure
		state.push_configuration = {}
		state.push_precondition = {}
		state.push_confirmation = {}
		state.push_request = {}
	} else {
		if state.push_result.state != nil do ksawery.push_result_close(&state.push_result)
		state.push_result = result
	}
	descriptor, described := ksawery.push_result_descriptor(&state.push_result)
	if described && !descriptor.refresh_required {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, descriptor.succeeded,
			"Repository push completed" if descriptor.succeeded else "Repository push failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		return ksawery_workflow_synchronization_outcome(.Finish_Push), true
	}
	verification := Ksawery_Repository_Verification_State.Unavailable
	if described do verification = .Verified if descriptor.succeeded else .Known_Failure
	return ksawery_workflow_prepare_synchronization_outcome(
		commands, verification, .Start_Push_Refresh, .Finish_Push,
		"Repository push could not refresh",
	)
}

@(private)
ksawery_workflow_complete_branch :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_branch(
		&state.process, commands.persistent_allocator,
	)
	if !opened {
		state.failure = failure
		ksawery_workflow_clear_branch_preparation(state)
	} else {
		if state.branch_result.state != nil do ksawery.branch_result_close(&state.branch_result)
		state.branch_result = result
	}
	descriptor, described := ksawery.branch_result_descriptor(&state.branch_result)
	if described && !descriptor.refresh_required {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, descriptor.succeeded,
			"Local branch operation completed" if descriptor.succeeded else "Local branch operation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		return ksawery_workflow_synchronization_outcome(.Finish_Branch), true
	}
	verification := Ksawery_Repository_Verification_State.Unavailable
	if described do verification = .Verified if descriptor.succeeded else .Known_Failure
	return ksawery_workflow_prepare_synchronization_outcome(
		commands, verification, .Start_Branch_Refresh, .Finish_Branch,
		"Local branch operation could not refresh",
	)
}

@(private)
ksawery_workflow_complete_tag :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_tag(
		&state.process, commands.persistent_allocator,
	)
	if !opened {
		state.failure = failure
		ksawery_workflow_clear_tag_preparation(state)
	} else {
		if state.tag_result.state != nil do ksawery.tag_result_close(&state.tag_result)
		state.tag_result = result
	}
	descriptor, described := ksawery.tag_result_descriptor(&state.tag_result)
	if described && !descriptor.refresh_required {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, descriptor.succeeded,
			"Local tag operation completed" if descriptor.succeeded else "Local tag operation failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		return ksawery_workflow_synchronization_outcome(.Finish_Tag), true
	}
	verification := Ksawery_Repository_Verification_State.Unavailable
	if described do verification = .Verified if descriptor.succeeded else .Known_Failure
	return ksawery_workflow_prepare_synchronization_outcome(
		commands, verification, .Start_Tag_Refresh, .Finish_Tag,
		"Local tag operation could not refresh",
	)
}

@(private)
ksawery_workflow_complete_synchronization :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Refs_And_Synchronization ||
	   state.process.state == nil {
		return {}, false
	}
	#partial switch state.pending {
	case .Remote_Configuration: return ksawery_workflow_complete_remote_configuration(commands, poll)
	case .Fetch:                return ksawery_workflow_complete_fetch(commands)
	case .Push_Configuration:   return ksawery_workflow_complete_push_configuration(commands, poll)
	case .Push:                 return ksawery_workflow_complete_push(commands)
	case .Branch:               return ksawery_workflow_complete_branch(commands)
	case .Tag:                  return ksawery_workflow_complete_tag(commands)
	case:
		return {}, false
	}
}

@(private)
ksawery_workflow_revision_inspection_outcome :: proc(
	diagnostic: string = "",
	process: Ksawery_Workflow_Process_Disposition = .Close,
	next_pending: Ksawery_Pending_Operation = .None,
	replacement_process: ksawery.Repository_Process = {},
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = next_pending,
		process = process,
		replacement_process = replacement_process,
		resolution = .Handler_Published,
		refresh = .None,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_revision_inspection_failure :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	range_inspection := state.pending == .Revision_Range_Summary ||
	                    state.pending == .Revision_Range_Comparison
	process_message := "Repository revision inspection failed"
	diagnostic := process_message
	if range_inspection {
		process_message = "Repository revision-range inspection failed"
		diagnostic = process_message
	}
	if state.process_coordinator.active {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			process_message,
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
	}
	state.failure = poll.failure
	ksawery_workflow_clear_revision_inspection(state)
	return ksawery_workflow_revision_inspection_outcome(diagnostic), true
}

@(private)
ksawery_workflow_complete_revision_detail_metadata :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	metadata, available := ksawery.repository_process_revision_output(&state.process)
	owned_metadata: [dynamic]u8
	copied := false
	if available do owned_metadata, copied = ksawery_workflow_copy_revision_output(
		metadata, commands.persistent_allocator,
	)
	if !available || !copied {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository revision inspection failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = .Allocation if available else .Process_Failed
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision inspection failed",
		), true
	}
	staging, staging_opened := ksawery_workflow_revision_staging_open(commands.persistent_allocator)
	if !staging_opened {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository revision inspection failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		delete(owned_metadata)
		state.failure = .Allocation
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision inspection failed",
		), true
	}
	staging.metadata = owned_metadata
	comparison, started, failure := ksawery.repository_process_start_revision_detail_comparison(
		&state.history,
		state.revision_detail_request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository revision comparison could not start",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		delete(staging.metadata)
		free(staging, commands.persistent_allocator)
		state.failure = failure
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision comparison could not start",
		), true
	}
	recorded, record_failure := ksawery_process_observation_replace_child(
		&state.process_coordinator,
		&state.process,
		&comparison,
		"Reading revision comparison",
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&comparison)
		delete(staging.metadata)
		free(staging, commands.persistent_allocator)
		state.failure = record_failure
		state.process_failure = record_failure
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision comparison could not start",
		), true
	}
	state.revision_staging = staging
	state.failure = .None
	return ksawery_workflow_revision_inspection_outcome(
		"", .Replace, .Revision_Detail_Comparison, comparison,
	), true
}

@(private)
ksawery_workflow_complete_revision_detail_comparison :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	comparison, available := ksawery.repository_process_revision_output(&state.process)
	staging := state.revision_staging
	detail, opened, failure := ksawery.revision_detail_open(
		state.repository,
		state.revision_detail_request,
		staging.metadata[:] if staging != nil else nil,
		comparison,
		poll.failure == .Output_Limit,
		commands.persistent_allocator,
	)
	recorded, record_failure := ksawery_process_observation_finish(
		&state.process_coordinator,
		&state.process,
		available && opened,
		"Repository revision detail available" if available && opened else "Repository revision inspection failed",
		ksawery_workflow_now(commands),
	)
	if !recorded do state.process_failure = record_failure
	if staging != nil && staging.metadata != nil do delete(staging.metadata)
	if staging != nil do staging.metadata = {}
	if !available || !opened {
		state.failure = failure if available else .Process_Failed
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision inspection failed",
		), true
	}
	if state.revision_detail.state != nil do ksawery.revision_detail_close(&state.revision_detail)
	state.revision_detail = detail
	state.failure = .None
	return ksawery_workflow_revision_inspection_outcome(), true
}

@(private)
ksawery_workflow_complete_revision_range_summary :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	summary, available := ksawery.repository_process_revision_output(&state.process)
	owned_summary: [dynamic]u8
	copied := false
	if available do owned_summary, copied = ksawery_workflow_copy_revision_output(
		summary, commands.persistent_allocator,
	)
	if !available || !copied {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository revision-range inspection failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = .Allocation if available else .Process_Failed
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision-range inspection failed",
		), true
	}
	staging, staging_opened := ksawery_workflow_revision_staging_open(commands.persistent_allocator)
	if !staging_opened {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository revision-range inspection failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		delete(owned_summary)
		state.failure = .Allocation
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision-range inspection failed",
		), true
	}
	staging.summary = owned_summary
	comparison, started, failure := ksawery.repository_process_start_revision_range_comparison(
		&state.history,
		state.revision_range_request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository revision-range comparison could not start",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		delete(staging.summary)
		free(staging, commands.persistent_allocator)
		state.failure = failure
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision-range comparison could not start",
		), true
	}
	recorded, record_failure := ksawery_process_observation_replace_child(
		&state.process_coordinator,
		&state.process,
		&comparison,
		"Reading revision range comparison",
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&comparison)
		delete(staging.summary)
		free(staging, commands.persistent_allocator)
		state.failure = record_failure
		state.process_failure = record_failure
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision-range comparison could not start",
		), true
	}
	state.revision_staging = staging
	state.failure = .None
	return ksawery_workflow_revision_inspection_outcome(
		"", .Replace, .Revision_Range_Comparison, comparison,
	), true
}

@(private)
ksawery_workflow_complete_revision_range_comparison :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	comparison, available := ksawery.repository_process_revision_output(&state.process)
	staging := state.revision_staging
	observation, opened, failure := ksawery.revision_range_observation_open(
		state.repository,
		state.revision_range_request,
		staging.summary[:] if staging != nil else nil,
		comparison,
		poll.failure == .Output_Limit,
		commands.persistent_allocator,
	)
	recorded, record_failure := ksawery_process_observation_finish(
		&state.process_coordinator,
		&state.process,
		available && opened,
		"Repository revision range available" if available && opened else "Repository revision-range inspection failed",
		ksawery_workflow_now(commands),
	)
	if !recorded do state.process_failure = record_failure
	if staging != nil && staging.summary != nil do delete(staging.summary)
	if staging != nil do staging.summary = {}
	if !available || !opened {
		state.failure = failure if available else .Process_Failed
		return ksawery_workflow_revision_inspection_outcome(
			"Repository revision-range inspection failed",
		), true
	}
	if state.revision_range.state != nil do ksawery.revision_range_observation_close(&state.revision_range)
	state.revision_range = observation
	state.failure = .None
	return ksawery_workflow_revision_inspection_outcome(), true
}

@(private)
ksawery_workflow_complete_revision_inspection :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Revision_Inspection ||
	   state.process.state == nil {
		return {}, false
	}
	if state.pending == .Revision_Detail_Metadata && poll.state == .Completed {
		return ksawery_workflow_complete_revision_detail_metadata(commands)
	}
	if state.pending == .Revision_Detail_Comparison &&
	   (poll.state == .Completed || poll.failure == .Output_Limit) {
		return ksawery_workflow_complete_revision_detail_comparison(commands, poll)
	}
	if state.pending == .Revision_Range_Summary && poll.state == .Completed {
		return ksawery_workflow_complete_revision_range_summary(commands)
	}
	if state.pending == .Revision_Range_Comparison &&
	   (poll.state == .Completed || poll.failure == .Output_Limit) {
		return ksawery_workflow_complete_revision_range_comparison(commands, poll)
	}
	return ksawery_workflow_complete_revision_inspection_failure(commands, poll)
}

@(private)
ksawery_workflow_changes_and_index_outcome :: proc(
	diagnostic: string,
	refresh: Ksawery_Workflow_Refresh_Continuation = .None,
	mutation_refresh: Ksawery_Mutation_Refresh = .None,
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = refresh,
		mutation_refresh = mutation_refresh,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_path_detail :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil do return {}, false
	state := commands.ksawery_workflow
	if state.pending != .Detail || state.process.state == nil do return {}, false
	if poll.state != .Completed && poll.failure != .Output_Limit {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			"Repository path inspection failed",
			ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = poll.failure
		return ksawery_workflow_changes_and_index_outcome(
			"Repository path inspection failed",
		), true
	}
	detail, opened, failure := ksawery.repository_process_take_path_detail(
		&state.process, &state.observation, commands.persistent_allocator,
	)
	recorded, record_failure := ksawery_process_observation_finish(
		&state.process_coordinator,
		&state.process,
		opened,
		"Repository path detail available" if opened else "Repository path inspection failed",
		ksawery_workflow_now(commands),
	)
	if !recorded do state.process_failure = record_failure
	if !opened {
		state.failure = failure
		return ksawery_workflow_changes_and_index_outcome(
			"Repository path inspection failed",
		), true
	}
	if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
	if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
	state.detail = detail
	diff, parsed, diff_failure := ksawery.diff_document_open(
		&state.detail,
		ksawery.DEFAULT_DIFF_LIMITS,
		commands.persistent_allocator,
	)
	if parsed {
		state.diff = diff
		state.diff_failure = .None
		_ = ksawery_extension_annotations_refresh_status(
			&state.extension_registry,
			&commands.host,
			&state.observation,
			&state.diff,
			commands.temporary_allocator,
		)
	} else {
		state.diff_failure = diff_failure
	}
	state.failure = .None
	return ksawery_workflow_changes_and_index_outcome(""), true
}

@(private)
ksawery_workflow_prepare_index_refresh_outcome :: proc(
	commands: ^Command_Context,
	refresh: Ksawery_Mutation_Refresh,
	verification: Ksawery_Repository_Verification_State,
	diagnostic: string,
	refresh_failure_message: string,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	effect, prepared, prepare_failure := ksawery_process_operation_prepare_refresh(
		&state.process_coordinator,
		&state.process,
		"Refreshing repository status",
		ksawery_workflow_now(commands),
	)
	if !prepared {
		state.process_failure = prepare_failure
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator,
			&state.process,
			false,
			refresh_failure_message,
			ksawery_workflow_now(commands),
		)
		return ksawery_workflow_changes_and_index_outcome(diagnostic), true
	}
	state.operation_effect = effect
	state.operation_verification = verification
	return ksawery_workflow_changes_and_index_outcome(
		diagnostic, .Start_Mutation_Refresh, refresh,
	), true
}

@(private)
ksawery_workflow_complete_index_action :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_index_action(
		&state.process,
		commands.persistent_allocator,
	)
	verification := Ksawery_Repository_Verification_State.Unavailable
	diagnostic := "Repository index action result was unavailable"
	if !opened {
		state.failure = failure
	} else {
		if state.action.state != nil do ksawery.index_action_result_close(&state.action)
		state.action = result
		descriptor, described := ksawery.index_action_result_descriptor(&state.action)
		if described && descriptor.succeeded {
			verification = .Verified
			diagnostic = "Repository path staged" if descriptor.action == .Stage else "Repository path unstaged"
			state.failure = .None
		} else {
			verification = .Known_Failure
			state.failure = descriptor.failure if described else .Process_Failed
			diagnostic = "Repository index action failed"
		}
	}
	return ksawery_workflow_prepare_index_refresh_outcome(
		commands, .Index, verification, diagnostic, "Repository index action could not refresh",
	)
}

@(private)
ksawery_workflow_complete_partial_index_action :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_partial_index_action(
		&state.process,
		commands.persistent_allocator,
	)
	verification := Ksawery_Repository_Verification_State.Unavailable
	diagnostic := "Repository partial index result was unavailable"
	if !opened {
		state.failure = failure
	} else {
		if state.partial_action.state != nil {
			ksawery.partial_index_action_result_close(&state.partial_action)
		}
		state.partial_action = result
		descriptor, described := ksawery.partial_index_action_result_descriptor(&state.partial_action)
		if described && descriptor.succeeded {
			verification = .Verified
			diagnostic = "Repository hunk staged" if descriptor.request.action == .Stage else "Repository hunk unstaged"
			state.failure = .None
		} else {
			verification = .Known_Failure
			state.failure = descriptor.failure if described else .Process_Failed
			diagnostic = "Repository partial index action failed"
		}
	}
	return ksawery_workflow_prepare_index_refresh_outcome(
		commands, .Partial_Index, verification, diagnostic,
		"Repository partial index action could not refresh",
	)
}

@(private)
ksawery_workflow_complete_grouped_index_action :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_grouped_index_action(
		&state.process,
		commands.persistent_allocator,
	)
	verification := Ksawery_Repository_Verification_State.Unavailable
	diagnostic := "Repository grouped index result was unavailable"
	if !opened {
		state.failure = failure
	} else {
		if state.grouped_action.state != nil {
			ksawery.grouped_index_action_result_close(&state.grouped_action)
		}
		state.grouped_action = result
		descriptor, described := ksawery.grouped_index_action_result_descriptor(&state.grouped_action)
		if described && descriptor.succeeded {
			verification = .Verified
			diagnostic = "Repository group staged" if descriptor.request.selection.action == .Stage else "Repository group unstaged"
			state.failure = .None
		} else {
			verification = .Known_Failure
			state.failure = descriptor.failure if described else .Process_Failed
			diagnostic = "Repository grouped index action failed"
		}
	}
	return ksawery_workflow_prepare_index_refresh_outcome(
		commands, .Grouped_Index, verification, diagnostic,
		"Repository grouped index action could not refresh",
	)
}

@(private)
ksawery_workflow_complete_discard_action :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_discard_action(
		&state.process,
		commands.persistent_allocator,
	)
	verification := Ksawery_Repository_Verification_State.Unavailable
	diagnostic := "Repository discard result was unavailable"
	if !opened {
		state.failure = failure
	} else {
		if state.discard_action.state != nil do ksawery.discard_action_result_close(&state.discard_action)
		state.discard_action = result
		descriptor, described := ksawery.discard_action_result_descriptor(&state.discard_action)
		if described && descriptor.succeeded {
			verification = .Verified
			diagnostic = "Repository working-tree changes discarded"
			state.failure = .None
		} else {
			verification = .Known_Failure
			state.failure = descriptor.failure if described else .Process_Failed
			diagnostic = "Repository discard failed"
		}
	}
	return ksawery_workflow_prepare_index_refresh_outcome(
		commands, .Discard, verification, diagnostic, "Repository discard could not refresh",
	)
}

@(private)
ksawery_workflow_complete_changes_and_index :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Changes_And_Index ||
	   state.process.state == nil {
		return {}, false
	}
	#partial switch state.pending {
	case .Detail:                return ksawery_workflow_complete_path_detail(commands, poll)
	case .Index_Action:          return ksawery_workflow_complete_index_action(commands)
	case .Partial_Index_Action:  return ksawery_workflow_complete_partial_index_action(commands)
	case .Grouped_Index_Action:  return ksawery_workflow_complete_grouped_index_action(commands)
	case .Discard_Action:        return ksawery_workflow_complete_discard_action(commands)
	case:
		return {}, false
	}
}

@(private)
ksawery_workflow_commit_outcome :: proc(
	diagnostic: string = "",
	refresh: Ksawery_Workflow_Refresh_Continuation = .None,
) -> Ksawery_Workflow_Completion_Outcome {
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Published,
		refresh = refresh,
		presentation = .Handler_Applied,
		diagnostic_intent = .Publish if len(diagnostic) > 0 else .Preserve,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_commit_precondition :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	precondition, opened, failure := ksawery.repository_process_take_commit_precondition(&state.process)
	if !opened {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Repository commit precondition failed", ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = poll.failure if poll.failure != .None else failure
		return ksawery_workflow_commit_outcome(
			"Repository commit precondition failed",
		), true
	}
	if precondition.operation != .Normal || precondition.unmerged_paths != 0 ||
	   (state.commit_mode != .Amend && precondition.staged_paths == 0) ||
	   (state.commit_mode == .Amend && precondition.head.kind != .Revision) {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Checked repository state does not admit this commit", ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = .Commit_Unavailable
		return ksawery_workflow_commit_outcome(
			"Checked repository state does not admit the selected commit mode",
		), true
	}
	if state.commit_mode != .Normal && !ksawery_workflow_commit_history_matches(state, precondition) {
		recorded, record_failure := ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Repository commit precondition became stale", ksawery_workflow_now(commands),
		)
		if !recorded do state.process_failure = record_failure
		state.failure = .Stale_Observation
		return ksawery_workflow_commit_outcome(
			"Repository History no longer matches the checked commit state",
		), true
	}
	state.commit_precondition = precondition
	if state.commit_mode == .Fixup {
		if preview_failure := ksawery_workflow_prepare_fixup_preview(state); preview_failure != .None {
			recorded, record_failure := ksawery_process_observation_finish(
				&state.process_coordinator, &state.process, false,
				"Selected revision cannot prepare a fixup commit", ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
			state.failure = preview_failure
			return ksawery_workflow_commit_outcome(
				"Selected History revision cannot prepare a fixup commit",
			), true
		}
	}
	detached, detach_failure := ksawery_process_operation_detach_child(
		&state.process_coordinator,
		&state.process,
	)
	if !detached {
		state.process_failure = detach_failure
		state.failure = detach_failure
		return ksawery_workflow_commit_outcome(
			"Repository commit precondition could not be retained",
		), true
	}
	published, publish_failure := ksawery_process_operation_publish_phase(
		&state.process_coordinator,
		nil,
		.Checking,
		"Waiting for commit message",
		false,
		ksawery_workflow_now(commands),
	)
	if !published {
		state.process_failure = publish_failure
		state.failure = publish_failure
		return ksawery_workflow_commit_outcome(
			"Repository commit precondition could not be retained",
		), true
	}
	state.view_mode = .Commit_Message
	state.position = {}
	state.failure = .None
	return ksawery_workflow_commit_outcome(), true
}

@(private)
ksawery_workflow_complete_commit_process :: proc(
	commands: ^Command_Context,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	state := commands.ksawery_workflow
	result, opened, failure := ksawery.repository_process_take_commit(
		&state.process,
		commands.persistent_allocator,
	)
	verification := Ksawery_Repository_Verification_State.Unavailable
	diagnostic := ""
	if !opened {
		state.failure = failure
		state.commit_return_to_draft = true
		diagnostic = "Repository commit result was unavailable"
	} else {
		if state.commit_result.state != nil do ksawery.commit_result_close(&state.commit_result)
		state.commit_result = result
		descriptor, described := ksawery.commit_result_descriptor(&state.commit_result)
		state.failure = descriptor.failure if described && !descriptor.succeeded else .None
		state.commit_return_to_draft = !described || !descriptor.succeeded
		verification = .Verified if described && descriptor.succeeded else .Known_Failure
	}
	effect, prepared, prepare_failure := ksawery_process_operation_prepare_refresh(
		&state.process_coordinator,
		&state.process,
		"Refreshing repository after commit",
		ksawery_workflow_now(commands),
	)
	if !prepared {
		state.process_failure = prepare_failure
		_, _ = ksawery_process_observation_finish(
			&state.process_coordinator, &state.process, false,
			"Repository commit could not refresh", ksawery_workflow_now(commands),
		)
		return ksawery_workflow_commit_outcome(diagnostic), true
	}
	state.operation_effect = effect
	state.operation_verification = verification
	return ksawery_workflow_commit_outcome(diagnostic, .Start_Commit_Refresh), true
}

@(private)
ksawery_workflow_complete_commit :: proc(
	commands: ^Command_Context,
	poll: ksawery.Repository_Process_Poll,
) -> (Ksawery_Workflow_Completion_Outcome, bool) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !ksawery_workflow_poll_is_terminal(poll) {
		return {}, false
	}
	state := commands.ksawery_workflow
	if ksawery_workflow_pending_family(state) != .Commit || state.process.state == nil {
		return {}, false
	}
	if state.pending == .Commit_Precondition {
		return ksawery_workflow_complete_commit_precondition(commands, poll)
	}
	if state.pending == .Commit do return ksawery_workflow_complete_commit_process(commands)
	return {}, false
}

@(private)
ksawery_workflow_advance_local_children :: proc(
	commands: ^Command_Context,
) -> (changed: bool, owned_turn: bool) {
	state := commands.ksawery_workflow
	if state == nil do return false, false
	if state.active && state.pending == .Extension_Operation && state.extension_operation != nil &&
	   state.extension_operation.active {
		return ksawery_workflow_step_extension_operation(commands), true
	}
	changed = ksawery_workflow_finish_extension_command_if_ready(commands)
	if state.active && state.pending == .Conflict_Assistance &&
	   state.conflict_assistance != nil && state.conflict_assistance.operation.active {
		return ksawery_workflow_step_conflict_assistance(commands) || changed, true
	}
	return changed, false
}

@(private)
ksawery_workflow_coordination_failure_outcome :: proc(
	commands: ^Command_Context,
	diagnostic: string,
) -> Ksawery_Workflow_Completion_Outcome {
	state := commands.ksawery_workflow
	if state != nil {
		if state.process_coordinator.active {
			recorded, record_failure := ksawery_process_observation_finish(
				&state.process_coordinator,
				&state.process,
				false,
				diagnostic,
				ksawery_workflow_now(commands),
			)
			if !recorded do state.process_failure = record_failure
		}
		state.failure = .Cleanup
	}
	return {
		consumed = true,
		changed = true,
		next_pending = .None,
		process = .Close,
		resolution = .Handler_Cleared,
		refresh = .None,
		presentation = .Preserve,
		diagnostic_intent = .Publish,
		diagnostic = diagnostic,
	}
}

@(private)
ksawery_workflow_complete_family :: proc(
	commands: ^Command_Context,
	family: Ksawery_Pending_Family,
	poll: ksawery.Repository_Process_Poll,
	outcome: ^Ksawery_Workflow_Completion_Outcome,
) -> bool {
	if outcome == nil do return false
	state := commands.ksawery_workflow
	switch family {
	case .Raw_Command:
		candidate, completed := ksawery_workflow_complete_raw_command(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .Repository_Observation:
		candidate, completed := ksawery_workflow_complete_repository_observation(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .Sequence_Coordination:
		candidate, completed := ksawery_workflow_complete_sequence(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .History:
		candidate, completed := ksawery_workflow_complete_history(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .Refs_And_Synchronization:
		if state.pending == .Refs_Observe || state.pending == .Refs_Refresh {
			candidate, completed := ksawery_workflow_complete_refs(commands, poll)
			if completed {
				outcome^ = candidate
				return true
			}
		} else {
			candidate, completed := ksawery_workflow_complete_synchronization(commands, poll)
			if completed {
				outcome^ = candidate
				return true
			}
		}
	case .Commit:
		candidate, completed := ksawery_workflow_complete_commit(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .Revision_Inspection:
		candidate, completed := ksawery_workflow_complete_revision_inspection(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .Inspection_Workflow:
		candidate, completed := ksawery_workflow_complete_inspection(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .Changes_And_Index:
		candidate, completed := ksawery_workflow_complete_changes_and_index(commands, poll)
		if completed {
			outcome^ = candidate
			return true
		}
	case .Idle_And_Local, .Invalid:
	}
	outcome^ = ksawery_workflow_coordination_failure_outcome(
		commands, "Ksawery workflow terminal observation had no completion owner",
	)
	return true
}

@(private)
ksawery_workflow_step :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	reclaimed := ksawery_workflow_reclaim_canvas(commands)
	local_changed, local_owned_turn := ksawery_workflow_advance_local_children(commands)
	if local_owned_turn do return reclaimed || local_changed
	if !state.active || state.process.state == nil || state.pending == .None {
		return reclaimed || local_changed
	}
	poll, polled := ksawery_workflow_poll_once(state, ksawery_workflow_now(commands))
	if !polled || !ksawery_workflow_poll_is_terminal(poll) do return reclaimed || local_changed
	family := ksawery_workflow_pending_family(state)
	outcome: Ksawery_Workflow_Completion_Outcome
	if !ksawery_workflow_complete_family(commands, family, poll, &outcome) {
		return reclaimed || local_changed
	}
	published := ksawery_workflow_publish_completion(commands, &outcome)
	finished_extension := ksawery_workflow_finish_extension_command_if_ready(commands)
	return published || finished_extension || reclaimed || local_changed
}

@(private)
ksawery_workflow_selected_path :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Path_Target, []u8, bool, ksawery.Failure_Code) {
	if state == nil || state.observation.state == nil do return {}, nil, false, .Invalid_Request
	target, selected, failure := ksawery.status_selection_path_target(&state.observation, state.selection)
	if !selected do return {}, nil, false, failure
	path_count, counted := ksawery.status_observation_path_count(&state.observation)
	if !counted do return {}, nil, false, .Path_Unavailable
	for index in 0 ..< path_count {
		path, found := ksawery.status_observation_path(&state.observation, index)
		if !found || path.id != target.path do continue
		text, copied := ksawery.status_observation_path_text(&state.observation, path)
		if copied && len(text) > 0 do return target, text, true, .None
		break
	}
	return {}, nil, false, .Path_Unavailable
}

@(private)
ksawery_workflow_path_has_modified_buffer :: proc(
	commands: ^Command_Context,
	path: []u8,
) -> (bool, bool) {
	if commands == nil || commands.host.call == nil || commands.ksawery_workflow == nil || len(path) == 0 {
		return false, false
	}
	absolute, path_error := os.join_path(
		{ksawery.repository_context_string(&commands.ksawery_workflow.repository), string(path)},
		commands.temporary_allocator,
	)
	if path_error != nil do return false, false
	defer delete(absolute, commands.temporary_allocator)
	inspection, inspected := host_session_request(
		&commands.host,
		.Inspect_Documents,
		0,
		product_module.SESSION_PATH_EXACT,
		absolute,
	)
	if !inspected do return false, false
	return inspection.flags & product_module.SESSION_DOCUMENT_MODIFIED != 0, true
}

@(private)
command_context_begin_ksawery_discard :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status || state.observation.state == nil ||
	   state.process.state != nil || commands.prompt_workflow.mode != .None {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	_, path, selected, selection_failure := ksawery_workflow_selected_path(state)
	if !selected {
		state.failure = selection_failure
		command_context_set_diagnostic(commands, "Selected repository target cannot be discarded")
		return Interaction_Result{changed = true}, {}
	}
	modified, inspected := ksawery_workflow_path_has_modified_buffer(commands, path)
	if !inspected do return {}, App_Failure{stage = .Session_Access}
	operation := state.next_action
	if operation == ksawery.Index_Operation_ID(0) do operation = ksawery.Index_Operation_ID(1)
	confirmation := ksawery.Discard_Confirmation_ID(u64(operation))
	request, prepared, failure := ksawery.discard_action_prepare(
		&state.observation,
		state.selection,
		operation,
		confirmation,
		modified,
	)
	if !prepared {
		state.failure = failure
		if failure == .Modified_Buffer {
			command_context_set_diagnostic(commands, "Discard is unavailable while the file buffer is modified")
		} else {
			command_context_set_diagnostic(commands, "Selected repository target cannot be discarded")
		}
		return Interaction_Result{changed = true}, {}
	}
	choices := prompt_yes_no_choices()
	prompt_ok, prompt_failure := interaction.prompt_init(
		&commands.prompt_workflow.prompt,
		{kind = .Fixed_Choice, choices = choices[:], allocator = commands.persistent_allocator},
	)
	if !prompt_ok do return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	if !prompt_workflow_begin_projection(&commands.prompt_workflow, .Ksawery_Discard_Choice) {
		_, _ = interaction.prompt_close(&commands.prompt_workflow.prompt)
		return {}, App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Generation_Limit}}
	}
	state.discard_request = request
	state.discard_path_length = u32(copy(state.discard_path[:], path))
	if map_failure := command_context_activate_prompt_map(commands, .Ksawery_Discard_Choice);
	   map_failure.stage != .None {
		command_context_end_prompt(commands)
		state.discard_request = {}
		state.discard_path_length = 0
		return {}, map_failure
	}
	state.next_action = operation + 1
	if state.next_action == ksawery.Index_Operation_ID(0) do state.next_action = ksawery.Index_Operation_ID(1)
	state.failure = .None
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_retain_discard_outcome :: proc(
	commands: ^Command_Context,
	request: ksawery.Discard_Action_Request,
	failure: ksawery.Failure_Code,
) {
	state := commands.ksawery_workflow
	if state == nil do return
	if state.discard_action.state != nil do ksawery.discard_action_result_close(&state.discard_action)
	result, opened, _ := ksawery.discard_action_result_open(
		request,
		0,
		nil,
		nil,
		failure,
		commands.persistent_allocator,
	)
	if opened do state.discard_action = result
	state.failure = .None
}

@(private)
dispatch_ksawery_discard_prompt :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || !state.active || state.discard_request.operation == ksawery.Index_Operation_ID(0) {
		return {}, App_Failure{stage = .Prompt}
	}
	metadata, resolution, resolved, resolve_failure := command_context_resolve_prompt_input(commands, input)
	if !resolved do return {}, resolve_failure
	if resolution.kind != .Command do return {}, {}
	cancelled := command_metadata_is_cancel(metadata) ||
	             command_metadata_is_contextual(metadata, .Prompt_Choice_2)
	if cancelled {
		_, _ = interaction.prompt_cancel(&commands.prompt_workflow.prompt)
		request := state.discard_request
		command_context_deactivate_prompt_map(commands, .Cancelled)
		command_context_end_prompt(commands)
		state.discard_request = {}
		state.discard_path_length = 0
		ksawery_workflow_retain_discard_outcome(commands, request, .Cancelled)
		command_context_set_diagnostic(commands, "Repository discard cancelled")
		return Interaction_Result{changed = true}, {}
	}
	if !command_metadata_is_contextual(metadata, .Prompt_Choice_1) do return {}, {}
	transition, prompt_failure := interaction.prompt_choice_accept(&commands.prompt_workflow.prompt, 1)
	if prompt_failure.code != .None || transition != .Completed {
		return {}, App_Failure{stage = .Prompt, prompt_failure = prompt_failure}
	}
	request := state.discard_request
	confirmed, confirmation_failure := ksawery.discard_action_confirm(
		&request,
		request.confirmation,
	)
	command_context_deactivate_prompt_map(commands, .Completed)
	command_context_end_prompt(commands)
	state.discard_request = {}
	state.discard_path_length = 0
	if !confirmed {
		ksawery_workflow_retain_discard_outcome(commands, request, confirmation_failure)
		command_context_set_diagnostic(commands, "Repository discard confirmation was rejected")
		return Interaction_Result{changed = true}, {}
	}
	_, path, selected, selection_failure := ksawery_workflow_selected_path(state)
	if !selected {
		ksawery_workflow_retain_discard_outcome(commands, request, selection_failure)
		_ = ksawery_workflow_refresh(commands)
		command_context_set_diagnostic(commands, "Repository discard target became stale")
		return Interaction_Result{changed = true}, {}
	}
	modified, inspected := ksawery_workflow_path_has_modified_buffer(commands, path)
	if !inspected do return {}, App_Failure{stage = .Session_Access}
	process, started, start_failure := ksawery.repository_process_start_discard_action(
		&state.observation,
		request,
		modified,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		ksawery_workflow_retain_discard_outcome(commands, request, start_failure)
		if start_failure == .Stale_Observation do _ = ksawery_workflow_refresh(commands)
		if start_failure == .Modified_Buffer {
			command_context_set_diagnostic(commands, "Discard stopped because the file buffer is modified")
		} else {
			command_context_set_diagnostic(commands, "Repository discard could not start")
		}
		return Interaction_Result{changed = true}, {}
	}
	path_text, path_described := ksawery_process_observation_path_text(&state.observation, request.target)
	if !path_described {
		ksawery.repository_process_close(&process)
		ksawery_workflow_retain_discard_outcome(commands, request, .Stale_Observation)
		command_context_set_diagnostic(commands, "Repository discard target became stale")
		return Interaction_Result{changed = true}, {}
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = .Discard,
			target_kind = .Path,
			title = "Discard Repository Changes",
			target = string(path_text),
			phase_detail = "Discarding working-tree changes",
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		ksawery_workflow_retain_discard_outcome(commands, request, record_failure)
		command_context_set_diagnostic(commands, "Repository discard could not start")
		return Interaction_Result{changed = true}, {}
	}
	if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
	if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
	state.diff_failure = .None
	if state.action.state != nil do ksawery.index_action_result_close(&state.action)
	if state.partial_action.state != nil do ksawery.partial_index_action_result_close(&state.partial_action)
	if state.grouped_action.state != nil do ksawery.grouped_index_action_result_close(&state.grouped_action)
	if state.discard_action.state != nil do ksawery.discard_action_result_close(&state.discard_action)
	state.process = process
	state.pending = .Discard_Action
	state.failure = .None
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_start_index_action :: proc(
	commands: ^Command_Context,
	action: ksawery.Index_Action,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status || state.observation.state == nil ||
	   state.process.state != nil {
		return false
	}
	if ksawery.grouped_selection_action_available(&state.grouped, action) {
		return ksawery_workflow_start_grouped_index_action(commands, action)
	}
	if state.selection.current.kind == .Diff_Unit {
		return ksawery_workflow_start_partial_index_action(commands, action)
	}
	operation := state.next_action
	if operation == ksawery.Index_Operation_ID(0) do operation = ksawery.Index_Operation_ID(1)
	request, prepared, failure := ksawery.index_action_prepare(
		&state.observation,
		state.selection,
		action,
		operation,
	)
	if !prepared {
		state.failure = failure
		if action == .Stage {
			command_context_set_diagnostic(commands, "Selected path cannot be staged")
		} else {
			command_context_set_diagnostic(commands, "Selected path cannot be unstaged")
		}
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_index_action(
		&state.observation,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		command_context_set_diagnostic(commands, "Repository index action could not start")
		return true
	}
	path_text, path_described := ksawery_process_observation_path_text(&state.observation, request.target)
	if !path_described {
		ksawery.repository_process_close(&process)
		state.failure = .Stale_Observation
		command_context_set_diagnostic(commands, "Repository index action could not start")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Stage
	title := "Stage Repository Path"
	phase_detail := "Staging repository path"
	if action == .Unstage {
		kind = .Unstage
		title = "Unstage Repository Path"
		phase_detail = "Unstaging repository path"
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = .Path,
			title = title,
			target = string(path_text),
			phase_detail = phase_detail,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Repository index action could not start")
		return true
	}
	if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
	if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
	state.diff_failure = .None
	if state.action.state != nil do ksawery.index_action_result_close(&state.action)
	if state.partial_action.state != nil do ksawery.partial_index_action_result_close(&state.partial_action)
	if state.grouped_action.state != nil do ksawery.grouped_index_action_result_close(&state.grouped_action)
	state.process = process
	state.pending = .Index_Action
	state.next_action = operation + 1
	if state.next_action == ksawery.Index_Operation_ID(0) {
		state.next_action = ksawery.Index_Operation_ID(1)
	}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_start_grouped_index_action :: proc(
	commands: ^Command_Context,
	action: ksawery.Index_Action,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status || state.observation.state == nil ||
	   state.grouped.state == nil || state.process.state != nil ||
	   !ksawery.grouped_selection_action_available(&state.grouped, action) {
		return false
	}
	operation := state.next_action
	if operation == ksawery.Index_Operation_ID(0) do operation = ksawery.Index_Operation_ID(1)
	document := &state.diff if state.diff.state != nil else nil
	request, prepared, failure := ksawery.grouped_index_action_prepare(
		&state.observation,
		document,
		&state.grouped,
		operation,
		ksawery.DEFAULT_PROCESS_LIMITS,
		commands.persistent_allocator,
	)
	if !prepared {
		state.failure = failure
		command_context_set_diagnostic(commands, "Selected repository group cannot be applied")
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_grouped_index_action(
		&state.observation,
		document,
		&state.grouped,
		&request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	request_descriptor, request_described := ksawery.grouped_index_action_request_descriptor(&request)
	ksawery.grouped_index_action_request_close(&request)
	if !started {
		state.failure = start_failure
		command_context_set_diagnostic(commands, "Repository grouped index action could not start")
		return true
	}
	if !request_described {
		ksawery.repository_process_close(&process)
		state.failure = .Cleanup
		command_context_set_diagnostic(commands, "Repository grouped index action could not start")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Stage
	title := fmt.tprintf("Stage %d Repository Targets", request_descriptor.selection.targets)
	phase_detail := "Staging selected repository targets"
	if action == .Unstage {
		kind = .Unstage
		title = fmt.tprintf("Unstage %d Repository Targets", request_descriptor.selection.targets)
		phase_detail = "Unstaging selected repository targets"
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = .Repository,
			title = title,
			target = ksawery.repository_context_string(&state.repository),
			phase_detail = phase_detail,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Repository grouped index action could not start")
		return true
	}
	if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
	if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
	state.diff_failure = .None
	if state.action.state != nil do ksawery.index_action_result_close(&state.action)
	if state.partial_action.state != nil do ksawery.partial_index_action_result_close(&state.partial_action)
	if state.grouped_action.state != nil do ksawery.grouped_index_action_result_close(&state.grouped_action)
	state.process = process
	state.pending = .Grouped_Index_Action
	state.next_action = operation + 1
	if state.next_action == ksawery.Index_Operation_ID(0) {
		state.next_action = ksawery.Index_Operation_ID(1)
	}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_start_partial_index_action :: proc(
	commands: ^Command_Context,
	action: ksawery.Index_Action,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status || state.observation.state == nil ||
	   state.diff.state == nil || state.process.state != nil {
		return false
	}
	operation := state.next_action
	if operation == ksawery.Index_Operation_ID(0) do operation = ksawery.Index_Operation_ID(1)
	request, prepared, failure := ksawery.partial_index_action_prepare(
		&state.observation,
		&state.diff,
		state.selection,
		action,
		operation,
		ksawery.DEFAULT_PROCESS_LIMITS,
		commands.persistent_allocator,
	)
	if !prepared {
		state.failure = failure
		if action == .Stage {
			command_context_set_diagnostic(commands, "Selected hunk cannot be staged")
		} else {
			command_context_set_diagnostic(commands, "Selected hunk cannot be unstaged")
		}
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_partial_index_action(
		&state.observation,
		&state.diff,
		&request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	request_descriptor, request_described := ksawery.partial_index_action_request_descriptor(&request)
	ksawery.partial_index_action_request_close(&request)
	if !started {
		state.failure = start_failure
		command_context_set_diagnostic(commands, "Repository partial index action could not start")
		return true
	}
	if !request_described {
		ksawery.repository_process_close(&process)
		state.failure = .Cleanup
		command_context_set_diagnostic(commands, "Repository partial index action could not start")
		return true
	}
	path_text, path_described := ksawery_process_observation_path_text(
		&state.observation,
		request_descriptor.target.path,
	)
	if !path_described {
		ksawery.repository_process_close(&process)
		state.failure = .Stale_Observation
		command_context_set_diagnostic(commands, "Repository partial index action could not start")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Stage
	title := "Stage Repository Hunk"
	phase_detail := "Staging repository hunk"
	if action == .Unstage {
		kind = .Unstage
		title = "Unstage Repository Hunk"
		phase_detail = "Unstaging repository hunk"
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = .Path,
			title = title,
			target = string(path_text),
			phase_detail = phase_detail,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Repository partial index action could not start")
		return true
	}
	if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
	if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
	state.diff_failure = .None
	if state.action.state != nil do ksawery.index_action_result_close(&state.action)
	if state.partial_action.state != nil do ksawery.partial_index_action_result_close(&state.partial_action)
	if state.grouped_action.state != nil do ksawery.grouped_index_action_result_close(&state.grouped_action)
	state.process = process
	state.pending = .Partial_Index_Action
	state.next_action = operation + 1
	if state.next_action == ksawery.Index_Operation_ID(0) {
		state.next_action = ksawery.Index_Operation_ID(1)
	}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_mark_current :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status || state.observation.state == nil ||
	   state.grouped.state == nil || state.process.state != nil {
		return false
	}
	document := &state.diff if state.diff.state != nil else nil
	marked, failure := ksawery.grouped_selection_mark(
		&state.observation,
		document,
		state.selection,
		&state.grouped,
	)
	if marked {
		state.failure = .None
		command_context_set_diagnostic(commands, "Repository target marked")
		return true
	}
	state.failure = failure
	command_context_set_diagnostic(commands, "Repository target could not be marked")
	return true
}

@(private)
ksawery_workflow_unmark_current :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status || state.observation.state == nil ||
	   state.grouped.state == nil || state.process.state != nil {
		return false
	}
	document := &state.diff if state.diff.state != nil else nil
	unmarked, failure := ksawery.grouped_selection_unmark(
		&state.observation,
		document,
		state.selection,
		&state.grouped,
	)
	if unmarked {
		state.failure = .None
		command_context_set_diagnostic(commands, "Repository target unmarked")
		return true
	}
	state.failure = failure
	command_context_set_diagnostic(commands, "Repository target was not marked")
	return true
}

@(private)
ksawery_workflow_clear_marks :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.grouped.state == nil || state.process.state != nil do return false
	descriptor, described := ksawery.grouped_selection_descriptor(&state.grouped)
	if !described || descriptor.targets == 0 do return false
	if !ksawery.grouped_selection_clear(&state.grouped) do return false
	state.failure = .None
	command_context_set_diagnostic(commands, "Repository marks cleared")
	return true
}

@(private)
ksawery_workflow_mark_ref_source :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs || state.refs.state == nil || state.process.state != nil {
		return false
	}
	if !ksawery.ref_selection_is_current(&state.refs, state.ref_selection) ||
	   state.ref_selection.current.kind != .Ref ||
	   state.ref_selection.current.reference.kind != .Local_Branch {
		state.failure = .Ref_Unavailable
		command_context_set_diagnostic(commands, "Select one local branch to mark for push")
		return true
	}
	state.ref_selection.marked = state.ref_selection.current.reference
	state.failure = .None
	command_context_set_diagnostic(commands, "Local branch marked for push")
	return true
}

@(private)
ksawery_workflow_unmark_ref_source :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs || state.process.state != nil do return false
	if state.ref_selection.current.kind != .Ref ||
	   state.ref_selection.current.reference != state.ref_selection.marked {
		state.failure = .Ref_Unavailable
		command_context_set_diagnostic(commands, "Selected branch is not the marked push source")
		return true
	}
	state.ref_selection.marked = {}
	state.failure = .None
	command_context_set_diagnostic(commands, "Marked push source cleared")
	return true
}

@(private)
ksawery_workflow_clear_ref_source :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs || state.process.state != nil || state.ref_selection.marked == {} {
		return false
	}
	state.ref_selection.marked = {}
	state.failure = .None
	command_context_set_diagnostic(commands, "Marked push source cleared")
	return true
}

@(private)
ksawery_workflow_clear_operation_resolution :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	state.mutation_refresh = .None
	state.operation_effect = {}
	state.operation_verification = .Unavailable
}

@(private)
ksawery_workflow_finish_unverified_operation :: proc(
	commands: ^Command_Context,
	message: string,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || !state.process_coordinator.active || state.operation_effect.association == {} {
		return false
	}
	resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
		&state.process_coordinator,
		state.operation_effect,
		.Unavailable,
		0,
		true,
	)
	if !resolved {
		state.process_failure = resolve_failure
		return false
	}
	finished, finish_failure := ksawery_process_operation_finish_resolution(
		&state.process_coordinator,
		nil,
		resolution,
		message,
		ksawery_workflow_now(commands),
	)
	if !finished do state.process_failure = finish_failure
	ksawery_workflow_clear_operation_resolution(state)
	return finished
}

@(private)
ksawery_workflow_finish_synchronization_record :: proc(
	commands: ^Command_Context,
	verification: Ksawery_Repository_Verification_State,
	message: string,
) {
	state := commands.ksawery_workflow
	if state == nil || !state.process_coordinator.active || state.operation_effect.association == {} do return
	refreshed_generation := state.process_coordinator.confirmed_observation
	if verification == .Unavailable do refreshed_generation = 0
	resolution, resolved, resolve_failure := ksawery_process_operation_resolve(
		&state.process_coordinator,
		state.operation_effect,
		verification,
		refreshed_generation,
		true,
	)
	if !resolved {
		state.process_failure = resolve_failure
		return
	}
	finished, finish_failure := ksawery_process_operation_finish_resolution(
		&state.process_coordinator,
		nil,
		resolution,
		message,
		ksawery_workflow_now(commands),
	)
	if !finished do state.process_failure = finish_failure
	ksawery_workflow_clear_operation_resolution(state)
}

@(private)
ksawery_workflow_refresh :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.observation.state == nil || state.process.state != nil do return false
	observation_generation := state.process_coordinator.confirmed_observation
	coordinated := state.process_coordinator.active
	if coordinated && (state.process_coordinator.active_phase != .Refreshing ||
	   state.process_coordinator.child_attached) {
		state.failure = .Action_Unavailable
		return false
	}
	request := ksawery.Process_Request{
		kind = .Observe_Status,
		repository = state.repository,
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	process, started, failure := ksawery.repository_process_start(
		request, ksawery_workflow_now(commands), commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		return false
	}
	recorded := false
	record_failure := ksawery.Failure_Code.None
	if coordinated {
		recorded, record_failure = ksawery_process_operation_attach_child(
			&state.process_coordinator,
			&process,
			ksawery_workflow_now(commands),
		)
	} else {
		recorded, record_failure = ksawery_process_observation_begin(
			&state.process_coordinator,
			&process,
			observation_generation,
			{
				kind = .Status,
				target_kind = .Repository,
				title = "Repository Status",
				target = ksawery.repository_context_string(&state.repository),
				phase_detail = "Refreshing repository status",
				refreshing = true,
			},
			ksawery_workflow_now(commands),
		)
	}
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return false
	}
	state.generation += 1
	state.process = process
	state.pending = .Refresh
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_start_history :: proc(
	commands: ^Command_Context,
	operation: Ksawery_Pending_Operation,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || !state.active || state.process.state != nil ||
	   (operation != .History_Observe && operation != .History_Refresh && operation != .History_Next) {
		return false
	}
	coordinated := state.process_coordinator.active
	if coordinated && (state.process_coordinator.active_phase != .Refreshing ||
	   state.process_coordinator.child_attached) {
		state.failure = .Action_Unavailable
		return false
	}
	request := ksawery.Process_Request{
		kind = .Observe_History,
		repository = state.repository,
		history = {limits = ksawery.DEFAULT_HISTORY_LIMITS},
		limits = ksawery.DEFAULT_PROCESS_LIMITS,
	}
	if operation == .History_Next {
		descriptor, described := ksawery.history_observation_descriptor(&state.history)
		if !described || descriptor.state != .Available || descriptor.continuation == {} {
			return false
		}
		request.history.continuation = descriptor.continuation
	}
	process, started, failure := ksawery.repository_process_start(
		request, ksawery_workflow_now(commands), commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		return false
	}
	next_generation := state.history_generation + 1
	if next_generation == ksawery.History_Generation(0) {
		ksawery.repository_process_close(&process)
		state.failure = .History_Limit
		return false
	}
	recorded := false
	record_failure := ksawery.Failure_Code.None
	if coordinated {
		recorded, record_failure = ksawery_process_operation_attach_child(
			&state.process_coordinator,
			&process,
			ksawery_workflow_now(commands),
		)
	} else {
		phase_detail := "Reading repository history"
		if operation == .History_Refresh do phase_detail = "Refreshing repository history"
		if operation == .History_Next do phase_detail = "Reading more repository history"
		recorded, record_failure = ksawery_process_observation_begin(
			&state.process_coordinator,
			&process,
			state.process_coordinator.confirmed_observation,
			{
				kind = .History,
				target_kind = .Repository,
				title = "Repository History",
				target = ksawery.repository_context_string(&state.repository),
				phase_detail = phase_detail,
			},
			ksawery_workflow_now(commands),
		)
	}
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return false
	}
	state.process = process
	state.pending = operation
	state.history_generation = next_generation
	ksawery_workflow_clear_revision_inspection(state)
	state.view_mode = .History
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_open_history :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status do return false
	return ksawery_workflow_start_history(commands, .History_Observe)
}

@(private)
ksawery_workflow_refresh_history :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil ||
	   (state.view_mode != .History && state.view_mode != .Revision_Detail && state.view_mode != .Revision_Range) {
		return false
	}
	return ksawery_workflow_start_history(commands, .History_Refresh)
}

@(private)
ksawery_workflow_next_history_page :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History do return false
	return ksawery_workflow_start_history(commands, .History_Next)
}

@(private)
ksawery_workflow_start_refs :: proc(
	commands: ^Command_Context,
	operation: Ksawery_Pending_Operation,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || !state.active || state.process.state != nil ||
	   (operation != .Refs_Observe && operation != .Refs_Refresh) {
		return false
	}
	coordinated := state.process_coordinator.active
	if coordinated && (state.process_coordinator.active_phase != .Refreshing ||
	   state.process_coordinator.child_attached) {
		state.failure = .Action_Unavailable
		return false
	}
	process, started, failure := ksawery.repository_process_start_ref_observation(
		state.repository,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		return false
	}
	next_generation := state.ref_generation + 1
	if next_generation == ksawery.Ref_Generation(0) {
		ksawery.repository_process_close(&process)
		state.failure = .Ref_Limit
		return false
	}
	recorded := false
	record_failure := ksawery.Failure_Code.None
	if coordinated {
		recorded, record_failure = ksawery_process_operation_attach_child(
			&state.process_coordinator,
			&process,
			ksawery_workflow_now(commands),
		)
	} else {
		phase_detail := "Reading repository refs"
		if operation == .Refs_Refresh do phase_detail = "Refreshing repository refs"
		recorded, record_failure = ksawery_process_observation_begin(
			&state.process_coordinator,
			&process,
			state.process_coordinator.confirmed_observation,
			{
				kind = .Refs,
				target_kind = .Repository,
				title = "Repository Refs",
				target = ksawery.repository_context_string(&state.repository),
				phase_detail = phase_detail,
			},
			ksawery_workflow_now(commands),
		)
	}
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		return false
	}
	state.process = process
	state.pending = operation
	state.ref_generation = next_generation
	state.view_mode = .Refs
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_open_refs :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status do return false
	return ksawery_workflow_start_refs(commands, .Refs_Observe)
}

@(private)
ksawery_workflow_refresh_refs :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs do return false
	return ksawery_workflow_start_refs(commands, .Refs_Refresh)
}

@(private)
ksawery_workflow_current_fetch_operation :: proc(state: ^Ksawery_Workflow_State) -> ksawery.Fetch_Operation_ID {
	if state == nil || state.next_fetch == ksawery.Fetch_Operation_ID(0) do return ksawery.Fetch_Operation_ID(1)
	return state.next_fetch
}

@(private)
ksawery_workflow_begin_fetch :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs || state.refs.state == nil || state.process.state != nil {
		return false
	}
	if !ksawery.ref_selection_is_current(&state.refs, state.ref_selection) ||
	   state.ref_selection.current.kind != .Remote {
		state.failure = .Remote_Unavailable
		command_context_set_diagnostic(commands, "Select one configured remote before fetching")
		return true
	}
	process, started, failure := ksawery.repository_process_start_remote_configuration(
		&state.refs,
		state.ref_selection,
		ksawery_workflow_now(commands),
		ksawery.DEFAULT_PROCESS_LIMITS,
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Selected remote configuration could not be checked")
		return true
	}
	remote := state.ref_selection.current.remote
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = .Fetch,
			target_kind = .Remote,
			title = "Fetch Repository Remote",
			target = ksawery.remote_name_string(&remote.name),
			phase_detail = "Checking remote configuration",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Selected remote configuration could not be checked")
		return true
	}
	state.fetch_configuration = {}
	state.fetch_request = {}
	state.process = process
	state.pending = .Remote_Configuration
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_start_prepared_fetch :: proc(
	commands: ^Command_Context,
	configuration: ksawery.Remote_Configuration_Identity,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.process.state != nil || state.refs.state == nil ||
	   state.observation.state == nil || !ksawery.remote_configuration_identity_is_valid(configuration) {
		return false
	}
	status, described := ksawery.status_observation_descriptor(&state.observation)
	if !described {
		state.failure = .Stale_Observation
		return false
	}
	operation := ksawery_workflow_current_fetch_operation(state)
	request, prepared, failure := ksawery.fetch_request_prepare(
		&state.refs,
		state.ref_selection,
		configuration,
		status.operation,
		operation,
	)
	if !prepared {
		state.failure = failure
		return false
	}
	process, started, start_failure := ksawery.repository_process_start_fetch(
		&state.refs,
		configuration,
		status.operation,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		return false
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator,
		&process,
		ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		return false
	}
	published, publish_failure := ksawery_process_operation_publish_phase(
		&state.process_coordinator,
		&process,
		.Executing,
		"Fetching repository remote",
		true,
		ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		return false
	}
	if state.fetch_result.state != nil do ksawery.fetch_result_close(&state.fetch_result)
	if state.branch_result.state != nil do ksawery.branch_result_close(&state.branch_result)
	if state.tag_result.state != nil do ksawery.tag_result_close(&state.tag_result)
	state.fetch_configuration = configuration
	state.fetch_request = request
	state.process = process
	state.pending = .Fetch
	state.next_fetch = operation + 1
	if state.next_fetch == ksawery.Fetch_Operation_ID(0) do state.next_fetch = ksawery.Fetch_Operation_ID(1)
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_finish_fetch_refresh :: proc(
	commands: ^Command_Context,
	refresh_failed: bool,
) {
	state := commands.ksawery_workflow
	if state == nil do return
	descriptor, described := ksawery.fetch_result_descriptor(&state.fetch_result)
	verification := Ksawery_Repository_Verification_State.Unavailable
	if !refresh_failed && described {
		verification = .Verified if descriptor.succeeded else .Known_Failure
	}
	message := "Repository remote fetch verified"
	if verification == .Known_Failure do message = "Repository remote fetch failed"
	if verification == .Unavailable do message = "Repository remote fetch outcome is indeterminate"
	ksawery_workflow_finish_synchronization_record(commands, verification, message)
	state.fetch_refresh = .None
	state.fetch_configuration = {}
	state.fetch_request = {}
	state.view_mode = .Refs
	if refresh_failed {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Repository fetch finished, but repository refresh failed")
		return
	}
	if !described {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Repository fetch result was unavailable")
		return
	}
	state.failure = descriptor.failure if !descriptor.succeeded else .None
	feedback := ksawery.fetch_feedback(descriptor)
	#partial switch feedback {
	case .Completed:
		command_context_set_diagnostic(commands, "Repository remote fetch completed")
	case .Cancelled:
		command_context_set_diagnostic(commands, "Repository remote fetch cancelled")
	case:
		command_context_set_diagnostic(commands, "Repository remote fetch failed")
	}
}

@(private)
ksawery_workflow_current_push_operation :: proc(state: ^Ksawery_Workflow_State) -> ksawery.Push_Operation_ID {
	if state == nil || state.next_push == ksawery.Push_Operation_ID(0) do return ksawery.Push_Operation_ID(1)
	return state.next_push
}

@(private)
ksawery_workflow_begin_push :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Refs || state.refs.state == nil ||
	   state.observation.state == nil || state.process.state != nil {
		return false
	}
	if !ksawery.ref_selection_is_current(&state.refs, state.ref_selection) ||
	   state.ref_selection.current.kind != .Remote {
		state.failure = .Remote_Unavailable
		command_context_set_diagnostic(commands, "Select one configured remote before preparing push")
		return true
	}
	if state.ref_selection.marked == {} || state.ref_selection.marked.kind != .Local_Branch {
		state.failure = .Ref_Unavailable
		command_context_set_diagnostic(commands, "Mark one local branch before preparing push")
		return true
	}
	process, started, failure := ksawery.repository_process_start_push_configuration(
		&state.refs,
		state.ref_selection,
		ksawery_workflow_now(commands),
		ksawery.DEFAULT_PROCESS_LIMITS,
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Selected remote push destination could not be checked")
		return true
	}
	remote := state.ref_selection.current.remote
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = .Push,
			target_kind = .Remote,
			title = "Push Repository Branch",
			target = ksawery.remote_name_string(&remote.name),
			phase_detail = "Checking push configuration",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Selected remote push destination could not be checked")
		return true
	}
	state.push_configuration = {}
	state.push_precondition = {}
	state.push_confirmation = {}
	state.push_request = {}
	state.process = process
	state.pending = .Push_Configuration
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_confirm_push :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Push_Confirmation || state.process.state != nil {
		return false
	}
	confirmed, confirmation_failure := ksawery.push_confirmation_confirm(
		&state.push_confirmation,
		state.push_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		command_context_set_diagnostic(commands, "Exact repository push confirmation was rejected")
		return true
	}
	operation := ksawery_workflow_current_push_operation(state)
	request, prepared, failure := ksawery.push_request_prepare(
		state.push_precondition,
		operation,
		&state.push_confirmation,
	)
	if !prepared {
		state.failure = failure
		state.view_mode = .Refs
		state.push_configuration = {}
		state.push_precondition = {}
		state.push_confirmation = {}
		command_context_set_diagnostic(commands, "Confirmed repository push request was rejected")
		return true
	}
	status, described := ksawery.status_observation_descriptor(&state.observation)
	if !described {
		state.failure = .Stale_Observation
		state.view_mode = .Refs
		command_context_set_diagnostic(commands, "Repository status no longer admits the confirmed push")
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_push(
		&state.refs,
		state.push_configuration,
		status.operation,
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		state.view_mode = .Refs
		state.push_configuration = {}
		state.push_precondition = {}
		state.push_confirmation = {}
		command_context_set_diagnostic(commands, "Checked repository push could not start")
		return true
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator,
		&process,
		ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		command_context_set_diagnostic(commands, "Checked repository push could not start")
		return true
	}
	published, publish_failure := ksawery_process_operation_publish_phase(
		&state.process_coordinator,
		&process,
		.Executing,
		"Pushing repository branch",
		true,
		ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		command_context_set_diagnostic(commands, "Checked repository push could not start")
		return true
	}
	if state.push_result.state != nil do ksawery.push_result_close(&state.push_result)
	if state.branch_result.state != nil do ksawery.branch_result_close(&state.branch_result)
	if state.tag_result.state != nil do ksawery.tag_result_close(&state.tag_result)
	state.push_request = request
	state.process = process
	state.pending = .Push
	state.view_mode = .Refs
	state.next_push = operation + 1
	if state.next_push == ksawery.Push_Operation_ID(0) do state.next_push = ksawery.Push_Operation_ID(1)
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_finish_push_refresh :: proc(
	commands: ^Command_Context,
	refresh_failed: bool,
) {
	state := commands.ksawery_workflow
	if state == nil do return
	descriptor, described := ksawery.push_result_descriptor(&state.push_result)
	verification := Ksawery_Repository_Verification_State.Unavailable
	if !refresh_failed && described {
		verification = .Verified if descriptor.succeeded else .Known_Failure
	}
	message := "Repository push verified"
	if verification == .Known_Failure do message = "Repository push failed"
	if verification == .Unavailable do message = "Repository push outcome is indeterminate"
	ksawery_workflow_finish_synchronization_record(commands, verification, message)
	state.push_refresh = .None
	state.push_configuration = {}
	state.push_precondition = {}
	state.push_confirmation = {}
	state.push_request = {}
	state.view_mode = .Refs
	if refresh_failed {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Repository push finished, but repository refresh failed")
		return
	}
	if !described {
		state.failure = .Process_Failed
		command_context_set_diagnostic(commands, "Repository push result was unavailable")
		return
	}
	state.failure = descriptor.failure if !descriptor.succeeded else .None
	feedback := ksawery.push_feedback(descriptor)
	#partial switch feedback {
	case .Completed:
		command_context_set_diagnostic(commands, "Repository branch push completed")
	case .Cancelled:
		command_context_set_diagnostic(commands, "Repository branch push cancelled")
	case:
		command_context_set_diagnostic(commands, "Repository branch push failed")
	}
}

@(private)
ksawery_workflow_commit_history_matches :: proc(
	state: ^Ksawery_Workflow_State,
	precondition: ksawery.Commit_Precondition,
) -> bool {
	if state == nil || state.history.state == nil || precondition.head.kind != .Revision do return false
	descriptor, described := ksawery.history_observation_descriptor(&state.history)
	if !described || descriptor.state != .Available || descriptor.repository != precondition.repository ||
	   descriptor.head != precondition.head.revision {
		return false
	}
	return state.commit_mode != .Fixup ||
	       (state.commit_target.generation == descriptor.generation && state.commit_target.revision != {})
}

@(private)
ksawery_workflow_current_commit_operation :: proc(state: ^Ksawery_Workflow_State) -> ksawery.Commit_Operation_ID {
	if state == nil || state.next_commit == ksawery.Commit_Operation_ID(0) do return ksawery.Commit_Operation_ID(1)
	return state.next_commit
}

@(private)
ksawery_workflow_prepare_fixup_preview :: proc(state: ^Ksawery_Workflow_State) -> ksawery.Failure_Code {
	if state == nil || state.commit_mode != .Fixup do return .Invalid_Request
	request, prepared, failure := ksawery.fixup_request_prepare(
		state.commit_precondition,
		&state.history,
		state.commit_target,
		ksawery_workflow_current_commit_operation(state),
	)
	if !prepared do return failure
	message, copied := ksawery.commit_message_text(&request.message)
	if !copied || len(message) > len(state.commit_draft) do return .Commit_Message_Invalid
	state.commit_draft = {}
	copy(state.commit_draft[:len(message)], message)
	state.commit_draft_length = u32(len(message))
	return .None
}

@(private)
ksawery_workflow_begin_commit :: proc(
	commands: ^Command_Context,
	mode := ksawery.Commit_Mode.Normal,
	target := ksawery.History_Target{},
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.observation.state == nil || state.process.state != nil ||
	   (mode == .Normal && state.view_mode != .Status) ||
	   (mode != .Normal && state.view_mode != .History) {
		return false
	}
	if mode == .Fixup && !ksawery.history_target_is_valid(target) {
		state.failure = .Revision_Unavailable
		command_context_set_diagnostic(commands, "Select an exact History revision before creating a fixup commit")
		return true
	}
	if state.commit_mode != mode {
		state.commit_draft = {}
		state.commit_draft_length = 0
	}
	state.commit_mode = mode
	state.commit_target = target
	state.amend_confirmation = {}
	process, started, failure := ksawery.repository_process_start_commit_precondition(
		&state.observation,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = failure
		command_context_set_diagnostic(commands, "Repository commit precondition could not start")
		return true
	}
	kind := ksawery.Repository_Operation_Kind.Commit
	title := "Create Repository Commit"
	target_kind := ksawery.Process_Target_Kind.Repository
	target_text := ksawery.repository_context_string(&state.repository)
	if mode == .Amend {
		kind = .Amend
		title = "Amend Repository Commit"
	} else if mode == .Fixup {
		kind = .Fixup
		title = "Create Repository Fixup"
		target_kind = .Revision
		target_revision := target.revision
		target_text = ksawery.revision_identity_string(&target_revision)
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = kind,
			target_kind = target_kind,
			title = title,
			target = target_text,
			phase_detail = "Checking commit preconditions",
			checking = true,
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Repository commit precondition could not start")
		return true
	}
	state.process = process
	state.pending = .Commit_Precondition
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_begin_amend :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History || state.history.state == nil do return false
	return ksawery_workflow_begin_commit(commands, .Amend)
}

@(private)
ksawery_workflow_begin_fixup :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History do return false
	target, selected, failure := ksawery_workflow_history_current_target(state)
	if !selected {
		state.failure = failure
		command_context_set_diagnostic(commands, "Select an exact History revision before creating a fixup commit")
		return true
	}
	return ksawery_workflow_begin_commit(commands, .Fixup, target)
}

@(private)
ksawery_workflow_commit_append :: proc(state: ^Ksawery_Workflow_State, text: string) -> bool {
	if state == nil || len(text) == 0 || !utf8.valid_string(text) ||
	   u64(state.commit_draft_length) + u64(len(text)) > ksawery.MAX_COMMIT_MESSAGE_BYTES {
		return false
	}
	for byte in transmute([]u8)text {
		if byte == 0 do return false
	}
	start := int(state.commit_draft_length)
	copy(state.commit_draft[start:], transmute([]u8)text)
	state.commit_draft_length += u32(len(text))
	return true
}

@(private)
ksawery_workflow_commit_delete_previous :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.commit_draft_length == 0 do return false
	start := int(state.commit_draft_length) - 1
	for start > 0 && state.commit_draft[start] & 0xc0 == 0x80 do start -= 1
	state.commit_draft_length = u32(start)
	return true
}

@(private)
ksawery_workflow_commit_finalize :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Commit_Message || state.process.state != nil {
		return false
	}
	operation := ksawery_workflow_current_commit_operation(state)
	switch state.commit_mode {
	case .Normal:
		message: ksawery.Commit_Message
		if !ksawery.commit_message_assign(&message, string(state.commit_draft[:state.commit_draft_length])) {
			state.failure = .Commit_Message_Invalid
			command_context_set_diagnostic(commands, "Commit message requires a nonempty subject")
			return true
		}
		request, prepared, failure := ksawery.commit_request_prepare(
			state.commit_precondition, message, operation,
		)
		if !prepared {
			state.failure = failure
			command_context_set_diagnostic(commands, "Checked repository state cannot create this commit")
			return true
		}
		return ksawery_workflow_start_prepared_commit(commands, request, operation)
	case .Amend:
		message: ksawery.Commit_Message
		if !ksawery.commit_message_assign(&message, string(state.commit_draft[:state.commit_draft_length])) {
			state.failure = .Commit_Message_Invalid
			command_context_set_diagnostic(commands, "Commit message requires a nonempty subject")
			return true
		}
		confirmation_id := state.next_confirmation
		if confirmation_id == ksawery.Commit_Confirmation_ID(0) do confirmation_id = ksawery.Commit_Confirmation_ID(1)
		confirmation, confirmed, confirmation_failure := ksawery.amend_confirmation_prepare(
			state.commit_precondition,
			&state.history,
			message,
			confirmation_id,
		)
		if !confirmed {
			state.failure = confirmation_failure
			command_context_set_diagnostic(commands, "Exact amend confirmation could not be prepared")
			return true
		}
		state.amend_confirmation = confirmation
		state.next_confirmation = confirmation_id + 1
		if state.next_confirmation == ksawery.Commit_Confirmation_ID(0) do state.next_confirmation = ksawery.Commit_Confirmation_ID(1)
		state.view_mode = .Amend_Confirmation
		state.failure = .None
		return true
	case .Fixup:
		request, prepared, failure := ksawery.fixup_request_prepare(
			state.commit_precondition,
			&state.history,
			state.commit_target,
			operation,
		)
		if !prepared {
			state.failure = failure
			command_context_set_diagnostic(commands, "Checked repository state cannot create this commit")
			return true
		}
		return ksawery_workflow_start_prepared_commit(commands, request, operation)
	case .Invalid:
		state.failure = .Invalid_Request
		command_context_set_diagnostic(commands, "Checked repository state cannot create this commit")
		return true
	}
	return false
}

@(private)
ksawery_workflow_start_prepared_commit :: proc(
	commands: ^Command_Context,
	request: ksawery.Commit_Request,
	operation: ksawery.Commit_Operation_ID,
) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.process.state != nil || !ksawery.commit_request_is_valid(request) {
		return false
	}
	process, started, start_failure := ksawery.repository_process_start_commit(
		request,
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		if state.commit_mode == .Amend {
			state.amend_confirmation = {}
			state.view_mode = .Commit_Message
		}
		command_context_set_diagnostic(commands, "Repository commit could not start")
		return true
	}
	attached, attach_failure := ksawery_process_operation_attach_child(
		&state.process_coordinator,
		&process,
		ksawery_workflow_now(commands),
	)
	if !attached {
		ksawery.repository_process_close(&process)
		state.failure = attach_failure
		_ = ksawery_process_observation_finish_without_child(
			&state.process_coordinator,
			.Failed,
			.Known_Failure,
			"Repository commit could not start",
			ksawery_workflow_now(commands),
		)
		command_context_set_diagnostic(commands, "Repository commit could not start")
		return true
	}
	published, publish_failure := ksawery_process_operation_publish_phase(
		&state.process_coordinator,
		&process,
		.Executing,
		"Creating repository commit",
		true,
		ksawery_workflow_now(commands),
	)
	if !published {
		_, _ = ksawery_process_operation_detach_child(&state.process_coordinator, &process)
		ksawery.repository_process_close(&process)
		state.failure = publish_failure
		_ = ksawery_process_observation_finish_without_child(
			&state.process_coordinator,
			.Failed,
			.Known_Failure,
			"Repository commit could not start",
			ksawery_workflow_now(commands),
		)
		command_context_set_diagnostic(commands, "Repository commit could not start")
		return true
	}
	if state.commit_result.state != nil do ksawery.commit_result_close(&state.commit_result)
	state.commit_request = request
	state.process = process
	state.pending = .Commit
	state.next_commit = operation + 1
	if state.next_commit == ksawery.Commit_Operation_ID(0) do state.next_commit = ksawery.Commit_Operation_ID(1)
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_confirm_amend :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Amend_Confirmation || state.process.state != nil {
		return false
	}
	confirmed, confirmation_failure := ksawery.amend_confirmation_confirm(
		&state.amend_confirmation,
		state.amend_confirmation.id,
	)
	if !confirmed {
		state.failure = confirmation_failure
		command_context_set_diagnostic(commands, "Exact amend confirmation was rejected")
		return true
	}
	operation := ksawery_workflow_current_commit_operation(state)
	request, prepared, failure := ksawery.amend_request_prepare(
		state.commit_precondition,
		state.amend_confirmation.message,
		operation,
		&state.amend_confirmation,
	)
	if !prepared {
		state.failure = failure
		state.amend_confirmation = {}
		state.view_mode = .Commit_Message
		command_context_set_diagnostic(commands, "Confirmed amend request was rejected")
		return true
	}
	return ksawery_workflow_start_prepared_commit(commands, request, operation)
}

@(private)
ksawery_workflow_raw_return_mode_is_valid :: proc(mode: Ksawery_View_Mode) -> bool {
	switch mode {
	case .Status, .Sequence, .Conflict, .History, .Refs, .Process, .Provider_Inspection,
	     .Revision_Detail, .Revision_Range, .Inspection_Workflow:
		return true
	case .Inspection_Input, .Inspection_Confirmation, .Resource, .Commit_Message,
	     .Raw_Command_Input, .Raw_Command_Confirmation,
	     .Amend_Confirmation, .Push_Confirmation, .Branch_Name,
	     .Branch_Confirmation, .Tag_Name, .Tag_Confirmation,
	     .Merge_Confirmation, .Rebase_Confirmation,
	     .Revision_Sequence_Confirmation, .Bisect_Confirmation,
	     .Conflict_Confirmation, .Extension_Command, .Status_Command_Dispatcher:
	}
	return false
}

@(private)
/* Clears every private raw-command owner before returning to the prior Ksawery surface. */
ksawery_workflow_clear_raw_command :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	state.raw_input = {}
	state.raw_intent = {}
	ksawery.raw_repository_command_confirmation_close(&state.raw_confirmation)
	ksawery.raw_repository_command_request_close(&state.raw_request)
	state.raw_failure = {}
	state.raw_terminal = {}
	state.raw_awaiting_refresh = false
	state.raw_refresh = .None
	state.raw_refresh_completed = {}
	state.raw_result = {}
}

@(private)
ksawery_workflow_return_from_raw_command :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || (state.view_mode != .Raw_Command_Input &&
	   state.view_mode != .Raw_Command_Confirmation) {
		return false
	}
	return_mode := state.raw_return_mode
	if !ksawery_workflow_raw_return_mode_is_valid(return_mode) do return_mode = .Status
	return_position := state.raw_return_position
	ksawery_workflow_clear_raw_command(state)
	state.view_mode = return_mode
	state.raw_return_mode = .Status
	state.raw_return_position = {}
	state.position = return_position
	return true
}

@(private)
ksawery_workflow_begin_raw_command :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.process.state != nil || !ksawery_workflow_raw_return_mode_is_valid(state.view_mode) {
		return false
	}
	return_mode := state.view_mode
	return_position := state.position
	advanced := state.advanced_workflow
	state.advanced_workflow = .Invalid
	if advanced == .Ignore_Shared || advanced == .Ignore_Private {
		return ksawery_workflow_open_ignore_file(commands, advanced)
	}
	ksawery_workflow_clear_raw_command(state)
	state.raw_input.mode = .Git
	state.raw_return_mode = return_mode
	state.raw_return_position = return_position
	state.view_mode = .Raw_Command_Input
	state.position = {}
	state.failure = .None
	template := ksawery_advanced_workflow_template(advanced)
	if len(template) > 0 && !ksawery_workflow_raw_command_append(state, template) {
		_ = ksawery_workflow_return_from_raw_command(state)
		command_context_set_diagnostic(commands, "Advanced repository workflow could not prepare bounded arguments")
		return false
	}
	if len(template) > 0 {
		command_context_set_diagnostic(commands, "Advanced repository workflow opened with reviewed Git arguments")
	} else {
		command_context_set_diagnostic(commands, "Raw repository command composition opened in Git mode")
	}
	return true
}

@(private)
ksawery_workflow_open_ignore_file :: proc(
	commands: ^Command_Context,
	workflow: Ksawery_Advanced_Workflow,
) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	relative := ".gitignore"
	if workflow == .Ignore_Private do relative = ".git/info/exclude"
	absolute, path_error := os.join_path(
		{ksawery.repository_context_string(&state.repository), relative},
		commands.temporary_allocator,
	)
	if path_error != nil {
		command_context_set_diagnostic(commands, "Repository ignore file path is unavailable")
		return false
	}
	defer delete(absolute, commands.temporary_allocator)
	opened, open_ok := host_session_request(&commands.host, .Open_Path, 0, 0, absolute)
	if !open_ok {
		command_context_set_diagnostic(commands, "Repository ignore file could not be opened")
		return false
	}
	state.visited = opened.target
	state.resource_return_mode = state.view_mode
	state.view_mode = .Resource
	state.failure = .None
	command_context_set_diagnostic(commands, "Repository ignore file opened for explicit editing")
	return true
}

@(private)
ksawery_advanced_workflow_template :: proc(workflow: Ksawery_Advanced_Workflow) -> string {
	switch workflow {
	case .Clone: return "clone "
	case .Clone_Shallow: return "clone --depth 1 "
	case .Clone_Bare: return "clone --bare "
	case .Clone_Mirror: return "clone --mirror "
	case .Init: return "init "
	case .Submodule_Add: return "submodule add "
	case .Submodule_List: return "submodule status "
	case .Submodule_Update: return "submodule update --init "
	case .Submodule_Sync: return "submodule sync "
	case .Submodule_Deinit: return "submodule deinit "
	case .Subtree_Add: return "subtree add "
	case .Subtree_Merge: return "subtree merge "
	case .Subtree_Pull: return "subtree pull "
	case .Subtree_Push: return "subtree push "
	case .Subtree_Split: return "subtree split "
	case .Notes_Add: return "notes add -m "
	case .Notes_Remove: return "notes remove "
	case .Notes_Prune: return "notes prune"
	case .Mail_Apply: return "am "
	case .Patch_Apply: return "apply "
	case .Patch_Create: return "format-patch "
	case .Patch_Save: return "diff --output=odra.patch "
	case .Request_Pull: return "request-pull "
	case .Sparse_Enable: return "sparse-checkout init --cone"
	case .Sparse_Disable: return "sparse-checkout disable"
	case .Sparse_Reapply: return "sparse-checkout reapply"
	case .Sparse_Set: return "sparse-checkout set "
	case .Sparse_Add: return "sparse-checkout add "
	case .Ignore_Shared, .Ignore_Private, .Invalid:
	}
	return ""
}

@(private)
ksawery_workflow_raw_command_append :: proc(state: ^Ksawery_Workflow_State, text: string) -> bool {
	if state == nil || state.view_mode != .Raw_Command_Input || len(text) == 0 ||
	   !utf8.valid_string(text) || int(state.raw_input.length) + len(text) >
	   int(ksawery.DEFAULT_RAW_REPOSITORY_COMMAND_BYTES) {
		return false
	}
	for byte in transmute([]u8)text {
		if byte == 0 || byte == '\n' || byte == '\r' || byte == 0x1b || byte == 0x7f ||
		   byte == 0x9b || (byte < 0x20 && byte != '\t') {
			return false
		}
	}
	start := int(state.raw_input.length)
	copy(state.raw_input.bytes[start:], transmute([]u8)text)
	state.raw_input.length += u16(len(text))
	return true
}

@(private)
ksawery_workflow_raw_command_delete_previous :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Raw_Command_Input || state.raw_input.length == 0 do return false
	start := int(state.raw_input.length) - 1
	for start > 0 && state.raw_input.bytes[start] & 0xc0 == 0x80 do start -= 1
	for index in start ..< int(state.raw_input.length) do state.raw_input.bytes[index] = 0
	state.raw_input.length = u16(start)
	return true
}

@(private)
ksawery_workflow_raw_command_toggle_mode :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Raw_Command_Input do return false
	state.raw_input.mode = .Shell if state.raw_input.mode == .Git else .Git
	state.raw_failure = {}
	return true
}

@(private)
ksawery_workflow_prepare_raw_command_confirmation :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.view_mode != .Raw_Command_Input || state.process.state != nil do return false
	input: ksawery.Raw_Repository_Command_Input
	assigned, input_failure := ksawery.raw_repository_command_input_assign(
		&input,
		state.raw_input.mode,
		string(state.raw_input.bytes[:state.raw_input.length]),
	)
	if !assigned {
		state.raw_failure = input_failure
		command_context_set_diagnostic(commands, "Raw repository command requires one valid nonempty line")
		return true
	}
	command_id := state.next_raw_command
	if command_id == ksawery.Raw_Repository_Command_ID(0) do command_id = 1
	intent := ksawery.Raw_Repository_Command_Intent {
		command = command_id,
		repository = state.repository,
		repository_generation = ksawery.Repository_Generation(state.generation),
		observation_generation = state.generation,
		input = input,
		refresh = ksawery.RAW_REPOSITORY_COMMAND_REFRESH,
		authority = .Explicit_User_Confirmation,
		redaction = .Omit_Sensitive_Content,
		retention = .Session_Transient,
		limits = ksawery.DEFAULT_RAW_REPOSITORY_COMMAND_LIMITS,
	}
	confirmation_id := state.next_raw_confirmation
	if confirmation_id == ksawery.Raw_Repository_Command_Confirmation_ID(0) do confirmation_id = 1
	confirmation, prepared, confirmation_failure :=
		ksawery.raw_repository_command_confirmation_prepare(intent, confirmation_id)
	if !prepared {
		state.raw_failure = confirmation_failure
		command_context_set_diagnostic(commands, "Exact raw repository command confirmation could not be prepared")
		return true
	}
	state.raw_input = input
	state.raw_intent = intent
	state.raw_confirmation = confirmation
	state.raw_failure = {}
	state.next_raw_command = command_id + 1
	if state.next_raw_command == 0 do state.next_raw_command = 1
	state.next_raw_confirmation = confirmation_id + 1
	if state.next_raw_confirmation == 0 do state.next_raw_confirmation = 1
	state.view_mode = .Raw_Command_Confirmation
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_confirm_raw_command :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.view_mode != .Raw_Command_Confirmation || state.process.state != nil do return false
	if !state.raw_confirmation.confirmed {
		confirmed, failure := ksawery.raw_repository_command_confirmation_confirm(
			&state.raw_confirmation,
			state.raw_confirmation.id,
			state.raw_intent,
		)
		if !confirmed {
			state.raw_failure = failure
			command_context_set_diagnostic(commands, "Exact raw repository command confirmation was rejected")
			return true
		}
	}
	operation := state.process_coordinator.next_operation
	request, prepared, request_failure := ksawery.raw_repository_command_request_prepare(
		operation,
		state.raw_intent,
		&state.raw_confirmation,
	)
	if !prepared {
		state.raw_failure = request_failure
		command_context_set_diagnostic(commands, "Confirmed raw repository command request was rejected")
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_raw_repository_command(
		request,
		state.repository,
		ksawery.Repository_Generation(state.generation),
		ksawery_workflow_now(commands),
		commands.persistent_allocator,
	)
	if !started {
		state.raw_failure = start_failure
		ksawery.raw_repository_command_request_close(&request)
		command_context_set_diagnostic(commands, "Confirmed raw repository command could not start")
		return true
	}
	repository := state.repository
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.generation,
		{
			kind = .Raw_Command,
			target_kind = .Repository,
			title = "Raw Repository Command",
			target = ksawery.repository_context_string(&repository),
			phase_detail = "Running separately confirmed raw repository command",
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		ksawery.raw_repository_command_request_close(&request)
		state.raw_failure = {code = .Process_Start, command = state.raw_intent.command}
		state.process_failure = record_failure
		command_context_set_diagnostic(commands, "Raw repository command Process record could not start")
		return true
	}
	state.raw_request = request
	state.raw_terminal = {}
	state.raw_awaiting_refresh = false
	state.process = process
	state.pending = .Raw_Command
	return_mode := state.raw_return_mode
	if !ksawery_workflow_raw_return_mode_is_valid(return_mode) do return_mode = .Status
	state.view_mode = return_mode
	state.position = state.raw_return_position
	state.raw_failure = {}
	state.failure = .None
	command_context_set_diagnostic(commands, "Raw repository command started")
	return true
}

@(private)
dispatch_ksawery_raw_command_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Raw_Command_Input || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control} {
		changed := ksawery_workflow_return_from_raw_command(state)
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Raw repository command composition cancelled")
		return Interaction_Result{changed = changed}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Tab && input.stroke.modifiers == {} {
		return Interaction_Result{changed = ksawery_workflow_raw_command_toggle_mode(state)}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_prepare_raw_command_confirmation(commands)}, {}
	}
	if input.kind == .Key && (input.stroke.kind == .Backspace || input.stroke.kind == .Delete) {
		return Interaction_Result{changed = ksawery_workflow_raw_command_delete_previous(state)}, {}
	}
	if (input.kind == .Text_Commit || input.kind == .Key) && len(input.text) > 0 &&
	   input.stroke.modifiers == {} {
		if ksawery_workflow_raw_command_append(state, input.text) {
			state.raw_failure = {}
			return Interaction_Result{changed = true}, {}
		}
		state.raw_failure = {code = .Invalid_Input}
		command_context_set_diagnostic(commands, "Raw repository command rejected invalid or oversized text")
		return Interaction_Result{changed = true}, {}
	}
	return {}, {}
}

@(private)
dispatch_ksawery_raw_command_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Raw_Command_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		changed := ksawery_workflow_return_from_raw_command(state)
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Raw repository command confirmation cancelled")
		return Interaction_Result{changed = changed}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_raw_command(commands)}, {}
	}
	return {}, {}
}

@(private)
dispatch_ksawery_commit_message_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Commit_Message || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control} {
		finished := ksawery_process_observation_finish_without_child(
			&state.process_coordinator,
			.Cancelled,
			.Cancelled_Before_Effect,
			"Commit composition cancelled",
			ksawery_workflow_now(commands),
		)
		if !finished do state.process_failure = .Cleanup
		state.view_mode = .History if state.commit_mode != .Normal else .Status
		state.commit_precondition = {}
		state.amend_confirmation = {}
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Commit composition cancelled")
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter {
		if input.stroke.modifiers == {.Control} {
			return Interaction_Result{changed = ksawery_workflow_commit_finalize(commands)}, {}
		}
		if state.commit_mode == .Fixup {
			state.failure = .Commit_Message_Invalid
			command_context_set_diagnostic(commands, "Fixup message form is derived from the exact selected revision")
			return Interaction_Result{changed = true}, {}
		}
		if ksawery_workflow_commit_append(state, "\n") do return Interaction_Result{changed = true}, {}
		state.failure = .Commit_Message_Invalid
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && (input.stroke.kind == .Backspace || input.stroke.kind == .Delete) {
		if state.commit_mode == .Fixup do return {}, {}
		return Interaction_Result{changed = ksawery_workflow_commit_delete_previous(state)}, {}
	}
	if (input.kind == .Text_Commit || input.kind == .Key) && len(input.text) > 0 &&
	   input.stroke.modifiers == {} {
		if state.commit_mode == .Fixup do return {}, {}
		if ksawery_workflow_commit_append(state, input.text) do return Interaction_Result{changed = true}, {}
		state.failure = .Commit_Message_Invalid
		command_context_set_diagnostic(commands, "Commit message rejected invalid or oversized text")
		return Interaction_Result{changed = true}, {}
	}
	return {}, {}
}

@(private)
dispatch_ksawery_amend_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Amend_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		state.amend_confirmation = {}
		state.view_mode = .Commit_Message
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Amend confirmation cancelled; message draft retained")
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_amend(commands)}, {}
	}
	return {}, {}
}

@(private)
dispatch_ksawery_push_confirmation_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Push_Confirmation || state.process.state != nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {})) {
		finished := ksawery_process_observation_finish_without_child(
			&state.process_coordinator,
			.Cancelled,
			.Cancelled_Before_Effect,
			"Repository push confirmation cancelled",
			ksawery_workflow_now(commands),
		)
		if !finished do state.process_failure = .Cleanup
		state.push_configuration = {}
		state.push_precondition = {}
		state.push_confirmation = {}
		state.push_request = {}
		state.view_mode = .Refs
		state.failure = .Cancelled
		command_context_set_diagnostic(commands, "Repository push confirmation cancelled")
		return Interaction_Result{changed = true}, {}
	}
	if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {.Control} {
		return Interaction_Result{changed = ksawery_workflow_confirm_push(commands)}, {}
	}
	return {}, {}
}

@(private)
ksawery_workflow_toggle_detail :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.observation.state == nil || state.process.state != nil do return false
	document := &state.diff if state.diff.state != nil else nil
	next, toggled, failure := ksawery.status_selection_toggle_expansion(
		&state.observation,
		state.selection,
		document,
	)
	if !toggled {
		state.failure = failure
		return false
	}
	state.selection = next
	if next.expanded == {} {
		if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
		if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
		state.diff_failure = .None
		return true
	}
	if state.detail.state != nil do ksawery.path_detail_close(&state.detail)
	if state.diff.state != nil do ksawery.diff_document_close(&state.diff)
	state.diff_failure = .None
	process, started, start_failure := ksawery.repository_process_start_path_detail(
		&state.observation, next.expanded, ksawery_workflow_now(commands), commands.persistent_allocator,
	)
	if !started {
		state.selection.expanded = {}
		state.failure = start_failure
		return false
	}
	path_text, described := ksawery_process_observation_path_text(&state.observation, next.expanded)
	if !described {
		ksawery.repository_process_close(&process)
		state.selection.expanded = {}
		state.failure = .Stale_Observation
		return false
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = .Path_Detail,
			target_kind = .Path,
			title = "Repository Path Detail",
			target = string(path_text),
			phase_detail = "Reading repository path detail",
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.selection.expanded = {}
		state.failure = record_failure
		return false
	}
	state.process = process
	state.pending = .Detail
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_history_current_target :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.History_Target, bool, ksawery.Failure_Code) {
	if state == nil || state.history.state == nil ||
	   !ksawery.history_selection_is_current(&state.history, state.history_selection) {
		return {}, false, .Stale_Observation
	}
	if state.history_selection.current.kind != .Revision {
		return {}, false, .Revision_Unavailable
	}
	return state.history_selection.current.revision, true, .None
}

@(private)
ksawery_workflow_history_detail_request :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Revision_Detail_Request, bool, ksawery.Failure_Code) {
	if state == nil || state.history.state == nil ||
	   !ksawery.history_selection_is_current(&state.history, state.history_selection) {
		return {}, false, .Stale_Observation
	}
	selected := state.history_selection.current
	if selected.kind == .Parent {
		return {
			target = selected.revision,
			parent = {kind = .Parent, parent = selected.parent},
			limits = ksawery.DEFAULT_REVISION_DETAIL_LIMITS,
		}, true, .None
	}
	if selected.kind != .Revision do return {}, false, .Revision_Unavailable
	descriptor, described := ksawery.history_observation_descriptor(&state.history)
	if !described || descriptor.state != .Available do return {}, false, .Revision_Unavailable
	for ordinal in 0 ..< descriptor.revision_count {
		entry, found := ksawery.history_observation_revision(&state.history, ordinal)
		if !found || entry.identity != selected.revision.revision do continue
		if entry.parent_count == 0 {
			return {
				target = selected.revision,
				parent = {kind = .Empty_Tree},
				limits = ksawery.DEFAULT_REVISION_DETAIL_LIMITS,
			}, true, .None
		}
		if entry.parent_count == 1 {
			return {
				target = selected.revision,
				parent = {kind = .Parent, parent = entry.parents[0]},
				limits = ksawery.DEFAULT_REVISION_DETAIL_LIMITS,
			}, true, .None
		}
		return {}, false, .Revision_Unavailable
	}
	return {}, false, .Revision_Unavailable
}

@(private)
ksawery_workflow_start_revision_detail :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History || state.process.state != nil do return false
	request, prepared, failure := ksawery_workflow_history_detail_request(state)
	if !prepared {
		state.failure = failure
		if state.history_selection.current.kind == .Revision {
			command_context_set_diagnostic(commands, "Select an explicit parent relationship for this merge revision")
		} else {
			command_context_set_diagnostic(commands, "Selected repository revision is unavailable")
		}
		return true
	}
	process, started, start_failure := ksawery.repository_process_start_revision_detail_metadata(
		&state.history, request, ksawery_workflow_now(commands), commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		command_context_set_diagnostic(commands, "Repository revision inspection could not start")
		return true
	}
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = .Revision_Detail,
			target_kind = .Revision,
			title = "Repository Revision Detail",
			target = ksawery.revision_identity_string(&request.target.revision),
			phase_detail = "Reading revision metadata",
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Repository revision inspection could not start")
		return true
	}
	ksawery_workflow_clear_revision_inspection(state)
	state.revision_detail_request = request
	state.process = process
	state.pending = .Revision_Detail_Metadata
	state.view_mode = .Revision_Detail
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_start_revision_range :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History || state.process.state != nil do return false
	target, selected, failure := ksawery_workflow_history_current_target(state)
	if !selected || state.history_selection.marked == {} || state.history_selection.marked == target {
		state.failure = failure if !selected else .Invalid_Request
		command_context_set_diagnostic(commands, "Mark one different revision before inspecting a range")
		return true
	}
	request := ksawery.Revision_Range_Request{
		range = {
			base = {generation = state.history_selection.marked.generation, revision = state.history_selection.marked.revision},
			target = {generation = target.generation, revision = target.revision},
		},
		limits = ksawery.DEFAULT_REVISION_RANGE_LIMITS,
	}
	process, started, start_failure := ksawery.repository_process_start_revision_range_summary(
		&state.history, request, ksawery_workflow_now(commands), commands.persistent_allocator,
	)
	if !started {
		state.failure = start_failure
		command_context_set_diagnostic(commands, "Repository revision-range inspection could not start")
		return true
	}
	range_target := fmt.tprintf(
		"%s..%s",
		ksawery.revision_identity_string(&request.range.base.revision),
		ksawery.revision_identity_string(&request.range.target.revision),
	)
	recorded, record_failure := ksawery_process_observation_begin(
		&state.process_coordinator,
		&process,
		state.process_coordinator.confirmed_observation,
		{
			kind = .Revision_Range,
			target_kind = .Revision_Range,
			title = "Repository Revision Range",
			target = range_target,
			phase_detail = "Reading revision range summary",
		},
		ksawery_workflow_now(commands),
	)
	if !recorded {
		ksawery.repository_process_close(&process)
		state.failure = record_failure
		command_context_set_diagnostic(commands, "Repository revision-range inspection could not start")
		return true
	}
	ksawery_workflow_clear_revision_inspection(state)
	state.revision_range_request = request
	state.process = process
	state.pending = .Revision_Range_Summary
	state.view_mode = .Revision_Range
	state.position = {}
	state.failure = .None
	return true
}

@(private)
ksawery_workflow_mark_history_revision :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History || state.process.state != nil do return false
	target, selected, failure := ksawery_workflow_history_current_target(state)
	if !selected {
		state.failure = failure
		command_context_set_diagnostic(commands, "Select a revision before marking a range endpoint")
		return true
	}
	state.history_selection.marked = target
	state.failure = .None
	command_context_set_diagnostic(commands, "Repository range base marked")
	return true
}

@(private)
ksawery_workflow_clear_history_mark :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .History || state.process.state != nil ||
	   state.history_selection.marked == {} {
		return false
	}
	state.history_selection.marked = {}
	state.failure = .None
	command_context_set_diagnostic(commands, "Repository range mark cleared")
	return true
}

@(private)
ksawery_workflow_process_records :: proc(state: ^Ksawery_Workflow_State) -> []ksawery.Process_Record {
	if state == nil || state.process_coordinator.allocator.procedure == nil do return nil
	return state.process_coordinator.records[:int(state.process_coordinator.record_count)]
}

@(private)
ksawery_workflow_open_sequence :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Status || state.sequence.state == nil || state.process.state != nil do return false
	descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	if !described || !descriptor.actions.inspect || descriptor.state == .Inactive do return false
	state.view_mode = .Sequence
	state.position = {}
	if descriptor.conflict_count > 0 && state.conflict_selection == ksawery.Conflict_ID(0) {
		state.conflict_selection = 1
	}
	return true
}

@(private)
ksawery_workflow_sequence_is_active :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.sequence.state == nil do return false
	descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	return described && descriptor.state != .Inactive
}

@(private)
ksawery_workflow_reconcile_conflict_selection :: proc(
	previous: ^ksawery.Sequence_Observation,
	current: ^ksawery.Sequence_Observation,
	selection: ksawery.Conflict_ID,
) -> ksawery.Conflict_ID {
	current_descriptor, current_described := ksawery.sequence_observation_descriptor(current)
	if !current_described || current_descriptor.conflict_count == 0 do return 0
	if previous == nil || previous.state == nil || selection == ksawery.Conflict_ID(0) do return 1
	selected, selected_found := ksawery.sequence_observation_conflict(previous, u32(selection) - 1)
	if !selected_found do return 1
	selected_path, selected_path_found := ksawery.sequence_observation_conflict_path(previous, selected)
	if !selected_path_found do return 1
	for index in 0 ..< current_descriptor.conflict_count {
		candidate, found := ksawery.sequence_observation_conflict(current, index)
		if !found do break
		path, path_found := ksawery.sequence_observation_conflict_path(current, candidate)
		if path_found && path == selected_path do return candidate.id
	}
	return 1
}

@(private)
ksawery_workflow_move_sequence_conflict :: proc(state: ^Ksawery_Workflow_State, next: bool) -> bool {
	if state == nil || state.view_mode != .Sequence || state.sequence.state == nil do return false
	descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	if !described || descriptor.conflict_count == 0 do return false
	current := u32(state.conflict_selection)
	if current == 0 do current = 1
	if next {
		if current >= descriptor.conflict_count do return false
		current += 1
	} else {
		if current <= 1 do return false
		current -= 1
	}
	state.conflict_selection = ksawery.Conflict_ID(current)
	state.position = {}
	return true
}

@(private)
ksawery_workflow_open_conflict :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Sequence || state.sequence.state == nil ||
	   state.conflict_selection == ksawery.Conflict_ID(0) {
		return false
	}
	_, found := ksawery.sequence_observation_conflict(
		&state.sequence,
		u32(state.conflict_selection) - 1,
	)
	if !found do return false
	state.view_mode = .Conflict
	state.position = {}
	return true
}

@(private)
ksawery_workflow_return_from_sequence :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil do return false
	if state.view_mode == .Conflict {
		state.view_mode = .Sequence
		state.position = {}
		return true
	}
	if state.view_mode == .Sequence {
		state.view_mode = .Status
		state.position = {}
		return true
	}
	return false
}

@(private)
ksawery_workflow_open_processes :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.view_mode != .Status && state.view_mode != .Sequence && state.view_mode != .Conflict &&
	   state.view_mode != .History && state.view_mode != .Refs {
		return false
	}
	records := ksawery_workflow_process_records(state)
	selection, begun := ksawery.process_selection_begin(records)
	if !begun {
		state.process_failure = .Presentation_Unavailable
		command_context_set_diagnostic(commands, "Repository Process inspection is unavailable")
		return true
	}
	state.process_return_mode = state.view_mode
	state.process_return_position = state.position
	state.process_selection = selection
	state.process_detail_open = false
	_ = ksawery_extension_annotations_refresh_process(
		&state.extension_registry,
		&commands.host,
		state.repository,
		records,
		commands.temporary_allocator,
	)
	state.view_mode = .Process
	state.position = {}
	state.process_failure = .None
	return true
}

@(private)
ksawery_workflow_refresh_processes :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.view_mode != .Process do return false
	reconciled, reconciled_ok, failure := ksawery.process_selection_reconcile(
		ksawery_workflow_process_records(state),
		state.process_selection,
	)
	if !reconciled_ok {
		state.process_failure = failure
		command_context_set_diagnostic(commands, "Repository Process inspection could not refresh")
		return true
	}
	state.process_selection = reconciled
	state.position = {}
	state.process_failure = .None
	return true
}

@(private)
/* Resolves one selected record action and revalidates its exact immutable generation. */
ksawery_workflow_process_action :: proc(
	state: ^Ksawery_Workflow_State,
	selection: ksawery.Process_Selection,
	kind: ksawery.Process_Action_Kind,
) -> (ksawery.Process_Action_Descriptor, bool, ksawery.Failure_Code) {
	if state == nil do return {}, false, .Invalid_Request
	records := ksawery_workflow_process_records(state)
	action, resolved, failure := ksawery.process_selection_action(records, selection, kind)
	if !resolved do return {}, false, failure
	current, current_failure := ksawery.process_surface_action_is_current(records, action)
	if !current do return {}, false, current_failure
	return action, true, .None
}

@(private)
ksawery_workflow_toggle_process_detail :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	if state.view_mode != .Process do return false
	_, inspected, action_failure := ksawery_workflow_process_action(
		state,
		state.process_selection,
		.Inspect,
	)
	if !inspected {
		state.process_failure = action_failure
		command_context_set_diagnostic(commands, "Repository Process inspection action is unavailable")
		return true
	}
	_, detailed, failure := ksawery.process_surface_detail(
		ksawery_workflow_process_records(state),
		state.process_selection,
	)
	if !detailed {
		state.process_failure = failure
		command_context_set_diagnostic(commands, "No repository Process record is available to inspect")
		return true
	}
	state.process_detail_open = !state.process_detail_open
	state.position = {}
	state.process_failure = .None
	return true
}

@(private)
/* Requests cancellation only through the exact action and associated native process generation. */
ksawery_workflow_cancel_process :: proc(commands: ^Command_Context, selected: bool) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	records := ksawery_workflow_process_records(state)
	selection := state.process_selection
	if !selected {
		begun: bool
		selection, begun = ksawery.process_selection_begin(records)
		if !begun do return false
	}
	action, available, action_failure := ksawery_workflow_process_action(state, selection, .Cancel)
	if !available {
		if action_failure == .Action_Unavailable do return false
		state.process_failure = action_failure
		command_context_set_diagnostic(commands, "Repository Process cancellation action became stale")
		return true
	}
	if state.pending == .Extension_Operation && state.extension_operation != nil &&
	   state.extension_operation.active {
		if ksawery_workflow_cancel_extension_operation(commands) {
			state.process_failure = .None
			return true
		}
		state.process_failure = .Action_Unavailable
		command_context_set_diagnostic(commands, "Checked external Process cancellation was rejected")
		return true
	}
	cancelled, cancel_failure := ksawery.repository_process_request_cancellation(
		&state.process,
		{
			operation = action.operation,
			generation = action.generation,
			requested_ns = ksawery_workflow_now(commands),
		},
	)
	if !cancelled {
		state.process_failure = cancel_failure
		command_context_set_diagnostic(commands, "Checked repository Process cancellation was rejected")
		return true
	}
	recorded, record_failure := ksawery_process_observation_note_cancellation(
		&state.process_coordinator,
		&state.process,
		ksawery_workflow_now(commands),
	)
	if !recorded {
		state.process_failure = record_failure
		command_context_set_diagnostic(commands, "Repository Process cancellation was requested but could not be recorded")
		return true
	}
	state.process_failure = .None
	command_context_set_diagnostic(commands, "Repository Process cancellation requested")
	return true
}

@(private)
ksawery_workflow_return_from_processes :: proc(state: ^Ksawery_Workflow_State) -> bool {
	if state == nil || state.view_mode != .Process do return false
	return_mode := state.process_return_mode
	if return_mode != .Status && return_mode != .Sequence && return_mode != .Conflict &&
	   return_mode != .History && return_mode != .Refs {
		return_mode = .Status
	}
	state.view_mode = return_mode
	state.process_return_mode = .Status
	state.position = state.process_return_position
	state.process_return_position = {}
	state.process_selection = {}
	state.process_detail_open = false
	state.process_failure = .None
	return true
}

@(private)
/* Projects one active-first immutable record through the existing compact feedback owner. */
ksawery_workflow_compact_process_feedback :: proc(
	state: ^Ksawery_Workflow_State,
	storage: []u8,
) -> (content: string, role: ui.Style_Role, active: bool, present: bool) {
	if state == nil || !state.active || len(storage) == 0 do return "", .Invalid, false, false
	return ksawery_process_compact_feedback(ksawery_workflow_process_records(state), storage)
}

@(private)
command_context_present_ksawery_command_navigation :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ksawery_workflow == nil ||
	   !commands.ksawery_workflow.active || commands.host.call == nil {
		return {}, App_Failure{stage = .Session_Access}
	}
	_ = constraints
	if !host_command_request(&commands.host, .Present_Navigation, "") {
		return {}, App_Failure{stage = .Command_Dispatch, host_status = .Failed}
	}
	return Interaction_Result{changed = true}, {}
}

@(private)
dispatch_ksawery_status_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
	direct_metadata: ^interaction.Command_Metadata = nil,
	constraints := display.Viewport_Constraints{width_cells = 80, height_rows = 24},
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ksawery_workflow == nil || !commands.ksawery_workflow.active {
		return {}, App_Failure{stage = .UI}
	}
	if commands.ksawery_workflow.view_mode == .Process && input.kind == .Key &&
	   input.stroke.kind == .Unicode_Scalar && input.stroke.scalar == 'g' &&
	   input.stroke.modifiers == {.Control} &&
	   ksawery_workflow_cancel_process(commands, true) {
		return Interaction_Result{changed = true}, {}
	}
	if commands.ksawery_workflow.pending == .Extension_Operation && input.kind == .Key &&
	   input.stroke.kind == .Unicode_Scalar && input.stroke.scalar == 'g' &&
	   input.stroke.modifiers == {.Control} {
		if ksawery_workflow_cancel_extension_operation(commands) {
			return Interaction_Result{changed = true}, {}
		}
	}
	if commands.ksawery_workflow.pending == .Raw_Command &&
	   commands.ksawery_workflow.process.state != nil && input.kind == .Key &&
	   input.stroke.kind == .Unicode_Scalar && input.stroke.scalar == 'g' &&
	   input.stroke.modifiers == {.Control} {
		if ksawery_workflow_cancel_process(commands, false) {
			return Interaction_Result{changed = true}, {}
		}
	}
	if (commands.ksawery_workflow.view_mode == .Commit_Message ||
	    commands.ksawery_workflow.view_mode == .Amend_Confirmation ||
	    commands.ksawery_workflow.pending == .Merge_Precondition ||
	    commands.ksawery_workflow.pending == .Merge ||
	    commands.ksawery_workflow.pending == .Rebase_Precondition ||
	    commands.ksawery_workflow.pending == .Rebase ||
	    commands.ksawery_workflow.pending == .Revision_Sequence_Precondition ||
	    commands.ksawery_workflow.pending == .Revision_Sequence ||
	    commands.ksawery_workflow.pending == .Bisect_Precondition ||
	    commands.ksawery_workflow.pending == .Bisect ||
	    commands.ksawery_workflow.pending == .Conflict_Precondition ||
	    commands.ksawery_workflow.pending == .Conflict_Resolution ||
	    (commands.ksawery_workflow.view_mode == .Refs &&
	     (commands.ksawery_workflow.pending == .Remote_Configuration ||
	      commands.ksawery_workflow.pending == .Fetch ||
	      commands.ksawery_workflow.pending == .Push_Configuration ||
	      commands.ksawery_workflow.pending == .Push ||
	      commands.ksawery_workflow.pending == .Branch ||
	      commands.ksawery_workflow.pending == .Tag))) &&
	   commands.ksawery_workflow.process.state != nil && input.kind == .Key &&
	   input.stroke.kind == .Unicode_Scalar && input.stroke.scalar == 'g' &&
	   input.stroke.modifiers == {.Control} {
		if ksawery_workflow_cancel_process(commands, false) {
			return Interaction_Result{changed = true}, {}
		}
		if ksawery.repository_process_cancel(&commands.ksawery_workflow.process) {
			return Interaction_Result{changed = true}, {}
		}
	}
	if commands.ksawery_workflow.view_mode == .Commit_Message &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_commit_message_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Raw_Command_Input &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_raw_command_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Inspection_Workflow && direct_metadata == nil {
		return dispatch_ksawery_inspection_input(commands, input)
	}
	if (commands.ksawery_workflow.view_mode == .Inspection_Input ||
	    commands.ksawery_workflow.view_mode == .Inspection_Confirmation) && direct_metadata == nil {
		return dispatch_ksawery_inspection_action_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Raw_Command_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_raw_command_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Amend_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_amend_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Push_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_push_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Branch_Name &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_branch_name_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Branch_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_branch_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Tag_Name &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_tag_name_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Tag_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_tag_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Merge_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_merge_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Rebase_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_rebase_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Revision_Sequence_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_revision_sequence_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Bisect_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_bisect_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Conflict_Confirmation &&
	   commands.ksawery_workflow.process.state == nil {
		return dispatch_ksawery_conflict_confirmation_input(commands, input)
	}
	if commands.ksawery_workflow.view_mode == .Extension_Command {
		return dispatch_ksawery_extension_command_input(commands, input)
	}
	metadata: interaction.Command_Metadata
	resolution: interaction.Resolution
	if commands.ksawery_workflow.view_mode == .Status_Command_Dispatcher && direct_metadata == nil {
		dispatcher_route, handled, changed := ksawery_status_command_dispatcher_input(
			commands.ksawery_workflow,
			input,
		)
		if handled && dispatcher_route == .Invalid {
			return Interaction_Result{changed = changed}, {}
		}
		if dispatcher_route != .Invalid {
			metadata.route = command.contextual_route(dispatcher_route)
			resolution.kind = .Command
		}
	} else if direct_metadata == nil &&
	          (commands.ksawery_workflow.view_mode == .Status ||
	           commands.ksawery_workflow.view_mode == .Refs) {
		family, family_input := ksawery_status_command_family_input(input)
		if family_input {
			if ksawery_status_command_dispatcher_open(commands.ksawery_workflow, family) {
				return Interaction_Result{changed = true}, {}
			}
		}
	}
	if resolution.kind == .Invalid && direct_metadata != nil {
		metadata = direct_metadata^
		resolution.kind = .Command
	} else if resolution.kind == .Invalid {
		if map_failure := command_context_sync_list_map(commands, .Ksawery_Status); map_failure.stage != .None {
			return {}, map_failure
		}
		metadata_value, resolution_value, resolved, resolution_failure :=
			command_context_resolve_context_input(commands, input)
		if !resolved do return {}, resolution_failure
		metadata = metadata_value
		resolution = resolution_value
	}
	if resolution.kind != .Command do return {}, {}
	racket_dispatch, _, racket_route_ok := command.racket_route_decode(metadata.route)
	if racket_route_ok && racket_dispatch == .Ksawery_Extension {
		return command_context_begin_ksawery_extension_command(
			commands, metadata,
		)
	}
	contextual_route, contextual_ok := command.contextual_route_decode(metadata.route)
	native_route, native_ok := command.native_route_decode(metadata.route)
	if native_ok && native_route == .Execute_Extended_Command {
		return command_context_present_ksawery_command_navigation(commands, constraints)
	}
	if native_ok && native_route == .Keyboard_Quit &&
	   commands.ksawery_workflow.view_mode == .Process &&
	   ksawery_workflow_cancel_process(commands, true) {
		return Interaction_Result{changed = true}, {}
	}
	if (contextual_ok && contextual_route == .Component_Close) ||
	   (native_ok && native_route == .Keyboard_Quit) {
		if commands.ksawery_workflow.view_mode == .Status_Command_Dispatcher {
			return Interaction_Result {
				changed = ksawery_status_command_dispatcher_restore(commands.ksawery_workflow),
			}, {}
		}
		if commands.ksawery_workflow.view_mode == .Inspection_Workflow {
			return Interaction_Result {
				changed = ksawery_workflow_return_from_inspection(commands.ksawery_workflow),
			}, {}
		}
		if commands.ksawery_workflow.view_mode == .Process {
			return Interaction_Result {
				changed = ksawery_workflow_return_from_processes(commands.ksawery_workflow),
			}, {}
		}
		if commands.ksawery_workflow.view_mode == .Provider_Inspection {
			return Interaction_Result {
				changed = ksawery_workflow_return_from_provider_inspection(commands.ksawery_workflow),
			}, {}
		}
		if commands.ksawery_workflow.view_mode == .Sequence ||
		   commands.ksawery_workflow.view_mode == .Conflict {
			return Interaction_Result {
				changed = ksawery_workflow_return_from_sequence(commands.ksawery_workflow),
			}, {}
		}
		if commands.ksawery_workflow.pending == .Raw_Command &&
		   commands.ksawery_workflow.process.state != nil {
			command_context_set_diagnostic(commands, "Cancel the raw repository command with C-g before leaving Ksawery")
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Refs && commands.ksawery_workflow.process.state != nil &&
		   (commands.ksawery_workflow.pending == .Remote_Configuration ||
		    commands.ksawery_workflow.pending == .Fetch ||
		    commands.ksawery_workflow.pending == .Push_Configuration ||
		    commands.ksawery_workflow.pending == .Push ||
		    commands.ksawery_workflow.pending == .Branch ||
		    commands.ksawery_workflow.pending == .Tag ||
		    commands.ksawery_workflow.pending == .Merge_Precondition ||
		    commands.ksawery_workflow.pending == .Merge ||
		    commands.ksawery_workflow.pending == .Rebase_Precondition ||
		    commands.ksawery_workflow.pending == .Rebase) {
			command_context_set_diagnostic(commands, "Cancel the checked repository operation with C-g before leaving Refs")
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Amend_Confirmation {
			commands.ksawery_workflow.amend_confirmation = {}
			commands.ksawery_workflow.view_mode = .Commit_Message
			commands.ksawery_workflow.failure = .Cancelled
			command_context_set_diagnostic(commands, "Amend confirmation cancelled; message draft retained")
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Push_Confirmation {
			commands.ksawery_workflow.push_configuration = {}
			commands.ksawery_workflow.push_precondition = {}
			commands.ksawery_workflow.push_confirmation = {}
			commands.ksawery_workflow.view_mode = .Refs
			commands.ksawery_workflow.failure = .Cancelled
			command_context_set_diagnostic(commands, "Repository push confirmation cancelled")
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Branch_Name ||
		   commands.ksawery_workflow.view_mode == .Branch_Confirmation {
			ksawery_workflow_clear_branch_preparation(commands.ksawery_workflow)
			commands.ksawery_workflow.view_mode = .Refs
			commands.ksawery_workflow.failure = .Cancelled
			command_context_set_diagnostic(commands, "Local branch operation cancelled")
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Tag_Name ||
		   commands.ksawery_workflow.view_mode == .Tag_Confirmation {
			ksawery_workflow_clear_tag_preparation(commands.ksawery_workflow)
			commands.ksawery_workflow.view_mode = .Refs
			commands.ksawery_workflow.failure = .Cancelled
			command_context_set_diagnostic(commands, "Local tag operation cancelled")
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Merge_Confirmation {
			_ = ksawery_process_observation_finish_without_child(
				&commands.ksawery_workflow.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
				"Merge confirmation cancelled", ksawery_workflow_now(commands),
			)
			return_mode := commands.ksawery_workflow.merge_action == .Start ? Ksawery_View_Mode.Refs : .Sequence
			ksawery_workflow_clear_merge_preparation(commands.ksawery_workflow)
			commands.ksawery_workflow.view_mode = return_mode
			commands.ksawery_workflow.failure = .Cancelled
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Rebase_Confirmation {
			_ = ksawery_process_observation_finish_without_child(
				&commands.ksawery_workflow.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
				"Rebase confirmation cancelled", ksawery_workflow_now(commands),
			)
			return_mode := commands.ksawery_workflow.rebase_action == .Start ? Ksawery_View_Mode.Refs : .Sequence
			ksawery_workflow_clear_rebase_preparation(
				commands.ksawery_workflow,
				commands.ksawery_workflow.rebase_action == .Start,
			)
			commands.ksawery_workflow.view_mode = return_mode
			commands.ksawery_workflow.failure = .Cancelled
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Revision_Sequence_Confirmation {
			_ = ksawery_process_observation_finish_without_child(
				&commands.ksawery_workflow.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
				"Sequenced revision confirmation cancelled", ksawery_workflow_now(commands),
			)
			commands.ksawery_workflow.revision_sequence_confirmation = {}
			commands.ksawery_workflow.revision_sequence_request = {}
			commands.ksawery_workflow.view_mode =
				commands.ksawery_workflow.revision_sequence_action == .Start ? .History : .Sequence
			commands.ksawery_workflow.failure = .Cancelled
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Bisect_Confirmation {
			_ = ksawery_process_observation_finish_without_child(
				&commands.ksawery_workflow.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
				"Manual bisect confirmation cancelled", ksawery_workflow_now(commands),
			)
			commands.ksawery_workflow.bisect_confirmation = {}
			commands.ksawery_workflow.bisect_request = {}
			commands.ksawery_workflow.view_mode =
				commands.ksawery_workflow.bisect_action == .Start ? .History : .Sequence
			commands.ksawery_workflow.failure = .Cancelled
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Conflict_Confirmation {
			_ = ksawery_process_observation_finish_without_child(
				&commands.ksawery_workflow.process_coordinator, .Cancelled, .Cancelled_Before_Effect,
				"Conflict resolution confirmation cancelled", ksawery_workflow_now(commands),
			)
			ksawery_workflow_clear_conflict_preparation(commands.ksawery_workflow)
			commands.ksawery_workflow.view_mode = .Conflict
			commands.ksawery_workflow.failure = .Cancelled
			return Interaction_Result{changed = true}, {}
		}
		if commands.ksawery_workflow.view_mode == .Resource || commands.ksawery_workflow.view_mode == .History ||
		   commands.ksawery_workflow.view_mode == .Refs ||
		   commands.ksawery_workflow.view_mode == .Revision_Detail || commands.ksawery_workflow.view_mode == .Revision_Range {
			if commands.ksawery_workflow.view_mode == .History &&
			   commands.ksawery_workflow.commit_refresh == .History {
				commands.ksawery_workflow.commit_refresh = .None
			}
			if commands.ksawery_workflow.view_mode == .Resource {
				return_mode := commands.ksawery_workflow.resource_return_mode
				if return_mode != .Conflict && return_mode != .Status do return_mode = .Status
				commands.ksawery_workflow.view_mode = return_mode
				commands.ksawery_workflow.resource_return_mode = .Status
				commands.ksawery_workflow.surface_restore_pending = true
			} else {
				commands.ksawery_workflow.view_mode = .History if commands.ksawery_workflow.view_mode == .Revision_Detail ||
					commands.ksawery_workflow.view_mode == .Revision_Range else .Status
			}
			commands.ksawery_workflow.visited = {}
			commands.ksawery_workflow.position = {}
			return Interaction_Result{changed = true}, {}
		}
		command_context_deactivate_context_map(commands, .Completed)
		return command_context_exit_ksawery_status(commands)
	}
	state := commands.ksawery_workflow
	if contextual_ok && contextual_route == .Ksawery_Providers {
		return Interaction_Result{changed = ksawery_workflow_open_provider_inspection(state)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Provider_Reload {
		return ksawery_workflow_reload_provider(commands)
	}
	if contextual_ok && contextual_route == .Ksawery_Provider_Disable {
		return ksawery_workflow_disable_provider(commands)
	}
	if contextual_ok && contextual_route == .Ksawery_Processes {
		return Interaction_Result{changed = ksawery_workflow_open_processes(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Sequence {
		return Interaction_Result{changed = ksawery_workflow_open_sequence(commands.ksawery_workflow)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Stashes {
		return Interaction_Result{changed = ksawery_workflow_start_inspection(commands, .Stash)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Worktrees {
		return Interaction_Result{changed = ksawery_workflow_start_inspection(commands, .Worktree)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Blame {
		return Interaction_Result{changed = ksawery_workflow_start_inspection(commands, .Blame)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Reflog {
		return Interaction_Result{changed = ksawery_workflow_start_inspection(commands, .Reflog)}, {}
	}
	if contextual_ok && contextual_route == .Component_Complete_Current &&
	   state.extension_annotation_selection.valid {
		generation, _, ready := ksawery_extension_annotation_active_context(state)
		if ready {
			command_name, available := ksawery_extension_annotation_selected_command(
				generation, state.extension_annotation_selection,
			)
			if available {
				if host_command_request(&commands.host, .Invoke, command_name) {
					return Interaction_Result{changed = true}, {}
				}
				command_context_set_diagnostic(commands, "Extension annotation command is unavailable")
				return Interaction_Result{changed = true}, {}
			}
		}
		state.extension_annotation_selection = {}
	}
	if state.view_mode == .Process && contextual_ok {
		if contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row {
			direction := ksawery.Process_Navigation.Previous
			if contextual_route == .Component_Next_Row do direction = .Next
			next, moved, failure := ksawery.process_selection_move(
				ksawery_workflow_process_records(state),
				state.process_selection,
				direction,
			)
			if moved {
				state.process_selection = next
				state.position = {}
				state.process_failure = .None
				return Interaction_Result{changed = true}, {}
			}
			state.process_failure = failure
			return Interaction_Result{changed = failure != .None}, {}
		}
		if contextual_route == .Component_Complete_Current ||
		   contextual_route == .Component_Activate_Current {
			return Interaction_Result{changed = ksawery_workflow_toggle_process_detail(commands)}, {}
		}
		if contextual_route == .Result_Refresh {
			return Interaction_Result{changed = ksawery_workflow_refresh_processes(commands)}, {}
		}
	}
	mutation_route := contextual_ok && (
		contextual_route == .Ksawery_Stage || contextual_route == .Ksawery_Unstage ||
		contextual_route == .Ksawery_Discard || contextual_route == .Ksawery_Commit ||
		contextual_route == .Ksawery_Raw_Command ||
		contextual_route == .Ksawery_Amend || contextual_route == .Ksawery_Fixup ||
		contextual_route == .Ksawery_Fetch || contextual_route == .Ksawery_Push ||
		contextual_route == .Ksawery_Branch_Create || contextual_route == .Ksawery_Branch_Switch ||
		contextual_route == .Ksawery_Branch_Rename || contextual_route == .Ksawery_Branch_Delete ||
		contextual_route == .Ksawery_Tag_Create || contextual_route == .Ksawery_Tag_Delete
	)
	if mutation_route && ksawery_workflow_sequence_is_active(state) {
		state.failure = .Action_Unavailable
		command_context_set_diagnostic(commands, "The active repository sequence admits only its explicit controls and conflict actions")
		return Interaction_Result{changed = true}, {}
	}
	operation_route := contextual_ok && (
		contextual_route == .Component_Complete_Current ||
		contextual_route == .Result_Refresh ||
		contextual_route == .Component_Activate_Current ||
		contextual_route == .Ksawery_Mark ||
		contextual_route == .Ksawery_Unmark ||
		contextual_route == .Ksawery_Clear_Marks ||
		contextual_route == .Ksawery_Provider_Reload ||
		contextual_route == .Ksawery_Provider_Disable ||
		contextual_route == .Ksawery_Stage ||
		contextual_route == .Ksawery_Unstage ||
		contextual_route == .Ksawery_Discard ||
		contextual_route == .Ksawery_Raw_Command ||
		contextual_route == .Ksawery_Commit ||
		contextual_route == .Ksawery_Amend ||
		contextual_route == .Ksawery_Fixup ||
		contextual_route == .Ksawery_Sequence ||
		contextual_route == .Ksawery_History ||
		contextual_route == .Ksawery_History_Next ||
		contextual_route == .Ksawery_Refs ||
		contextual_route == .Ksawery_Fetch ||
		contextual_route == .Ksawery_Push ||
		contextual_route == .Ksawery_Branch_Create ||
		contextual_route == .Ksawery_Branch_Switch ||
		contextual_route == .Ksawery_Branch_Rename ||
		contextual_route == .Ksawery_Branch_Delete ||
		contextual_route == .Ksawery_Tag_Create ||
		contextual_route == .Ksawery_Tag_Delete ||
		contextual_route == .Ksawery_Merge_Fast_Forward ||
		contextual_route == .Ksawery_Merge ||
		contextual_route == .Ksawery_Merge_No_Fast_Forward ||
		contextual_route == .Ksawery_Merge_Continue ||
		contextual_route == .Ksawery_Merge_Abort ||
		contextual_route == .Ksawery_Rebase ||
		contextual_route == .Ksawery_Rebase_Autosquash ||
		contextual_route == .Ksawery_Rebase_Continue ||
		contextual_route == .Ksawery_Rebase_Skip ||
		contextual_route == .Ksawery_Rebase_Abort ||
		contextual_route == .Ksawery_Sequence_Mark ||
		contextual_route == .Ksawery_Sequence_Unmark ||
		contextual_route == .Ksawery_Cherry_Pick ||
		contextual_route == .Ksawery_Cherry_Pick_Continue ||
		contextual_route == .Ksawery_Cherry_Pick_Skip ||
		contextual_route == .Ksawery_Cherry_Pick_Abort ||
		contextual_route == .Ksawery_Revert ||
		contextual_route == .Ksawery_Revert_Continue ||
		contextual_route == .Ksawery_Revert_Skip ||
		contextual_route == .Ksawery_Revert_Abort ||
		contextual_route == .Ksawery_Bisect_Good ||
		contextual_route == .Ksawery_Bisect_Bad ||
		contextual_route == .Ksawery_Bisect_Start ||
		contextual_route == .Ksawery_Bisect_Skip ||
		contextual_route == .Ksawery_Bisect_Reset ||
		contextual_route == .Ksawery_Conflict_Mark ||
		contextual_route == .Ksawery_Conflict_Assist ||
		contextual_route == .Ksawery_Conflict_Use_Base ||
		contextual_route == .Ksawery_Conflict_Use_Current ||
		contextual_route == .Ksawery_Conflict_Use_Applied ||
		contextual_route == .Ksawery_Conflict_Delete
	)
	if operation_route && state.pending == .Sequence_Observe && state.process.state != nil {
		_ = ksawery.repository_process_cancel(&state.process)
		_ = ksawery_workflow_step(commands)
	}
	conflict_assistance_active := state.conflict_assistance != nil &&
		state.conflict_assistance.operation.active
	if operation_route && (state.process.state != nil || conflict_assistance_active) {
		command_context_set_diagnostic(commands, "Repository operation already in progress")
		return Interaction_Result{changed = true}, {}
	}
	if contextual_ok && (contextual_route == .Component_Previous_Row || contextual_route == .Component_Next_Row) {
		if state.view_mode == .Sequence {
			return Interaction_Result {
				changed = ksawery_workflow_move_sequence_conflict(
					state,
					contextual_route == .Component_Next_Row,
				),
			}, {}
		} else if state.view_mode == .History && state.history.state != nil {
			direction := ksawery.History_Navigation.Previous
			if contextual_route == .Component_Next_Row do direction = .Next
			next, moved, _ := ksawery.history_selection_move(
				&state.history, state.history_selection, direction,
			)
			if moved {
				state.history_selection = next
				return Interaction_Result{changed = true}, {}
			}
		} else if state.view_mode == .Refs && state.refs.state != nil {
			direction := ksawery.Ref_Navigation.Previous
			if contextual_route == .Component_Next_Row do direction = .Next
			next, moved, _ := ksawery.ref_selection_move(&state.refs, state.ref_selection, direction)
			if moved {
				state.ref_selection = next
				return Interaction_Result{changed = true}, {}
			}
		} else if state.view_mode == .Status && state.observation.state != nil {
			direction := ksawery.Status_Navigation.Previous
			if contextual_route == .Component_Next_Row do direction = .Next
			document := &state.diff if state.diff.state != nil else nil
			next, moved, _ := ksawery.status_selection_move(
				&state.observation,
				state.selection,
				direction,
				document,
			)
			if moved {
				state.selection = next
				return Interaction_Result{changed = true}, {}
			}
		}
		return {}, {}
	}
	if contextual_ok && contextual_route == .Component_Complete_Current {
		changed := false
		if state.view_mode == .Sequence {
			changed = ksawery_workflow_open_conflict(state)
		} else if state.view_mode == .History {
			changed = ksawery_workflow_start_revision_detail(commands)
		} else if state.view_mode == .Status {
			if state.extension_status_selection.valid && state.extension_status != nil &&
			   state.observation.state != nil {
				descriptor, described := ksawery.status_observation_descriptor(&state.observation)
				values := [1]ksawery.Extension_Status_Generation{state.extension_status^}
				command_name, available := ksawery_extension_status_selected_command(
					values[:], descriptor, state.extension_status_selection,
				)
				if described && available {
					if host_command_request(&commands.host, .Invoke, command_name) {
						return Interaction_Result{changed = true}, {}
					}
					command_context_set_diagnostic(commands, "Extension Status command is unavailable")
					return Interaction_Result{changed = true}, {}
				}
			}
			changed = ksawery_workflow_toggle_detail(commands)
		}
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Result_Refresh {
		changed := ksawery_workflow_refresh_history(commands) if state.view_mode == .History ||
			state.view_mode == .Revision_Detail || state.view_mode == .Revision_Range else
			ksawery_workflow_refresh_refs(commands) if state.view_mode == .Refs else ksawery_workflow_refresh(commands)
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_History {
		return Interaction_Result{changed = ksawery_workflow_open_history(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_History_Next {
		return Interaction_Result{changed = ksawery_workflow_next_history_page(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Refs {
		return Interaction_Result{changed = ksawery_workflow_open_refs(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Fetch {
		return Interaction_Result{changed = ksawery_workflow_begin_fetch(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Push {
		return Interaction_Result{changed = ksawery_workflow_begin_push(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Branch_Create {
		return Interaction_Result{changed = ksawery_workflow_begin_branch(commands, .Create)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Branch_Switch {
		return Interaction_Result{changed = ksawery_workflow_begin_branch(commands, .Switch)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Branch_Rename {
		return Interaction_Result{changed = ksawery_workflow_begin_branch(commands, .Rename)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Branch_Delete {
		return Interaction_Result{changed = ksawery_workflow_begin_branch(commands, .Delete)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Tag_Create {
		return Interaction_Result{changed = ksawery_workflow_begin_tag(commands, .Create)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Tag_Delete {
		return Interaction_Result{changed = ksawery_workflow_begin_tag(commands, .Delete)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Merge_Fast_Forward {
		return Interaction_Result{changed = ksawery_workflow_begin_merge(commands, .Start, .Fast_Forward_Only)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Merge {
		return Interaction_Result{changed = ksawery_workflow_begin_merge(commands, .Start, .Allow_Merge_Commit)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Merge_No_Fast_Forward {
		return Interaction_Result{changed = ksawery_workflow_begin_merge(commands, .Start, .Require_Merge_Commit)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Merge_Continue {
		return Interaction_Result{changed = ksawery_workflow_begin_merge(commands, .Continue)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Merge_Abort {
		return Interaction_Result{changed = ksawery_workflow_begin_merge(commands, .Abort)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Rebase {
		return Interaction_Result{changed = ksawery_workflow_begin_rebase(commands, .Start, .Ordinary)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Rebase_Autosquash {
		return Interaction_Result{changed = ksawery_workflow_begin_rebase(commands, .Start, .Autosquash)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Rebase_Continue {
		return Interaction_Result{changed = ksawery_workflow_begin_rebase(commands, .Continue)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Rebase_Skip {
		return Interaction_Result{changed = ksawery_workflow_begin_rebase(commands, .Skip)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Rebase_Abort {
		return Interaction_Result{changed = ksawery_workflow_begin_rebase(commands, .Abort)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Sequence_Mark {
		return Interaction_Result{changed = ksawery_workflow_mark_revision_sequence_target(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Sequence_Unmark {
		return Interaction_Result{changed = ksawery_workflow_unmark_revision_sequence_target(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Cherry_Pick {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Cherry_Pick, .Start)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Cherry_Pick_Continue {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Cherry_Pick, .Continue)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Cherry_Pick_Skip {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Cherry_Pick, .Skip)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Cherry_Pick_Abort {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Cherry_Pick, .Abort)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Revert {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Revert, .Start)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Revert_Continue {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Revert, .Continue)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Revert_Skip {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Revert, .Skip)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Revert_Abort {
		return Interaction_Result{changed = ksawery_workflow_begin_revision_sequence(commands, .Revert, .Abort)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Bisect_Good {
		changed := ksawery_workflow_mark_bisect_boundary(commands, true) if state.view_mode == .History else
			ksawery_workflow_begin_bisect(commands, .Good)
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Bisect_Bad {
		changed := ksawery_workflow_mark_bisect_boundary(commands, false) if state.view_mode == .History else
			ksawery_workflow_begin_bisect(commands, .Bad)
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Bisect_Start {
		return Interaction_Result{changed = ksawery_workflow_begin_bisect(commands, .Start)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Bisect_Skip {
		return Interaction_Result{changed = ksawery_workflow_begin_bisect(commands, .Skip)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Bisect_Reset {
		return Interaction_Result{changed = ksawery_workflow_begin_bisect(commands, .Reset)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Conflict_Mark {
		return Interaction_Result{changed = ksawery_workflow_begin_conflict_resolution(commands, .Mark_Saved_Result)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Conflict_Assist {
		return ksawery_workflow_conflict_assist(commands)
	}
	if contextual_ok && contextual_route == .Ksawery_Conflict_Use_Base {
		return Interaction_Result{changed = ksawery_workflow_begin_conflict_resolution(commands, .Use_Base)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Conflict_Use_Current {
		return Interaction_Result{changed = ksawery_workflow_begin_conflict_resolution(commands, .Use_Current)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Conflict_Use_Applied {
		return Interaction_Result{changed = ksawery_workflow_begin_conflict_resolution(commands, .Use_Applied)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Conflict_Delete {
		return Interaction_Result{changed = ksawery_workflow_begin_conflict_resolution(commands, .Delete_Result)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Raw_Command {
		return Interaction_Result{changed = ksawery_workflow_begin_raw_command(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Commit {
		return Interaction_Result{changed = ksawery_workflow_begin_commit(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Amend {
		return Interaction_Result{changed = ksawery_workflow_begin_amend(commands)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Fixup {
		return Interaction_Result{changed = ksawery_workflow_begin_fixup(commands)}, {}
	}
	if contextual_ok && contextual_route == .Component_Activate_Current {
		if state.view_mode == .Sequence {
			return Interaction_Result{changed = ksawery_workflow_open_conflict(state)}, {}
		}
		if state.view_mode == .Conflict {
			return ksawery_workflow_visit_conflict(commands)
		}
		if state.view_mode == .History {
			changed := ksawery_workflow_start_revision_range(commands) if state.history_selection.marked != {} else
				ksawery_workflow_start_revision_detail(commands)
			return Interaction_Result{changed = changed}, {}
		}
		return ksawery_workflow_visit_selected(commands)
	}
	if contextual_ok && contextual_route == .Ksawery_Mark {
		changed := ksawery_workflow_mark_history_revision(commands) if state.view_mode == .History else
			ksawery_workflow_mark_ref_source(commands) if state.view_mode == .Refs else
			ksawery_workflow_mark_current(commands)
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Unmark {
		changed := ksawery_workflow_clear_history_mark(commands) if state.view_mode == .History else
			ksawery_workflow_unmark_ref_source(commands) if state.view_mode == .Refs else
			ksawery_workflow_unmark_current(commands)
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Clear_Marks {
		changed := ksawery_workflow_clear_revision_sequence_targets(commands) if state.view_mode == .History && ksawery_workflow_revision_sequence_target_count(state) > 0 else
			ksawery_workflow_clear_history_mark(commands) if state.view_mode == .History else
			ksawery_workflow_clear_ref_source(commands) if state.view_mode == .Refs else
			ksawery_workflow_clear_marks(commands)
		return Interaction_Result{changed = changed}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Stage {
		return Interaction_Result{changed = ksawery_workflow_start_index_action(commands, .Stage)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Unstage {
		return Interaction_Result{changed = ksawery_workflow_start_index_action(commands, .Unstage)}, {}
	}
	if contextual_ok && contextual_route == .Ksawery_Discard {
		return command_context_begin_ksawery_discard(commands)
	}
	return {}, {}
}

@(private)
ksawery_workflow_visit_selected :: proc(commands: ^Command_Context) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Status || state.observation.state == nil ||
	   state.process.state != nil {
		return {}, {}
	}
	target, available, failure := ksawery.status_selection_path_target(&state.observation, state.selection)
	if !available {
		state.failure = failure
		return Interaction_Result{changed = true}, {}
	}
	path_count, counted := ksawery.status_observation_path_count(&state.observation)
	if !counted do return {}, {}
	path_text: []u8
	for index in 0 ..< path_count {
		path, found := ksawery.status_observation_path(&state.observation, index)
		if !found || path.id != target.path do continue
		path_text, _ = ksawery.status_observation_path_text(&state.observation, path)
		break
	}
	if len(path_text) == 0 {
		state.failure = .Path_Unavailable
		return Interaction_Result{changed = true}, {}
	}
	absolute, path_error := os.join_path(
		{ksawery.repository_context_string(&state.repository), string(path_text)},
		commands.temporary_allocator,
	)
	if path_error != nil {
		state.failure = .Path_Unavailable
		return Interaction_Result{changed = true}, {}
	}
	defer delete(absolute, commands.temporary_allocator)
	opened, open_ok := host_session_request(
		&commands.host,
		.Open_Path,
		0,
		0,
		absolute,
	)
	if !open_ok {
		return {}, App_Failure{stage = .Session_Publish, host_status = .Failed}
	}
	state.visited = opened.target
	state.resource_return_mode = .Status
	state.view_mode = .Resource
	state.failure = .None
	return Interaction_Result{changed = true}, {}
}

@(private)
present_ksawery_status_ui :: proc(
	commands: ^Command_Context,
	constraints: display.Viewport_Constraints,
	next_snapshot_id: ^u64,
) -> App_Failure {
	if commands == nil || commands.ksawery_workflow == nil || !commands.ksawery_workflow.active ||
	   next_snapshot_id == nil || constraints.width_cells == 0 || constraints.height_rows == 0 {
		return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_List_View}}
	}
	ksawery_workflow_step(commands)
	state := commands.ksawery_workflow
	ksawery_extension_annotation_reconcile_selection(state)
	if state.view_mode == .Resource {
		return present_ksawery_resource_ui(
			commands,
		)
	}
	content_rows, rows_ok := transient_input_content_rows(commands, constraints)
	if !rows_ok do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Invalid_Layout}}
	if map_failure := command_context_sync_list_map(commands, .Ksawery_Status); map_failure.stage != .None {
		return map_failure
	}
	definitions: []ui.List_Item_Definition
	text: []u8
	prepared := false
	if commands.prompt_workflow.mode == .Ksawery_Discard_Choice {
		definitions, text, prepared = ksawery_discard_prompt_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Sequence {
		definitions, text, prepared = ksawery_sequence_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Conflict {
		definitions, text, prepared = ksawery_conflict_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .History {
		definitions, text, prepared = ksawery_history_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Refs {
		definitions, text, prepared = ksawery_refs_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Process {
		definitions, text, prepared = ksawery_process_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Provider_Inspection {
		definitions, text, prepared = ksawery_provider_inspection_list_definitions(
			commands, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Revision_Detail {
		definitions, text, prepared = ksawery_revision_detail_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Revision_Range {
		definitions, text, prepared = ksawery_revision_range_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Inspection_Workflow {
		definitions, text, prepared = ksawery_inspection_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Inspection_Input || state.view_mode == .Inspection_Confirmation {
		definitions, text, prepared = ksawery_inspection_action_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Commit_Message {
		definitions, text, prepared = ksawery_commit_message_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Raw_Command_Input {
		definitions, text, prepared = ksawery_raw_command_input_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Raw_Command_Confirmation {
		definitions, text, prepared = ksawery_raw_command_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Amend_Confirmation {
		definitions, text, prepared = ksawery_amend_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Push_Confirmation {
		definitions, text, prepared = ksawery_push_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Branch_Name {
		definitions, text, prepared = ksawery_branch_name_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Branch_Confirmation {
		definitions, text, prepared = ksawery_branch_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Tag_Name {
		definitions, text, prepared = ksawery_tag_name_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Tag_Confirmation {
		definitions, text, prepared = ksawery_tag_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Merge_Confirmation {
		definitions, text, prepared = ksawery_merge_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Rebase_Confirmation {
		definitions, text, prepared = ksawery_rebase_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Revision_Sequence_Confirmation {
		definitions, text, prepared = ksawery_revision_sequence_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Bisect_Confirmation {
		definitions, text, prepared = ksawery_bisect_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Conflict_Confirmation {
		definitions, text, prepared = ksawery_conflict_confirmation_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Extension_Command {
		definitions, text, prepared = ksawery_extension_command_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else if state.view_mode == .Status_Command_Dispatcher {
		definitions, text, prepared = ksawery_status_command_dispatcher_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	} else {
		definitions, text, prepared = ksawery_status_list_definitions(
			state, content_rows, commands.temporary_allocator,
		)
	}
	if !prepared do return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
	defer delete(definitions, commands.temporary_allocator)
	defer delete(text, commands.temporary_allocator)
	position := state.position
	if commands.prompt_workflow.mode == .None && state.diagnostic_length > 0 {
		decorated, decorated_ok := ksawery_list_prepend_diagnostic(
			state, definitions, commands.temporary_allocator,
		)
		if !decorated_ok {
			return App_Failure{stage = .UI, ui = {operation = .Prepare, code = .Allocation}}
		}
		defer delete(decorated, commands.temporary_allocator)
		definitions = decorated
		if position.current_item >= 0 do position.current_item += 1
		position.first_visible_item = 0
		position.viewport_items = min(content_rows, u32(len(definitions)))
	}
	return command_context_publish_ksawery_list(commands, definitions, text, constraints, position)
}

@(private)
ksawery_list_prepend_diagnostic :: proc(
	state: ^Ksawery_Workflow_State,
	definitions: []ui.List_Item_Definition,
	allocator: runtime.Allocator,
) -> ([]ui.List_Item_Definition, bool) {
	if state == nil || state.diagnostic_length == 0 || allocator.procedure == nil ||
	   len(definitions) >= int(ui.MAX_LIST_ITEMS) {
		return nil, false
	}
	decorated, allocation_error := make([]ui.List_Item_Definition, len(definitions) + 1, allocator)
	if allocation_error != nil do return nil, false
	decorated[0] = {
		id = KSAWERY_DIAGNOSTIC_LIST_ITEM_ID,
		text = string(state.diagnostic[:state.diagnostic_length]),
		passive = true,
	}
	copy(decorated[1:], definitions)
	return decorated, true
}

@(private)
ksawery_discard_prompt_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || state.discard_path_length == 0 || viewport_items == 0 ||
	   allocator.procedure == nil {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 3, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, 3 * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	path := string(state.discard_path[:state.discard_path_length])
	write := 0
	if !ksawery_append_presented_label(
		rows, storage, &write, 0xDD00_0000_0000_0001,
		fmt.tprintf("Discard working-tree changes in %s?", path), true,
		{surface = .Status, subject = .Operation, destructive = true},
	) || !ksawery_append_presented_label(
		rows, storage, &write, 0xDD00_0000_0000_0002, "[y]es", false,
		{surface = .Status, subject = .Operation, destructive = true},
	) || !ksawery_append_presented_label(
		rows, storage, &write, 0xDD00_0000_0000_0003, "[n]o", false,
		{surface = .Status, subject = .Operation},
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = 1,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return rows[:write], storage, true
}

@(private)
present_ksawery_resource_ui :: proc(
	commands: ^Command_Context,
) -> App_Failure {
	if commands == nil || commands.host.call == nil do return {stage = .Session_Access}
	state := commands.ksawery_workflow
	if state == nil || state.visited == 0 do return {stage = .Session_Access}
	_, presented := host_session_request(
		&commands.host,
		.Present_Entry,
		state.visited,
		0,
		"",
	)
	if !presented do return {stage = .Session_Access, host_status = .Failed}
	return {}
}

@(private)
ksawery_process_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	records := ksawery_workflow_process_records(state)
	annotation_observation := ksawery.Extension_Annotation_Observation {
		family = .Process,
		repository = state.repository,
		generation = ksawery_extension_process_annotation_generation(records),
	}
	annotation_generation := ksawery_extension_annotation_generation(
		&state.extension_registry, .Process,
	)
	annotation_rows := ksawery_extension_annotation_visible_row_count(
		annotation_generation, annotation_observation,
	)
	if !ksawery.process_selection_is_current(records, state.process_selection) {
		previous_operation := state.process_selection.current.operation
		reconciled, reconciled_ok, _ := ksawery.process_selection_reconcile(records, state.process_selection)
		if !reconciled_ok do return nil, nil, false
		state.process_selection = reconciled
		if reconciled.current.operation != previous_operation do state.process_detail_open = false
	}
	surface, described := ksawery.process_surface_descriptor(records)
	if !described do return nil, nil, false
	detail_output_bytes: u32
	detail_diagnostic_bytes: u32
	if state.process_detail_open {
		detail, detailed, _ := ksawery.process_surface_detail(records, state.process_selection)
		if detailed {
			detail_output_bytes = detail.content.output.length
			detail_diagnostic_bytes = detail.content.diagnostic.length
		}
	}
	count := min(
		int(surface.row_count) + annotation_rows + 14 + int(detail_output_bytes) + int(detail_diagnostic_bytes),
		int(ui.MAX_LIST_ITEMS),
	)
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	if !ksawery_append_presented_label(
		rows, storage, &write, 0xF000_0000_0000_0001, "Ksawery Processes", true,
		{surface = .Process, subject = .Section},
	) || !ksawery_append_presented_label(
		rows, storage, &write, 0xF000_0000_0000_0002,
		fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)), true,
		{surface = .Process, subject = .Repository},
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.process_failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xF000_0000_0000_0003,
			fmt.tprintf("Repository Process inspection failed: %v", state.process_failure), true,
			{surface = .Process, subject = .Failure, destructive = true},
		)
	}
	if surface.state == .Empty {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xF000_0000_0000_0004,
			"No repository processes are retained in this Ksawery session", true,
			{surface = .Process, subject = .Operation},
		)
	} else {
		for ordinal in 0 ..< surface.row_count {
			row, projected, _ := ksawery.process_surface_row(records, ordinal)
			if !projected do break
			title, title_ok, _ := ksawery.process_surface_text(records, row.id, .Title)
			_, target, target_ok, _ := ksawery.process_surface_target(records, row.id)
			if !title_ok || !target_ok do break
			prefix := "Active" if row.active else "Retained"
			state_label := fmt.tprintf("%v", row.phase) if row.active else fmt.tprintf("%v", row.outcome)
			label := ksawery_process_bounded_label(fmt.tprintf(
				"%s: %s -> %s [%s] %d ms",
				prefix,
				string(title),
				string(target),
				state_label,
				row.timing.elapsed_ns / i64(time.Millisecond),
			))
			current := state.process_selection.current == row.id
			row_index := write
			if !ksawery_append_presented_label(
				rows, storage, &write, ksawery_process_ui_item_id(ordinal), label, false,
				{surface = .Process, subject = .Operation, current = current,
				 destructive = row.lifecycle == .Failed || row.lifecycle == .Indeterminate},
			) {
				break
			}
			if current do state.position.current_item = i32(row_index)
			annotation_target, annotation_target_ready := ksawery.extension_annotation_target_from_process(
				annotation_observation, row,
			)
			if annotation_target_ready {
				annotation_current, _ := ksawery_extension_annotation_append_target(
					rows, storage, &write, annotation_generation, annotation_observation,
					annotation_target, state.extension_annotation_selection,
				)
				if annotation_current >= 0 do state.position.current_item = annotation_current
			}
		}
	}
	if state.process_detail_open && surface.state == .Available {
		detail, detailed, _ := ksawery.process_surface_detail(records, state.process_selection)
		if detailed {
			phase, phase_ok, _ := ksawery.process_surface_text(records, detail.row.id, .Phase_Detail)
			message, message_ok, _ := ksawery.process_surface_text(records, detail.row.id, .Message)
			output, output_ok, _ := ksawery.process_surface_text(records, detail.row.id, .Output)
			diagnostic, diagnostic_ok, _ := ksawery.process_surface_text(records, detail.row.id, .Diagnostic)
			if phase_ok && len(phase) > 0 {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xF100_0000_0000_0001,
					ksawery_process_bounded_label(fmt.tprintf("Phase: %s", string(phase))), true,
					{surface = .Process, subject = .Operation},
				)
			}
			if message_ok && len(message) > 0 {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xF100_0000_0000_0002,
					ksawery_process_bounded_label(fmt.tprintf("Outcome: %s", string(message))), true,
					{surface = .Process, subject = .Operation},
				)
			}
			if detail.content.exit_status_available {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xF100_0000_0000_0003,
					fmt.tprintf("Exit status: %d", detail.content.exit_status), true,
					{surface = .Process, subject = .Operation},
				)
			}
			if output_ok && len(output) > 0 {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xF100_0000_0000_0004,
					fmt.tprintf("Output%s:", " (truncated)" if detail.content.output_truncated else ""), true,
					{surface = .Process, subject = .Operation},
				)
				output_ok = ksawery_process_append_text(
					rows, storage, &write, output, 0xF200_0000_0000_0000, .Operation,
				)
			}
			if output_ok && diagnostic_ok && len(diagnostic) > 0 {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xF300_0000_0000_0001,
					fmt.tprintf("Diagnostics%s:", " (truncated)" if detail.content.diagnostic_truncated else ""), true,
					{surface = .Process, subject = .Failure},
				)
				diagnostic_ok = ksawery_process_append_text(
					rows, storage, &write, diagnostic, 0xF400_0000_0000_0000, .Failure,
				)
			}
			if !output_ok || !diagnostic_ok {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xF600_0000_0000_0001,
					"[Process detail presentation truncated at the visible row limit]", true,
					{surface = .Process, subject = .Failure},
				)
			}
		}
	}
	return_label := "Status"
	if state.process_return_mode == .History do return_label = "History"
	if state.process_return_mode == .Refs do return_label = "Refs"
	action_hint := ""
	if _, inspect_available, _ := ksawery_workflow_process_action(
		state,
		state.process_selection,
		.Inspect,
	); inspect_available {
		action_hint = "Enter inspect; "
	}
	if _, cancel_available, _ := ksawery_workflow_process_action(
		state,
		state.process_selection,
		.Cancel,
	); cancel_available {
		action_hint = fmt.tprintf("%sC-g cancel; ", action_hint)
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xF000_0000_0000_0005,
		fmt.tprintf("Action: %sg refresh; q return to %s", action_hint, return_label), true,
		{surface = .Process, subject = .Operation},
	)
	definitions = rows[:write]
	current_item := i32(-1)
	if (state.process_selection.current != {} || state.extension_annotation_selection.valid) &&
	   state.position.current_item >= 0 &&
	   state.position.current_item < i32(write) {
		current_item = state.position.current_item
	}
	if current_item < 0 {
		for row, index in definitions {
			if !row.passive {
				current_item = i32(index)
				break
			}
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_process_append_text :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	content: []u8,
	id_base: u64,
	subject: ksawery.Presentation_Subject,
) -> bool {
	offset := 0
	row: u64
	for offset < len(content) && write^ + 2 < len(rows) {
		end := offset
		limit := min(len(content), offset + KSAWERY_LIST_ROW_BYTES - 4)
		for end < limit && content[end] != '\n' do end += 1
		label := fmt.tprintf("    %s", string(content[offset:end]))
		if !ksawery_append_presented_label(
			rows, storage, write, ui.List_Item_ID(id_base | row + 1), label, true,
			{surface = .Process, subject = subject, destructive = subject == .Failure},
		) {
			return false
		}
		row += 1
		offset = end + 1 if end < len(content) && content[end] == '\n' else end
	}
	return offset >= len(content)
}

@(private)
ksawery_process_bounded_label :: proc(label: string) -> string {
	if len(label) <= KSAWERY_LIST_ROW_BYTES do return label
	end := KSAWERY_LIST_ROW_BYTES - 3
	for end > 0 && !utf8.rune_start(label[end]) do end -= 1
	return fmt.tprintf("%s...", label[:end])
}

@(private)
ksawery_process_ui_item_id :: proc(ordinal: u32) -> ui.List_Item_ID {
	return ui.List_Item_ID(0xF500_0000_0000_0000 | u64(ordinal) + 1)
}

@(private)
ksawery_refs_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	items: u32
	tracking: u32
	refs_descriptor: ksawery.Ref_Observation_Descriptor
	refs_described := false
	push_output, push_diagnostic: []u8
	branch_output, branch_diagnostic: []u8
	tag_output, tag_diagnostic: []u8
	if state.refs.state != nil {
		items, _ = ksawery.ref_hierarchy_item_count(&state.refs)
		refs_descriptor, refs_described = ksawery.ref_observation_descriptor(&state.refs)
		if refs_described do tracking = refs_descriptor.tracking_relationships
	}
	annotation_observation := ksawery.Extension_Annotation_Observation {
		family = .Refs,
		repository = refs_descriptor.repository,
		generation = u64(refs_descriptor.generation),
	}
	annotation_generation := ksawery_extension_annotation_generation(
		&state.extension_registry, .Refs,
	)
	annotation_rows := ksawery_extension_annotation_visible_row_count(
		annotation_generation, annotation_observation,
	)
	if state.push_result.state != nil {
		push_output, push_diagnostic, _ = ksawery.push_result_output(&state.push_result)
	}
	if state.branch_result.state != nil {
		branch_output, branch_diagnostic, _ = ksawery.branch_result_output(&state.branch_result)
	}
	if state.tag_result.state != nil {
		tag_output, tag_diagnostic, _ = ksawery.tag_result_output(&state.tag_result)
	}
	count := min(
		int(items + tracking) + annotation_rows + 18 + len(push_output) + len(push_diagnostic) +
		len(branch_output) + len(branch_diagnostic) + len(tag_output) + len(tag_diagnostic),
		int(ui.MAX_LIST_ITEMS),
	)
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	if !ksawery_append_presented_label(rows, storage, &write, 1, "Ksawery Refs", true, {surface = .Refs, subject = .Section}) ||
	   !ksawery_append_presented_label(
		rows, storage, &write, 2, fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)), true,
		{surface = .Refs, subject = .Repository},
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xE200_0000_0000_0001,
			fmt.tprintf("Repository Ref operation failed: %v", state.failure), false,
			{surface = .Refs, subject = .Failure, destructive = true},
		)
	}
	if state.refs.state == nil {
		if state.failure == .None {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 3, "Observing repository refs...", false,
				{surface = .Refs, subject = .Operation},
			)
		}
	} else {
		descriptor := refs_descriptor
		if !refs_described {
			delete(rows, allocator)
			delete(storage, allocator)
			return nil, nil, false
		}
		if descriptor.head.state == .Unborn {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 3, "HEAD: unborn", true,
				{surface = .Refs, subject = .Branch},
			)
		} else if descriptor.head.state == .Symbolic {
			branch := descriptor.head.branch
			_ = ksawery_append_presented_label(
				rows, storage, &write, 3,
				fmt.tprintf("HEAD: %s %s", ksawery.ref_name_string(&branch.name), ksawery.revision_identity_string(&descriptor.head.object)), true,
				{surface = .Refs, subject = .Branch, head = true},
			)
		} else if descriptor.head.state == .Detached {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 3, fmt.tprintf("HEAD: detached %s", ksawery.revision_identity_string(&descriptor.head.object)), true,
				{surface = .Refs, subject = .Branch, head = true},
			)
		}
		if state.pending == .Remote_Configuration {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 5, "Checking selected remote configuration...", true,
				{surface = .Refs, subject = .Operation},
			)
		} else if state.pending == .Fetch {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 5, "Fetching selected repository remote...", true,
				{surface = .Refs, subject = .Operation},
			)
		} else if state.pending == .Push_Configuration {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 5, "Checking exact branch push destination...", true,
				{surface = .Refs, subject = .Operation},
			)
		} else if state.pending == .Push {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 5, "Pushing confirmed repository branch...", true,
				{surface = .Refs, subject = .Operation},
			)
		} else if state.pending == .Branch {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 5, "Applying confirmed local branch operation...", true,
				{surface = .Refs, subject = .Operation},
			)
		} else if state.pending == .Tag {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 5, "Applying confirmed local tag operation...", true,
				{surface = .Refs, subject = .Operation},
			)
		} else if state.tag_result.state != nil {
			tag_descriptor, tag_described := ksawery.tag_result_descriptor(&state.tag_result)
			if tag_described {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 5,
					fmt.tprintf("Tag result: %v", ksawery.tag_feedback(tag_descriptor)), true,
					{surface = .Refs, subject = .Operation},
				)
				ksawery_status_append_process_text(rows, storage, &write, tag_output, 0xD800_0000_0000_1000)
				ksawery_status_append_process_text(rows, storage, &write, tag_diagnostic, 0xD800_0000_0000_2000)
			}
		} else if state.branch_result.state != nil {
			branch_descriptor, branch_described := ksawery.branch_result_descriptor(&state.branch_result)
			if branch_described {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 5,
					fmt.tprintf("Branch result: %v", ksawery.branch_feedback(branch_descriptor)), true,
					{surface = .Refs, subject = .Operation},
				)
				ksawery_status_append_process_text(rows, storage, &write, branch_output, 0xD500_0000_0000_1000)
				ksawery_status_append_process_text(rows, storage, &write, branch_diagnostic, 0xD500_0000_0000_2000)
			}
		} else if state.push_result.state != nil {
			push_descriptor, push_described := ksawery.push_result_descriptor(&state.push_result)
			if push_described {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 5,
					fmt.tprintf("Push result: %v", ksawery.push_feedback(push_descriptor)), true,
					{surface = .Refs, subject = .Operation},
				)
				ksawery_status_append_process_text(rows, storage, &write, push_output, 0xD100_0000_0000_1000)
				ksawery_status_append_process_text(rows, storage, &write, push_diagnostic, 0xD100_0000_0000_2000)
			}
		} else if state.fetch_result.state != nil {
			fetch_descriptor, fetch_described := ksawery.fetch_result_descriptor(&state.fetch_result)
			if fetch_described {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 5,
					fmt.tprintf("Fetch result: %v", ksawery.fetch_feedback(fetch_descriptor)), true,
					{surface = .Refs, subject = .Operation},
				)
			}
		}
		for ordinal in 0 ..< items {
			item, found := ksawery.ref_hierarchy_item(&state.refs, ordinal)
			if !found do break
			label, subject, prepared := ksawery_refs_item_label(item)
			if !prepared do break
			current := state.ref_selection.current == item
			marked := item.kind == .Ref && item.reference == state.ref_selection.marked
			head := descriptor.head.state == .Symbolic && item.kind == .Ref && item.reference == descriptor.head.branch
			row := write
			if !ksawery_append_presented_label(
				rows, storage, &write, ksawery_refs_ui_item_id(ordinal), label, false,
				{surface = .Refs, subject = subject, current = current, marked = marked, head = head},
			) {
				break
			}
			if current do state.position.current_item = i32(row)
			annotation_target: ksawery.Extension_Annotation_Target
			annotation_target_ready := false
			if item.kind == .Ref {
				annotation_target, annotation_target_ready = ksawery.extension_annotation_target_from_ref(
					annotation_observation, item.reference,
				)
			} else if item.kind == .Remote {
				annotation_target, annotation_target_ready = ksawery.extension_annotation_target_from_remote(
					annotation_observation, item.remote,
				)
			}
			if annotation_target_ready {
				annotation_current, _ := ksawery_extension_annotation_append_target(
					rows, storage, &write, annotation_generation, annotation_observation,
					annotation_target, state.extension_annotation_selection,
				)
				if annotation_current >= 0 do state.position.current_item = annotation_current
			}
		}
		for ordinal in 0 ..< descriptor.tracking_relationships {
			relationship, found := ksawery.ref_observation_tracking(&state.refs, ordinal)
			if !found do break
			local := relationship.local
			upstream := relationship.upstream
			label := ksawery_refs_bounded_label(fmt.tprintf(
				"Tracking: %s -> %s %v +%d -%d",
				ksawery.ref_name_string(&local.name),
				ksawery.ref_name_string(&upstream.name),
				relationship.state,
				relationship.ahead,
				relationship.behind,
			))
			_ = ksawery_append_presented_label(
				rows, storage, &write, ui.List_Item_ID(0xE000_0000_0000_0000 | u64(ordinal) + 1), label, true,
				{surface = .Refs, subject = .Tracking},
			)
		}
		action := "Action: n create branch; t create tag; g refresh refs; $ processes; q return to Status"
		if state.pending == .Remote_Configuration || state.pending == .Fetch ||
		   state.pending == .Push_Configuration || state.pending == .Push || state.pending == .Branch ||
		   state.pending == .Tag || state.pending == .Merge_Precondition || state.pending == .Merge ||
		   state.pending == .Rebase_Precondition || state.pending == .Rebase {
			action = "Action: C-g cancel checked repository operation; $ processes; q return to Status"
		} else if state.ref_selection.current.kind == .Remote {
			action = "Action: n create branch; p confirm marked push; & fetch remote; g refresh; $ processes; q return"
		} else if state.ref_selection.current.kind == .Ref &&
		          state.ref_selection.current.reference.kind == .Local_Branch {
			action = "Action: =/i/I merge; e/E rebase/autosquash; S switch; R rename; D delete; * mark push; g refresh"
		} else if state.ref_selection.current.kind == .Ref &&
		          state.ref_selection.current.reference.kind == .Remote_Tracking_Branch {
			action = "Action: =/i/I merge; e/E rebase/autosquash; t create tag; g refresh; $ processes; q return"
		} else if state.ref_selection.current.kind == .Ref &&
		          state.ref_selection.current.reference.kind == .Tag {
			action = "Action: =/i/I merge; e/E rebase/autosquash commit-backed tag; T delete; g refresh"
		}
		_ = ksawery_append_presented_label(
			rows, storage, &write, 4, action, true,
			{surface = .Refs, subject = .Operation},
		)
	}
	definitions = rows[:write]
	current_item := i32(-1)
	if (state.ref_selection.current.kind != .Invalid || state.extension_annotation_selection.valid) &&
	   state.position.current_item >= 0 &&
	   state.position.current_item < i32(write) {
		current_item = state.position.current_item
	}
	if current_item < 0 {
		for row, index in definitions {
			if !row.passive {
				current_item = i32(index)
				break
			}
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_refs_item_label :: proc(item: ksawery.Ref_Item_ID) -> (string, ksawery.Presentation_Subject, bool) {
	switch item.kind {
	case .Ref:
		reference := item.reference
		name := ksawery.ref_name_string(&reference.name)
		object := ksawery.revision_identity_string(&reference.object)
		if len(name) == 0 || len(object) == 0 do return "", .Invalid, false
		subject := ksawery.Presentation_Subject.Branch
		prefix := "Branch"
		if reference.kind == .Remote_Tracking_Branch do prefix = "Remote branch"
		if reference.kind == .Tag {
			prefix = "Tag"
			subject = .Tag
		}
		return ksawery_refs_bounded_label(fmt.tprintf("%s: %s %s", prefix, name, object)), subject, true
	case .Remote:
		remote := item.remote
		name := ksawery.remote_name_string(&remote.name)
		if len(name) == 0 do return "", .Invalid, false
		return ksawery_refs_bounded_label(fmt.tprintf("Remote: %s", name)), .Remote, true
	case .Head, .Invalid:
		return "", .Invalid, false
	}
	return "", .Invalid, false
}

@(private)
ksawery_refs_ui_item_id :: proc(ordinal: u32) -> ui.List_Item_ID {
	return ui.List_Item_ID(0xE100_0000_0000_0000 | u64(ordinal) + 1)
}

@(private)
ksawery_refs_bounded_label :: proc(label: string) -> string {
	if len(label) <= KSAWERY_LIST_ROW_BYTES do return label
	return fmt.tprintf("%s...", label[:KSAWERY_LIST_ROW_BYTES - 3])
}

@(private)
ksawery_history_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	item_count: u32
	history_descriptor: ksawery.History_Observation_Descriptor
	history_described := false
	if state.history.state != nil {
		item_count, _ = ksawery.history_hierarchy_item_count(&state.history)
		history_descriptor, history_described = ksawery.history_observation_descriptor(&state.history)
	}
	annotation_observation := ksawery.Extension_Annotation_Observation {
		family = .History,
		repository = history_descriptor.repository,
		generation = u64(history_descriptor.generation),
	}
	annotation_generation := ksawery_extension_annotation_generation(
		&state.extension_registry, .History,
	)
	annotation_rows := ksawery_extension_annotation_visible_row_count(
		annotation_generation, annotation_observation,
	)
	count := min(int(item_count) + annotation_rows + 8, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	if !ksawery_append_presented_label(
		rows, storage, &write, 1, "Ksawery History", true,
		{surface = .History, subject = .Section},
	) || !ksawery_append_presented_label(
		rows, storage, &write, 2, fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)), true,
		{surface = .History, subject = .Repository},
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 3, fmt.tprintf("History observation failed: %v", state.failure), false,
			{surface = .History, subject = .Failure, destructive = true},
		)
	} else if state.history.state == nil {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 3, "Observing repository history...", false,
			{surface = .History, subject = .Operation},
		)
	} else {
		descriptor := history_descriptor
		if !history_described {
			delete(rows, allocator)
			delete(storage, allocator)
			return nil, nil, false
		}
		switch descriptor.state {
		case .Unborn:
			_ = ksawery_append_presented_label(
				rows, storage, &write, 3, "Repository has no committed revisions", false,
				{surface = .History, subject = .Operation},
			)
		case .Exhausted:
			_ = ksawery_append_presented_label(
				rows, storage, &write, 3, "No additional history entries", false,
				{surface = .History, subject = .Operation},
			)
		case .Available:
			_ = ksawery_append_presented_label(
				rows, storage, &write, 3, fmt.tprintf("HEAD: %s", ksawery.revision_identity_string(&descriptor.head)), true,
				{surface = .History, subject = .Branch, head = true},
			)
			if result, result_described := ksawery.commit_result_descriptor(&state.commit_result); result_described && result.succeeded {
				result_label := fmt.tprintf("Created: %s", ksawery.revision_identity_string(&result.lineage.resulting))
				switch result.request.mode {
				case .Amend:
					result_label = fmt.tprintf(
						"Amended: %s -> %s",
						ksawery.revision_identity_string(&result.lineage.replaced),
						ksawery.revision_identity_string(&result.lineage.resulting),
					)
				case .Fixup:
					result_label = fmt.tprintf(
						"Fixup created: %s; target: %s",
						ksawery.revision_identity_string(&result.lineage.resulting),
						ksawery.revision_identity_string(&result.lineage.fixup_target),
					)
				case .Normal:
				case .Invalid:
				}
				_ = ksawery_append_presented_label(
					rows, storage, &write, 5, result_label, true,
					{surface = .History, subject = .Operation},
				)
			}
			for ordinal in 0 ..< item_count {
				item, found := ksawery.history_hierarchy_item(&state.history, ordinal)
				if !found do break
				label, prepared := ksawery_history_item_label(&state.history, item)
				if !prepared do break
				current := state.history_selection.current == item
				marked := (item.kind == .Revision && state.history_selection.marked != {} &&
					state.history_selection.marked == item.revision) ||
					ksawery_workflow_history_item_is_sequence_marked(state, item) ||
					ksawery_workflow_history_item_is_bisect_marked(state, item)
				subject := ksawery.Presentation_Subject.Revision
				if item.kind == .Parent do subject = .Parent
				row := write
				appended := ksawery_append_presented_label(
					rows, storage, &write, ksawery_history_ui_item_id(ordinal), label, false,
					{surface = .History, subject = subject, current = current, marked = marked, head = item.kind == .Revision && item.revision.revision == descriptor.head},
				)
				if !appended do break
				if current do state.position.current_item = i32(row)
				if item.kind == .Revision {
					annotation_target, annotation_target_ready := ksawery.extension_annotation_target_from_revision(
						annotation_observation, item.revision,
					)
					if annotation_target_ready {
						annotation_current, _ := ksawery_extension_annotation_append_target(
							rows, storage, &write, annotation_generation, annotation_observation,
							annotation_target, state.extension_annotation_selection,
						)
						if annotation_current >= 0 do state.position.current_item = annotation_current
					}
				}
			}
			if ksawery.revision_identity_is_valid(state.bisect_bad) || state.bisect_good_count > 0 {
				bad_label := "not selected"
				if ksawery.revision_identity_is_valid(state.bisect_bad) {
					bad_label = ksawery.revision_identity_string(&state.bisect_bad)
				}
				_ = ksawery_append_presented_label(
					rows, storage, &write, 4,
					fmt.tprintf("Bisect: bad %s; %d good; G toggle good; B set bad; ? start; g refresh; q return", bad_label, state.bisect_good_count), true,
					{surface = .History, subject = .Operation},
				)
			} else if ksawery_workflow_revision_sequence_target_count(state) > 0 {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 4,
					fmt.tprintf("Ordered set: %d commit(s); a add; U remove; P cherry-pick; V revert; 0 clear; Tab inspect; g refresh; q return", ksawery_workflow_revision_sequence_target_count(state)), true,
					{surface = .History, subject = .Operation},
				)
			} else if state.history_selection.marked != {} {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 4,
					fmt.tprintf("Range base: %s; A amend HEAD; F fixup selection; Tab inspect; Enter inspect range; - clear; $ processes; q return", ksawery.revision_identity_string(&state.history_selection.marked.revision)), true,
					{surface = .History, subject = .Operation},
				)
			} else if descriptor.continuation != {} {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 4, "Action: a add ordered commit; select a parent row to choose merge mainline; A amend; F fixup; Tab inspect; * range base; f next; g refresh; $ processes; q return", true,
					{surface = .History, subject = .Operation},
				)
			} else {
				_ = ksawery_append_presented_label(
					rows, storage, &write, 4, "Action: a add ordered commit; select a parent row to choose merge mainline; A amend; F fixup; Tab inspect; * range base; g refresh; $ processes; q return", true,
					{surface = .History, subject = .Operation},
				)
			}
		case .Invalid:
			delete(rows, allocator)
			delete(storage, allocator)
			return nil, nil, false
		}
	}
	definitions = rows[:write]
	current_item := i32(-1)
	if (state.history_selection.current.kind != .Invalid || state.extension_annotation_selection.valid) &&
	   state.position.current_item >= 0 && state.position.current_item < i32(write) {
		current_item = state.position.current_item
	}
	if current_item < 0 {
		for row, index in definitions {
			if !row.passive {
				current_item = i32(index)
				break
			}
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_history_item_label :: proc(
	observation: ^ksawery.History_Observation,
	item: ksawery.History_Item_ID,
) -> (string, bool) {
	if observation == nil || !ksawery.history_item_id_is_valid(item) do return "", false
	if item.kind == .Parent {
		parent := item.parent
		return fmt.tprintf("  parent %s", ksawery.revision_identity_string(&parent)), true
	}
	if item.kind != .Revision do return "", false
	count, available := ksawery.history_observation_revision_count(observation)
	if !available do return "", false
	for ordinal in 0 ..< count {
		revision, found := ksawery.history_observation_revision(observation, ordinal)
		if !found || revision.identity != item.revision.revision do continue
		subject, copied := ksawery.history_observation_text(observation, revision.subject)
		if !copied do return "", false
		identity := ksawery.revision_identity_string(&revision.identity)
		prefix_bytes := len(identity) + 1
		if prefix_bytes >= KSAWERY_LIST_ROW_BYTES do return "", false
		visible_subject := subject[:min(len(subject), KSAWERY_LIST_ROW_BYTES - prefix_bytes)]
		return fmt.tprintf("%s %s", identity, string(visible_subject)), true
	}
	return "", false
}

@(private)
ksawery_history_ui_item_id :: proc(ordinal: u32) -> ui.List_Item_ID {
	return ui.List_Item_ID(0xB000_0000_0000_0000 | u64(ordinal) + 1)
}

@(private)
ksawery_revision_preview :: proc(text: []u8, limit: int) -> string {
	if limit <= 0 || len(text) == 0 do return ""
	return string(text[:min(len(text), limit)])
}

@(private)
ksawery_revision_append_diff_rows :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	id_prefix: u64,
	diff: []u8,
) {
	offset := 0
	ordinal: u64
	for offset < len(diff) && ordinal < 32 && write^ < len(rows) {
		end := offset
		limit := min(len(diff), offset + KSAWERY_LIST_ROW_BYTES - 10)
		for end < limit && diff[end] != '\n' do end += 1
		label := fmt.tprintf("    %s", string(diff[offset:end]))
		appended := ksawery_append_presented_label(
			rows, storage, write, ui.List_Item_ID(id_prefix | ordinal + 1), label, true,
			{surface = .History, subject = .Path},
		)
		if !appended do return
		ordinal += 1
		if end < len(diff) && diff[end] == '\n' {
			offset = end + 1
		} else {
			offset = end
		}
	}
}

@(private)
ksawery_revision_detail_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	path_count: u32
	if state.revision_detail.state != nil {
		descriptor, described := ksawery.revision_detail_descriptor(&state.revision_detail)
		if !described do return nil, nil, false
		path_count = descriptor.changed_paths
	}
	count := min(12 + int(path_count) + 32, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	if !ksawery_append_presented_label(
		rows, storage, &write, 0xC000_0000_0000_0001, "Ksawery Revision Inspection", false,
		{surface = .History, subject = .Section},
	) || !ksawery_append_presented_label(
		rows, storage, &write, 0xC000_0000_0000_0002,
		fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)), true,
		{surface = .History, subject = .Repository},
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC000_0000_0000_0003,
			fmt.tprintf("Revision inspection failed: %v", state.failure), false,
			{surface = .History, subject = .Failure, destructive = true},
		)
	} else if state.revision_detail.state == nil {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC000_0000_0000_0003, "Inspecting repository revision...", false,
			{surface = .History, subject = .Operation},
		)
	} else {
		descriptor, described := ksawery.revision_detail_descriptor(&state.revision_detail)
		if !described {
			delete(rows, allocator)
			delete(storage, allocator)
			return nil, nil, false
		}
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC000_0000_0000_0003,
			fmt.tprintf("Revision: %s", ksawery.revision_identity_string(&descriptor.target.revision)), true,
			{surface = .History, subject = .Revision, current = true},
		)
		parent_label := "Base: empty tree" if descriptor.parent.kind == .Empty_Tree else
			fmt.tprintf("Parent: %s", ksawery.revision_identity_string(&descriptor.parent.parent))
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC000_0000_0000_0004, parent_label, true,
			{surface = .History, subject = .Parent},
		)
		author, author_ok := ksawery.revision_detail_text(&state.revision_detail, descriptor.author_name)
		committed, committed_ok := ksawery.revision_detail_text(&state.revision_detail, descriptor.committed_at)
		if author_ok && committed_ok {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC000_0000_0000_0005,
				fmt.tprintf("Author: %s; committed: %s", ksawery_revision_preview(author, 120), ksawery_revision_preview(committed, 120)), true,
				{surface = .History, subject = .Revision},
			)
		}
		subject, subject_ok := ksawery.revision_detail_text(&state.revision_detail, descriptor.subject)
		if subject_ok {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC000_0000_0000_0006,
				fmt.tprintf("Subject: %s", ksawery_revision_preview(subject, 280)), true,
				{surface = .History, subject = .Revision},
			)
		}
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC000_0000_0000_0007,
			fmt.tprintf("Changed paths: %d; diff bytes: %d; truncated: %v", descriptor.changed_paths, descriptor.diff_bytes, descriptor.truncated), true,
			{surface = .History, subject = .Operation},
		)
		for ordinal in 0 ..< descriptor.changed_paths {
			if write >= len(rows) - 1 do break
			path, found := ksawery.revision_detail_changed_path(&state.revision_detail, ordinal)
			if !found do break
			path_text, copied := ksawery.revision_detail_changed_path_text(&state.revision_detail, path.path)
			if !copied do break
			_ = ksawery_append_presented_label(
				rows, storage, &write, ui.List_Item_ID(0xC100_0000_0000_0000 | u64(ordinal) + 1),
				fmt.tprintf("  %v %s", path.kind, ksawery_revision_preview(path_text, 270)), true,
				{surface = .History, subject = .Path},
			)
		}
		diff, copied := ksawery.revision_detail_diff(&state.revision_detail)
		if copied do ksawery_revision_append_diff_rows(rows, storage, &write, 0xC200_0000_0000_0000, diff)
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xC000_0000_0000_0008, "Action: g refresh history; q return to History", true,
		{surface = .History, subject = .Operation},
	)
	definitions = rows[:write]
	current_item := i32(-1)
	for row, index in definitions {
		if !row.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = current_item,
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}

@(private)
ksawery_revision_range_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	path_count: u32
	revision_count: u32
	if state.revision_range.state != nil {
		descriptor, described := ksawery.revision_range_observation_descriptor(&state.revision_range)
		if !described do return nil, nil, false
		path_count = descriptor.changed_paths
		revision_count = descriptor.revision_count
	}
	count := min(12 + int(path_count) + int(revision_count) + 32, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	if !ksawery_append_presented_label(
		rows, storage, &write, 0xD000_0000_0000_0001, "Ksawery Revision Range", false,
		{surface = .History, subject = .Section},
	) || !ksawery_append_presented_label(
		rows, storage, &write, 0xD000_0000_0000_0002,
		fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)), true,
		{surface = .History, subject = .Repository},
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD000_0000_0000_0003,
			fmt.tprintf("Revision-range inspection failed: %v", state.failure), false,
			{surface = .History, subject = .Failure, destructive = true},
		)
	} else if state.revision_range.state == nil {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD000_0000_0000_0003, "Inspecting repository revision range...", false,
			{surface = .History, subject = .Operation},
		)
	} else {
		descriptor, described := ksawery.revision_range_observation_descriptor(&state.revision_range)
		if !described {
			delete(rows, allocator)
			delete(storage, allocator)
			return nil, nil, false
		}
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD000_0000_0000_0003,
			fmt.tprintf("Base: %s", ksawery.revision_identity_string(&descriptor.range.base.revision)), true,
			{surface = .History, subject = .Parent},
		)
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD000_0000_0000_0004,
			fmt.tprintf("Target: %s", ksawery.revision_identity_string(&descriptor.range.target.revision)), true,
			{surface = .History, subject = .Revision, current = true},
		)
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD000_0000_0000_0005,
			fmt.tprintf("Revisions: %d; changed paths: %d; diff bytes: %d; truncated: %v", descriptor.revision_count, descriptor.changed_paths, descriptor.diff_bytes, descriptor.truncated), true,
			{surface = .History, subject = .Operation},
		)
		for ordinal in 0 ..< descriptor.revision_count {
			if write >= len(rows) - 1 do break
			summary, found := ksawery.revision_range_observation_summary(&state.revision_range, ordinal)
			if !found do break
			subject, copied := ksawery.revision_range_observation_text(&state.revision_range, summary.subject)
			if !copied do break
			_ = ksawery_append_presented_label(
				rows, storage, &write, ui.List_Item_ID(0xD100_0000_0000_0000 | u64(ordinal) + 1),
				fmt.tprintf("  %s %s", ksawery.revision_identity_string(&summary.revision), ksawery_revision_preview(subject, 220)), true,
				{surface = .History, subject = .Revision},
			)
		}
		for ordinal in 0 ..< descriptor.changed_paths {
			if write >= len(rows) - 1 do break
			path, found := ksawery.revision_range_observation_changed_path(&state.revision_range, ordinal)
			if !found do break
			path_text, copied := ksawery.revision_range_observation_changed_path_text(&state.revision_range, path.path)
			if !copied do break
			_ = ksawery_append_presented_label(
				rows, storage, &write, ui.List_Item_ID(0xD200_0000_0000_0000 | u64(ordinal) + 1),
				fmt.tprintf("  %v %s", path.kind, ksawery_revision_preview(path_text, 270)), true,
				{surface = .History, subject = .Path},
			)
		}
		diff, copied := ksawery.revision_range_observation_diff(&state.revision_range)
		if copied do ksawery_revision_append_diff_rows(rows, storage, &write, 0xD300_0000_0000_0000, diff)
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xD000_0000_0000_0006, "Action: g refresh history; q return to History", true,
		{surface = .History, subject = .Operation},
	)
	definitions = rows[:write]
	current_item := i32(-1)
	for row, index in definitions {
		if !row.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = current_item,
		first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}

@(private)
ksawery_raw_command_input_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || state.view_mode != .Raw_Command_Input || viewport_items == 0 ||
	   allocator.procedure == nil {
		return nil, nil, false
	}
	command_text := string(state.raw_input.bytes[:state.raw_input.length])
	count := min(16 + len(command_text), int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	mode_label := "Mode: Git arguments (Odra supplies the git executable)"
	command_label := "Command arguments:"
	if state.raw_input.mode == .Shell {
		mode_label = "Mode: shell program (interpreted as one command string)"
		command_label = "Shell program:"
	}
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xCA00_0000_0000_0001, "Ksawery Raw Repository Command", true,
		{surface = .Status, subject = .Section},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xCA00_0000_0000_0002,
		"Authority: explicit high-authority user action; never an ordinary provider command", true,
		{surface = .Status, subject = .Failure, destructive = true},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xCA00_0000_0000_0003, mode_label, true,
		{surface = .Status, subject = .Repository},
	) && ksawery_status_append_label(
		rows, storage, &write, 0xCA00_0000_0000_0004,
		"Tab switches Git/shell; C-Enter reviews the exact request; C-g cancels and clears", true,
	) && ksawery_status_append_label(
		rows, storage, &write, 0xCA00_0000_0000_0005,
		"Input is bounded to 1 KiB and retained only for this active Ksawery session", true,
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.raw_failure.code != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCA00_0000_0000_0006,
			fmt.tprintf("Raw command feedback: %v", state.raw_failure.code), true,
			{surface = .Status, subject = .Failure, destructive = true},
		)
	}
	_ = ksawery_status_append_label(rows, storage, &write, 0xCA00_0000_0000_0010, command_label, false)
	if len(command_text) > 0 {
		ksawery_status_append_process_text(rows, storage, &write, transmute([]u8)command_text, 0xCA00_0000_0000_0100)
	}
	definitions = rows[:write]
	current_item := i32(-1)
	for definition, index in definitions {
		if !definition.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_raw_command_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || state.view_mode != .Raw_Command_Confirmation || viewport_items == 0 ||
	   allocator.procedure == nil || !ksawery.raw_repository_command_intent_is_valid(state.raw_intent) ||
	   state.raw_confirmation.intent != state.raw_intent {
		return nil, nil, false
	}
	command_text := ksawery.raw_repository_command_input_text(&state.raw_confirmation.intent.input)
	if len(command_text) == 0 do return nil, nil, false
	count := min(18 + len(command_text), int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	mode_label := "Exact mode: Git arguments supplied to the git executable"
	request_label := "Exact Git arguments:"
	if state.raw_intent.input.mode == .Shell {
		mode_label = "Exact mode: shell program interpreted as one command string"
		request_label = "Exact shell program:"
	}
	confirmation_instruction := "C-Enter confirms this exact request; q or C-g cancels and clears it"
	if state.raw_confirmation.confirmed {
		confirmation_instruction = "This exact high-authority request is confirmed; execution has not started"
	}
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xCB00_0000_0000_0001, "Ksawery Raw Command Confirmation", true,
		{surface = .Status, subject = .Section},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xCB00_0000_0000_0002,
		"High authority: this command may make arbitrary repository or filesystem changes", true,
		{surface = .Status, subject = .Failure, destructive = true},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xCB00_0000_0000_0003, mode_label, true,
		{surface = .Status, subject = .Repository},
	) && ksawery_status_append_label(
		rows, storage, &write, 0xCB00_0000_0000_0004, confirmation_instruction, false,
	) && ksawery_status_append_label(
		rows, storage, &write, 0xCB00_0000_0000_0005,
		"Started execution requires a full compatible refresh; zero exit alone is not verified success", true,
	) && ksawery_status_append_label(
		rows, storage, &write, 0xCB00_0000_0000_0006,
		"The entered command is session-transient and omitted from public Process evidence", true,
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.raw_failure.code != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCB00_0000_0000_0007,
			fmt.tprintf("Confirmation feedback: %v", state.raw_failure.code), true,
			{surface = .Status, subject = .Failure, destructive = true},
		)
	}
	_ = ksawery_status_append_label(rows, storage, &write, 0xCB00_0000_0000_0010, request_label, true)
	ksawery_status_append_process_text(
		rows, storage, &write, transmute([]u8)command_text, 0xCB00_0000_0000_0100,
	)
	definitions = rows[:write]
	current_item := i32(-1)
	for definition, index in definitions {
		if !definition.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_commit_message_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	commit_output, commit_diagnostic: []u8
	if state.commit_result.state != nil {
		commit_output, commit_diagnostic, _ = ksawery.commit_result_output(&state.commit_result)
	}
	count := min(14 + int(state.commit_draft_length) + len(commit_output) + len(commit_diagnostic), int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	mode_label := "Mode: normal commit from the checked index"
	instruction := "Enter adds a line; C-Enter finalizes; C-g cancels and retains the draft"
	target_label := ""
	switch state.commit_mode {
	case .Amend:
		mode_label = "Mode: amend the checked repository HEAD"
		instruction = "Enter adds a line; C-Enter prepares exact confirmation; C-g cancels and retains the draft"
		if state.commit_precondition.head.kind == .Revision {
			target_label = fmt.tprintf("Observed HEAD: %s", ksawery.revision_identity_string(&state.commit_precondition.head.revision))
		}
	case .Fixup:
		mode_label = "Mode: fixup for the selected exact revision"
		instruction = "Derived message is read-only; C-Enter finalizes; C-g cancels and retains the draft"
		target_label = fmt.tprintf("Fixup target: %s", ksawery.revision_identity_string(&state.commit_target.revision))
	case .Normal:
	case .Invalid:
	}
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xC100_0000_0000_0001, "Ksawery Commit Message", true,
		{surface = .Status, subject = .Section},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC100_0000_0000_0002, mode_label, true,
		{surface = .Status, subject = .Repository},
	) && ksawery_status_append_label(
		rows, storage, &write, 0xC100_0000_0000_0003,
		instruction, true,
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if len(target_label) > 0 {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC100_0000_0000_0005, target_label, true,
			{surface = .Status, subject = .Revision, current = state.commit_mode == .Amend},
		)
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC100_0000_0000_0004,
			fmt.tprintf("Commit feedback: %v", state.failure), true,
			{surface = .Status, subject = .Failure, destructive = true},
		)
	}
	if state.commit_draft_length == 0 {
		_ = ksawery_status_append_label(rows, storage, &write, 0xC100_0000_0000_0010, "Subject:", false)
	} else {
		draft := state.commit_draft[:state.commit_draft_length]
		subject_end := 0
		for subject_end < len(draft) && draft[subject_end] != '\n' do subject_end += 1
		_ = ksawery_status_append_label(rows, storage, &write, 0xC100_0000_0000_0010, "Subject:", false)
		ksawery_status_append_process_text(rows, storage, &write, draft[:subject_end], 0xC100_0000_0000_0100)
		if subject_end < len(draft) && write < len(rows) {
			_ = ksawery_status_append_label(rows, storage, &write, 0xC100_0000_0000_0011, "Body:", true)
			ksawery_status_append_process_text(rows, storage, &write, draft[subject_end + 1:], 0xC100_0000_0000_0200)
		}
	}
	ksawery_status_append_process_text(rows, storage, &write, commit_output, 0xC100_0000_0000_1000)
	ksawery_status_append_process_text(rows, storage, &write, commit_diagnostic, 0xC100_0000_0000_2000)
	definitions = rows[:write]
	current_item := i32(-1)
	for definition, index in definitions {
		if !definition.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_amend_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	message, message_available := ksawery.commit_message_text(&state.amend_confirmation.message)
	subject, subject_available := ksawery.commit_target_subject_text(&state.amend_confirmation.target.subject)
	if !message_available || !subject_available do return nil, nil, false
	count := min(14 + len(message), int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xC200_0000_0000_0001, "Ksawery Amend Confirmation", true,
		{surface = .Status, subject = .Section},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC200_0000_0000_0002,
		"This replaces the observed repository HEAD with a newly created commit.", true,
		{surface = .Status, subject = .Failure, destructive = true},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC200_0000_0000_0003,
		fmt.tprintf("Observed HEAD: %s", ksawery.revision_identity_string(&state.amend_confirmation.target.observation.revision)), true,
		{surface = .Status, subject = .Revision, current = true, head = true},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC200_0000_0000_0004,
		fmt.tprintf("Observed subject: %s", string(subject)), true,
		{surface = .Status, subject = .Revision},
	) && ksawery_status_append_label(
		rows, storage, &write, 0xC200_0000_0000_0005,
		"C-Enter confirms this exact amend; C-g returns to the retained draft.", false,
	) && ksawery_status_append_label(
		rows, storage, &write, 0xC200_0000_0000_0006,
		"Publication safety is not inferred; remotes and refs are outside this operation.", true,
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC200_0000_0000_0007,
			fmt.tprintf("Amend feedback: %v", state.failure), true,
			{surface = .Status, subject = .Failure, destructive = true},
		)
	}
	_ = ksawery_status_append_label(rows, storage, &write, 0xC200_0000_0000_0010, "Replacement subject:", true)
	subject_end := 0
	for subject_end < len(message) && message[subject_end] != '\n' do subject_end += 1
	ksawery_status_append_process_text(rows, storage, &write, message[:subject_end], 0xC200_0000_0000_0100)
	if subject_end < len(message) && write < len(rows) {
		_ = ksawery_status_append_label(rows, storage, &write, 0xC200_0000_0000_0011, "Replacement body:", true)
		ksawery_status_append_process_text(rows, storage, &write, message[subject_end + 1:], 0xC200_0000_0000_0200)
	}
	definitions = rows[:write]
	current_item := i32(-1)
	for definition, index in definitions {
		if !definition.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_push_confirmation_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil ||
	   !ksawery.push_precondition_is_valid(state.push_precondition) {
		return nil, nil, false
	}
	rows, rows_error := make([]ui.List_Item_Definition, 10, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, len(rows) * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	precondition := state.push_precondition
	source_name := ksawery.ref_name_string(&precondition.source.name)
	source_object := ksawery.revision_identity_string(&precondition.source.object)
	remote_name := ksawery.remote_name_string(&precondition.destination.remote.name)
	destination_name := ksawery.ref_name_string(&precondition.destination.branch)
	write := 0
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xD200_0000_0000_0001, "Ksawery Push Confirmation", true,
		{surface = .Refs, subject = .Section},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xD200_0000_0000_0002,
		fmt.tprintf("Source: %s %s", source_name, source_object), true,
		{surface = .Refs, subject = .Branch, current = true},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xD200_0000_0000_0003,
		fmt.tprintf("Remote: %s", remote_name), true,
		{surface = .Refs, subject = .Remote},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xD200_0000_0000_0004,
		fmt.tprintf("Destination: %s", destination_name), true,
		{surface = .Refs, subject = .Branch},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xD200_0000_0000_0005,
		"This publishes exactly one tracked branch without force or deletion.", true,
		{surface = .Refs, subject = .Failure, destructive = true},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xD200_0000_0000_0006,
		"Remote policy and receiver state remain Git authority.", true,
		{surface = .Refs, subject = .Failure, destructive = true},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xD200_0000_0000_0007,
		"C-Enter confirms this exact push; C-g cancels.", false,
		{surface = .Refs, subject = .Operation},
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xD200_0000_0000_0008,
			fmt.tprintf("Push feedback: %v", state.failure), true,
			{surface = .Refs, subject = .Failure, destructive = true},
		)
	}
	definitions = rows[:write]
	current_item := i32(-1)
	for definition, index in definitions {
		if !definition.passive {
			current_item = i32(index)
			break
		}
	}
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_sequence_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil || state.sequence.state == nil {
		return nil, nil, false
	}
	descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	if !described do return nil, nil, false
	sequence_observation := ksawery.Extension_Annotation_Observation {
		family = .Sequence,
		repository = descriptor.repository,
		generation = u64(descriptor.generation),
	}
	conflict_observation := sequence_observation
	conflict_observation.family = .Conflict
	sequence_annotation_generation := ksawery_extension_annotation_generation(
		&state.extension_registry, .Sequence,
	)
	conflict_annotation_generation := ksawery_extension_annotation_generation(
		&state.extension_registry, .Conflict,
	)
	annotation_rows := ksawery_extension_annotation_visible_row_count(
		sequence_annotation_generation, sequence_observation,
	) + ksawery_extension_annotation_visible_row_count(
		conflict_annotation_generation, conflict_observation,
	)
	count := min(int(descriptor.conflict_count) + annotation_rows + 12, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	current_item := i32(-1)
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xC100_0000_0000_0001, "Ksawery Sequence", true,
		{surface = .Sequence, subject = .Section},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC100_0000_0000_0002,
		fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)), true,
		{surface = .Sequence, subject = .Repository},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC100_0000_0000_0003,
		fmt.tprintf("Operation: %v [%v, %v]", descriptor.kind, descriptor.state, descriptor.origin), true,
		{surface = .Sequence, subject = .Operation, destructive = descriptor.state == .Unsupported},
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if descriptor.step != {} {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC100_0000_0000_0004,
			fmt.tprintf("Step: %d of %d", descriptor.step.position, descriptor.step.total), true,
			{surface = .Sequence, subject = .Step},
		)
	}
	if descriptor.current != {} {
		current := descriptor.current
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC100_0000_0000_0005,
			fmt.tprintf("Current: %s", ksawery.revision_identity_string(&current)), true,
			{surface = .Sequence, subject = .Revision},
		)
	}
	if descriptor.target != {} {
		target := descriptor.target
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC100_0000_0000_0006,
			fmt.tprintf("Target: %s", ksawery.revision_identity_string(&target)), true,
			{surface = .Sequence, subject = .Revision},
		)
	}
	sequence_target := ksawery.Sequence_Target {
		generation = descriptor.generation,
		fingerprint = descriptor.fingerprint,
	}
	if annotation_target, annotation_target_ready := ksawery.extension_annotation_target_from_sequence(
		sequence_observation, sequence_target,
	); annotation_target_ready {
		annotation_current, _ := ksawery_extension_annotation_append_target(
			rows, storage, &write, sequence_annotation_generation, sequence_observation,
			annotation_target, state.extension_annotation_selection,
		)
		if annotation_current >= 0 do current_item = annotation_current
	}
	if descriptor.state == .Truncated {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC100_0000_0000_0007,
			fmt.tprintf("Conflicts: %d of %d retained", descriptor.conflict_count, descriptor.observed_conflicts), true,
			{surface = .Sequence, subject = .Failure, destructive = true},
		)
	}
	for index in 0 ..< descriptor.conflict_count {
		conflict, found := ksawery.sequence_observation_conflict(&state.sequence, index)
		if !found do break
		path, copied := ksawery.sequence_observation_conflict_path(&state.sequence, conflict)
		if !copied do break
		current := conflict.id == state.conflict_selection
		row := write
		if !ksawery_append_presented_label(
			rows, storage, &write, ui.List_Item_ID(0xC200_0000_0000_0000 | u64(conflict.id)),
			fmt.tprintf("Conflict: %s [%v]", path, conflict.kind), false,
			{surface = .Sequence, subject = .Conflict, current = current},
		) {
			break
		}
		if current do current_item = i32(row)
		annotation_target, annotation_target_ready := ksawery.extension_annotation_target_from_conflict(
			conflict_observation,
			{sequence = sequence_target, conflict = conflict.id},
		)
		if annotation_target_ready {
			annotation_current, _ := ksawery_extension_annotation_append_target(
				rows, storage, &write, conflict_annotation_generation, conflict_observation,
				annotation_target, state.extension_annotation_selection,
			)
			if annotation_current >= 0 do current_item = annotation_current
		}
	}
	actions := "Enter inspect conflict; g refresh; q return"
	if descriptor.kind == .Merge {
		actions = "Enter inspect conflict; > continue merge; X abort merge; g refresh; q return"
	} else if descriptor.kind == .Rebase {
		actions = "Enter inspect conflict; ] continue; ; skip; Z abort rebase; g refresh; q return"
	} else if descriptor.kind == .Cherry_Pick {
		actions = "Enter inspect conflict; { continue; l skip; Y abort cherry-pick; g refresh; q return"
	} else if descriptor.kind == .Revert {
		actions = "Enter inspect conflict; } continue; j skip; Q abort revert; g refresh; q return"
	} else if descriptor.kind == .Bisect {
		actions = "G good; B bad; | skip; ~ reset; g refresh; $ processes; q return"
		if ksawery.bisect_progress_is_valid(state.bisect_progress) {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC100_0000_0000_0009,
				fmt.tprintf("Manual progress: %d classified; %d skipped; %d remaining", state.bisect_progress.classifications, state.bisect_progress.skipped, state.bisect_progress.remaining), true,
				{surface = .Sequence, subject = .Step},
			)
		}
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xC100_0000_0000_0008,
		actions, descriptor.conflict_count > 0,
		{surface = .Sequence, subject = .Operation},
	)
	if current_item < 0 && descriptor.conflict_count == 0 do current_item = i32(write - 1)
	definitions = rows[:write]
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_conflict_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil || state.sequence.state == nil ||
	   state.conflict_selection == ksawery.Conflict_ID(0) {
		return nil, nil, false
	}
	conflict, found := ksawery.sequence_observation_conflict(
		&state.sequence,
		u32(state.conflict_selection) - 1,
	)
	if !found do return nil, nil, false
	path, copied := ksawery.sequence_observation_conflict_path(&state.sequence, conflict)
	if !copied do return nil, nil, false
	descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
	if !described do return nil, nil, false
	annotation_observation := ksawery.Extension_Annotation_Observation {
		family = .Conflict,
		repository = descriptor.repository,
		generation = u64(descriptor.generation),
	}
	annotation_generation := ksawery_extension_annotation_generation(
		&state.extension_registry, .Conflict,
	)
	annotation_rows := ksawery_extension_annotation_visible_row_count(
		annotation_generation, annotation_observation,
	)
	row_capacity := min(15 + annotation_rows, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, row_capacity, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, row_capacity * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xC300_0000_0000_0001, "Ksawery Conflict", true,
		{surface = .Conflict, subject = .Section},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC300_0000_0000_0002, fmt.tprintf("Path: %s", path), true,
		{surface = .Conflict, subject = .Conflict},
	) && ksawery_append_presented_label(
		rows, storage, &write, 0xC300_0000_0000_0003,
		fmt.tprintf("Conflict kind: %v (%c%c)", conflict.kind, conflict.index, conflict.worktree), true,
		{surface = .Conflict, subject = .Conflict},
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	side_labels := [3]string{"Base (common ancestor)", "Current (ours / HEAD)", "Applied (theirs / incoming)"}
	for stage, index in conflict.stages {
		label := fmt.tprintf("%s: unavailable", side_labels[index])
		if stage.available {
			object := stage.object
			label = fmt.tprintf(
				"%s: %s mode %06o",
				side_labels[index],
				ksawery.revision_identity_string(&object),
				stage.mode,
			)
		}
		_ = ksawery_append_presented_label(
			rows, storage, &write, ui.List_Item_ID(0xC300_0000_0000_0010 + u64(index)), label, true,
			{surface = .Conflict, subject = .Stage},
		)
	}
	current_item := i32(-1)
	sequence_target := ksawery.Sequence_Target {
		generation = descriptor.generation,
		fingerprint = descriptor.fingerprint,
	}
	annotation_target, annotation_target_ready := ksawery.extension_annotation_target_from_conflict(
		annotation_observation,
		{sequence = sequence_target, conflict = conflict.id},
	)
	if annotation_target_ready {
		annotation_current, _ := ksawery_extension_annotation_append_target(
			rows, storage, &write, annotation_generation, annotation_observation,
			annotation_target, state.extension_annotation_selection,
		)
		if annotation_current >= 0 do current_item = annotation_current
	}
	assistance, assistance_available := ksawery_conflict_assistance_workflow_inspect(
		state.conflict_assistance,
	)
	if assistance_available &&
	   state.conflict_assistance.evaluation.request.target.conflict ==
		{sequence = sequence_target, conflict = conflict.id} {
		label_copy := assistance.label
		provider_label := string(label_copy.bytes[:label_copy.length])
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xC300_0000_0000_0020,
			fmt.tprintf("Assistance: %s", provider_label), true,
			{surface = .Conflict, subject = .Operation},
		)
		if assistance.response == .Guidance {
			guidance_copy := assistance.guidance
			guidance := string(guidance_copy.bytes[:guidance_copy.length])
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC300_0000_0000_0021,
				fmt.tprintf("Guidance: %s", guidance), true,
				{surface = .Conflict, subject = .Operation},
			)
		} else if assistance.tool_available {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC300_0000_0000_0022,
				"External tool proposal available; press H to run it through Process", true,
				{surface = .Conflict, subject = .Operation},
			)
		} else if assistance.fallback {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC300_0000_0000_0023,
				"Built-in fallback: core conflict actions remain available", true,
				{surface = .Conflict, subject = .Operation},
			)
		}
	}
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xC300_0000_0000_0004,
		"H asks helper; Enter visits result; x marks saved result; 1/2/3 choose a complete side; K deletes; q returns", false,
		{surface = .Conflict, subject = .Operation},
	)
	if current_item < 0 do current_item = i32(write - 1)
	definitions = rows[:write]
	state.position = {
		presentation_generation = 1,
		selection_owner = .View,
		current_item = current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}

@(private)
ksawery_status_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || viewport_items == 0 || allocator.procedure == nil do return nil, nil, false
	state.extension_status = ksawery_extension_status_generation(&state.extension_registry)
	path_count: u32
	if state.observation.state != nil {
		path_count, _ = ksawery.status_observation_path_count(&state.observation)
	}
	status_descriptor: ksawery.Observation_Descriptor
	status_described := false
	if state.observation.state != nil {
		status_descriptor, status_described = ksawery.status_observation_descriptor(&state.observation)
	}
	annotation_observation := ksawery.Extension_Annotation_Observation {
		family = .Status,
		repository = status_descriptor.repository,
		generation = u64(status_descriptor.generation),
	}
	annotation_generation := ksawery_extension_annotation_generation(
		&state.extension_registry, .Status,
	)
	annotation_rows := ksawery_extension_annotation_visible_row_count(
		annotation_generation, annotation_observation,
	)
	extension_status_values: [1]ksawery.Extension_Status_Generation
	extension_status_generations: []ksawery.Extension_Status_Generation
	if status_described && state.extension_status != nil {
		extension_status_values[0] = state.extension_status^
		extension_status_generations = extension_status_values[:]
	}
	extension_status_rows := ksawery_extension_status_visible_row_count(
		extension_status_generations,
		status_descriptor,
	)
	detail_content: []u8
	if state.detail.state != nil && ksawery.path_detail_is_current(&state.detail, &state.observation) {
		detail_content, _ = ksawery.path_detail_content(&state.detail)
	}
	action_output, action_diagnostic: []u8
	if state.action.state != nil {
		action_output, action_diagnostic, _ = ksawery.index_action_result_output(&state.action)
	} else if state.partial_action.state != nil {
		action_output, action_diagnostic, _ = ksawery.partial_index_action_result_output(&state.partial_action)
	} else if state.grouped_action.state != nil {
		action_output, action_diagnostic, _ = ksawery.grouped_index_action_result_output(&state.grouped_action)
	} else if state.discard_action.state != nil {
		action_output, action_diagnostic, _ = ksawery.discard_action_result_output(&state.discard_action)
	}
	count := min(
		int(path_count) + 16 + len(detail_content) + len(action_output) + len(action_diagnostic) +
			extension_status_rows + annotation_rows,
		int(ui.MAX_LIST_ITEMS),
	)
	allocation_error: runtime.Allocator_Error
	rows: []ui.List_Item_Definition
	rows, allocation_error = make([]ui.List_Item_Definition, count, allocator)
	if allocation_error != nil do return nil, nil, false
	storage: []u8
	storage, allocation_error = make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if allocation_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	if !ksawery_append_presented_label(
		rows, storage, &write, ui.List_Item_ID(1), "Ksawery Status", true,
		{surface = .Status, subject = .Section},
	) || !ksawery_append_presented_label(
		rows, storage, &write, ui.List_Item_ID(2), fmt.tprintf("Repository: %s", ksawery.repository_context_string(&state.repository)), true,
		{surface = .Status, subject = .Repository},
	) {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	if state.raw_result.outcome != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, 0xCC00_0000_0000_0001,
			fmt.tprintf(
				"Raw command: %v; stdout %d bytes; diagnostics omitted; full refresh %v",
				state.raw_result.outcome,
				state.raw_result.output_bytes,
				state.raw_result.refresh_completed,
			),
			true,
			{surface = .Status, subject = .Operation, destructive = state.raw_result.outcome != .Verified_Success},
		)
	}
	process_storage: [KSAWERY_LIST_ROW_BYTES]u8
	process_feedback, process_role, _, process_present :=
		ksawery_workflow_compact_process_feedback(state, process_storage[:])
	if process_present {
		process_row := write
		if ksawery_append_presented_label(
			rows, storage, &write, 0xCC00_0000_0000_0003,
			process_feedback, true,
			{surface = .Status, subject = .Operation, destructive = process_role == .Diagnostic_Rejected},
		) {
			rows[process_row].emphasis_style = process_role
		}
	}
	if state.failure != .None {
		_ = ksawery_append_presented_label(
			rows, storage, &write, ui.List_Item_ID(3), fmt.tprintf("Status observation failed: %v", state.failure), false,
			{surface = .Status, subject = .Failure, destructive = true},
		)
	} else if state.observation.state == nil {
		_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(3), "Observing repository status...", false)
	} else {
		descriptor, described := ksawery.status_observation_descriptor(&state.observation)
		if described do _ = ksawery_append_presented_label(
			rows, storage, &write, ui.List_Item_ID(3), fmt.tprintf("Branch: %s", string(descriptor.branch.bytes[:descriptor.branch.length])), true,
			{surface = .Status, subject = .Branch},
		)
		if state.pending == .Sequence_Observe {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC000_0000_0000_0001,
				"Sequence: observing current Git operation...", true,
				{surface = .Status, subject = .Operation},
			)
		} else if state.sequence_failure != .None {
			_ = ksawery_append_presented_label(
				rows, storage, &write, 0xC000_0000_0000_0002,
				fmt.tprintf("Sequence observation failed: %v", state.sequence_failure), true,
				{surface = .Status, subject = .Failure, destructive = true},
			)
		} else if state.sequence.state != nil {
			sequence, sequence_described := ksawery.sequence_observation_descriptor(&state.sequence)
			if sequence_described && sequence.state != .Inactive {
				step := ""
				if sequence.step != {} do step = fmt.tprintf(" step %d/%d", sequence.step.position, sequence.step.total)
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xC000_0000_0000_0003,
					fmt.tprintf(
						"Sequence: %v%s, %d conflicts [%v]",
						sequence.kind,
						step,
						sequence.observed_conflicts,
						sequence.origin,
					),
					true,
					{surface = .Status, subject = .Operation, destructive = sequence.state == .Unsupported},
				)
				_ = ksawery_append_presented_label(
					rows, storage, &write, 0xC000_0000_0000_0004,
					"Action: o inspect active sequence", true,
					{surface = .Status, subject = .Operation},
				)
			}
		}
		if state.pending == .Index_Action || state.pending == .Partial_Index_Action ||
		   state.pending == .Grouped_Index_Action || state.pending == .Discard_Action {
			label := "Applying selected path action..."
			if state.pending == .Partial_Index_Action do label = "Applying selected hunk action..."
			if state.pending == .Grouped_Index_Action do label = "Applying marked repository targets..."
			if state.pending == .Discard_Action do label = "Discarding selected working-tree path..."
			_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(4), label, true)
		} else if state.action.state != nil {
			action_descriptor, action_described := ksawery.index_action_result_descriptor(&state.action)
			if action_described {
				label := fmt.tprintf("Index action %v failed: %v", action_descriptor.action, action_descriptor.failure)
				if action_descriptor.succeeded do label = fmt.tprintf("Index action %v completed", action_descriptor.action)
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(4), label, true)
				ksawery_status_append_process_text(rows, storage, &write, action_output, 0xD000_0000_0000_0000)
				ksawery_status_append_process_text(rows, storage, &write, action_diagnostic, 0xE000_0000_0000_0000)
			}
		} else if state.partial_action.state != nil {
			action_descriptor, action_described := ksawery.partial_index_action_result_descriptor(&state.partial_action)
			if action_described {
				label := fmt.tprintf("Hunk action %v failed: %v", action_descriptor.request.action, action_descriptor.failure)
				if action_descriptor.succeeded {
					label = fmt.tprintf("Hunk action %v completed", action_descriptor.request.action)
				}
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(4), label, true)
				ksawery_status_append_process_text(rows, storage, &write, action_output, 0xD000_0000_0000_0000)
				ksawery_status_append_process_text(rows, storage, &write, action_diagnostic, 0xE000_0000_0000_0000)
			}
		} else if state.grouped_action.state != nil {
			action_descriptor, action_described := ksawery.grouped_index_action_result_descriptor(&state.grouped_action)
			if action_described {
				label := fmt.tprintf(
					"Grouped action %v failed: %v",
					action_descriptor.request.selection.action,
					action_descriptor.failure,
				)
				if action_descriptor.succeeded {
					label = fmt.tprintf(
						"Grouped action %v completed",
						action_descriptor.request.selection.action,
					)
				}
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(4), label, true)
				ksawery_status_append_process_text(rows, storage, &write, action_output, 0xD000_0000_0000_0000)
				ksawery_status_append_process_text(rows, storage, &write, action_diagnostic, 0xE000_0000_0000_0000)
			}
		} else if state.discard_action.state != nil {
			action_descriptor, action_described := ksawery.discard_action_result_descriptor(&state.discard_action)
			if action_described {
				label := fmt.tprintf("Discard failed: %v", action_descriptor.failure)
				if action_descriptor.succeeded do label = "Discard completed"
				if action_descriptor.failure == .Cancelled do label = "Discard cancelled"
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(4), label, true)
				ksawery_status_append_process_text(rows, storage, &write, action_output, 0xD000_0000_0000_0000)
				ksawery_status_append_process_text(rows, storage, &write, action_diagnostic, 0xE000_0000_0000_0000)
			}
		}
		grouped_descriptor, grouped_described := ksawery.grouped_selection_descriptor(&state.grouped)
		if grouped_described && grouped_descriptor.targets > 0 {
			granularity := "paths"
			if grouped_descriptor.granularity == .Diff_Units do granularity = "hunks"
			_ = ksawery_status_append_label(
				rows,
				storage,
				&write,
				ui.List_Item_ID(8),
				fmt.tprintf(
					"Marked: %d %s for %v; x target actions; * add; - remove; 0 clear",
					grouped_descriptor.targets,
					granularity,
					grouped_descriptor.action,
				),
				true,
			)
		}
		groups := [?]ksawery.Change_Group{
			ksawery.Change_Group.Unmerged,
			ksawery.Change_Group.Untracked,
			ksawery.Change_Group.Unstaged,
			ksawery.Change_Group.Staged,
		}
		for group in groups {
			group_count := ksawery_status_group_count(&state.observation, group)
			if group_count == 0 do continue
			group_item := ksawery.Status_Item_ID{kind = .Group, group = group}
			group_row := write
			if !ksawery_status_append_label(rows, storage, &write, ksawery_status_ui_item_id(group_item), fmt.tprintf("%s (%d)", ksawery_status_group_label(group), group_count), false) do break
			for path_index in 0 ..< int(path_count) {
				path, found := ksawery.status_observation_path(&state.observation, u32(path_index))
				if !found || path.group != group do continue
				path_text, copied := ksawery.status_observation_path_text(&state.observation, path)
				path_item := ksawery.Status_Item_ID{kind = .Path, group = group, path = path.id}
				path_row := write
				row_selection := state.selection
				row_selection.current = path_item
				marked := ksawery.grouped_selection_contains_current(
					&state.observation,
					nil,
					row_selection,
					&state.grouped,
				)
				prefix := "  "
				if marked do prefix = "* "
				if !copied || !ksawery_status_append_label(rows, storage, &write, ksawery_status_ui_item_id(path_item), fmt.tprintf("%s%s", prefix, string(path_text)), false) do break
				if state.selection.current == path_item do state.position.current_item = i32(path_row)
				annotation_target, annotation_target_ready := ksawery.extension_annotation_target_from_path(
					annotation_observation,
					{generation = status_descriptor.generation, path = path.id},
				)
				if annotation_target_ready {
					annotation_current, _ := ksawery_extension_annotation_append_target(
						rows, storage, &write, annotation_generation, annotation_observation,
						annotation_target, state.extension_annotation_selection,
					)
					if annotation_current >= 0 do state.position.current_item = annotation_current
				}
				if state.selection.expanded.path == path.id && len(detail_content) > 0 {
					if state.diff.state != nil && ksawery.diff_document_is_current(&state.diff, &state.observation) {
						ksawery_status_append_diff_document(
							rows, storage, &write, state, annotation_generation,
							annotation_observation,
						)
					} else {
						ksawery_status_append_detail(rows, storage, &write, path.id, detail_content)
					}
					detail_descriptor, detail_described := ksawery.path_detail_descriptor(&state.detail)
					if detail_described && detail_descriptor.truncated {
						_ = ksawery_status_append_label(
							rows, storage, &write,
							ui.List_Item_ID(0xF000_0000_0000_0000 | u64(path.id)),
							"    [detail truncated at configured limit]", true,
						)
					} else if state.diff_failure != .None {
						_ = ksawery_status_append_label(
							rows, storage, &write,
							ui.List_Item_ID(0xF100_0000_0000_0000 | u64(path.id)),
							fmt.tprintf("    [partial selection unavailable: %v]", state.diff_failure),
							true,
						)
					}
				}
			}
			if state.selection.current == group_item do state.position.current_item = i32(group_row)
		}
		if path_count == 0 {
			_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(6), "Working tree clean", false)
		}
		if extension_status_rows > 0 && len(rows) - write >= extension_status_rows {
			extension_current, _ := ksawery_extension_status_append(
				rows,
				storage,
				&write,
				extension_status_generations,
				status_descriptor,
				state.extension_status_selection,
			)
			if extension_current >= 0 do state.position.current_item = extension_current
		}
		_ = ksawery_status_append_label(
			rows, storage, &write, ui.List_Item_ID(11),
			"Action: $ inspect repository processes", true,
		)
		if state.process.state == nil && !ksawery_workflow_sequence_is_active(state) {
			_ = ksawery_status_append_label(
				rows, storage, &write, ui.List_Item_ID(12),
				"Commands: ? index; g refresh; d diff; r rebase; m merge; M remote; C clone; x target actions",
				true,
			)
			_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(7), "Action: h browse repository history", true)
			_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(10), "Action: b browse repository refs", true)
			if ksawery_status_group_count(&state.observation, .Staged) > 0 &&
			   ksawery_status_group_count(&state.observation, .Unmerged) == 0 {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(9), "Action: c compose a normal commit from the checked index", true)
			}
			document := &state.diff if state.diff.state != nil else nil
			if ksawery.grouped_selection_action_available(&state.grouped, .Stage) {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(5), "Action: s stage marked targets", true)
			} else if ksawery.grouped_selection_action_available(&state.grouped, .Unstage) {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(5), "Action: u unstage marked targets", true)
			} else if document != nil && ksawery.partial_index_action_available(&state.observation, document, state.selection, .Stage) {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(5), "Action: s stage selected hunk", true)
			} else if document != nil && ksawery.partial_index_action_available(&state.observation, document, state.selection, .Unstage) {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(5), "Action: u unstage selected hunk", true)
			} else if ksawery.discard_action_available(&state.observation, state.selection) {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(5), "Action: s stage or x d discard selected path", true)
			} else if ksawery.index_action_available(&state.observation, state.selection, .Stage) {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(5), "Action: s stage selected path", true)
			} else if ksawery.index_action_available(&state.observation, state.selection, .Unstage) {
				_ = ksawery_status_append_label(rows, storage, &write, ui.List_Item_ID(5), "Action: u unstage selected path", true)
			}
		}
	}
	definitions = rows[:write]
	current_item := i32(-1)
	if (state.selection.current.kind != .Invalid || state.extension_status_selection.valid ||
	    state.extension_annotation_selection.valid) &&
	   state.position.current_item >= 0 && state.position.current_item < i32(write) {
		current_item = state.position.current_item
		if definitions[int(current_item)].passive do current_item = -1
	}
	if current_item < 0 {
		for row, index in definitions {
			if !row.passive {
				current_item = i32(index)
				_ = ksawery_workflow_select_ui_item(state, row.id)
				break
			}
		}
	}
	state.position = {presentation_generation = 1, selection_owner = .View, current_item = current_item, first_visible_item = 0, viewport_items = min(viewport_items, u32(write))}
	return definitions, storage, true
}

@(private)
ksawery_status_append_diff_document :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	state: ^Ksawery_Workflow_State,
	annotation_generation: ^ksawery.Extension_Annotation_Generation,
	annotation_observation: ksawery.Extension_Annotation_Observation,
) {
	if state == nil || state.diff.state == nil do return
	presentation, available := ksawery.diff_document_presentation(&state.diff)
	descriptor, described := ksawery.diff_document_descriptor(&state.diff)
	if !available || !described do return
	for unit_index in 0 ..< descriptor.unit_count {
		unit, found := ksawery.diff_document_unit(&state.diff, unit_index)
		if !found do return
		start := int(unit.presentation.offset)
		end := start + int(unit.presentation.length)
		if start < 0 || end < start || end > len(presentation) do return
		content := presentation[start:end]
		item := ksawery.Status_Item_ID {
			kind = .Diff_Unit,
			group = ksawery_status_diff_group(unit.target.layer),
			path = unit.target.path.path,
			source = unit.target.source,
			unit = unit.target.unit,
		}
		if item.group == .Invalid do return
		offset := 0
		line_index: u64
		for offset < len(content) && write^ < len(rows) {
			line_end := offset
			limit := min(len(content), offset + KSAWERY_LIST_ROW_BYTES - 4)
			for line_end < limit && content[line_end] != '\n' do line_end += 1
			selectable := line_index == 0
			prefix := "    "
			if selectable {
				row_selection := state.selection
				row_selection.current = item
				if ksawery.grouped_selection_contains_current(
					&state.observation,
					&state.diff,
					row_selection,
					&state.grouped,
				) {
					prefix = "  * "
				}
			}
			label := fmt.tprintf("%s%s", prefix, string(content[offset:line_end]))
			id := ksawery_status_ui_item_id(item)
			if !selectable {
				id = ui.List_Item_ID(0xA000_0000_0000_0000 | u64(write^ + 1))
			}
			row := write^
			if !ksawery_status_append_label(rows, storage, write, id, label, !selectable) do return
			if selectable && state.selection.current == item do state.position.current_item = i32(row)
			line_index += 1
			offset = line_end + 1 if line_end < len(content) && content[line_end] == '\n' else line_end
		}
		annotation_target, annotation_target_ready := ksawery.extension_annotation_target_from_diff_unit(
			annotation_observation, unit.target,
		)
		if annotation_target_ready {
			annotation_current, _ := ksawery_extension_annotation_append_target(
				rows, storage, write, annotation_generation, annotation_observation,
				annotation_target, state.extension_annotation_selection,
			)
			if annotation_current >= 0 do state.position.current_item = annotation_current
		}
	}
}

@(private)
ksawery_status_append_process_text :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	content: []u8,
	id_base: u64,
) {
	offset := 0
	row: u64
	for offset < len(content) && write^ < len(rows) {
		end := offset
		limit := min(len(content), offset + KSAWERY_LIST_ROW_BYTES - 4)
		for end < limit && content[end] != '\n' do end += 1
		label := fmt.tprintf("    %s", string(content[offset:end]))
		if !ksawery_status_append_label(rows, storage, write, ui.List_Item_ID(id_base | row + 1), label, true) {
			return
		}
		row += 1
		offset = end + 1 if end < len(content) && content[end] == '\n' else end
	}
}

@(private)
ksawery_status_append_detail :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	path: ksawery.Path_ID,
	content: []u8,
) {
	offset := 0
	row: u64
	for offset < len(content) && write^ < len(rows) {
		end := offset
		limit := min(len(content), offset + KSAWERY_LIST_ROW_BYTES - 4)
		for end < limit && content[end] != '\n' do end += 1
		label := fmt.tprintf("    %s", string(content[offset:end]))
		id := ui.List_Item_ID(0x8000_0000_0000_0000 | (u64(path) << 32) | row + 1)
		if !ksawery_status_append_label(rows, storage, write, id, label, true) do return
		row += 1
		if end < len(content) && content[end] == '\n' {
			offset = end + 1
		} else {
			offset = end
		}
	}
}

@(private)
ksawery_status_append_label :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	id: ui.List_Item_ID,
	label: string,
	passive: bool,
) -> bool {
	return ksawery_append_presented_label(
		rows, storage, write, id, label, passive,
		{surface = .Status, subject = .Path},
	)
}

@(private)
ksawery_append_presented_label :: proc(
	rows: []ui.List_Item_Definition,
	storage: []u8,
	write: ^int,
	id: ui.List_Item_ID,
	label: string,
	passive: bool,
	presentation: ksawery.Presentation_State,
) -> bool {
	if write == nil || write^ >= len(rows) || len(label) > KSAWERY_LIST_ROW_BYTES do return false
	role, composed := ksawery.presentation_role_compose(presentation)
	if !composed do return false
	offset := write^ * KSAWERY_LIST_ROW_BYTES
	copy(storage[offset:offset + len(label)], transmute([]u8)label)
	if id == ui.List_Item_ID(0) do return false
	rows[write^] = {
		id = id,
		text = string(storage[offset:offset + len(label)]),
		passive = passive,
		emphasis_bytes = u32(len(label)),
		emphasis_style = ksawery_presentation_style_role(role),
	}
	if !passive {
		rows[write^].action = {
			owner_id = KSAWERY_UI_OWNER_ID,
			action_id = KSAWERY_LIST_SELECT_ACTION,
			generation = KSAWERY_UI_TARGET_GENERATION,
		}
	}
	write^ += 1
	return true
}

@(private)
ksawery_presentation_style_role :: proc(role: ksawery.Presentation_Role) -> ui.Style_Role {
	switch role.emphasis {
	case .Current: return .List_Current
	case .Marked: return .List_Mark_Save
	case .Head: return .List_Emphasis
	case .Destructive: return .Diagnostic_Rejected
	case .None:
	}
	switch role.subject {
	case .Repository, .Remote: return .Status_Project
	case .Branch: return .Status_Identity
	case .Tag: return .List_Normal
	case .Tracking: return .Filesystem_Metadata
	case .Section: return .List_Emphasis
	case .Parent: return .Filesystem_Metadata
	case .Operation: return .Status_Alert
	case .Step, .Stage: return .Filesystem_Metadata
	case .Conflict: return .Status_Alert
	case .Failure: return .Diagnostic_Rejected
	case .Path, .Revision: return .List_Normal
	case .Invalid: return .List_Normal
	}
	return .List_Normal
}

@(private)
ksawery_status_ui_item_id :: proc(item: ksawery.Status_Item_ID) -> ui.List_Item_ID {
	if item.kind == .Group do return ui.List_Item_ID(u64(item.group) << 32)
	if item.kind == .Path do return ui.List_Item_ID((u64(item.group) << 32) | u64(item.path))
	if item.kind == .Diff_Unit {
		return ui.List_Item_ID(
			0x9000_0000_0000_0000 | (u64(item.path) << 16) | u64(item.unit),
		)
	}
	return ui.List_Item_ID(0)
}

@(private)
ksawery_workflow_select_ui_item :: proc(state: ^Ksawery_Workflow_State, id: ui.List_Item_ID) -> bool {
	if state == nil || id == ui.List_Item_ID(0) {
		return false
	}
	if state.view_mode == .Extension_Command && state.extension_command_family != nil {
		for index in 0 ..< len(state.extension_command_family.family.arguments) {
			if id == ui.List_Item_ID(0xCC00_0000_0000_0100 + u64(index)) {
				state.extension_command_cursor = u16(index)
				return true
			}
		}
		if id == ui.List_Item_ID(0xCC00_0000_0000_FF00) {
			state.extension_command_cursor = u16(len(state.extension_command_family.family.arguments))
			return true
		}
		return false
	}
	if generation, observation, ready := ksawery_extension_annotation_active_context(state); ready {
		if ksawery_extension_annotation_select_ui_item(
			generation, observation, id, &state.extension_annotation_selection,
		) {
			state.extension_status_selection = {}
			return true
		}
	}
	if state.view_mode == .Process {
		records := ksawery_workflow_process_records(state)
		surface, available := ksawery.process_surface_descriptor(records)
		if !available do return false
		for ordinal in 0 ..< surface.row_count {
			if ksawery_process_ui_item_id(ordinal) != id do continue
			row, projected, _ := ksawery.process_surface_row(records, ordinal)
			if !projected do return false
			state.process_selection.current = row.id
			state.process_failure = .None
			state.extension_annotation_selection = {}
			return true
		}
		return false
	}
	if state.view_mode == .History && state.history.state != nil {
		count, available := ksawery.history_hierarchy_item_count(&state.history)
		if !available do return false
		for ordinal in 0 ..< count {
			if ksawery_history_ui_item_id(ordinal) != id do continue
			item, found := ksawery.history_hierarchy_item(&state.history, ordinal)
			if !found do return false
			state.history_selection.current = item
			state.extension_annotation_selection = {}
			return true
		}
		return false
	}
	if state.view_mode == .Refs && state.refs.state != nil {
		count, available := ksawery.ref_hierarchy_item_count(&state.refs)
		if !available do return false
		for ordinal in 0 ..< count {
			if ksawery_refs_ui_item_id(ordinal) != id do continue
			item, found := ksawery.ref_hierarchy_item(&state.refs, ordinal)
			if !found do return false
			state.ref_selection.current = item
			state.extension_annotation_selection = {}
			return true
		}
		return false
	}
	if state.view_mode != .Status || state.observation.state == nil do return false
	descriptor, described := ksawery.status_observation_descriptor(&state.observation)
	if described && state.extension_status != nil {
		values := [1]ksawery.Extension_Status_Generation{state.extension_status^}
		if ksawery_extension_status_select_ui_item(
			values[:], descriptor, id, &state.extension_status_selection,
		) {
			state.extension_annotation_selection = {}
			return true
		}
	}
	document := &state.diff if state.diff.state != nil else nil
	count, available := ksawery.status_hierarchy_item_count(&state.observation, document)
	if !available do return false
	for ordinal in 0 ..< count {
		item, found := ksawery.status_hierarchy_item(&state.observation, ordinal, document)
		if found && ksawery_status_ui_item_id(item.id) == id {
			state.selection.current = item.id
			state.extension_status_selection = {}
			state.extension_annotation_selection = {}
			return true
		}
	}
	return false
}

@(private)
ksawery_status_diff_group :: proc(layer: ksawery.Diff_Layer) -> ksawery.Change_Group {
	if layer == .Working_Tree do return .Unstaged
	if layer == .Index do return .Staged
	return .Invalid
}

@(private)
ksawery_status_group_count :: proc(observation: ^ksawery.Status_Observation, group: ksawery.Change_Group) -> u32 {
	count: u32
	path_count, available := ksawery.status_observation_path_count(observation)
	if !available do return 0
	for index in 0 ..< int(path_count) {
		path, found := ksawery.status_observation_path(observation, u32(index))
		if found && path.group == group do count += 1
	}
	return count
}

@(private)
ksawery_status_group_label :: proc(group: ksawery.Change_Group) -> string {
	switch group {
	case .Unmerged: return "Unmerged"
	case .Untracked: return "Untracked"
	case .Unstaged: return "Unstaged"
	case .Staged: return "Staged"
	case .Invalid: return "Invalid"
	}
	return "Invalid"
}

/* command_context_begin_ksawery_extension_command opens one exact typed family editor. */
command_context_begin_ksawery_extension_command :: proc(
	commands: ^Command_Context,
	metadata: interaction.Command_Metadata,
) -> (Interaction_Result, App_Failure) {
	if commands == nil || commands.ksawery_workflow == nil || commands.host.call == nil {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	state := commands.ksawery_workflow
	if !state.active || state.process.state != nil || state.process_coordinator.active ||
	   state.extension_command_family != nil ||
	   state.extension_command_workflow.active {
		command_context_set_diagnostic(commands, "Ksawery extension command is unavailable while another repository operation is active")
		return Interaction_Result{changed = true}, {}
	}
	dispatch, operation, routed := command.racket_route_decode(metadata.route)
	if !routed || dispatch != .Ksawery_Extension || operation == 0 ||
	   state.extension_registry.active == nil || !state.extension_registry.active.enabled {
		command_context_set_diagnostic(commands, "Ksawery extension command route is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	data, loaded := ksawery_extension_command_load(
		&commands.host,
		state.extension_registry.active,
		state.extension_registry.personal_generation,
		{route = metadata.route},
		metadata.name,
		commands.temporary_allocator,
	)
	if !loaded {
		command_context_set_diagnostic(commands, "Ksawery extension command family could not be loaded from the active generation")
		return Interaction_Result{changed = true}, {}
	}
	defer ksawery_extension_command_data_close(data)
	context_value, context_ok := ksawery_workflow_extension_command_context(
		state,
		ksawery.Extension_Capability_Generation(state.extension_registry.capability_generation + 1),
	)
	if !context_ok {
		command_context_set_diagnostic(commands, "Ksawery extension command has no current repository context")
		return Interaction_Result{changed = true}, {}
	}
	request := state.next_extension_command_request
	if request == 0 {
		command_context_set_diagnostic(commands, "Ksawery extension command request identities are exhausted")
		return Interaction_Result{changed = true}, {}
	}
	family_state, allocation_error := new(ksawery_command.Ksawery_Command_Family_State, state.allocator)
	if allocation_error != nil {
		command_context_set_diagnostic(commands, "Ksawery extension command editor could not allocate bounded state")
		return Interaction_Result{changed = true}, {}
	}
	begun, _ := ksawery_command.ksawery_command_family_begin(
		family_state,
		data.family,
		data.action,
		context_value,
		request,
		state.allocator,
	)
	if !begun {
		free(family_state, state.allocator)
		command_context_set_diagnostic(commands, "Ksawery extension command is unavailable for the current target")
		return Interaction_Result{changed = true}, {}
	}
	state.extension_command_family = family_state
	state.next_extension_command_request += 1
	state.extension_command_route = {
		route = metadata.route,
		contributor = data.family.contributor,
		family = data.family.family,
		family_generation = data.family.generation,
		action = data.action,
	}
	copy(state.extension_command_name[:], transmute([]u8)metadata.name)
	state.extension_command_name_length = u16(len(metadata.name))
	state.extension_command_return_mode = state.view_mode
	state.extension_command_return_position = state.position
	state.extension_command_cursor = 0
	state.extension_command_text_editing = false
	state.extension_command_text_length = 0
	state.view_mode = .Extension_Command
	state.position = {}
	state.failure = .None
	command_context_set_diagnostic(commands, "Editing typed Ksawery extension command arguments")
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_extension_command_context :: proc(
	state: ^Ksawery_Workflow_State,
	capability_generation: ksawery.Extension_Capability_Generation,
) -> (ksawery.Extension_Command_Context, bool) {
	if state == nil || state.extension_registry.active == nil || capability_generation == 0 do return {}, false
	observation, target, target_present, ready := ksawery_workflow_extension_command_observation(state)
	if !ready do return {}, false
	operation_state := ksawery.Extension_Command_Operation_State.Idle
	if state.process.state != nil || state.process_coordinator.active {
		operation_state = .Active
	} else if observation.family == .Conflict {
		operation_state = .Conflict
	} else if observation.family == .Sequence {
		operation_state = .Sequence
	}
	return {
		contributor = state.extension_registry.active.inspection.handle,
		repository = observation.repository,
		repository_generation = ksawery.Repository_Generation(observation.generation),
		worktree_generation = ksawery.Worktree_Generation(observation.generation),
		observation = observation.family,
		observation_generation = observation.generation,
		surface = ksawery_extension_annotation_surface(observation.family),
		surface_generation = ksawery.Extension_Surface_Generation(observation.generation),
		selection_generation = observation.generation,
		target_present = target_present,
		target = target,
		operation_state = operation_state,
		mutation_available = operation_state == .Idle,
		capability_generation = capability_generation,
	}, true
}

@(private)
ksawery_workflow_extension_command_observation :: proc(
	state: ^Ksawery_Workflow_State,
) -> (ksawery.Extension_Annotation_Observation, ksawery.Extension_Annotation_Target, bool, bool) {
	if state == nil do return {}, {}, false, false
	observation: ksawery.Extension_Annotation_Observation
	switch state.view_mode {
	case .Status:
		descriptor, described := ksawery.status_observation_descriptor(&state.observation)
		if !described do return {}, {}, false, false
		observation = {family = .Status, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .History:
		descriptor, described := ksawery.history_observation_descriptor(&state.history)
		if !described do return {}, {}, false, false
		observation = {family = .History, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .Refs:
		descriptor, described := ksawery.ref_observation_descriptor(&state.refs)
		if !described do return {}, {}, false, false
		observation = {family = .Refs, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .Sequence, .Conflict:
		descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
		if !described do return {}, {}, false, false
		family := ksawery.Extension_Observation_Family.Sequence
		if state.view_mode == .Conflict do family = .Conflict
		observation = {family = family, repository = descriptor.repository, generation = u64(descriptor.generation)}
	case .Process:
		records := ksawery_workflow_process_records(state)
		_, described := ksawery.process_surface_descriptor(records)
		if !described do return {}, {}, false, false
		observation = {
			family = .Process,
			repository = state.repository,
			generation = ksawery_extension_process_annotation_generation(records),
		}
	case .Provider_Inspection, .Inspection_Workflow, .Inspection_Input, .Inspection_Confirmation,
	     .Extension_Command, .Status_Command_Dispatcher:
		return {}, {}, false, false
	case .Revision_Detail, .Revision_Range, .Resource, .Commit_Message,
	     .Raw_Command_Input, .Raw_Command_Confirmation, .Amend_Confirmation,
	     .Push_Confirmation, .Branch_Name, .Branch_Confirmation, .Tag_Name,
	     .Tag_Confirmation, .Merge_Confirmation, .Rebase_Confirmation,
	     .Revision_Sequence_Confirmation, .Bisect_Confirmation, .Conflict_Confirmation:
		return {}, {}, false, false
	}
	selection := state.extension_annotation_selection
	if selection.valid && selection.observation_family == observation.family &&
	   selection.observation_generation == observation.generation {
		return observation, selection.target, true, true
	}
	target, selected := ksawery_workflow_extension_command_target(state, observation)
	return observation, target, selected, true
}

@(private)
ksawery_workflow_extension_command_target :: proc(
	state: ^Ksawery_Workflow_State,
	observation: ksawery.Extension_Annotation_Observation,
) -> (ksawery.Extension_Annotation_Target, bool) {
	switch observation.family {
	case .Status:
		if state.selection.current.kind == .Diff_Unit && state.diff.state != nil {
			unit, found, _ := ksawery.status_selection_diff_unit_target(
				&state.observation, &state.diff, state.selection,
			)
			if found do return ksawery.extension_annotation_target_from_diff_unit(observation, unit)
		}
		path, found, _ := ksawery.status_selection_path_target(&state.observation, state.selection)
		if found do return ksawery.extension_annotation_target_from_path(observation, path)
	case .History:
		current, found, _ := ksawery_workflow_history_current_target(state)
		if found {
			if state.history_selection.marked != {} && state.history_selection.marked != current {
				return ksawery.extension_annotation_target_from_revision_range(
					observation,
					{
						base = {generation = state.history_selection.marked.generation,
						        revision = state.history_selection.marked.revision},
						target = {generation = current.generation, revision = current.revision},
					},
				)
			}
			return ksawery.extension_annotation_target_from_revision(observation, current)
		}
	case .Refs:
		if ksawery.ref_selection_is_current(&state.refs, state.ref_selection) {
			if state.ref_selection.current.kind == .Ref {
				return ksawery.extension_annotation_target_from_ref(
					observation, state.ref_selection.current.reference,
				)
			}
			if state.ref_selection.current.kind == .Remote {
				return ksawery.extension_annotation_target_from_remote(
					observation, state.ref_selection.current.remote,
				)
			}
		}
	case .Sequence, .Conflict:
		descriptor, described := ksawery.sequence_observation_descriptor(&state.sequence)
		if !described do return {}, false
		sequence := ksawery.Sequence_Target{generation = descriptor.generation, fingerprint = descriptor.fingerprint}
		if observation.family == .Conflict && state.conflict_selection != 0 {
			return ksawery.extension_annotation_target_from_conflict(
				observation,
				{sequence = sequence, conflict = state.conflict_selection},
			)
		}
		return ksawery.extension_annotation_target_from_sequence(observation, sequence)
	case .Process:
		records := ksawery_workflow_process_records(state)
		if !ksawery.process_selection_is_current(records, state.process_selection) ||
		   state.process_selection.current == {} {
			return {}, false
		}
		surface, described := ksawery.process_surface_descriptor(records)
		if !described do return {}, false
		for ordinal in 0 ..< surface.row_count {
			row, projected, _ := ksawery.process_surface_row(records, ordinal)
			if projected && row.id == state.process_selection.current {
				return ksawery.extension_annotation_target_from_process(observation, row)
			}
		}
	}
	return {}, false
}

@(private)
dispatch_ksawery_extension_command_input :: proc(
	commands: ^Command_Context,
	input: interaction.Input,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.view_mode != .Extension_Command || state.extension_command_family == nil {
		return {}, App_Failure{stage = .UI}
	}
	if input.kind == .Key && input.stroke.kind == .Unicode_Scalar &&
	   ((input.stroke.scalar == 'g' && input.stroke.modifiers == {.Control}) ||
	    (input.stroke.scalar == 'q' && input.stroke.modifiers == {} &&
	     !state.extension_command_text_editing)) {
		return Interaction_Result{changed = ksawery_workflow_cancel_extension_command(commands)}, {}
	}
	if state.extension_command_text_editing {
		if input.kind == .Key && input.stroke.kind == .Enter && input.stroke.modifiers == {} {
			return Interaction_Result{changed = ksawery_workflow_commit_extension_command_text(commands)}, {}
		}
		if input.kind == .Key && (input.stroke.kind == .Backspace || input.stroke.kind == .Delete) {
			if state.extension_command_text_length == 0 do return {}, {}
			end := int(state.extension_command_text_length)
			start := end - 1
			for start > 0 && !utf8.rune_start(state.extension_command_text[start]) do start -= 1
			state.extension_command_text_length = u16(start)
			return Interaction_Result{changed = true}, {}
		}
		if (input.kind == .Text_Commit || input.kind == .Key) && len(input.text) > 0 &&
		   input.stroke.modifiers == {} {
			limit := len(state.extension_command_text)
			if int(state.extension_command_text_length) + len(input.text) > limit ||
			   !utf8.valid_string(input.text) {
				command_context_set_diagnostic(commands, "Ksawery extension argument text exceeds its bounded storage")
				return Interaction_Result{changed = true}, {}
			}
			copy(state.extension_command_text[state.extension_command_text_length:], transmute([]u8)input.text)
			state.extension_command_text_length += u16(len(input.text))
			return Interaction_Result{changed = true}, {}
		}
		return {}, {}
	}
	count := len(state.extension_command_family.family.arguments) + 1
	if input.kind == .Key && input.stroke.modifiers == {} {
		#partial switch input.stroke.kind {
		case .Up:
			if state.extension_command_cursor > 0 do state.extension_command_cursor -= 1
			return Interaction_Result{changed = true}, {}
		case .Down:
			if int(state.extension_command_cursor) + 1 < count do state.extension_command_cursor += 1
			return Interaction_Result{changed = true}, {}
		case .Enter:
			if int(state.extension_command_cursor) == len(state.extension_command_family.family.arguments) {
				return ksawery_workflow_submit_extension_command(commands)
			}
			return Interaction_Result{changed = ksawery_workflow_edit_extension_command_argument(commands)}, {}
		}
	}
	return {}, {}
}

@(private)
ksawery_workflow_edit_extension_command_argument :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.extension_command_family == nil do return false
	family := state.extension_command_family
	index := int(state.extension_command_cursor)
	if index < 0 || index >= len(family.family.arguments) do return false
	argument := family.family.arguments[index]
	entry := family.entries[index]
	switch argument.kind {
	case .Boolean:
		value := true
		if entry.present do value = !entry.value.boolean
		changed, _ := ksawery_command.ksawery_command_family_set_boolean(family, argument.id, value)
		return changed
	case .Closed_Choice:
		if len(argument.choices) == 0 do return false
		choice_index := 0
		if entry.present {
			for choice, candidate_index in argument.choices {
				if choice.id == entry.value.choice {
					choice_index = (candidate_index + 1) % len(argument.choices)
					break
				}
			}
		}
		changed, _ := ksawery_command.ksawery_command_family_set_choice(
			family, argument.id, argument.choices[choice_index].id,
		)
		return changed
	case .Text, .Opaque:
		state.extension_command_text_length = 0
		if entry.present {
			content := entry.value.content
			copy(state.extension_command_text[:], content.bytes[:content.length])
			state.extension_command_text_length = content.length
		}
		state.extension_command_text_editing = true
		return true
	case .Selection, .Ref, .Revision, .Revision_Range:
		context_value := family.command_context
		if !context_value.target_present {
			command_context_set_diagnostic(commands, "Current Ksawery selection does not provide this semantic argument")
			return true
		}
		changed, _ := ksawery_command.ksawery_command_family_set_target(
			family, argument.id, argument.kind, context_value.target,
		)
		if !changed do command_context_set_diagnostic(commands, "Current Ksawery selection is incompatible with this argument")
		return true
	case .Invalid:
	}
	return false
}

@(private)
ksawery_workflow_commit_extension_command_text :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.extension_command_family == nil || !state.extension_command_text_editing do return false
	index := int(state.extension_command_cursor)
	if index < 0 || index >= len(state.extension_command_family.family.arguments) do return false
	argument := state.extension_command_family.family.arguments[index]
	content := state.extension_command_text[:state.extension_command_text_length]
	changed := false
	if argument.kind == .Text {
		changed, _ = ksawery_command.ksawery_command_family_set_text(
			state.extension_command_family, argument.id, string(content),
		)
	} else if argument.kind == .Opaque {
		changed, _ = ksawery_command.ksawery_command_family_set_opaque(
			state.extension_command_family, argument.id, content,
		)
	}
	if !changed {
		command_context_set_diagnostic(commands, "Ksawery extension argument rejected the entered value")
		return true
	}
	state.extension_command_text_editing = false
	state.extension_command_text_length = 0
	return true
}

@(private)
ksawery_workflow_cancel_extension_command :: proc(commands: ^Command_Context) -> bool {
	state := commands.ksawery_workflow
	if state == nil || state.extension_command_family == nil do return false
	_, _ = ksawery_command.ksawery_command_family_cancel(state.extension_command_family)
	completion_mode := state.extension_command_return_mode
	ksawery_workflow_close_extension_command_editor(state)
	state.extension_command_completion_mode = completion_mode
	state.failure = .Cancelled
	command_context_set_diagnostic(commands, "Ksawery extension command cancelled without executing an operation")
	return true
}

@(private)
ksawery_workflow_close_extension_command_editor :: proc(state: ^Ksawery_Workflow_State) {
	if state == nil do return
	if state.extension_command_family != nil {
		ksawery_command.ksawery_command_family_close(state.extension_command_family)
		free(state.extension_command_family, state.allocator)
	}
	state.extension_command_family = nil
	state.extension_command_route = {}
	state.extension_command_name = {}
	state.extension_command_name_length = 0
	state.extension_command_text_editing = false
	state.extension_command_text_length = 0
	state.extension_command_cursor = 0
	state.view_mode = state.extension_command_return_mode
	state.position = state.extension_command_return_position
	state.extension_command_return_mode = .Status
	state.extension_command_return_position = {}
}

@(private)
ksawery_workflow_submit_extension_command :: proc(
	commands: ^Command_Context,
) -> (Interaction_Result, App_Failure) {
	state := commands.ksawery_workflow
	if state == nil || state.extension_command_family == nil ||
	   state.extension_registry.active == nil {
		return {}, App_Failure{stage = .Command_Dispatch}
	}
	confirmation := state.next_extension_command_confirmation
	if confirmation == 0 {
		command_context_set_diagnostic(commands, "Ksawery extension confirmation identities are exhausted")
		return Interaction_Result{changed = true}, {}
	}
	confirmed, _ := ksawery_command.ksawery_command_family_confirm(state.extension_command_family, confirmation)
	if !confirmed {
		command_context_set_diagnostic(commands, "Ksawery extension command arguments or confirmation are incomplete")
		return Interaction_Result{changed = true}, {}
	}
	provisional_context, context_ok := ksawery_workflow_extension_command_context_for_mode(
		state,
		state.extension_command_return_mode,
		ksawery.Extension_Capability_Generation(state.extension_registry.capability_generation + 1),
	)
	if !context_ok {
		command_context_set_diagnostic(commands, "Ksawery extension command context became stale")
		return Interaction_Result{changed = true}, {}
	}
	action, action_found := ksawery_extension_command_action(
		state.extension_command_family.family,
		state.extension_command_family.action,
	)
	if !action_found ||
	   (action.authority != .Request_Core_Action && action.authority != .Submit_External_Operation) {
		command_context_set_diagnostic(commands, "Ksawery extension command action has no executable authority")
		return Interaction_Result{changed = true}, {}
	}
	scope := ksawery_workflow_extension_command_scope(state, provisional_context)
	requested_authority := ksawery.Extension_Authorities{.Request_Core_Action}
	if action.authority == .Submit_External_Operation {
		requested_authority = {.Submit_External_Operation}
	}
	capability, turn_begun, _ := ksawery_extension_provider_turn_begin(
		&state.extension_registry, scope, requested_authority,
	)
	if !turn_begun {
		command_context_set_diagnostic(commands, "Ksawery extension command capability is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	defer ksawery_extension_provider_turn_end(&state.extension_registry)
	current_context := provisional_context
	current_context.capability_generation = capability.generation
	state.extension_command_family.command_context = current_context
	request, prepared, _ := ksawery_command.ksawery_command_family_prepare(state.extension_command_family)
	if !prepared {
		command_context_set_diagnostic(commands, "Ksawery extension command request was rejected")
		return Interaction_Result{changed = true}, {}
	}
	current_scope := state.extension_registry.active.active_scope
	if action.authority == .Submit_External_Operation {
		routed, _ := ksawery_extension_command_workflow_begin_external(
			&state.extension_command_workflow,
			&state.extension_registry,
			state.extension_command_route,
			state.extension_command_family.family,
			request,
			current_context,
			capability,
			current_scope,
			current_scope.owner_thread,
			0,
			0,
			state.process.state != nil || state.process_coordinator.active,
		)
		if !routed {
			command_context_set_diagnostic(commands, "Ksawery extension command failed closed before external execution")
			return Interaction_Result{changed = true}, {}
		}
		name := string(state.extension_command_name[:state.extension_command_name_length])
		data, evaluated := ksawery_extension_command_external_operation(
			&commands.host,
			&state.extension_registry,
			state.extension_registry.personal_generation,
			state.extension_command_route,
			name,
			request,
			state.allocator,
		)
		if !evaluated || data == nil ||
		   (data.plan.effect != .Read_Only && !current_scope.mutation_available) {
			if data != nil do ksawery_extension_command_operation_data_close(data)
			_ = ksawery_extension_command_workflow_abort(&state.extension_command_workflow)
			ksawery_workflow_close_extension_command_editor(state)
			command_context_set_diagnostic(commands, "Ksawery extension command returned no admissible external operation")
			return Interaction_Result{changed = true}, {}
		}
		submission := ksawery.Extension_Operation_Submission {
			request = ksawery.Extension_Operation_Request_ID(request.id),
			contributor = current_scope.contributor,
			contribution = data.plan.contribution,
			repository = current_scope.repository,
			repository_generation = current_scope.repository_generation,
		}
		if state.extension_operation == nil {
			operation, allocation_error := new(Ksawery_Extension_Operation_Workflow, state.allocator)
			if allocation_error != nil {
				ksawery_extension_command_operation_data_close(data)
				_ = ksawery_extension_command_workflow_abort(&state.extension_command_workflow)
				ksawery_workflow_close_extension_command_editor(state)
				command_context_set_diagnostic(commands, "Ksawery extension operation state could not be allocated")
				return Interaction_Result{changed = true}, {}
			}
			state.extension_operation = operation
		}
		started, _ := ksawery_extension_operation_workflow_begin(
			state.extension_operation,
			&state.process_coordinator,
			submission,
			data.plan,
			data.declaration,
			current_scope.contributor,
			current_scope.repository,
			current_scope.repository_generation,
			ksawery_workflow_now(commands),
		)
		if !started {
			ksawery_extension_command_operation_data_close(data)
			_ = ksawery_extension_command_workflow_abort(&state.extension_command_workflow)
			ksawery_workflow_close_extension_command_editor(state)
			command_context_set_diagnostic(commands, "Ksawery extension command external operation was rejected by Process")
			return Interaction_Result{changed = true}, {}
		}
		ksawery_extension_command_operation_data_close(data)
		state.next_extension_command_confirmation += 1
		state.extension_operation_return_mode = state.extension_command_return_mode
		state.extension_operation_return_position = state.extension_command_return_position
		state.extension_operation_refresh = .None
		state.extension_operation_refresh_completed = {.Process}
		ksawery_workflow_close_extension_command_editor(state)
		state.pending = .Extension_Operation
		state.failure = .None
		command_context_set_diagnostic(commands, "Ksawery extension command external operation is running in Process")
		return Interaction_Result{changed = true}, {}
	}
	core_request, routed, _ := ksawery_extension_command_workflow_begin(
		&state.extension_command_workflow,
		&state.extension_registry,
		state.extension_command_route,
		state.extension_command_family.family,
		request,
		current_context,
		capability,
		current_scope,
		current_scope.owner_thread,
		0,
		0,
		state.process.state != nil || state.process_coordinator.active,
	)
	if !routed {
		command_context_set_diagnostic(commands, "Ksawery extension command failed closed before core execution")
		return Interaction_Result{changed = true}, {}
	}
	state.next_extension_command_confirmation += 1
	name, mapped := ksawery_workflow_extension_core_command_name(core_request.operation)
	if !mapped {
		_ = ksawery_extension_command_workflow_abort(&state.extension_command_workflow)
		ksawery_workflow_close_extension_command_editor(state)
		command_context_set_diagnostic(commands, "Ksawery extension command requested an unsupported core operation")
		return Interaction_Result{changed = true}, {}
	}
	if !host_command_request(&commands.host, .Invoke, name) {
		_ = ksawery_extension_command_workflow_abort(&state.extension_command_workflow)
		ksawery_workflow_close_extension_command_editor(state)
		command_context_set_diagnostic(commands, "Ksawery extension core command is unavailable")
		return Interaction_Result{changed = true}, {}
	}
	ksawery_workflow_close_extension_command_editor(state)
	state.failure = .None
	command_context_set_diagnostic(commands, "Ksawery extension command admitted one checked core action")
	return Interaction_Result{changed = true}, {}
}

@(private)
ksawery_workflow_extension_command_context_for_mode :: proc(
	state: ^Ksawery_Workflow_State,
	mode: Ksawery_View_Mode,
	capability_generation: ksawery.Extension_Capability_Generation,
) -> (ksawery.Extension_Command_Context, bool) {
	current := state.view_mode
	state.view_mode = mode
	context_value, ok := ksawery_workflow_extension_command_context(state, capability_generation)
	state.view_mode = current
	return context_value, ok
}

@(private)
ksawery_workflow_extension_command_scope :: proc(
	state: ^Ksawery_Workflow_State,
	context_value: ksawery.Extension_Command_Context,
) -> ksawery.Extension_Turn_Scope {
	target: ksawery.Extension_Target
	if context_value.target_present {
		kind := ksawery.Extension_Target_Kind.None
		switch context_value.target.family {
		case .Path, .Diff_Unit: kind = .Path
		case .Revision:          kind = .Revision
		case .Revision_Range:    kind = .Revision_Range
		case .Ref:               kind = .Ref
		case .Remote:            kind = .Remote
		case .Conflict:          kind = .Conflict
		case .Sequence:          kind = .Sequence
		case .Process:           kind = .Process
		case .Invalid:
		}
		identity := u64(14_695_981_039_346_656_037)
		target_copy := context_value.target
		for value in target_copy.identity[:target_copy.length] {
			identity = (identity ~ u64(value)) * 1_099_511_628_211
		}
		if identity == 0 do identity = 1
		target = {kind = kind, generation = context_value.target.generation, identity = identity}
	}
	provider := state.extension_registry.active
	return {
		turn = ksawery.Extension_Turn_ID(state.extension_command_family.request),
		contributor = context_value.contributor,
		repository = context_value.repository,
		repository_generation = context_value.repository_generation,
		worktree_generation = context_value.worktree_generation,
		observation_generation = ksawery.Observation_Generation(context_value.observation_generation),
		surface = context_value.surface,
		surface_generation = context_value.surface_generation,
		selection_generation = ksawery.Extension_Selection_Generation(context_value.selection_generation),
		target = target,
		capability_generation = context_value.capability_generation,
		owner_thread = u64(os.get_current_thread_id()),
		deadline_ns = provider.limits.turn_deadline_ns,
		callback_budget = provider.limits.callbacks_per_turn,
		active_operation = context_value.operation_state != .Idle,
		mutation_available = context_value.mutation_available,
	}
}

@(private)
ksawery_workflow_extension_core_command_name :: proc(
	operation: ksawery.Repository_Operation_Kind,
) -> (string, bool) {
	switch operation {
	case .Stage:                return "ksawery-stage", true
	case .Unstage:              return "ksawery-unstage", true
	case .Discard:              return "ksawery-discard", true
	case .Commit:               return "ksawery-commit", true
	case .Amend:                return "ksawery-amend", true
	case .Fixup:                return "ksawery-fixup", true
	case .Fetch:                return "ksawery-fetch", true
	case .Push:                 return "ksawery-push", true
	case .Create_Branch:        return "ksawery-branch-create", true
	case .Switch_Branch:        return "ksawery-branch-switch", true
	case .Rename_Branch:        return "ksawery-branch-rename", true
	case .Delete_Branch:        return "ksawery-branch-delete", true
	case .Create_Tag:           return "ksawery-tag-create", true
	case .Delete_Tag:           return "ksawery-tag-delete", true
	case .Merge:                return "ksawery-merge", true
	case .Continue_Merge:       return "ksawery-merge-continue", true
	case .Abort_Merge:          return "ksawery-merge-abort", true
	case .Rebase:               return "ksawery-rebase", true
	case .Continue_Rebase:      return "ksawery-rebase-continue", true
	case .Skip_Rebase:          return "ksawery-rebase-skip", true
	case .Abort_Rebase:         return "ksawery-rebase-abort", true
	case .Cherry_Pick:          return "ksawery-cherry-pick", true
	case .Continue_Cherry_Pick: return "ksawery-cherry-pick-continue", true
	case .Skip_Cherry_Pick:     return "ksawery-cherry-pick-skip", true
	case .Abort_Cherry_Pick:    return "ksawery-cherry-pick-abort", true
	case .Revert:               return "ksawery-revert", true
	case .Continue_Revert:      return "ksawery-revert-continue", true
	case .Skip_Revert:          return "ksawery-revert-skip", true
	case .Abort_Revert:         return "ksawery-revert-abort", true
	case .Bisect:               return "ksawery-bisect-start", true
	case .Bisect_Good:          return "ksawery-bisect-good", true
	case .Bisect_Bad:           return "ksawery-bisect-bad", true
	case .Bisect_Skip:          return "ksawery-bisect-skip", true
	case .Bisect_Reset:         return "ksawery-bisect-reset", true
	case .Resolve_Conflict:     return "ksawery-conflict-mark-resolved", true
	case .Invalid, .Status, .Sequence, .History, .Refs, .Revision_Detail,
	     .Revision_Range, .Path_Detail, .Stash, .Worktree, .Blame, .Reflog,
	     .External_Operation, .Raw_Command:
	}
	return "", false
}

@(private)
ksawery_workflow_finish_extension_command_if_ready :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || commands.ksawery_workflow == nil do return false
	state := commands.ksawery_workflow
	workflow := &state.extension_command_workflow
	if !workflow.active || state.process.state != nil || state.process_coordinator.active ||
	   state.view_mode != state.extension_command_completion_mode {
		return false
	}
	context_value, context_ok := ksawery_workflow_extension_command_context(
		state,
		workflow.initial_context.capability_generation,
	)
	if !context_ok {
		_ = ksawery_extension_command_workflow_abort(workflow)
		state.extension_command_completion_mode = .Status
		command_context_set_diagnostic(commands, "Ksawery extension command result lost its compatible repository context")
		return true
	}
	refreshed := context_value.repository_generation > workflow.initial_context.repository_generation &&
		context_value.worktree_generation >= workflow.initial_context.worktree_generation
	status := ksawery.Extension_Command_Result_Status.Rejected
	core_action_requested := false
	if refreshed {
		status = .Completed
		core_action_requested = true
	} else if state.failure == .Cancelled {
		status = .Cancelled
	} else if state.failure != .None {
		status = .Failed
	}
	result := ksawery.Extension_Command_Result {
		request = workflow.request,
		family = workflow.family,
		family_generation = workflow.family_generation,
		action = workflow.action,
		status = status,
		core_action_requested = core_action_requested,
	}
	completed, _ := ksawery_extension_command_workflow_complete(
		workflow, result, context_value, refreshed,
	)
	if !completed {
		_ = ksawery_extension_command_workflow_abort(workflow)
		command_context_set_diagnostic(commands, "Ksawery extension command result failed closed")
	} else if status == .Completed {
		command_context_set_diagnostic(commands, "Ksawery extension command completed after repository refresh")
	} else if status == .Cancelled {
		command_context_set_diagnostic(commands, "Ksawery extension command was cancelled before a verified effect")
	} else {
		command_context_set_diagnostic(commands, "Ksawery extension command ended without a verified repository effect")
	}
	state.extension_command_completion_mode = .Status
	return true
}

@(private)
ksawery_extension_command_list_definitions :: proc(
	state: ^Ksawery_Workflow_State,
	viewport_items: u32,
	allocator: runtime.Allocator,
) -> (definitions: []ui.List_Item_Definition, text: []u8, ok: bool) {
	if state == nil || state.view_mode != .Extension_Command || state.extension_command_family == nil ||
	   viewport_items == 0 || allocator.procedure == nil {
		return nil, nil, false
	}
	family := state.extension_command_family
	count := min(len(family.family.arguments) + 6, int(ui.MAX_LIST_ITEMS))
	rows, rows_error := make([]ui.List_Item_Definition, count, allocator)
	if rows_error != nil do return nil, nil, false
	storage, storage_error := make([]u8, count * KSAWERY_LIST_ROW_BYTES, allocator)
	if storage_error != nil {
		delete(rows, allocator)
		return nil, nil, false
	}
	write := 0
	family_label := family.family.label
	action_label := "Run"
	for action in family.family.actions {
		if action.id == family.action {
			label := action.label
			action_label = string(label.bytes[:label.length])
			break
		}
	}
	ready := ksawery_append_presented_label(
		rows, storage, &write, 0xCC00_0000_0000_0001,
		fmt.tprintf("Ksawery Extension Command: %s", string(family_label.bytes[:family_label.length])), true,
		{surface = .Status, subject = .Section},
	) && ksawery_status_append_label(
		rows, storage, &write, 0xCC00_0000_0000_0002,
		"Up/Down selects; Enter edits or binds; C-g cancels without effects", true,
	)
	if !ready {
		delete(rows, allocator)
		delete(storage, allocator)
		return nil, nil, false
	}
	for argument, index in family.family.arguments {
		label_copy := argument.label
		value := "unset"
		entry := family.entries[index]
		if entry.present {
			switch entry.value.kind {
			case .Boolean: value = "true" if entry.value.boolean else "false"
			case .Closed_Choice:
				value = "selected"
				for choice in argument.choices {
					if choice.id == entry.value.choice {
						choice_label := choice.label
						value = string(choice_label.bytes[:choice_label.length])
						break
					}
				}
			case .Text, .Opaque:
				content := entry.value.content
				value = string(content.bytes[:content.length])
			case .Selection, .Ref, .Revision, .Revision_Range: value = "current semantic target"
			case .Invalid:
			}
		}
		if state.extension_command_text_editing && int(state.extension_command_cursor) == index {
			value = string(state.extension_command_text[:state.extension_command_text_length])
		}
		if len(value) > 180 {
			end := 177
			for end > 0 && !utf8.rune_start(value[end]) do end -= 1
			value = fmt.tprintf("%s...", value[:end])
		}
		row := write
		if !ksawery_status_append_label(
			rows, storage, &write, ui.List_Item_ID(0xCC00_0000_0000_0100 + u64(index)),
			fmt.tprintf("%s: %s", string(label_copy.bytes[:label_copy.length]), value), false,
		) {
			delete(rows, allocator)
			delete(storage, allocator)
			return nil, nil, false
		}
		if int(state.extension_command_cursor) == index do state.position.current_item = i32(row)
	}
	action_row := write
	_ = ksawery_append_presented_label(
		rows, storage, &write, 0xCC00_0000_0000_FF00,
		fmt.tprintf("Confirm and request checked core action: %s", action_label), false,
		{surface = .Status, subject = .Operation, destructive = true},
	)
	if int(state.extension_command_cursor) == len(family.family.arguments) {
		state.position.current_item = i32(action_row)
	}
	definitions = rows[:write]
	state.position = {
		presentation_generation = u64(family.edit_generation),
		selection_owner = .View,
		current_item = state.position.current_item,
		first_visible_item = 0,
		viewport_items = min(viewport_items, u32(write)),
	}
	return definitions, storage, true
}
