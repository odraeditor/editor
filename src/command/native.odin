// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../document"
import "../editor"
import "../interaction"
import "../kill_ring"
import "../history"
import "../indentation"
import "../language"
import "../layout"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"
import "core:unicode/utf8"

/* NATIVE_BASE_COMMAND_COUNT is the native catalog size before Jan Stage 2 commands. */
NATIVE_BASE_COMMAND_COUNT :: 370
/* NATIVE_COMMAND_COUNT is the complete native command set for this capability. */
NATIVE_COMMAND_COUNT :: NATIVE_BASE_COMMAND_COUNT + JAN_STRUCTURED_COMMAND_COUNT + JAN_PLANNING_COMMAND_COUNT + JAN_COMPUTATION_COMMAND_COUNT + JAN_OUTPUT_COMMAND_COUNT + LANGUAGE_SUPPORT_COMMAND_COUNT + PACKAGE_CATALOG_COMMAND_COUNT
/* BUILT_IN_BASE_COMMAND_COUNT includes only declarations owned by native subsystems. */
BUILT_IN_BASE_COMMAND_COUNT :: NATIVE_COMMAND_COUNT + INTERACTION_COMMAND_COUNT

/* Native_Completion classifies successful native command effects for the coordinator. */
Native_Completion :: enum u8 {
	Invalid,
	No_Op,
	View_Changed,
	Buffer_Committed,
	Text_Retained,
	Pending_Input_Cancelled,
	Exit_Requested,
	Document_Saved,
	Document_Target_Required,
	Incremental_Search_Forward_Requested,
	Incremental_Search_Backward_Requested,
	Incremental_Regexp_Search_Forward_Requested,
	Incremental_Regexp_Search_Backward_Requested,
	Search_Symbol_At_Point_Requested,
	Search_Word_Requested,
	Search_Occur_Requested,
	Search_Highlight_Symbol_Requested,
	Search_Highlight_Phrase_Requested,
	Search_Highlight_Regexp_Requested,
	Search_Highlight_Lines_Requested,
	Search_Highlight_Remove_Requested,
	Search_Next_Occurrence_Requested,
	Search_Previous_Occurrence_Requested,
	Query_Replace_Requested,
	Query_Replace_Regexp_Requested,
	Find_File_Requested,
	Find_Alternate_File_Requested,
	Write_File_Requested,
	Save_Some_Buffers_Requested,
	Insert_File_Requested,
	Next_Buffer_Requested,
	Previous_Buffer_Requested,
	Numeric_Navigation_Target_Requested,
	Rigid_Indentation_Requested,
	Switch_To_Buffer_Requested,
	Find_File_Other_Pane_Requested,
	Switch_To_Buffer_Other_Pane_Requested,
	Display_Buffer_Other_Pane_Requested,
	Kill_Buffer_Requested,
	List_Buffers_Requested,
	Interaction_Profile_Reload_Requested,
	Personal_Commands_Reload_Requested,
	Command_Navigation_Requested,
	Command_Description_Requested,
	Help_Requested,
	Interaction_Profile_Selection_Requested,
	Modal_Repeat_Inspection_Requested,
	Keyboard_Macro_Start_Requested,
	Keyboard_Macro_End_Requested,
	Keyboard_Macro_Call_Last_Requested,
	Keyboard_Macro_Finish_Or_Call_Requested,
	Keyboard_Macro_Name_Last_Requested,
	Keyboard_Macro_Call_Named_Requested,
	Theme_Selection_Requested,
	Theme_Inspection_Requested,
	Project_Inspect_Active_Requested,
	Project_Promote_Requested,
	Project_Unregister_Requested,
	Project_Find_File_Requested,
	Project_Switch_Buffer_Requested,
	Project_Save_Buffers_Requested,
	Project_Close_Buffers_Requested,
	Project_Refresh_Requested,
	Project_Command_Menu_Requested,
	Describe_Project_Bindings_Requested,
	Recovery_Requested,
	Describe_Language_State_Requested,
	Describe_Structural_State_Requested,
	Language_Diagnostics_Requested,
	Next_Language_Diagnostic_Requested,
	Previous_Language_Diagnostic_Requested,
	Language_Service_Inspection_Requested,
	Language_Service_Restart_Requested,
	Language_Interaction_Requested,
	Package_Catalog_Interaction_Requested,
	Workspace_Add_Project_Requested,
	Workspace_Remove_Project_Requested,
	Workspace_Unregister_Requested,
	Save_Location_Requested,
	List_Locations_Requested,
	Visit_Location_Requested,
	Store_Number_Requested,
	Increment_Number_Requested,
	Store_Text_Requested,
	Store_Region_Text_Requested,
	Store_Position_Requested,
	Insert_Slot_Requested,
	Store_Layout_Requested,
	Visit_Slot_Requested,
	Restore_Layout_Requested,
	Next_Location_Requested,
	Previous_Location_Requested,
	Symbol_Navigator_Requested,
	Project_Search_Text_Requested,
	Project_Search_Text_Regexp_Requested,
	Project_Search_Repeat_Requested,
	Status_Bar_Inspect_Requested,
	Status_Bar_Actions_Requested,
	Status_Bar_Activate_Segment_Requested,
	Gutter_Command_Requested,
	Maksym_Command_Requested,
	Darek_Command_Requested,
	Completion_Command_Requested,
	Terminal_Command_Requested,
	Ksawery_Status_Requested,
	Jan_Command_Requested,
}

/* Native_Explicit_Range provides one immutable region without publishing selection state. */
Native_Explicit_Range :: struct {
	present:  bool,
	start:    editor.Position,
	end:      editor.Position,
	backward: bool,
}

/* Native_Context contains checked owners and borrowed values for one native dispatch. */
Native_Context :: struct {
	registry:            ^interaction.Command_Registry,
	command:             interaction.Command_Handle,
	buffer:              ^editor.Buffer,
	document:            ^document.Document,
	view_registry:       ^editor_view.Registry,
	view:                editor_view.View_Handle,
	text:                string,
	profile:             display.Display_Profile,
	constraints:         display.Viewport_Constraints,
	temporary_allocator: runtime.Allocator,
	persistent_allocator: runtime.Allocator,
	transaction_id:      edit_transaction.Transaction_ID,
	undo_unit_id:        edit_transaction.Undo_Unit_ID,
	history_store:       ^history.Store,
	location_history:    ^Location_History,
	history_grouping:    history.Grouping_Context,
	kill_ring:           ^kill_ring.Ring,
	kill_sequence_id:    u64,
	event_sequence:      u64,
	yank_context:        ^Yank_Context,
	layout_registry:     ^layout.Registry,
	commit_observer:     edit_transaction.Commit_Observer,
	language_owner:      ^language.Tree_Sitter_Owner,
	language_source:     ^editor.Buffer_Snapshot,
	structural_scope:    language.Structural_Scope,
	editor_session_id:   Editor_Session_ID,
	structural_access:   Structural_Access_Set,
	structural_capability_generation: u64,
	structural_state:    ^Structural_Capability_State,
	cancelled:           bool,
	argument_present:    bool,
	argument:            i64,
	repeat_count:        u64,
	explicit_range:      Native_Explicit_Range,
	replace_text_input:  bool,
	replay_route:        Native_Route,
	replay_entry_route:  Native_Route,
	replay_replace_text: bool,
}

/*
Native_Result reports the complete confirmed native transition.
Call native_result_close after consuming any borrowed commit views.
*/
Native_Result :: struct {
	completion: Native_Completion,
	transaction: edit_transaction.Transaction,
	commit:      edit_transaction.Commit_Result,
	save:       document.Save_Result,
	transfer:   kill_ring.Reservation_Result,
	personal_result: []u8,
	personal_result_allocator: runtime.Allocator,
}

/* Yank_Context retains one exact immediately preceding yank or rotation range. */
Yank_Context :: struct {
	valid:           bool,
	view:            editor_view.View_Handle,
	buffer_id:       editor.Buffer_ID,
	revision:        editor.Revision,
	start:           editor.Byte_Offset,
	end:             editor.Byte_Offset,
	ring_generation: kill_ring.Generation,
	entry_id:        kill_ring.Entry_ID,
}

/* native_result_close releases retained transaction result storage after command consumers finish. */
native_result_close :: proc(result: ^Native_Result) {
	if result == nil {
		return
	}
	if edit_transaction.transaction_is_valid(&result.transaction) {
		closed, close_failure := edit_transaction.transaction_close(&result.transaction)
		assert(closed && close_failure.code == .None)
	}
	result.commit = {}
	if result.personal_result != nil && result.personal_result_allocator.procedure != nil {
		delete(result.personal_result, result.personal_result_allocator)
	}
	result.personal_result = nil
	result.personal_result_allocator = {}
}

/* native_command_definitions returns the semantic native registry declarations. */
native_base_command_definitions :: proc() -> [NATIVE_BASE_COMMAND_COUNT]interaction.Command_Definition {
	return {
		native_definition(.Cursor_Previous_Grapheme, "cursor-previous-grapheme", {.View}, "Move to the previous grapheme."),
		native_definition(.Cursor_Next_Grapheme, "cursor-next-grapheme", {.View}, "Move to the next grapheme."),
		native_definition(.Cursor_Previous_Line, "cursor-previous-line", {.View}, "Move to the previous logical line."),
		native_definition(.Cursor_Next_Line, "cursor-next-line", {.View}, "Move to the next logical line."),
		native_definition(.Cursor_Line_Start, "cursor-line-start", {.View}, "Move to the logical line start."),
		native_definition(.Cursor_Line_End, "cursor-line-end", {.View}, "Move to the logical line end."),
		native_definition(.Cursor_Previous_Word, "cursor-previous-word", {.View}, "Move to the previous word."),
		native_definition(.Cursor_Next_Word, "cursor-next-word", {.View}, "Move to the next word."),
		native_definition(.Cursor_Next_Word_Start, "cursor-next-word-start", {.View}, "Move to the next word start."),
		native_definition(.Cursor_Word_End, "cursor-word-end", {.View}, "Move to the current or next word end."),
		native_definition(.Cursor_Line_First_Non_Whitespace, "cursor-line-first-non-whitespace", {.View}, "Move to the first non-whitespace grapheme on the logical line."),
		native_definition(.Cursor_Buffer_Start, "cursor-buffer-start", {.View}, "Move to the start of the active buffer."),
		native_definition(.Cursor_Buffer_End, "cursor-buffer-end", {.View}, "Move to the end of the active buffer."),
		native_definition(.Goto_Line, "goto-line", {.View}, "Move to a one-based logical line number."),
		native_definition(.Goto_Char, "goto-char", {.View}, "Move to a one-based grapheme position."),
		native_text_argument_definition(.Cursor_Find_Next_Character, "cursor-find-next-character", {.View}, "Move to the next matching character on the logical line."),
		native_text_argument_definition(.Cursor_Find_Previous_Character, "cursor-find-previous-character", {.View}, "Move to the previous matching character on the logical line."),
		native_text_argument_definition(.Cursor_Till_Next_Character, "cursor-till-next-character", {.View}, "Move immediately before the next matching character on the logical line."),
		native_text_argument_definition(.Cursor_Till_Previous_Character, "cursor-till-previous-character", {.View}, "Move immediately after the previous matching character on the logical line."),
		native_definition(.Toggle_Overwrite_Mode, "toggle-overwrite-mode", {.View}, "Enable or disable direct overwrite input."),
		native_definition(.Scroll_Previous_Page, "scroll-previous-page", {.View}, "Move toward the previous viewport page."),
		native_definition(.Scroll_Next_Page, "scroll-next-page", {.View}, "Move toward the next viewport page."),
		native_definition(.Recenter, "recenter", {.View}, "Center point vertically in the active viewport."),
		native_definition(.Help_About_Help, "help-about-help", {.Lifecycle}, "List the built-in help and discovery commands."),
		native_definition(.Apropos_Command, "apropos-command", {.Lifecycle}, "Search registered interactive commands and inspect one selection."),
		native_definition(.Info, "info", {.Lifecycle}, "Open the built-in User Guide index."),
		native_definition(.Describe_Function, "describe-function", {.Lifecycle}, "Select and describe one registered interactive command."),
		native_definition(.Describe_Variable, "describe-variable", {.Lifecycle}, "Inspect Odra configuration owners and their discovery commands."),
		native_definition(.Describe_Syntax_Table, "describe-syntax-table", {.Lifecycle}, "Inspect the active structural syntax provider."),
		native_definition(.Open_Tutorial, "open-tutorial", {.Lifecycle}, "Open the built-in editing tutorial."),
		native_definition(.Select_Word, "select-word", {.View}, "Select the direct-profile word at point."),
		native_definition(.Select_Paragraph, "select-paragraph", {.View}, "Select the logical paragraph at point."),
		native_definition(.Select_Buffer, "select-buffer", {.View}, "Select the complete active buffer."),
		native_definition(.Select_Definition, "select-definition", {.View}, "Select the current language definition at point."),
		native_definition(.Narrow_To_Region, "narrow-to-region", {.View}, "Restrict the active view to the selected region.", {.Active_Buffer, .Active_Region}),
		native_definition(.Narrow_To_Definition, "narrow-to-definition", {.View}, "Restrict the active view to the current language definition."),
		native_definition(.Widen, "widen", {.View}, "Restore the complete active buffer projection."),
		native_definition(.Pop_Selection_Location, "pop-selection-location", {.View}, "Return to the prior retained selection or location."),
		native_definition(.Save_Location, "save-location", {.Lifecycle}, "Save the active location under a persistent name."),
		native_definition(.List_Locations, "list-locations", {.Lifecycle}, "List persistent named locations."),
		native_definition(.Visit_Location, "visit-location", {.Lifecycle}, "Visit one persistent named location."),
		native_definition(.Store_Number, "store-number", {.Lifecycle}, "Store a persistent named integer."),
		native_definition(.Increment_Number, "increment-number", {.Lifecycle}, "Increment a persistent named integer."),
		native_definition(.Store_Text, "store-text", {.Lifecycle}, "Store a persistent named text value."),
		native_definition(.Store_Region_Text, "store-region-text", {.Buffer, .Lifecycle}, "Store the active region as persistent named text.", {.Active_Buffer, .Active_Region}),
		native_definition(.Store_Position, "store-position", {.Lifecycle}, "Store the active document position under a persistent name."),
		native_definition(.Insert_Slot, "insert-slot", {.Buffer, .View, .Text_Mutation}, "Insert one persistent named text value."),
		native_definition(.Store_Layout, "store-layout", {.Lifecycle}, "Store the current portable pane layout."),
		native_definition(.Visit_Slot, "visit-slot", {.Lifecycle}, "Visit one persistent named position or layout."),
		native_definition(.Restore_Layout, "restore-layout", {.Lifecycle}, "Restore one persistent portable pane layout."),
		native_definition(.Next_Location, "next-location", {.View, .Lifecycle}, "Move to the next location from the active source."),
		native_definition(.Previous_Location, "previous-location", {.View, .Lifecycle}, "Move to the previous location from the active source."),
		native_definition(.Symbol_Navigator, "symbol-navigator", {.View, .Lifecycle}, "Open the active buffer symbol index."),
		native_definition(.Project_Search_Text, "project-search-text", {.View, .Lifecycle}, "Search literal text across the active Project."),
		native_definition(.Project_Search_Text_Regexp, "project-search-text-regexp", {.View, .Lifecycle}, "Search a regular expression across the active Project."),
		native_definition(.Project_Search_Repeat, "project-search-repeat", {.View, .Lifecycle}, "Repeat the most recent Project search."),
		native_definition(.Status_Bar_Inspect, "status-bar-inspect", {.View, .Lifecycle}, "Inspect visible Status Bar segments."),
		native_definition(.Status_Bar_Actions, "status-bar-actions", {.View, .Lifecycle}, "List actions exposed by visible Status Bar segments."),
		native_definition(.Status_Bar_Activate_Segment, "status-bar-activate-segment", {.View, .Lifecycle}, "Select and invoke one visible Status Bar segment action."),
		native_definition(.Gutter_Toggle_Line_Numbers, "gutter-toggle-line-numbers", {.View}, "Show or hide line numbers in the active view."),
		native_definition(.Gutter_Cycle_Line_Number_Mode, "gutter-cycle-line-number-mode", {.View}, "Cycle the active view through line-number modes."),
		native_definition(.Gutter_Set_Line_Numbers_None, "gutter-set-line-numbers-none", {.View}, "Disable numbering in the active view."),
		native_definition(.Gutter_Set_Line_Numbers_Absolute, "gutter-set-line-numbers-absolute", {.View}, "Use absolute numbering in the active view."),
		native_definition(.Gutter_Set_Line_Numbers_Relative, "gutter-set-line-numbers-relative", {.View}, "Use relative numbering in the active view."),
		native_definition(.Gutter_Set_Line_Numbers_Hybrid, "gutter-set-line-numbers-hybrid", {.View}, "Use hybrid numbering in the active view."),
		native_definition(.Gutter_Set_Numbering_Logical, "gutter-set-numbering-logical", {.View}, "Use logical-line numbering in the active view."),
		native_definition(.Gutter_Set_Numbering_Visual, "gutter-set-numbering-visual", {.View}, "Request visual-row numbering for the active view."),
		native_definition(.Gutter_Toggle_Line_Number_Side, "gutter-toggle-line-number-side", {.View}, "Move line numbers between the left and right Gutter."),
		native_definition(.Gutter_Inspect_Numbering, "gutter-inspect-numbering", {.View}, "Inspect the active view's effective numbering policy."),
		native_definition(.Gutter_Inspect_Markers, "gutter-inspect-markers", {.View}, "Inspect semantic markers at the active line."),
		native_definition(.Gutter_Refresh_Markers, "gutter-refresh-markers", {.View}, "Refresh semantic markers for the active buffer."),
		native_definition(.Gutter_Invoke_Primary_Marker_Action, "gutter-invoke-primary-marker-action", {.View}, "Invoke the primary semantic marker action at the active line."),
		native_definition(.Complete_At_Point, "complete-at-point", {.View, .Lifecycle}, "Request completion candidates at point."),
		native_definition(.Completion_Next, "completion-next", {.View}, "Select the next completion candidate."),
		native_definition(.Completion_Previous, "completion-previous", {.View}, "Select the previous completion candidate."),
		native_definition(.Completion_First, "completion-first", {.View}, "Select the first completion candidate."),
		native_definition(.Completion_Last, "completion-last", {.View}, "Select the last completion candidate."),
		native_definition(.Completion_Accept, "completion-accept", {.Buffer, .View, .Text_Mutation}, "Accept the selected completion candidate."),
		native_definition(.Completion_Cancel, "completion-cancel", {.View}, "Cancel the active completion interaction."),
		native_definition(.Completion_Inspect, "completion-inspect", {.View, .Lifecycle}, "Inspect the active completion candidate."),
		native_definition(.Completion_Show_Documentation, "completion-show-documentation", {.View, .Lifecycle}, "Show documentation for the active completion candidate."),
		native_definition(.Describe_Completion_State, "describe-completion-state", {.Lifecycle}, "Inspect the active completion session and provider state."),
		native_definition(.Ksawery_Status, "ksawery-status", {.Lifecycle}, "Open repository Status in a full-canvas Ksawery session."),
		native_definition(.Maksym_Open_Directory, "maksym-open-directory", {.View, .Lifecycle}, "Select and open one directory in Maksym."),
		native_definition(.Maksym_Open_Directory_Other_Pane, "maksym-open-directory-other-pane", {.View, .Lifecycle}, "Select and open one directory in another pane."),
		native_definition(.Maksym_Open_Directory_Below, "maksym-open-directory-below", {.View, .Lifecycle}, "Split below and open one selected directory there."),
		native_definition(.Maksym_Open_Directory_Right, "maksym-open-directory-right", {.View, .Lifecycle}, "Split right and open one selected directory there."),
		native_definition(.Maksym_Open_Containing_Directory, "maksym-open-containing-directory", {.View, .Lifecycle}, "Open the active document directory and select its entry."),
		native_definition(.Maksym_Open_Containing_Directory_Other_Pane, "maksym-open-containing-directory-other-pane", {.View, .Lifecycle}, "Open the active document directory in another pane and select its entry."),
		native_definition(.Maksym_Next_Entry, "maksym-next-entry", {.View}, "Move to the next Maksym entry."),
		native_definition(.Maksym_Previous_Entry, "maksym-previous-entry", {.View}, "Move to the previous Maksym entry."),
		native_definition(.Maksym_Parent_Directory, "maksym-parent-directory", {.View, .Lifecycle}, "Open the parent directory in Maksym."),
		native_definition(.Maksym_Jump_To_Entry, "maksym-jump-to-entry", {.View, .Lifecycle}, "Select and visit one entry in the active Maksym buffer."),
		native_definition(.Maksym_Open_Entry, "maksym-open-entry", {.View, .Lifecycle}, "Open the selected Maksym entry."),
		native_definition(.Maksym_Open_Entry_Other_Pane, "maksym-open-entry-other-pane", {.View, .Lifecycle}, "Open the selected Maksym entry in another pane."),
		native_definition(.Maksym_Display_Entry_Other_Pane, "maksym-display-entry-other-pane", {.View, .Lifecycle}, "Display the selected Maksym entry in another pane without changing focus."),
		native_definition(.Maksym_Refresh, "maksym-refresh", {.View, .Lifecycle}, "Refresh the active Maksym directory generation."),
		native_definition(.Maksym_Toggle_Details, "maksym-toggle-details", {.View, .Lifecycle}, "Toggle Maksym listing metadata."),
		native_definition(.Maksym_Cycle_Sort, "maksym-cycle-sort", {.View, .Lifecycle}, "Cycle the active Maksym listing sort order."),
		native_definition(.Maksym_Toggle_Editable_Listing, "maksym-toggle-editable-listing", {.View, .Lifecycle}, "Enter or leave editable filename mode for the active Maksym listing."),
		native_definition(.Maksym_Apply_Editable_Listing, "maksym-apply-editable-listing", {.View, .Lifecycle}, "Validate, review, and apply prepared Maksym filename changes."),
		native_definition(.Maksym_Cancel_Editable_Listing, "maksym-cancel-editable-listing", {.View, .Lifecycle}, "Discard prepared Maksym filename changes."),
		native_definition(.Maksym_Editable_Next_Line, "maksym-editable-next-line", {.View}, "Move to the next editable Maksym filename."),
		native_definition(.Maksym_Editable_Previous_Line, "maksym-editable-previous-line", {.View}, "Move to the previous editable Maksym filename."),
		native_definition(.Darek_Toggle, "darek-toggle", {.View, .Lifecycle}, "Show or hide the Darek tree panel."),
		native_definition(.Darek_Select, "darek-select", {.View, .Lifecycle}, "Show and focus the Darek tree panel."),
		native_definition(.Darek_Focus_Toggle, "darek-focus-toggle", {.View, .Lifecycle}, "Exchange focus between Darek and the most recent ordinary pane."),
		native_definition(.Darek_Show_Directory, "darek-show-directory", {.View, .Lifecycle}, "Select and show one local directory in Darek."),
		native_definition(.Darek_Find_Current_File, "darek-find-current-file", {.View, .Lifecycle}, "Reveal the active document file in Darek."),
		native_definition(.Darek_Show_Current_Project, "darek-show-current-project", {.View, .Lifecycle}, "Show the active Project in Darek."),
		native_definition(.Darek_Next_Node, "darek-next-node", {.View}, "Move to the next visible Darek node."),
		native_definition(.Darek_Previous_Node, "darek-previous-node", {.View}, "Move to the previous visible Darek node."),
		native_definition(.Darek_Next_Sibling, "darek-next-sibling", {.View}, "Move to the next visible Darek sibling."),
		native_definition(.Darek_Previous_Sibling, "darek-previous-sibling", {.View}, "Move to the previous visible Darek sibling."),
		native_definition(.Darek_Next_Project, "darek-next-project", {.View}, "Move to the next visible Darek Project root."),
		native_definition(.Darek_Previous_Project, "darek-previous-project", {.View}, "Move to the previous visible Darek Project root."),
		native_definition(.Darek_Move_Project_Up, "darek-move-project-up", {.View, .Lifecycle}, "Move the current Darek Project earlier in its Workspace."),
		native_definition(.Darek_Move_Project_Down, "darek-move-project-down", {.View, .Lifecycle}, "Move the current Darek Project later in its Workspace."),
		native_definition(.Darek_Project_Add, "darek-project-add", {.View, .Lifecycle}, "Add a registered Project to the current Darek Workspace."),
		native_definition(.Darek_Project_Remove, "darek-project-remove", {.View, .Lifecycle}, "Remove the current Project from the Darek Workspace."),
		native_definition(.Darek_Project_Rename, "darek-project-rename", {.View, .Lifecycle}, "Rename the current Darek Project."),
		native_definition(.Darek_Project_Collapse, "darek-project-collapse", {.View}, "Collapse the current Darek Project root."),
		native_definition(.Darek_Project_Collapse_Others, "darek-project-collapse-others", {.View}, "Collapse every other Darek Project root."),
		native_definition(.Darek_Workspace_Switch, "darek-workspace-switch", {.View, .Lifecycle}, "Select a registered Workspace for Darek."),
		native_definition(.Darek_Workspace_Next, "darek-workspace-next", {.View, .Lifecycle}, "Select the next registered Workspace for Darek."),
		native_definition(.Darek_Root_Parent, "darek-root-parent", {.View, .Lifecycle}, "Show the parent of the exclusive Darek root."),
		native_definition(.Darek_Root_Current_Directory, "darek-root-current-directory", {.View, .Lifecycle}, "Show the selected Darek directory as the exclusive root."),
		native_definition(.Darek_Parent_Node, "darek-parent-node", {.View}, "Move to the visible parent Darek node."),
		native_definition(.Darek_Structure_Action, "darek-structure-action", {.View}, "Expand, collapse, or visit the selected Darek node."),
		native_definition(.Darek_Visit_Action, "darek-visit-action", {.View, .Lifecycle}, "Visit the selected Darek node."),
		native_definition(.Darek_Open, "darek-open", {.View, .Lifecycle}, "Open the selected Darek node in the current destination."),
		native_definition(.Darek_Open_Split_Below, "darek-open-split-below", {.View, .Lifecycle}, "Open the selected Darek node in a new pane below."),
		native_definition(.Darek_Open_Split_Right, "darek-open-split-right", {.View, .Lifecycle}, "Open the selected Darek node in a new pane to the right."),
		native_definition(.Darek_Open_And_Hide, "darek-open-and-hide", {.View, .Lifecycle}, "Open the selected Darek node and hide Darek."),
		native_definition(.Darek_Open_Mru_Pane, "darek-open-mru-pane", {.View, .Lifecycle}, "Open the selected Darek node in the most recent eligible pane."),
		native_definition(.Darek_Open_External, "darek-open-external", {.View, .Lifecycle}, "Open the selected Darek node through an external provider."),
		native_definition(.Darek_Create_File, "darek-create-file", {.View, .Lifecycle}, "Create a file beneath the resolved Darek directory."),
		native_definition(.Darek_Create_Directory, "darek-create-directory", {.View, .Lifecycle}, "Create a directory beneath the resolved Darek directory."),
		native_definition(.Darek_Rename_Node, "darek-rename-node", {.View, .Lifecycle}, "Rename the selected Darek filesystem node."),
		native_definition(.Darek_Move_Node, "darek-move-node", {.View, .Lifecycle}, "Move the selected Darek filesystem node."),
		native_definition(.Darek_Copy_Node, "darek-copy-node", {.View, .Lifecycle}, "Copy the selected Darek filesystem node."),
		native_definition(.Darek_Delete_Node, "darek-delete-node", {.View, .Lifecycle}, "Review and permanently delete the selected Darek filesystem node."),
		native_definition(.Darek_Copy_Absolute_Path, "darek-copy-absolute-path", {.View, .Lifecycle}, "Retain the selected Darek node absolute path."),
		native_definition(.Darek_Copy_Project_Relative_Path, "darek-copy-project-relative-path", {.View, .Lifecycle}, "Retain the selected Darek node path relative to its Project."),
		native_definition(.Darek_Copy_Project_Root, "darek-copy-project-root", {.View, .Lifecycle}, "Retain the selected Darek node Project root."),
		native_definition(.Darek_Copy_Name, "darek-copy-name", {.View, .Lifecycle}, "Retain the selected Darek node filesystem name."),
		native_definition(.Darek_Collapse_Or_Parent, "darek-collapse-or-parent", {.View}, "Collapse the selected Darek node or move to its parent."),
		native_definition(.Darek_Collapse_Parent, "darek-collapse-parent", {.View}, "Collapse the selected Darek node parent."),
		native_definition(.Darek_Collapse_All_Projects, "darek-collapse-all-projects", {.View}, "Collapse every visible Darek Project root."),
		native_definition(.Darek_Refresh, "darek-refresh", {.View}, "Refresh the selected Darek directory generation."),
		native_definition(.Darek_Toggle_Peek, "darek-toggle-peek", {.View, .Lifecycle}, "Enable or disable preview of the selected Darek file."),
		native_definition(.Darek_Other_Pane_Next_Line, "darek-other-pane-next-line", {.View}, "Scroll the Darek preview pane forward by one line."),
		native_definition(.Darek_Other_Pane_Previous_Line, "darek-other-pane-previous-line", {.View}, "Scroll the Darek preview pane backward by one line."),
		native_definition(.Darek_Other_Pane_Next_Page, "darek-other-pane-next-page", {.View}, "Scroll the Darek preview pane forward by one page."),
		native_definition(.Darek_Other_Pane_Previous_Page, "darek-other-pane-previous-page", {.View}, "Scroll the Darek preview pane backward by one page."),
		native_definition(.Darek_Toggle_File_Follow, "darek-toggle-file-follow", {.View, .Lifecycle}, "Enable or disable revealing the active document in Darek."),
		native_definition(.Darek_Toggle_Hidden_Files, "darek-toggle-hidden-files", {.View, .Lifecycle}, "Show or hide dot-prefixed Darek entries."),
		native_definition(.Darek_Toggle_VCS_Ignored, "darek-toggle-vcs-ignored", {.View, .Lifecycle}, "Show or hide Darek entries marked ignored by the active version-control provider."),
		native_definition(.Darek_Toggle_File_Watch, "darek-toggle-file-watch", {.View, .Lifecycle}, "Enable or disable bounded filesystem watch reconciliation."),
		native_definition(.Darek_Toggle_VCS_Decorations, "darek-toggle-vcs-decorations", {.View, .Lifecycle}, "Show or hide copied version-control decorations in Darek."),
		native_definition(.Darek_Toggle_Diagnostics, "darek-toggle-diagnostics", {.View, .Lifecycle}, "Show or hide copied diagnostic decorations in Darek."),
		native_definition(.Darek_Select_Sort, "darek-select-sort", {.View, .Lifecycle}, "Select the deterministic Darek sibling ordering."),
		native_definition(.Darek_Filter, "darek-filter", {.View, .Lifecycle}, "Filter Darek by a bounded copied name substring."),
		native_definition(.Darek_Panel_Left, "darek-panel-left", {.View, .Lifecycle}, "Place Darek at the left editor edge."),
		native_definition(.Darek_Panel_Right, "darek-panel-right", {.View, .Lifecycle}, "Place Darek at the right editor edge."),
		native_definition(.Darek_Decrease_Width, "darek-decrease-width", {.View, .Lifecycle}, "Reduce Darek width by one bounded step."),
		native_definition(.Darek_Increase_Width, "darek-increase-width", {.View, .Lifecycle}, "Increase Darek width by one bounded step."),
		native_definition(.Darek_Fit_Width, "darek-fit-width", {.View, .Lifecycle}, "Fit Darek width to visible bounded content."),
		native_definition(.Darek_Toggle_Extra_Width, "darek-toggle-extra-width", {.View, .Lifecycle}, "Exchange Darek normal and extra-wide widths."),
		native_definition(.Darek_Toggle_Width_Lock, "darek-toggle-width-lock", {.View, .Lifecycle}, "Enable or disable automatic Darek width fitting."),
		native_definition(.Darek_Toggle_Directory_Compression, "darek-toggle-directory-compression", {.View, .Lifecycle}, "Enable or disable compact single-directory hierarchy indentation."),
		native_definition(.Darek_Narrow_Current_Project, "darek-narrow-current-project", {.View, .Lifecycle}, "Show only the current Project tree in Darek."),
		native_definition(.Darek_Show_All_Projects, "darek-show-all-projects", {.View, .Lifecycle}, "Show every Darek Project root."),
		native_definition(.Darek_Shell_Command, "darek-shell-command", {.View, .Lifecycle}, "Run a shell command from the selected Darek context."),
		native_definition(.Darek_Shell_Command_Project, "darek-shell-command-project", {.View, .Lifecycle}, "Run a shell command from the selected Darek Project root."),
		native_definition(.Darek_Bulk_Actions, "darek-bulk-actions", {.View, .Lifecycle}, "Open the selected Darek context in Maksym for checked bulk actions."),
		native_definition(.Darek_Context_Actions, "darek-context-actions", {.View, .Lifecycle}, "List commands applicable to the selected Darek node."),
		native_definition(.Darek_Help, "darek-help", {.View, .Lifecycle}, "Describe effective Darek commands and bindings."),
		native_definition(.Darek_Help_Advanced, "darek-help-advanced", {.View, .Lifecycle}, "Describe the complete effective Darek command and prefix map."),
		native_definition(.Darek_Hide, "darek-hide", {.View, .Lifecycle}, "Hide Darek while preserving its view state."),
		native_definition(.Darek_Close, "darek-close", {.View, .Lifecycle}, "Close Darek and release its retained state."),
		native_definition(.ISearch_Forward, "isearch-forward", {.View}, "Start or repeat forward incremental literal search."),
		native_definition(.ISearch_Backward, "isearch-backward", {.View}, "Start or repeat backward incremental literal search."),
		native_definition(.ISearch_Forward_Regexp, "isearch-forward-regexp", {.View}, "Start or repeat forward incremental regular-expression search."),
		native_definition(.ISearch_Backward_Regexp, "isearch-backward-regexp", {.View}, "Start or repeat backward incremental regular-expression search."),
		native_definition(.Search_Symbol_At_Point, "search-symbol-at-point", {.View}, "Search forward for the symbol at point."),
		native_definition(.Search_Word, "search-word", {.View}, "Search forward for words matching entered text."),
		native_definition(.Occur, "occur", {.View, .Lifecycle}, "List lines matching a regular expression."),
		native_definition(.Highlight_Symbol_At_Point, "highlight-symbol-at-point", {.View}, "Highlight every match for the symbol at point."),
		native_definition(.Highlight_Phrase, "highlight-phrase", {.View}, "Highlight every match for entered text."),
		native_definition(.Highlight_Regexp, "highlight-regexp", {.View}, "Highlight every match for an entered regular expression."),
		native_definition(.Highlight_Lines, "highlight-lines-matching-regexp", {.View}, "Highlight matches on lines selected by a regular expression."),
		native_definition(.Highlight_Remove, "unhighlight-regexp", {.View}, "Remove the active search highlight."),
		native_definition(.Search_Next_Occurrence, "search-next-occurrence", {.View}, "Visit the next occurrence from the most recent confirmed search."),
		native_definition(.Search_Previous_Occurrence, "search-previous-occurrence", {.View}, "Visit the previous occurrence from the most recent confirmed search."),
		native_definition(.Query_Replace, "query-replace", {.Buffer, .View, .Text_Mutation}, "Start interactive literal query replacement."),
		native_definition(.Query_Replace_Regexp, "query-replace-regexp", {.Buffer, .View, .Text_Mutation}, "Start interactive regular-expression query replacement."),
		native_definition(.Replace_String, "replace-string", {.Buffer, .View, .Text_Mutation}, "Replace every admitted literal match atomically."),
		native_definition(.Replace_Regexp, "replace-regexp", {.Buffer, .View, .Text_Mutation}, "Replace every admitted regular-expression match atomically."),
		{
			name = "insert-text",
			route = native_route(.Insert_Text),
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
			effects = {.Buffer, .View, .Text_Mutation},
			description = "Insert committed text at the primary cursor.",
			provenance = native_command_provenance(),
		},
		{
			name = "insert-text-after-point",
			route = native_route(.Insert_Text_After_Point),
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Required,
			effects = {.Buffer, .View, .Text_Mutation},
			description = "Insert admitted text after the current grapheme.",
			provenance = native_command_provenance(),
		},
		native_definition(.Delete_Previous_Grapheme, "delete-previous-grapheme", {.Buffer, .View, .Text_Mutation}, "Delete the previous grapheme."),
		native_definition(.Delete_Next_Grapheme, "delete-next-grapheme", {.Buffer, .View, .Text_Mutation}, "Delete the next grapheme."),
		native_definition(.Insert_Line_Break, "insert-line-break", {.Buffer, .View, .Text_Mutation}, "Insert one canonical line feed."),
		native_definition(.Insert_Indentation, "insert-indentation", {.Buffer, .View, .Text_Mutation}, "Insert one resolved indentation unit."),
		native_definition(.Indent_Lines, "indent-lines", {.Buffer, .View, .Text_Mutation}, "Indent every logical line intersecting the active range."),
		native_definition(.Outdent_Lines, "outdent-lines", {.Buffer, .View, .Text_Mutation}, "Outdent every logical line intersecting the active range."),
		native_definition(.Indent_Rigidly, "indent-rigidly", {.View, .Lifecycle}, "Begin checked rigid indentation for the active region.", {.Active_Buffer, .Active_Region}),
		native_definition(.Rigid_Indent_Right, "rigid-indent-right", {.Buffer, .View, .Text_Mutation}, "Increase active rigid indentation by one column."),
		native_definition(.Rigid_Indent_Left, "rigid-indent-left", {.Buffer, .View, .Text_Mutation}, "Decrease active rigid indentation by one column."),
		native_definition(.Rigid_Indent_Right_Fast, "rigid-indent-right-fast", {.Buffer, .View, .Text_Mutation}, "Increase active rigid indentation by one indentation width."),
		native_definition(.Rigid_Indent_Left_Fast, "rigid-indent-left-fast", {.Buffer, .View, .Text_Mutation}, "Decrease active rigid indentation by one indentation width."),
		native_definition(.Normalize_Indentation_To_Tabs, "normalize-indentation-to-tabs", {.Buffer, .View, .Text_Mutation}, "Convert leading indentation to literal tabs."),
		native_definition(.Normalize_Indentation_To_Spaces, "normalize-indentation-to-spaces", {.Buffer, .View, .Text_Mutation}, "Convert leading indentation to spaces."),
		native_definition(.Undo, "undo", {.Buffer, .View, .Text_Mutation}, "Undo one user-visible edit unit."),
		native_definition(.Redo, "redo", {.Buffer, .View, .Text_Mutation}, "Redo the preferred user-visible edit unit."),
		native_definition(.Save_Associated_Document, "save-associated-document", {.Lifecycle}, "Save the associated document."),
		native_definition(.Set_Mark, "set-mark-command", {.View}, "Set mark at point and activate the region."),
		native_definition(.Deactivate_Mark, "deactivate-mark", {.View}, "Deactivate the region while retaining mark."),
		native_definition(.Exchange_Point_And_Mark, "exchange-point-and-mark", {.View}, "Exchange point and mark and activate the region."),
		native_definition(.Copy_Region, "copy-region", {.Buffer}, "Copy the active region into retained text.", {.Active_Buffer, .Active_Region}),
		native_definition(.Kill_Region, "kill-region", {.Buffer, .View, .Text_Mutation}, "Copy and reversibly delete the active region.", {.Active_Buffer, .Active_Region}),
		native_definition(.Kill_Line, "kill-line", {.Buffer, .View, .Text_Mutation}, "Kill text from point through the logical line end."),
		native_definition(.Backward_Kill_Word, "backward-kill-word", {.Buffer, .View, .Text_Mutation}, "Kill the previous word."),
		native_definition(.Kill_Word, "kill-word", {.Buffer, .View, .Text_Mutation}, "Kill the next word."),
		native_definition(.Delete_Region, "delete-region", {.Buffer, .View, .Text_Mutation}, "Reversibly delete the active region without retaining it.", {.Active_Buffer, .Active_Region}),
		native_definition(.Delete_Blank_Lines, "delete-blank-lines", {.Buffer, .View, .Text_Mutation}, "Delete surrounding blank logical lines."),
		native_definition(.Fill_Paragraph, "fill-paragraph", {.Buffer, .View, .Text_Mutation}, "Reflow the paragraph at point."),
		native_definition(.Transpose_Words, "transpose-words", {.Buffer, .View, .Text_Mutation}, "Transpose the words around point."),
		native_definition(.Upcase_Word, "upcase-word", {.Buffer, .View, .Text_Mutation}, "Uppercase the next word."),
		native_definition(.Downcase_Word, "downcase-word", {.Buffer, .View, .Text_Mutation}, "Lowercase the next word."),
		native_definition(.Capitalize_Word, "capitalize-word", {.Buffer, .View, .Text_Mutation}, "Capitalize the next word."),
		native_definition(.Comment_Dwim, "comment-dwim", {.Buffer, .View, .Text_Mutation}, "Add or remove a context-appropriate comment."),
		native_definition(.Dynamic_Abbrev_Expand, "dabbrev-expand", {.Buffer, .View, .Text_Mutation}, "Expand the word prefix before point from buffer text."),
		native_definition(.Yank, "yank", {.Buffer, .View, .Text_Mutation}, "Insert the newest retained text entry."),
		native_definition(.Yank_After_Point, "yank-after-point", {.Buffer, .View, .Text_Mutation}, "Insert the newest retained text entry after the current grapheme."),
		native_definition(.Yank_Pop, "yank-pop", {.Buffer, .View, .Text_Mutation}, "Replace the preceding yank with the next retained entry."),
		{
			name = "replace-region-text",
			route = native_route(.Replace_Region_Text),
			implementation = .Native,
			invocation = .Ordinary,
			text_requirement = .Required,
			effects = {.Buffer, .View, .Text_Mutation},
			description = "Replace one explicit or active region with admitted text.",
			provenance = native_command_provenance(),
		},
		native_definition(.Find_File, "find-file", {.Lifecycle}, "Open or select a local file buffer."),
		native_definition(.Find_Alternate_File, "find-alternate-file", {.Lifecycle}, "Replace the current clean buffer with another local file."),
		native_definition(.Write_File, "write-file", {.Lifecycle}, "Save the current buffer to a selected file and visit that file."),
		native_definition(.Save_Some_Buffers, "save-some-buffers", {.Lifecycle}, "Review or save every modified file-visiting buffer in the current session."),
		native_optional_text_definition(.Insert_File, "insert-file", {.Buffer, .View, .Lifecycle, .Text_Mutation}, "Insert the contents of a selected local file at point."),
		native_definition(.Toggle_Read_Only, "toggle-read-only", {.Lifecycle}, "Enable or disable mutation of the current text buffer."),
		native_definition(.Next_Buffer, "next-buffer", {.Lifecycle}, "Select the next buffer in stable session order."),
		native_definition(.Previous_Buffer, "previous-buffer", {.Lifecycle}, "Select the previous buffer in stable session order."),
		native_definition(.Switch_To_Buffer, "switch-to-buffer", {.Lifecycle}, "Select a live buffer or create a named buffer."),
		native_definition(.Find_File_Other_Pane, "find-file-other-pane", {.Lifecycle}, "Open or select a local file buffer in another pane and focus it."),
		native_definition(.Switch_To_Buffer_Other_Pane, "switch-to-buffer-other-pane", {.Lifecycle}, "Show a live or newly named buffer in another pane and focus it."),
		native_definition(.Display_Buffer_Other_Pane, "display-buffer-other-pane", {.Lifecycle}, "Display a selected buffer in another pane without changing focus."),
		native_definition(.Kill_Buffer, "kill-buffer", {.Lifecycle}, "Close one selected buffer with dirty-state protection."),
		native_definition(.List_Buffers, "list-buffers", {.Lifecycle}, "Present the live buffer inventory."),
		native_definition(
			.Reload_Interaction_Profile,
			"reload-interaction-profile",
			{.Lifecycle},
			"Reload the staged interaction profile for this editor session.",
		),
		native_definition(
			.Reload_Personal_Commands,
			"reload-personal-commands",
			{.Lifecycle},
			"Reload personal commands and their interaction profile.",
		),
		native_definition(
			.Execute_Extended_Command,
			"execute-extended-command",
			{.Lifecycle},
			"Select and execute a registered interactive command.",
		),
		native_definition(
			.Select_Interaction_Profile,
			"select-interaction-profile",
			{.Lifecycle},
			"Select one interaction profile for this editor session.",
		),
		native_definition(
			.Modal_Enter_Insert,
			"modal-enter-insert",
			{.Lifecycle},
			"Enter the modal profile Insert state at point.",
		),
		native_definition(
			.Modal_Enter_Insert_After,
			"modal-enter-insert-after",
			{.View, .Lifecycle},
			"Move after the current grapheme and enter the modal profile Insert state.",
		),
		native_definition(
			.Modal_Enter_Replace,
			"modal-enter-replace",
			{.Lifecycle},
			"Enter the modal profile Replace state at point.",
		),
		native_definition(
			.Modal_Enter_Normal,
			"modal-enter-normal",
			{.Lifecycle},
			"Cancel modal input and enter the modal profile Normal state.",
		),
		native_optional_text_definition(
			.Modal_Repeat_Last_Change,
			"modal-repeat-last-change",
			{.Buffer, .View, .Text_Mutation},
			"Repeat the most recent admitted modal change in the current context.",
		),
		native_definition(
			.Describe_Modal_Repeat,
			"describe-modal-repeat",
			{.Lifecycle},
			"Inspect the bounded semantic record used by modal last-change repetition.",
		),
		native_definition(
			.Start_Keyboard_Macro,
			"start-kbd-macro",
			{.Lifecycle},
			"Start recording canonical commands into a fresh keyboard macro.",
		),
		native_definition(
			.End_Keyboard_Macro,
			"end-kbd-macro",
			{.Lifecycle},
			"Finish recording and retain the current keyboard macro.",
		),
		native_definition(
			.Call_Last_Keyboard_Macro,
			"call-last-kbd-macro",
			{.Buffer, .View, .Lifecycle, .Text_Mutation},
			"Replay the most recently completed keyboard macro.",
		),
		native_definition(
			.Finish_Or_Call_Keyboard_Macro,
			"kmacro-end-or-call-macro",
			{.Buffer, .View, .Lifecycle, .Text_Mutation},
			"Finish recording or replay the most recently completed keyboard macro.",
		),
		native_definition(
			.Name_Last_Keyboard_Macro,
			"name-last-kbd-macro",
			{.Lifecycle},
			"Retain the most recent keyboard macro under a session-local name.",
		),
		native_definition(
			.Call_Named_Keyboard_Macro,
			"call-named-kbd-macro",
			{.Lifecycle},
			"Replay a session-local named keyboard macro.",
		),
		native_definition(
			.Select_Rectangle,
			"select-rectangle",
			{.View},
			"Project the active canonical region as a logical grapheme rectangle.",
			{.Active_Buffer, .Active_Region},
		),
		native_definition(
			.Copy_Rectangle,
			"copy-rectangle",
			{.Buffer},
			"Copy the active logical rectangle as newline-separated retained text.",
			{.Active_Buffer, .Active_Region},
		),
		native_definition(
			.Kill_Rectangle,
			"kill-rectangle",
			{.Buffer, .View, .Text_Mutation},
			"Remove and retain every range in the active logical rectangle atomically.",
			{.Active_Buffer, .Active_Region},
		),
		native_text_argument_definition(
			.Replace_Rectangle_Text,
			"replace-rectangle-text",
			{.Buffer, .View, .Text_Mutation},
			"Replace every range in the active logical rectangle atomically.",
			{.Active_Buffer, .Active_Region},
		),
		native_definition(
			.Modal_Enter_Visual_Character,
			"modal-enter-visual-character",
			{.View, .Lifecycle},
			"Enter the modal profile Visual Character state over the canonical region.",
		),
		native_definition(
			.Modal_Enter_Visual_Line,
			"modal-enter-visual-line",
			{.View, .Lifecycle},
			"Enter the modal profile Visual Line state over the canonical region.",
		),
		native_definition(
			.Modal_Enter_Visual_Block,
			"modal-enter-visual-block",
			{.View, .Lifecycle},
			"Enter the modal profile Visual Block state over a logical rectangle.",
		),
		native_definition(
			.Modal_Enter_Insert_Line_First,
			"modal-enter-insert-line-first",
			{.View, .Lifecycle},
			"Move to the first non-whitespace boundary and enter the modal profile Insert state.",
		),
		native_definition(
			.Modal_Enter_Insert_Line_End,
			"modal-enter-insert-line-end",
			{.View, .Lifecycle},
			"Move to the logical line end and enter the modal profile Insert state.",
		),
		native_definition(
			.Modal_Open_Line_Below,
			"modal-open-line-below",
			{.Buffer, .View, .Lifecycle, .Text_Mutation},
			"Insert one logical line below and enter the modal profile Insert state.",
		),
		native_definition(
			.Modal_Open_Line_Above,
			"modal-open-line-above",
			{.Buffer, .View, .Lifecycle, .Text_Mutation},
			"Insert one logical line above and enter the modal profile Insert state.",
		),
		native_definition(
			.Select_Theme,
			"select-theme",
			{.Lifecycle},
			"Select one confirmed session theme.",
		),
		native_definition(
			.Describe_Theme,
			"describe-theme",
			{.Lifecycle},
			"Inspect the active session theme and registry policy.",
		),
		native_definition(
			.Dir_Open,
			"open-directory",
			{.Lifecycle},
			"Open one local Dir without creating a Project.",
			{},
		),
		native_definition(
			.Project_Inspect_Active,
			"describe-project",
			{.Lifecycle},
			"Inspect the active Project identity and root summary.",
			{},
		),
		native_definition(
			.Project_Promote,
			"project-promote",
			{.Lifecycle},
			"Save the active Dir as a Project.",
			{},
		),
		native_definition(
			.Project_Unregister,
			"project-unregister",
			{.Lifecycle},
			"Remove one selected Project from the global Project registry.",
			{},
		),
		native_definition(
			.Workspace_Add_Project,
			"workspace-add-project",
			{.Lifecycle},
			"Add one selected Project to one selected Workspace.",
			{},
		),
		native_definition(
			.Workspace_Remove_Project,
			"workspace-remove-project",
			{.Lifecycle},
			"Remove one selected Project from one selected Workspace.",
			{},
		),
		native_definition(
			.Workspace_Unregister,
			"workspace-unregister",
			{.Lifecycle},
			"Remove one selected Workspace from the global Workspace registry.",
			{},
		),
		native_definition(.Project_Find_File, "project-find-file", {.Lifecycle}, "Select and open one file in the active Project.", {}),
		native_definition(.Project_Switch_Buffer, "project-switch-buffer", {.Lifecycle}, "Select one live buffer owned by the active Project.", {}),
		native_definition(.Project_Save_Buffers, "project-save-buffers", {.Lifecycle}, "Save modified file-backed buffers owned by the active Project.", {}),
		native_definition(.Project_Close_Buffers, "project-close-buffers", {.Lifecycle}, "Close active Project buffers with ordinary dirty-state protection.", {}),
		native_definition(.Project_Refresh, "project-refresh", {.Lifecycle}, "Reconcile active Project directory observations.", {}),
		native_definition(.Project_Command_Menu, "project-command-menu", {.Lifecycle}, "Present the active Project command collection.", {}),
		native_definition(.Describe_Project_Bindings, "describe-project-bindings", {.Lifecycle}, "Inspect effective and reserved Project-prefix bindings.", {}),
		native_definition(.Recover_Unsaved_Work, "recover-unsaved-work", {.Lifecycle}, "Review retained unsaved-work recovery candidates.", {}),
		native_definition(.Describe_Language_State, "describe-language-state", {.Lifecycle}, "Inspect copied language-analysis state for the active buffer.", {}),
		native_definition(.Jan_Inspect_Syntax, "jan-inspect-syntax", {.Lifecycle}, "Inspect Jan syntax, attributes, generations, and recovery at point."),
		native_definition(.Jan_Lint, "jan-lint", {.Lifecycle}, "Produce bounded read-only Jan diagnostics for the current revision."),
		native_definition(.Jan_Lint_Refresh, "jan-lint-refresh", {.Lifecycle}, "Recompute bounded Jan diagnostics for the current revision."),
		native_definition(.Jan_Language_Status, "jan-language-status", {.Lifecycle}, "Inspect Jan recognition, provider, baseline, limits, and latest rejection."),
		native_definition(.Describe_Structural_State, "describe-structural-state", {.Lifecycle}, "Inspect copied structural syntax state for the active buffer.", {}),
		native_definition(.List_Language_Diagnostics, "list-language-diagnostics", {.View, .Lifecycle}, "Present current diagnostics for the active buffer or Project."),
		native_definition(.Next_Language_Diagnostic, "next-language-diagnostic", {.View, .Lifecycle}, "Move to the next current diagnostic."),
		native_definition(.Previous_Language_Diagnostic, "previous-language-diagnostic", {.View, .Lifecycle}, "Move to the previous current diagnostic."),
		language_document_command_definition(.Describe_Language_Support, "describe-language-support", {.Lifecycle}, "Inspect effective language and service catalogs for the active document."),
		language_document_command_definition(.Describe_Language_Service, "describe-language-service", {.Lifecycle}, "Inspect the selected language service and its current health."),
		language_document_command_definition(.Restart_Language_Service, "restart-language-service", {.Lifecycle}, "Spend one bounded restart attempt for the selected failed language service."),
		native_definition(.Structural_Forward, "structural-forward", {.View}, "Move to the end of the next named structural node."),
		native_definition(.Structural_Backward, "structural-backward", {.View}, "Move to the start of the previous named structural node."),
		native_definition(.Structural_Up, "structural-up", {.View}, "Move to the start of the enclosing named structural node."),
		native_definition(.Structural_Down, "structural-down", {.View}, "Move to the start of the first named child structural node."),
		native_definition(.Structural_Select, "structural-select", {.View}, "Select the enclosing named structural node."),
		native_definition(.Structural_Indent, "structural-indent", {.Buffer, .View, .Text_Mutation}, "Indent the active structural range."),
		native_definition(.Split_Pane_Below, "split-pane-below", {.Lifecycle}, "Split the active pane below."),
		native_definition(.Split_Pane_Right, "split-pane-right", {.Lifecycle}, "Split the active pane to the right."),
		native_definition(.Close_Pane, "close-pane", {.Lifecycle}, "Close the active non-final pane."),
		native_definition(.Keep_Only_Pane, "keep-only-pane", {.Lifecycle}, "Keep only the active pane."),
		native_definition(.Focus_Next_Pane, "focus-next-pane", {.Lifecycle}, "Focus the next pane in spatial order."),
		native_definition(.Focus_Pane_Left, "focus-pane-left", {.Lifecycle}, "Focus the adjacent pane to the left."),
		native_definition(.Focus_Pane_Down, "focus-pane-down", {.Lifecycle}, "Focus the adjacent pane below."),
		native_definition(.Focus_Pane_Up, "focus-pane-up", {.Lifecycle}, "Focus the adjacent pane above."),
		native_definition(.Focus_Pane_Right, "focus-pane-right", {.Lifecycle}, "Focus the adjacent pane to the right."),
		native_definition(.Enlarge_Pane_Vertically, "enlarge-pane-vertically", {.Lifecycle}, "Enlarge the active pane vertically by one row."),
		native_definition(.Enlarge_Pane_Horizontally, "enlarge-pane-horizontally", {.Lifecycle}, "Enlarge the active pane horizontally by one column."),
		native_definition(.Shrink_Pane_Horizontally, "shrink-pane-horizontally", {.Lifecycle}, "Shrink the active pane horizontally by one column."),
		native_definition(.Balance_Panes, "balance-panes", {.Lifecycle}, "Balance visible pane dimensions."),
		native_definition(.Balance_Pane_Areas, "balance-pane-areas", {.Lifecycle}, "Balance visible pane areas."),
		native_definition(.Terminal_Open, "terminal-open", {.View, .Lifecycle}, "Select or create the active scope default terminal.", {}),
		native_definition(.Terminal_New, "terminal-new", {.View, .Lifecycle}, "Create and present another terminal session.", {}),
		native_definition(.Terminal_Open_Here, "terminal-open-here", {.View, .Lifecycle}, "Create a terminal in the active resource directory."),
		native_definition(.Terminal_Open_Project, "terminal-open-project", {.View, .Lifecycle}, "Create a terminal in the active or recent Project.", {}),
		native_definition(.Terminal_Open_Other_Pane, "terminal-open-other-pane", {.View, .Lifecycle}, "Create or present a terminal in another pane.", {}),
		native_definition(.Terminal_Toggle, "terminal-toggle", {.View, .Lifecycle}, "Show or hide the remembered terminal presentation.", {}),
		native_definition(.Terminal_List, "terminal-list", {.View, .Lifecycle}, "List retained terminal sessions.", {}),
		native_definition(.Terminal_Rename, "terminal-rename", {.View, .Lifecycle}, "Rename the active terminal session.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Copy_Mode, "terminal-copy-mode", {.View}, "Enter retained terminal text navigation.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Copy_Mode_Done, "terminal-copy-mode-done", {.View}, "Return from terminal copy mode to live input.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Yank, "terminal-yank", {.View, .Lifecycle}, "Paste the newest retained text into the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Yank_Pop, "terminal-yank-pop", {.View, .Lifecycle}, "Replace the preceding terminal yank with the next retained entry.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Beginning_Of_Line, "terminal-beginning-of-line", {.View}, "Move terminal copy point to the projected line beginning.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_End_Of_Line, "terminal-end-of-line", {.View}, "Move terminal copy point to the projected line end.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Reset_Cursor_Point, "terminal-reset-cursor-point", {.View}, "Align terminal copy point with the live cursor.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Next_Prompt, "terminal-next-prompt", {.View}, "Navigate to the next confirmed retained prompt boundary.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Previous_Prompt, "terminal-previous-prompt", {.View}, "Navigate to the previous confirmed retained prompt boundary.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Next_Error, "terminal-next-error", {.View, .Lifecycle}, "Visit the next recognized result location through unified location navigation.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Open_Link, "terminal-open-link", {.View}, "Activate the validated hyperlink at the active terminal cursor.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Clear, "terminal-clear", {.View, .Lifecycle}, "Clear the active terminal display through ordinary terminal input.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Clear_Scrollback, "terminal-clear-scrollback", {.View, .Lifecycle}, "Clear retained scrollback for the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Next_Key, "terminal-send-next-key", {.View}, "Forward the next normalized input to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Return, "terminal-send-return", {.Lifecycle}, "Send Return to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Tab, "terminal-send-tab", {.Lifecycle}, "Send Tab to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Escape, "terminal-send-escape", {.Lifecycle}, "Send Escape to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Backspace, "terminal-send-backspace", {.Lifecycle}, "Send Backspace to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Delete, "terminal-send-delete", {.Lifecycle}, "Send Delete to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Up, "terminal-send-up", {.Lifecycle}, "Send Up to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Down, "terminal-send-down", {.Lifecycle}, "Send Down to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Left, "terminal-send-left", {.Lifecycle}, "Send Left to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Right, "terminal-send-right", {.Lifecycle}, "Send Right to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Prior, "terminal-send-prior", {.Lifecycle}, "Send Page Up to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Next, "terminal-send-next", {.Lifecycle}, "Send Page Down to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Send_Space, "terminal-send-space", {.Lifecycle}, "Send Space to the active terminal.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Undo, "terminal-undo", {.Lifecycle}, "Send the configured terminal-side undo input.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Terminal_Terminate, "terminal-terminate", {.View, .Lifecycle}, "Request termination of the active terminal process.", {.Active_Buffer, .Active_Terminal}),
		native_definition(.Shell_Command, "shell-command", {.View, .Lifecycle}, "Run a shell command and present its output."),
		native_definition(.Async_Shell_Command, "async-shell-command", {.View, .Lifecycle}, "Run a shell command without replacing the active editor view."),
		native_definition(.Compile, "compile", {.View, .Lifecycle}, "Run and retain a compilation command."),
		native_definition(.Recompile, "recompile", {.View, .Lifecycle}, "Run the last retained compilation command."),
		{
			name = "keyboard-quit",
			route = native_route(.Keyboard_Quit),
			implementation = .Native,
			invocation = .Cancellation,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Cancel pending input or deactivate the active region.",
			interactive = true,
			requirements = {.Active_Buffer},
			provenance = native_command_provenance(),
		},
		native_definition(.Request_Editor_Exit, "request-editor-exit", {.Lifecycle}, "Request orderly editor exit."),
	}
}

/* native_command_definitions composes the base catalog with Jan domain commands. */
native_command_definitions :: proc() -> [NATIVE_COMMAND_COUNT]interaction.Command_Definition {
	result: [NATIVE_COMMAND_COUNT]interaction.Command_Definition
	base := native_base_command_definitions()
	for definition, index in base do result[index] = definition
	jan := jan_structured_command_definitions()
	for definition, index in jan do result[NATIVE_BASE_COMMAND_COUNT + index] = definition
	planning := jan_planning_command_definitions()
	for definition, index in planning {
		result[NATIVE_BASE_COMMAND_COUNT + JAN_STRUCTURED_COMMAND_COUNT + index] = definition
	}
	computation := jan_computation_command_definitions()
	for definition, index in computation {
		result[NATIVE_BASE_COMMAND_COUNT + JAN_STRUCTURED_COMMAND_COUNT + JAN_PLANNING_COMMAND_COUNT + index] = definition
	}
	output := jan_output_command_definitions()
	for definition, index in output {
		result[NATIVE_BASE_COMMAND_COUNT + JAN_STRUCTURED_COMMAND_COUNT + JAN_PLANNING_COMMAND_COUNT + JAN_COMPUTATION_COMMAND_COUNT + index] = definition
	}
	language_support := language_support_command_definitions()
	for definition, index in language_support {
		result[NATIVE_BASE_COMMAND_COUNT + JAN_STRUCTURED_COMMAND_COUNT + JAN_PLANNING_COMMAND_COUNT + JAN_COMPUTATION_COMMAND_COUNT + JAN_OUTPUT_COMMAND_COUNT + index] = definition
	}
	package_catalog := package_catalog_command_definitions()
	for definition, index in package_catalog {
		result[NATIVE_BASE_COMMAND_COUNT + JAN_STRUCTURED_COMMAND_COUNT + JAN_PLANNING_COMMAND_COUNT + JAN_COMPUTATION_COMMAND_COUNT + JAN_OUTPUT_COMMAND_COUNT + LANGUAGE_SUPPORT_COMMAND_COUNT + index] = definition
	}
	return result
}

/* built_in_base_command_definitions returns the native-owned initial command set. */
built_in_base_command_definitions :: proc() -> [BUILT_IN_BASE_COMMAND_COUNT]interaction.Command_Definition {
	result: [BUILT_IN_BASE_COMMAND_COUNT]interaction.Command_Definition
	native := native_command_definitions()
	for definition, index in native {
		result[index] = definition
	}
	contextual := interaction_command_definitions()
	for definition, index in contextual {
		result[NATIVE_COMMAND_COUNT + index] = definition
	}
	return result
}

/* native_command_execute validates and executes one named Odin-owned view command. */
native_command_execute :: proc(
	request: Native_Context,
) -> (result: Native_Result, ok: bool, failure: Failure_Context) {
	if request.registry == nil || request.buffer == nil || request.view_registry == nil {
		return {}, false, Failure_Context{code = .Invalid_Command, command = request.command}
	}
	metadata, metadata_ok, metadata_failure := interaction.command_metadata(
		request.registry,
		request.command,
	)
	if !metadata_ok {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			interaction_code = metadata_failure.code,
			command = request.command,
		}
	}
	if metadata.implementation != .Native {
		return {}, false, Failure_Context {
			code = .Wrong_Implementation,
			command = request.command,
		}
	}
	route, route_ok := native_route_decode(metadata.route)
	if !route_ok {
		return {}, false, Failure_Context {
			code = .Unknown_Native_Command,
			command = request.command,
		}
	}
	if request.cancelled {
		return {}, false, Failure_Context{code = .Cancelled, command = request.command}
	}
	if metadata.text_requirement == .Prohibited && len(request.text) != 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	if metadata.text_requirement == .Required && len(request.text) == 0 {
		return {}, false, Failure_Context{code = .Missing_Text, command = request.command}
	}
	if request.yank_context != nil && route != .Yank_Pop {
		request.yank_context^ = {}
	}

	logical, logical_ok, logical_failure := editor_view.snapshot(
		request.view_registry,
		request.view,
	)
	if !logical_ok {
		return {}, false, native_view_failure(request.command, logical_failure)
	}
	buffer_stats, buffer_ok, buffer_failure := editor.buffer_stats(request.buffer)
	if !buffer_ok {
		return {}, false, native_editor_failure(request.command, buffer_failure)
	}
	if logical.buffer_id != buffer_stats.buffer_id || logical.revision != buffer_stats.revision {
		editor_code := editor.Failure_Code.Stale_Revision
		if logical.buffer_id != buffer_stats.buffer_id {
			editor_code = .Wrong_Buffer
		}
		return {}, false, Failure_Context {
			code = .View_Failure,
			command = request.command,
			view_code = .Editor_Failure,
			editor_code = editor_code,
		}
	}
	if native_route_is_darek(route) {
		return Native_Result{completion = .Darek_Command_Requested}, true, {}
	}
	if native_route_is_terminal(route) {
		return Native_Result{completion = .Terminal_Command_Requested}, true, {}
	}
	if native_route_is_jan_structured(route) || native_route_is_jan_planning(route) ||
	   native_route_is_jan_computation(route) || native_route_is_jan_output(route) {
		return Native_Result{completion = .Jan_Command_Requested}, true, {}
	}

	#partial switch route {
	case .ISearch_Forward:
		return Native_Result{completion = .Incremental_Search_Forward_Requested}, true, {}
	case .ISearch_Backward:
		return Native_Result{completion = .Incremental_Search_Backward_Requested}, true, {}
	case .ISearch_Forward_Regexp:
		return Native_Result{completion = .Incremental_Regexp_Search_Forward_Requested}, true, {}
	case .ISearch_Backward_Regexp:
		return Native_Result{completion = .Incremental_Regexp_Search_Backward_Requested}, true, {}
	case .Search_Symbol_At_Point:
		return Native_Result{completion = .Search_Symbol_At_Point_Requested}, true, {}
	case .Search_Word:
		return Native_Result{completion = .Search_Word_Requested}, true, {}
	case .Occur:
		return Native_Result{completion = .Search_Occur_Requested}, true, {}
	case .Highlight_Symbol_At_Point:
		return Native_Result{completion = .Search_Highlight_Symbol_Requested}, true, {}
	case .Highlight_Phrase:
		return Native_Result{completion = .Search_Highlight_Phrase_Requested}, true, {}
	case .Highlight_Regexp:
		return Native_Result{completion = .Search_Highlight_Regexp_Requested}, true, {}
	case .Highlight_Lines:
		return Native_Result{completion = .Search_Highlight_Lines_Requested}, true, {}
	case .Highlight_Remove:
		return Native_Result{completion = .Search_Highlight_Remove_Requested}, true, {}
	case .Search_Next_Occurrence:
		return Native_Result{completion = .Search_Next_Occurrence_Requested}, true, {}
	case .Search_Previous_Occurrence:
		return Native_Result{completion = .Search_Previous_Occurrence_Requested}, true, {}
	case .Symbol_Navigator:
		return Native_Result{completion = .Symbol_Navigator_Requested}, true, {}
	case .Project_Search_Text:
		return Native_Result{completion = .Project_Search_Text_Requested}, true, {}
	case .Project_Search_Text_Regexp:
		return Native_Result{completion = .Project_Search_Text_Regexp_Requested}, true, {}
	case .Project_Search_Repeat:
		return Native_Result{completion = .Project_Search_Repeat_Requested}, true, {}
	case .Status_Bar_Inspect:
		return Native_Result{completion = .Status_Bar_Inspect_Requested}, true, {}
	case .Status_Bar_Actions:
		return Native_Result{completion = .Status_Bar_Actions_Requested}, true, {}
	case .Status_Bar_Activate_Segment:
		return Native_Result{completion = .Status_Bar_Activate_Segment_Requested}, true, {}
	case .Gutter_Toggle_Line_Numbers, .Gutter_Cycle_Line_Number_Mode,
	     .Gutter_Set_Line_Numbers_None, .Gutter_Set_Line_Numbers_Absolute,
	     .Gutter_Set_Line_Numbers_Relative, .Gutter_Set_Line_Numbers_Hybrid,
	     .Gutter_Set_Numbering_Logical, .Gutter_Set_Numbering_Visual,
	     .Gutter_Toggle_Line_Number_Side, .Gutter_Inspect_Numbering,
	     .Gutter_Inspect_Markers, .Gutter_Refresh_Markers,
	     .Gutter_Invoke_Primary_Marker_Action:
		return Native_Result{completion = .Gutter_Command_Requested}, true, {}
	case .Complete_At_Point, .Completion_Next, .Completion_Previous,
	     .Completion_First, .Completion_Last, .Completion_Accept,
	     .Completion_Cancel, .Completion_Inspect, .Completion_Show_Documentation,
	     .Describe_Completion_State:
		return Native_Result{completion = .Completion_Command_Requested}, true, {}
	case .Ksawery_Status:
		return Native_Result{completion = .Ksawery_Status_Requested}, true, {}
	case .Maksym_Open_Directory, .Maksym_Open_Directory_Other_Pane,
	     .Maksym_Open_Directory_Below, .Maksym_Open_Directory_Right,
	     .Maksym_Open_Containing_Directory, .Maksym_Open_Containing_Directory_Other_Pane,
	     .Maksym_Next_Entry, .Maksym_Previous_Entry, .Maksym_Parent_Directory,
	     .Maksym_Jump_To_Entry, .Maksym_Open_Entry, .Maksym_Open_Entry_Other_Pane,
	     .Maksym_Display_Entry_Other_Pane, .Maksym_Refresh,
	     .Maksym_Toggle_Details, .Maksym_Cycle_Sort,
	     .Maksym_Toggle_Editable_Listing, .Maksym_Apply_Editable_Listing,
	     .Maksym_Cancel_Editable_Listing, .Maksym_Editable_Next_Line,
	     .Maksym_Editable_Previous_Line:
		return Native_Result{completion = .Maksym_Command_Requested}, true, {}
	case .Query_Replace:
		return Native_Result{completion = .Query_Replace_Requested}, true, {}
	case .Query_Replace_Regexp:
		return Native_Result{completion = .Query_Replace_Regexp_Requested}, true, {}
	case .Find_File:
		return Native_Result{completion = .Find_File_Requested}, true, {}
	case .Find_Alternate_File:
		return Native_Result{completion = .Find_Alternate_File_Requested}, true, {}
	case .Write_File:
		return Native_Result{completion = .Write_File_Requested}, true, {}
	case .Save_Some_Buffers:
		return Native_Result{completion = .Save_Some_Buffers_Requested}, true, {}
	case .Insert_File:
		if len(request.text) == 0 {
			return Native_Result{completion = .Insert_File_Requested}, true, {}
		}
		return native_insert(
			request,
			logical,
			request.text,
			metadata.name,
			edit_transaction.MAX_TEXT_BYTES,
		)
	case .Next_Buffer:
		return Native_Result{completion = .Next_Buffer_Requested}, true, {}
	case .Previous_Buffer:
		return Native_Result{completion = .Previous_Buffer_Requested}, true, {}
	case .Switch_To_Buffer:
		return Native_Result{completion = .Switch_To_Buffer_Requested}, true, {}
	case .Find_File_Other_Pane:
		return Native_Result{completion = .Find_File_Other_Pane_Requested}, true, {}
	case .Switch_To_Buffer_Other_Pane:
		return Native_Result{completion = .Switch_To_Buffer_Other_Pane_Requested}, true, {}
	case .Display_Buffer_Other_Pane:
		return Native_Result{completion = .Display_Buffer_Other_Pane_Requested}, true, {}
	case .Kill_Buffer:
		return Native_Result{completion = .Kill_Buffer_Requested}, true, {}
	case .List_Buffers:
		return Native_Result{completion = .List_Buffers_Requested}, true, {}
	case .Reload_Interaction_Profile:
		return Native_Result{completion = .Interaction_Profile_Reload_Requested}, true, {}
	case .Reload_Personal_Commands:
		return Native_Result{completion = .Personal_Commands_Reload_Requested}, true, {}
	case .Execute_Extended_Command:
		return Native_Result{completion = .Command_Navigation_Requested}, true, {}
	case .Apropos_Command, .Describe_Function:
		return Native_Result{completion = .Command_Description_Requested}, true, {}
	case .Help_About_Help, .Info, .Describe_Variable, .Open_Tutorial:
		return Native_Result{completion = .Help_Requested}, true, {}
	case .Select_Interaction_Profile:
		return Native_Result{completion = .Interaction_Profile_Selection_Requested}, true, {}
	case .Modal_Enter_Insert, .Modal_Enter_Replace, .Modal_Enter_Normal,
	     .Modal_Enter_Visual_Character, .Modal_Enter_Visual_Line,
	     .Modal_Enter_Visual_Block:
		return Native_Result{completion = .No_Op}, true, {}
	case .Describe_Modal_Repeat:
		return Native_Result{completion = .Modal_Repeat_Inspection_Requested}, true, {}
	case .Start_Keyboard_Macro:
		return Native_Result{completion = .Keyboard_Macro_Start_Requested}, true, {}
	case .End_Keyboard_Macro:
		return Native_Result{completion = .Keyboard_Macro_End_Requested}, true, {}
	case .Call_Last_Keyboard_Macro:
		return Native_Result{completion = .Keyboard_Macro_Call_Last_Requested}, true, {}
	case .Finish_Or_Call_Keyboard_Macro:
		return Native_Result{completion = .Keyboard_Macro_Finish_Or_Call_Requested}, true, {}
	case .Name_Last_Keyboard_Macro:
		return Native_Result{completion = .Keyboard_Macro_Name_Last_Requested}, true, {}
	case .Call_Named_Keyboard_Macro:
		return Native_Result{completion = .Keyboard_Macro_Call_Named_Requested}, true, {}
	case .Select_Theme:
		return Native_Result{completion = .Theme_Selection_Requested}, true, {}
	case .Describe_Theme:
		return Native_Result{completion = .Theme_Inspection_Requested}, true, {}
	case .Dir_Open:
		return Native_Result{completion = .Maksym_Command_Requested}, true, {}
	case .Project_Inspect_Active:
		return Native_Result{completion = .Project_Inspect_Active_Requested}, true, {}
	case .Project_Promote:
		return Native_Result{completion = .Project_Promote_Requested}, true, {}
	case .Project_Unregister:
		return Native_Result{completion = .Project_Unregister_Requested}, true, {}
	case .Project_Find_File:
		return Native_Result{completion = .Project_Find_File_Requested}, true, {}
	case .Project_Switch_Buffer:
		return Native_Result{completion = .Project_Switch_Buffer_Requested}, true, {}
	case .Project_Save_Buffers:
		return Native_Result{completion = .Project_Save_Buffers_Requested}, true, {}
	case .Project_Close_Buffers:
		return Native_Result{completion = .Project_Close_Buffers_Requested}, true, {}
	case .Project_Refresh:
		return Native_Result{completion = .Project_Refresh_Requested}, true, {}
	case .Project_Command_Menu:
		return Native_Result{completion = .Project_Command_Menu_Requested}, true, {}
	case .Describe_Project_Bindings:
		return Native_Result{completion = .Describe_Project_Bindings_Requested}, true, {}
	case .Recover_Unsaved_Work:
		return Native_Result{completion = .Recovery_Requested}, true, {}
	case .Workspace_Add_Project:
		return Native_Result{completion = .Workspace_Add_Project_Requested}, true, {}
	case .Workspace_Remove_Project:
		return Native_Result{completion = .Workspace_Remove_Project_Requested}, true, {}
	case .Workspace_Unregister:
		return Native_Result{completion = .Workspace_Unregister_Requested}, true, {}
	case .Save_Location:
		return Native_Result{completion = .Save_Location_Requested}, true, {}
	case .List_Locations:
		return Native_Result{completion = .List_Locations_Requested}, true, {}
	case .Visit_Location:
		return Native_Result{completion = .Visit_Location_Requested}, true, {}
	case .Store_Number:
		return Native_Result{completion = .Store_Number_Requested}, true, {}
	case .Increment_Number:
		return Native_Result{completion = .Increment_Number_Requested}, true, {}
	case .Store_Text:
		return Native_Result{completion = .Store_Text_Requested}, true, {}
	case .Store_Region_Text:
		return Native_Result{completion = .Store_Region_Text_Requested}, true, {}
	case .Store_Position:
		return Native_Result{completion = .Store_Position_Requested}, true, {}
	case .Insert_Slot:
		return Native_Result{completion = .Insert_Slot_Requested}, true, {}
	case .Store_Layout:
		return Native_Result{completion = .Store_Layout_Requested}, true, {}
	case .Visit_Slot:
		return Native_Result{completion = .Visit_Slot_Requested}, true, {}
	case .Restore_Layout:
		return Native_Result{completion = .Restore_Layout_Requested}, true, {}
	case .Next_Location:
		return Native_Result{completion = .Next_Location_Requested}, true, {}
	case .Previous_Location:
		return Native_Result{completion = .Previous_Location_Requested}, true, {}
	case .Describe_Language_State:
		return Native_Result{completion = .Describe_Language_State_Requested}, true, {}
	case .Jan_Inspect_Syntax, .Jan_Lint, .Jan_Lint_Refresh, .Jan_Language_Status:
		return Native_Result{completion = .Jan_Command_Requested}, true, {}
	case .Describe_Structural_State, .Describe_Syntax_Table:
		return Native_Result{completion = .Describe_Structural_State_Requested}, true, {}
	case .List_Language_Diagnostics:
		return Native_Result{completion = .Language_Diagnostics_Requested}, true, {}
	case .Next_Language_Diagnostic:
		return Native_Result{completion = .Next_Language_Diagnostic_Requested}, true, {}
	case .Previous_Language_Diagnostic:
		return Native_Result{completion = .Previous_Language_Diagnostic_Requested}, true, {}
	case .Describe_Language_Support, .Describe_Language_Service:
		return Native_Result{completion = .Language_Service_Inspection_Requested}, true, {}
	case .Restart_Language_Service:
		return Native_Result{completion = .Language_Service_Restart_Requested}, true, {}
	case .Language_Show_Hover, .Language_Go_To_Definition,
	     .Language_Find_References, .Language_Document_Symbols,
	     .Language_Workspace_Symbols, .Language_Signature_Help,
	     .Language_Rename, .Language_Format_Buffer, .Language_Format_Region,
	     .Language_Code_Actions, .Describe_Language_Bundle,
	     .Language_Support_Doctor, .Language_Bundle_List,
	     .Language_Bundle_Search, .Language_Bundle_Install,
	     .Language_Bundle_Enable, .Language_Bundle_Disable,
	     .Language_Bundle_Update, .Language_Bundle_Rollback,
	     .Language_Bundle_Remove, .Language_Bundle_Refresh_Catalogs:
		return Native_Result{completion = .Language_Interaction_Requested}, true, {}
	case .Package_Catalog_List, .Package_Catalog_Add,
	     .Package_Catalog_Disable, .Package_Catalog_Remove,
	     .Package_Catalog_Refresh, .Package_Catalog_Search,
	     .Package_Catalog_Describe, .Package_Manual_Acquire,
	     .Package_Advisory_List, .Package_Curator_Validate,
	     .Package_Catalog_Doctor, .Package_List, .Package_Discover,
	     .Package_Describe, .Package_Install, .Package_Enable,
	     .Package_Disable, .Package_Update, .Package_Rollback,
	     .Package_Remove, .Package_Cleanup, .Package_Doctor:
		return Native_Result{completion = .Package_Catalog_Interaction_Requested}, true, {}
	case .Select_Word, .Select_Paragraph, .Select_Buffer:
		return native_selection_expand(request, logical, route)
	case .Select_Rectangle:
		if len(request.text) != 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		if !logical.region_active || !logical.mark.present {
			return {}, false, Failure_Context{code = .Region_Unavailable, command = request.command}
		}
		selected, select_failure := editor_view.set_selection_shape(
			request.view_registry, request.view, .Rectangle, .Grapheme,
		)
		if !selected do return {}, false, native_view_failure(request.command, select_failure)
		return Native_Result{completion = .View_Changed}, true, {}
	case .Copy_Rectangle:
		return native_copy_rectangle(request, logical)
	case .Kill_Rectangle:
		return native_edit_rectangle(request, logical, "", true, metadata.name)
	case .Replace_Rectangle_Text:
		return native_edit_rectangle(request, logical, request.text, false, metadata.name)
	case .Select_Definition:
		return native_select_definition(request)
	case .Narrow_To_Region:
		return native_narrow_to_region(request, logical)
	case .Narrow_To_Definition:
		return native_narrow_to_definition(request, logical)
	case .Widen:
		return native_widen(request)
	case .Pop_Selection_Location:
		return native_selection_location_pop(request, logical)
	case .Structural_Forward, .Structural_Backward, .Structural_Up, .Structural_Down,
	     .Structural_Select, .Structural_Indent:
		return native_structural_command(request, route)
	case .Split_Pane_Below, .Split_Pane_Right, .Close_Pane, .Keep_Only_Pane,
	     .Focus_Pane_Left, .Focus_Pane_Down, .Focus_Pane_Up, .Focus_Pane_Right,
	     .Focus_Next_Pane, .Enlarge_Pane_Vertically, .Enlarge_Pane_Horizontally,
	     .Shrink_Pane_Horizontally, .Balance_Panes, .Balance_Pane_Areas:
		return native_layout_command(request, route)
	case .Keyboard_Quit:
		if len(request.text) != 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		if !logical.region_active {
			return Native_Result{completion = .Pending_Input_Cancelled}, true, {}
		}
		deactivated, deactivate_failure := editor_view.set_region_active(
			request.view_registry,
			request.view,
			false,
		)
		if !deactivated {
			return {}, false, native_view_failure(request.command, deactivate_failure)
		}
		return Native_Result{completion = .View_Changed}, true, {}
	case .Set_Mark:
		marked, mark_failure := editor_view.set_mark(
			request.view_registry,
			request.view,
			logical.point_position,
			true,
		)
		if !marked {
			return {}, false, native_view_failure(request.command, mark_failure)
		}
		return Native_Result{completion = .View_Changed}, true, {}
	case .Deactivate_Mark:
		if !logical.region_active {
			return Native_Result{completion = .No_Op}, true, {}
		}
		deactivated, deactivate_failure := editor_view.set_region_active(
			request.view_registry,
			request.view,
			false,
		)
		if !deactivated {
			return {}, false, native_view_failure(request.command, deactivate_failure)
		}
		return Native_Result{completion = .View_Changed}, true, {}
	case .Exchange_Point_And_Mark:
		exchanged, exchange_failure := editor_view.exchange_point_and_mark(
			request.view_registry,
			request.view,
		)
		if !exchanged {
			return {}, false, native_view_failure(request.command, exchange_failure)
		}
		return Native_Result{completion = .View_Changed}, true, {}
	case .Request_Editor_Exit:
		if len(request.text) != 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		return Native_Result{completion = .Exit_Requested}, true, {}
	case .Save_Associated_Document:
		if request.document == nil {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		document_status, status_ok, status_failure := document.document_status(request.document)
		if !status_ok {
			return {}, false, native_document_failure(request.command, status_failure)
		}
		if document_status.persistence == .Unassociated {
			return Native_Result{completion = .Document_Target_Required}, true, {}
		}
		prepared: document.Prepared_Save
		prepared_ok, prepare_failure := document.save_prepare(
			request.document,
			request.buffer,
			&prepared,
		)
		if !prepared_ok {
			return {}, false, native_document_failure(request.command, prepare_failure)
		}
		save_result, saved, save_failure := document.prepared_save_publish(&prepared)
		if !saved {
			command_failure := native_document_failure(request.command, save_failure)
			command_failure.publication = save_result.publication
			return Native_Result{save = save_result}, false, command_failure
		}
		return Native_Result{completion = .Document_Saved, save = save_result}, true, {}
	case .Toggle_Read_Only:
		read_only, inspected, inspect_failure := editor.buffer_read_only(request.buffer)
		if !inspected {
			return {}, false, native_editor_failure(request.command, inspect_failure)
		}
		_, set_ok, set_failure := editor.buffer_read_only_set(request.buffer, !read_only)
		if !set_ok {
			return {}, false, native_editor_failure(request.command, set_failure)
		}
		return Native_Result{completion = .View_Changed}, true, {}
	case .Insert_Text:
		return native_insert(request, logical, request.text, metadata.name)
	case .Modal_Repeat_Last_Change:
		return native_modal_repeat(request, logical, metadata.name)
	case .Insert_Text_After_Point:
		next, desired, target_ok, target_failure := display.navigation_target(
			request.buffer, logical, .Next_Grapheme, request.profile,
		)
		if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
		logical.point_position = next
		logical.desired_display_column = desired
		return native_insert(request, logical, request.text, metadata.name)
	case .Insert_Line_Break:
		if len(request.text) != 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		return native_insert(request, logical, "\n", metadata.name)
	case .Insert_Indentation:
		return native_insert_indentation(request, logical, metadata.name)
	case .Modal_Open_Line_Below:
		return native_modal_open_line(request, logical, true, metadata.name)
	case .Modal_Open_Line_Above:
		return native_modal_open_line(request, logical, false, metadata.name)
	case .Copy_Region:
		return native_copy_region(request, logical)
	case .Kill_Region:
		return native_remove_region(request, logical, true, metadata.name)
	case .Kill_Line:
		return native_kill_line(request, logical, metadata.name)
	case .Backward_Kill_Word:
		return native_kill_word(request, logical, true, metadata.name)
	case .Kill_Word:
		return native_kill_word(request, logical, false, metadata.name)
	case .Delete_Region:
		return native_remove_region(request, logical, false, metadata.name)
	case .Delete_Blank_Lines:
		return native_delete_blank_lines(request, logical, metadata.name)
	case .Fill_Paragraph:
		return native_fill_paragraph(request, logical, metadata.name)
	case .Transpose_Words:
		return native_transpose_words(request, logical, metadata.name)
	case .Upcase_Word:
		return native_change_word_case(request, logical, .Upper, metadata.name)
	case .Downcase_Word:
		return native_change_word_case(request, logical, .Lower, metadata.name)
	case .Capitalize_Word:
		return native_change_word_case(request, logical, .Capitalized, metadata.name)
	case .Comment_Dwim:
		return native_comment_dwim(request, logical, metadata.name)
	case .Dynamic_Abbrev_Expand:
		return native_dynamic_abbrev_expand(request, logical, metadata.name)
	case .Yank:
		return native_yank(request, logical, false, metadata.name)
	case .Yank_After_Point:
		next, desired, target_ok, target_failure := display.navigation_target(
			request.buffer, logical, .Next_Grapheme, request.profile,
		)
		if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
		logical.point_position = next
		logical.desired_display_column = desired
		return native_yank(request, logical, false, metadata.name)
	case .Yank_Pop:
		return native_yank(request, logical, true, metadata.name)
	case .Replace_Region_Text:
		return native_replace_region_text(request, logical, metadata.name)
	case .Indent_Lines:
		return native_indent_lines(request, logical, false, metadata.name)
	case .Outdent_Lines:
		return native_indent_lines(request, logical, true, metadata.name)
	case .Indent_Rigidly:
		return Native_Result{completion = .Rigid_Indentation_Requested}, true, {}
	case .Rigid_Indent_Right:
		return native_indent_lines(request, logical, false, metadata.name, 1)
	case .Rigid_Indent_Left:
		return native_indent_lines(request, logical, true, metadata.name, 1)
	case .Rigid_Indent_Right_Fast:
		return native_indent_lines(request, logical, false, metadata.name, logical.indentation_policy.policy.indent_width)
	case .Rigid_Indent_Left_Fast:
		return native_indent_lines(request, logical, true, metadata.name, logical.indentation_policy.policy.indent_width)
	case .Normalize_Indentation_To_Tabs:
		return native_normalize_indentation(request, logical, .Tabs, metadata.name)
	case .Normalize_Indentation_To_Spaces:
		return native_normalize_indentation(request, logical, .Spaces, metadata.name)
	case .Delete_Previous_Grapheme:
		return native_delete(request, logical, true, metadata.name)
	case .Delete_Next_Grapheme:
		return native_delete(request, logical, false, metadata.name)
	case .Undo:
		return native_history_navigate(request, .Undo)
	case .Redo:
		return native_history_navigate(request, .Redo)
	case .Cursor_Previous_Grapheme, .Cursor_Next_Grapheme, .Modal_Enter_Insert_After,
	     .Modal_Enter_Insert_Line_First, .Modal_Enter_Insert_Line_End,
	     .Cursor_Previous_Line, .Cursor_Next_Line, .Cursor_Line_Start, .Cursor_Line_End,
	     .Cursor_Previous_Word, .Cursor_Next_Word, .Cursor_Next_Word_Start,
	     .Cursor_Word_End, .Cursor_Line_First_Non_Whitespace,
	     .Cursor_Buffer_Start, .Cursor_Buffer_End,
	     .Cursor_Find_Next_Character, .Cursor_Find_Previous_Character,
	     .Cursor_Till_Next_Character, .Cursor_Till_Previous_Character:
		return native_move(request, logical, route)
	case .Goto_Line, .Goto_Char:
		if !request.argument_present {
			return Native_Result{completion = .Numeric_Navigation_Target_Requested}, true, {}
		}
		return native_move_absolute(request, logical, route)
	case .Toggle_Overwrite_Mode:
		if len(request.text) != 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		_, toggled, toggle_failure := editor_view.toggle_overwrite_mode(
			request.view_registry,
			request.view,
		)
		if !toggled {
			return {}, false, native_view_failure(request.command, toggle_failure)
		}
		return Native_Result{completion = .View_Changed}, true, {}
	case .Scroll_Previous_Page, .Scroll_Next_Page:
		return native_scroll_page(request, logical, route == .Scroll_Next_Page)
	case .Recenter:
		return native_recenter(request, logical)
	case .Replace_String, .Replace_Regexp, .Invalid:
		return {}, false, Failure_Context{code = .Unknown_Native_Command, command = request.command}
	}
	unreachable()
}

@(private)
native_structural_command :: proc(
	request: Native_Context,
	route: Native_Route,
) -> (Native_Result, bool, Failure_Context) {
	operation: language.Structural_Operation
	#partial switch route {
	case .Structural_Forward: operation = .Forward
	case .Structural_Backward: operation = .Backward
	case .Structural_Up: operation = .Up
	case .Structural_Down: operation = .Down
	case .Structural_Select: operation = .Select
	case .Structural_Indent: operation = .Indent
	case .Select_Definition: operation = .Definition
	}
	ctx := Structural_Editor_Context {
		native = request,
		owner = request.language_owner,
		source = request.language_source,
		scope = request.structural_scope,
	}
	if request.structural_state != nil && request.editor_session_id != Editor_Session_ID(0) &&
	   request.structural_access != {} && request.structural_capability_generation != 0 {
		capability := Structural_Capability_Context {
			editor_session_id = request.editor_session_id,
			access = request.structural_access,
			capability_generation = request.structural_capability_generation,
			editor = ctx,
			state = request.structural_state,
		}
		capability_scope, capability_scoped, capability_failure :=
			structural_capability_scope(capability)
		if !capability_scoped do return {}, false, capability_failure
		capability_result, invoked, invoke_failure := structural_capability_invoke(
			capability,
			capability_scope,
			operation,
		)
		if !invoked do return {}, false, invoke_failure
		result := capability_result.editor.native
		capability_result.editor.native = {}
		structural_capability_result_close(&capability_result)
		return result, true, {}
	}
	scope, scoped, scope_failure := structural_editor_scope(ctx)
	if !scoped do return {}, false, scope_failure
	structural_result, executed, execute_failure := structural_editor_run(
		ctx,
		Structural_Editor_Request{expected_scope = scope, operation = operation},
	)
	if !executed do return {}, false, execute_failure
	result := structural_result.native
	structural_result.native = {}
	structural_editor_result_close(&structural_result)
	return result, true, {}
}

@(private)
native_layout_command :: proc(
	request: Native_Context,
	route: Native_Route,
) -> (Native_Result, bool, Failure_Context) {
	if request.layout_registry == nil {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	handle, handle_ok, handle_failure := layout.registry_handle(request.layout_registry)
	if !handle_ok {
		return {}, false, native_layout_failure(request.command, handle_failure)
	}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(request.layout_registry, handle)
	if !snapshot_ok {
		return {}, false, native_layout_failure(request.command, snapshot_failure)
	}
	active_node, active_found := native_layout_active_node(snapshot)
	if !active_found || active_node.view != request.view {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	#partial switch route {
	case .Split_Pane_Below:
		_, changed, failure := layout.registry_split_below(request.layout_registry, snapshot.active_pane)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Split_Pane_Right:
		_, changed, failure := layout.registry_split_right(request.layout_registry, snapshot.active_pane)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Close_Pane:
		_, changed, failure := layout.registry_close_pane(request.layout_registry, snapshot.active_pane)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Keep_Only_Pane:
		if snapshot.pane_count == 1 {
			return Native_Result{completion = .No_Op}, true, {}
		}
		_, changed, failure := layout.registry_keep_only(request.layout_registry, snapshot.active_pane)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Focus_Next_Pane:
		if snapshot.pane_count == 1 {
			return Native_Result{completion = .No_Op}, true, {}
		}
		next, found := native_layout_next_pane(snapshot)
		if !found {
			return {}, false, Failure_Context{code = .Layout_Failure, command = request.command}
		}
		_, changed, failure := layout.registry_focus(request.layout_registry, next)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Focus_Pane_Left, .Focus_Pane_Down, .Focus_Pane_Up, .Focus_Pane_Right:
		direction := Native_Pane_Direction.Left
		#partial switch route {
		case .Focus_Pane_Down:  direction = .Down
		case .Focus_Pane_Up:    direction = .Up
		case .Focus_Pane_Right: direction = .Right
		case:                   direction = .Left
		}
		target, found := native_layout_directional_pane(snapshot, active_node, direction)
		if !found {
			return Native_Result{completion = .No_Op}, true, {}
		}
		_, changed, failure := layout.registry_focus(request.layout_registry, target)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Enlarge_Pane_Vertically:
		_, changed, failure := layout.registry_resize_pane(
			request.layout_registry,
			snapshot.active_pane,
			.Above_Below,
			1,
		)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Enlarge_Pane_Horizontally:
		_, changed, failure := layout.registry_resize_pane(
			request.layout_registry,
			snapshot.active_pane,
			.Left_Right,
			1,
		)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Shrink_Pane_Horizontally:
		_, changed, failure := layout.registry_resize_pane(
			request.layout_registry,
			snapshot.active_pane,
			.Left_Right,
			-1,
		)
		if !changed {
			return {}, false, native_layout_failure(request.command, failure)
		}
	case .Balance_Panes:
		balanced, balanced_ok, failure := layout.registry_balance_panes(
			request.layout_registry,
			snapshot.handle,
		)
		if !balanced_ok {
			return {}, false, native_layout_failure(request.command, failure)
		}
		if !balanced.changed {
			return Native_Result{completion = .No_Op}, true, {}
		}
	case .Balance_Pane_Areas:
		balanced, balanced_ok, failure := layout.registry_balance_pane_areas(
			request.layout_registry,
			snapshot.handle,
		)
		if !balanced_ok {
			return {}, false, native_layout_failure(request.command, failure)
		}
		if !balanced.changed {
			return Native_Result{completion = .No_Op}, true, {}
		}
	case:
		return {}, false, Failure_Context{code = .Unknown_Native_Command, command = request.command}
	}
	return Native_Result{completion = .View_Changed}, true, {}
}

@(private)
native_layout_active_node :: proc(snapshot: layout.Snapshot) -> (layout.Node_Descriptor, bool) {
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.active {
			return node, true
		}
	}
	return {}, false
}

@(private)
native_layout_next_pane :: proc(snapshot: layout.Snapshot) -> (layout.Pane_Handle, bool) {
	first: layout.Pane_Handle
	return_next := false
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind != .Pane {
			continue
		}
		if first.pane_id == layout.Pane_ID(0) {
			first = node.pane
		}
		if return_next {
			return node.pane, true
		}
		if node.active {
			return_next = true
		}
	}
	return first, first.pane_id != layout.Pane_ID(0) && return_next
}

@(private)
Native_Pane_Direction :: enum u8 {
	Left,
	Down,
	Up,
	Right,
}

@(private)
native_layout_directional_pane :: proc(
	snapshot: layout.Snapshot,
	active: layout.Node_Descriptor,
	direction: Native_Pane_Direction,
) -> (layout.Pane_Handle, bool) {
	selected: layout.Pane_Handle
	best_axis := max(i32)
	best_orthogonal := max(i32)
	for index in 0 ..< int(snapshot.node_count) {
		candidate := snapshot.nodes[index]
		if candidate.kind != .Pane || candidate.active do continue
		current := active.geometry.outer
		other := candidate.geometry.outer
		axis, overlap, center_delta: i32
		#partial switch direction {
		case .Left:
			if other.column + other.width > current.column do continue
			axis = current.column - (other.column + other.width)
			overlap = min(current.row + current.height, other.row + other.height) - max(current.row, other.row)
			center_delta = abs((current.row * 2 + current.height) - (other.row * 2 + other.height))
		case .Right:
			if other.column < current.column + current.width do continue
			axis = other.column - (current.column + current.width)
			overlap = min(current.row + current.height, other.row + other.height) - max(current.row, other.row)
			center_delta = abs((current.row * 2 + current.height) - (other.row * 2 + other.height))
		case .Up:
			if other.row + other.height > current.row do continue
			axis = current.row - (other.row + other.height)
			overlap = min(current.column + current.width, other.column + other.width) - max(current.column, other.column)
			center_delta = abs((current.column * 2 + current.width) - (other.column * 2 + other.width))
		case .Down:
			if other.row < current.row + current.height do continue
			axis = other.row - (current.row + current.height)
			overlap = min(current.column + current.width, other.column + other.width) - max(current.column, other.column)
			center_delta = abs((current.column * 2 + current.width) - (other.column * 2 + other.width))
		}
		if overlap <= 0 do continue
		orthogonal := center_delta - overlap
		if selected.pane_id == layout.Pane_ID(0) || axis < best_axis ||
		   axis == best_axis && orthogonal < best_orthogonal ||
		   axis == best_axis && orthogonal == best_orthogonal &&
		   candidate.pane.pane_id < selected.pane_id {
			selected = candidate.pane
			best_axis = axis
			best_orthogonal = orthogonal
		}
	}
	return selected, selected.pane_id != layout.Pane_ID(0)
}

@(private)
native_layout_failure :: proc(
	command: interaction.Command_Handle,
	failure: layout.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .Layout_Failure,
		command = command,
		layout_code = failure.code,
		layout_failure = failure,
		limit = failure.maximum,
		actual = failure.actual,
	}
}

@(private)
native_document_failure :: proc(
	command: interaction.Command_Handle,
	document_failure: document.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .Publication_Failure,
		command = command,
		document_code = document_failure.code,
		publication = document_failure.publication,
		limit = document_failure.limit,
		actual = document_failure.actual,
	}
}

@(private)
native_definition :: proc(
	route: Native_Route,
	name: string,
	effects: interaction.Command_Effects,
	description: string,
	requirements: interaction.Command_Requirements = {.Active_Buffer},
) -> interaction.Command_Definition {
	return interaction.Command_Definition {
		name = name,
		route = native_route(route),
		implementation = .Native,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		effects = effects,
		description = description,
		interactive = true,
		requirements = requirements,
		provenance = native_command_provenance(),
	}
}

@(private)
native_text_argument_definition :: proc(
	route: Native_Route,
	name: string,
	effects: interaction.Command_Effects,
	description: string,
	requirements: interaction.Command_Requirements = {.Active_Buffer},
) -> interaction.Command_Definition {
	definition := native_definition(route, name, effects, description, requirements)
	definition.text_requirement = .Required
	return definition
}

@(private)
native_optional_text_definition :: proc(
	route: Native_Route,
	name: string,
	effects: interaction.Command_Effects,
	description: string,
) -> interaction.Command_Definition {
	definition := native_definition(route, name, effects, description)
	definition.text_requirement = .Optional
	return definition
}

@(private)
native_move_absolute :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	route: Native_Route,
) -> (Native_Result, bool, Failure_Context) {
	failure := validate_display_request(request, logical, 2, false)
	if failure.code != .None do return {}, false, failure
	if request.argument < 1 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	target, target_ok, target_failure := editor.buffer_position(request.buffer, 0)
	if !target_ok do return {}, false, native_editor_failure(request.command, target_failure)
	if route == .Goto_Line {
		for _ in i64(1) ..< request.argument {
			line, line_ok, line_failure := editor.buffer_line_at_position(request.buffer, target)
			if !line_ok do return {}, false, native_editor_failure(request.command, line_failure)
			if line.next_start <= target.byte_offset do break
			target, target_ok, target_failure = editor.buffer_position(request.buffer, line.next_start)
			if !target_ok do return {}, false, native_editor_failure(request.command, target_failure)
		}
		return native_move_publish(request, logical, target, 0)
	}
	working := logical
	working.point_position = target
	working.desired_display_column = 0
	for _ in i64(1) ..< request.argument {
		next, desired, moved, move_failure := display.navigation_target(
			request.buffer,
			working,
			.Next_Grapheme,
			request.profile,
		)
		if !moved do return {}, false, native_display_failure(request.command, move_failure)
		if next == working.point_position do break
		working.point_position = next
		working.desired_display_column = desired
	}
	return native_move_publish(request, logical, working.point_position, working.desired_display_column)
}

@(private)
native_command_provenance :: proc() -> interaction.Definition_Provenance {
	return interaction.Definition_Provenance {
		provider = "odra-native",
		source = "src/command/native.odin",
	}
}

@(private)
native_move :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	route: Native_Route,
) -> (Native_Result, bool, Failure_Context) {
	failure := validate_display_request(request, logical, 2, false)
	if failure.code != .None {
		return {}, false, failure
	}
	repeat_count := request.repeat_count
	if repeat_count == 0 do repeat_count = 1
	if repeat_count > interaction.MAX_MODAL_COUNT {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.command,
			limit = interaction.MAX_MODAL_COUNT,
			actual = repeat_count,
		}
	}
	if route == .Cursor_Find_Next_Character || route == .Cursor_Find_Previous_Character ||
	   route == .Cursor_Till_Next_Character || route == .Cursor_Till_Previous_Character {
		kind := display.Line_Character_Target_Kind.Find_Next
		#partial switch route {
		case .Cursor_Find_Next_Character:     kind = .Find_Next
		case .Cursor_Find_Previous_Character: kind = .Find_Previous
		case .Cursor_Till_Next_Character:     kind = .Till_Next
		case .Cursor_Till_Previous_Character: kind = .Till_Previous
		case: unreachable()
		}
		target, desired, found, target_ok, target_failure := display.line_character_navigation_target(
			request.buffer,
			logical,
			request.text,
			kind,
			repeat_count,
			request.profile,
		)
		if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
		if !found do return Native_Result{completion = .No_Op}, true, {}
		return native_move_publish(request, logical, target, desired)
	}
	kind: display.Navigation_Kind
	#partial switch route {
	case .Cursor_Previous_Grapheme: kind = .Previous_Grapheme
	case .Cursor_Next_Grapheme, .Modal_Enter_Insert_After: kind = .Next_Grapheme
	case .Cursor_Previous_Line:     kind = .Previous_Line
	case .Cursor_Next_Line:         kind = .Next_Line
	case .Cursor_Line_Start:        kind = .Line_Start
	case .Cursor_Line_End:          kind = .Line_End
	case .Cursor_Previous_Word:     kind = .Previous_Word
	case .Cursor_Next_Word:         kind = .Next_Word
	case .Cursor_Next_Word_Start:   kind = .Next_Word_Start
	case .Cursor_Word_End:          kind = .Next_Word
	case .Cursor_Line_First_Non_Whitespace: kind = .Line_First_Non_Whitespace
	case .Modal_Enter_Insert_Line_First: kind = .Line_First_Non_Whitespace
	case .Modal_Enter_Insert_Line_End:   kind = .Line_End
	case .Cursor_Buffer_Start:      kind = .Buffer_Start
	case .Cursor_Buffer_End:        kind = .Buffer_End
	case: unreachable()
	}
	working := logical
	target := logical.point_position
	desired := logical.desired_display_column
	for _ in 0 ..< repeat_count {
		target_ok: bool
		target_failure: display.Failure_Context
		target, desired, target_ok, target_failure = display.navigation_target(
			request.buffer,
			working,
			kind,
			request.profile,
		)
		if !target_ok {
			return {}, false, native_display_failure(request.command, target_failure)
		}
		if target == working.point_position && desired == working.desired_display_column do break
		working.point_position = target
		working.desired_display_column = desired
	}
	return native_move_publish(request, logical, target, desired)
}

@(private)
native_move_publish :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	target: editor.Position,
	desired: u32,
) -> (Native_Result, bool, Failure_Context) {
	column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		target,
		request.profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, false, native_display_failure(request.command, column_failure)
	}
	plan, planned, plan_failure := cursor_reveal_plan(
		request.buffer,
		logical,
		target,
		column,
		request.constraints,
	)
	if !planned {
		plan_failure.command = request.command
		return {}, false, plan_failure
	}
	if target == logical.point_position && desired == logical.desired_display_column && !plan.update {
		return Native_Result{completion = .No_Op}, true, {}
	}
	moved, move_failure := editor_view.move_point(
		request.view_registry,
		request.view,
		target,
		desired,
		.Preserve,
	)
	if !moved {
		return {}, false, native_view_failure(request.command, move_failure)
	}
	if plan.update {
		updated, update_failure := editor_view.set_viewport(
			request.view_registry,
			request.view,
			plan.origin,
			plan.horizontal,
		)
		if !updated {
			return {}, false, native_view_failure(request.command, update_failure)
		}
	}
	return Native_Result{completion = .View_Changed}, true, {}
}

@(private)
native_modal_open_line :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	below: bool,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	kind := display.Navigation_Kind.Line_Start
	if below do kind = .Line_End
	target, desired, target_ok, target_failure := display.navigation_target(
		request.buffer,
		logical,
		kind,
		request.profile,
	)
	if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
	working := logical
	working.point_position = target
	working.desired_display_column = desired
	result, inserted, insert_failure := native_insert(request, working, "\n", command_name)
	if !inserted || below do return result, inserted, insert_failure
	position, position_ok, position_failure := editor.buffer_position(
		request.buffer,
		target.byte_offset,
	)
	if !position_ok {
		native_result_close(&result)
		return {}, false, native_editor_failure(request.command, position_failure)
	}
	moved, move_failure := editor_view.set_point(request.view_registry, request.view, position)
	if !moved {
		native_result_close(&result)
		return {}, false, native_view_failure(request.command, move_failure)
	}
	return result, true, {}
}

@(private)
native_modal_repeat :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	replay := request
	replay.replace_text_input = request.replay_replace_text
	#partial switch request.replay_route {
	case .Insert_Text:
		working := logical
		text := request.text
		combined: [interaction.MAX_TEXT_BYTES]u8
		#partial switch request.replay_entry_route {
		case .Modal_Enter_Insert_After:
			next, desired, target_ok, target_failure := display.navigation_target(
				request.buffer, working, .Next_Grapheme, request.profile,
			)
			if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
			working.point_position = next
			working.desired_display_column = desired
		case .Modal_Enter_Insert_Line_First, .Modal_Enter_Insert_Line_End,
		     .Modal_Open_Line_Below, .Modal_Open_Line_Above:
			kind := display.Navigation_Kind.Line_First_Non_Whitespace
			if request.replay_entry_route == .Modal_Enter_Insert_Line_End ||
			   request.replay_entry_route == .Modal_Open_Line_Below {
				kind = .Line_End
			} else if request.replay_entry_route == .Modal_Open_Line_Above {
				kind = .Line_Start
			}
			target, desired, target_ok, target_failure := display.navigation_target(
				request.buffer, working, kind, request.profile,
			)
			if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
			working.point_position = target
			working.desired_display_column = desired
			if request.replay_entry_route == .Modal_Open_Line_Below {
				if len(text) + 1 > len(combined) {
					return {}, false, Failure_Context{code = .Text_Limit, command = request.command, limit = interaction.MAX_TEXT_BYTES, actual = u64(len(text) + 1)}
				}
				combined[0] = '\n'
				copy(combined[1:], transmute([]u8)text)
				text = string(combined[:len(text) + 1])
			} else if request.replay_entry_route == .Modal_Open_Line_Above {
				if len(text) + 1 > len(combined) {
					return {}, false, Failure_Context{code = .Text_Limit, command = request.command, limit = interaction.MAX_TEXT_BYTES, actual = u64(len(text) + 1)}
				}
				copy(combined[:], transmute([]u8)text)
				combined[len(text)] = '\n'
				text = string(combined[:len(text) + 1])
			}
		case .Modal_Enter_Insert, .Modal_Enter_Replace, .Invalid:
		case:
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		return native_insert(replay, working, text, command_name)
	case .Insert_Text_After_Point:
		next, desired, target_ok, target_failure := display.navigation_target(
			request.buffer, logical, .Next_Grapheme, request.profile,
		)
		if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
		working := logical
		working.point_position = next
		working.desired_display_column = desired
		return native_insert(replay, working, request.text, command_name)
	case .Delete_Previous_Grapheme:
		return native_delete(replay, logical, true, command_name)
	case .Delete_Next_Grapheme:
		return native_delete(replay, logical, false, command_name)
	case .Kill_Region:
		return native_remove_region(replay, logical, true, command_name)
	case .Replace_Region_Text:
		return native_replace_region_text(replay, logical, command_name)
	case .Indent_Lines:
		return native_indent_lines(replay, logical, false, command_name)
	case .Outdent_Lines:
		return native_indent_lines(replay, logical, true, command_name)
	case .Yank:
		return native_yank(replay, logical, false, command_name)
	case .Yank_After_Point:
		next, desired, target_ok, target_failure := display.navigation_target(
			request.buffer, logical, .Next_Grapheme, request.profile,
		)
		if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
		working := logical
		working.point_position = next
		working.desired_display_column = desired
		return native_yank(replay, working, false, command_name)
	case:
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
}

@(private)
native_selection_expand :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	route: Native_Route,
) -> (Native_Result, bool, Failure_Context) {
	range: display.Selection_Range
	found := true
	#partial switch route {
	case .Select_Word:
		failure := validate_display_request(request, logical, 2, false)
		if failure.code != .None do return {}, false, failure
		selection_ok: bool
		selection_failure: display.Failure_Context
		range, found, selection_ok, selection_failure = display.word_selection_range(
			request.buffer,
			logical,
			request.profile,
		)
		if !selection_ok do return {}, false, native_display_failure(request.command, selection_failure)
	case .Select_Paragraph:
		selection_ok: bool
		selection_failure: display.Failure_Context
		range, selection_ok, selection_failure = display.paragraph_selection_range(request.buffer, logical)
		if !selection_ok do return {}, false, native_display_failure(request.command, selection_failure)
	case .Select_Buffer:
		stats, stats_ok, stats_failure := editor.buffer_stats(request.buffer)
		if !stats_ok do return {}, false, native_editor_failure(request.command, stats_failure)
		start, start_ok, start_failure := editor.buffer_position(request.buffer, 0)
		if !start_ok do return {}, false, native_editor_failure(request.command, start_failure)
		end, end_ok, end_failure := editor.buffer_position(request.buffer, editor.Byte_Offset(stats.text_bytes))
		if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
		range = {start = start, end = end}
	case: unreachable()
	}
	if !found do return Native_Result{completion = .No_Op}, true, {}
	return native_selection_publish(request, logical, range)
}

@(private)
native_select_definition :: proc(request: Native_Context) -> (Native_Result, bool, Failure_Context) {
	if request.language_owner == nil || request.language_source == nil ||
	   !language.structural_scope_is_valid(request.structural_scope) {
		return Native_Result{completion = .No_Op}, true, {}
	}
	previous, previous_ok, previous_failure := editor.buffer_selection_snapshot(request.buffer)
	if !previous_ok do return {}, false, native_editor_failure(request.command, previous_failure)
	result, selected, selection_failure := native_structural_command(request, .Select_Definition)
	if !selected || result.completion != .View_Changed do return result, selected, selection_failure
	state, copied := location_state_from_selection(previous)
	if copied && request.location_history != nil {
		pushed := location_history_push(request.location_history, state)
		assert(pushed)
	}
	return result, true, {}
}

@(private)
native_selection_publish :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	range: display.Selection_Range,
) -> (Native_Result, bool, Failure_Context) {
	column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		range.end,
		request.profile,
		logical.tab_width,
	)
	if !column_ok do return {}, false, native_display_failure(request.command, column_failure)
	selected, select_failure := editor_view.select_range(
		request.view_registry,
		request.view,
		range.start,
		range.end,
		column,
	)
	if !selected do return {}, false, native_view_failure(request.command, select_failure)
	previous := editor.Selection_Snapshot {
		buffer_id = logical.buffer_id,
		revision = logical.revision,
		point_position = logical.point_position,
		mark = {present = logical.mark.present, position = logical.mark.position},
		region_active = logical.region_active,
	}
	state, copied := location_state_from_selection(previous)
	if copied && request.location_history != nil {
		pushed := location_history_push(request.location_history, state)
		assert(pushed)
	}
	return Native_Result{completion = .View_Changed}, true, {}
}

@(private)
native_selection_location_pop :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
) -> (Native_Result, bool, Failure_Context) {
	if request.location_history == nil do return Native_Result{completion = .No_Op}, true, {}
	for {
		state, popped := location_history_pop(request.location_history)
		if !popped do return Native_Result{completion = .No_Op}, true, {}
		if state.buffer_id != logical.buffer_id || state.revision != logical.revision do continue
		column, column_ok, column_failure := display.position_display_column(
			request.buffer,
			state.point,
			request.profile,
			logical.tab_width,
		)
		if !column_ok do return {}, false, native_display_failure(request.command, column_failure)
		if state.mark.present {
			if state.region_active {
				selected, select_failure := editor_view.select_range(
					request.view_registry,
					request.view,
					state.mark.position,
					state.point,
					column,
				)
				if !selected do return {}, false, native_view_failure(request.command, select_failure)
			} else {
				marked, mark_failure := editor_view.set_mark(
					request.view_registry,
					request.view,
					state.mark.position,
					false,
				)
				if !marked do return {}, false, native_view_failure(request.command, mark_failure)
				moved, move_failure := editor_view.move_point(
					request.view_registry,
					request.view,
					state.point,
					column,
					.Preserve,
				)
				if !moved do return {}, false, native_view_failure(request.command, move_failure)
			}
		} else {
			cleared, clear_failure := editor_view.clear_mark(request.view_registry, request.view)
			if !cleared do return {}, false, native_view_failure(request.command, clear_failure)
			moved, move_failure := editor_view.set_point(request.view_registry, request.view, state.point)
			if !moved do return {}, false, native_view_failure(request.command, move_failure)
		}
		return Native_Result{completion = .View_Changed}, true, {}
	}
}

@(private)
native_recenter :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	failure := validate_display_request(request, logical, 2, false)
	if failure.code != .None do return {}, false, failure
	origin, _, origin_ok, origin_failure := page_line_target(
		request.buffer,
		logical,
		logical.point_position,
		0,
		request.constraints.height_rows / 2,
		false,
		request.profile,
	)
	if !origin_ok do return {}, false, native_display_failure(request.command, origin_failure)
	if origin == logical.viewport_origin_position && logical.horizontal_display_column == 0 {
		return Native_Result{completion = .No_Op}, true, {}
	}
	updated, update_failure := editor_view.set_viewport(
		request.view_registry,
		request.view,
		origin,
		0,
	)
	if !updated do return {}, false, native_view_failure(request.command, update_failure)
	return Native_Result{completion = .View_Changed}, true, {}
}

@(private)
native_scroll_page :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	forward: bool,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	failure := validate_display_request(request, logical, 2, false)
	if failure.code != .None do return {}, false, failure
	repeat_count := request.repeat_count
	if repeat_count == 0 do repeat_count = 1
	if repeat_count > interaction.MAX_MODAL_COUNT {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.command,
			limit = interaction.MAX_MODAL_COUNT,
			actual = repeat_count,
		}
	}

	rows := request.constraints.height_rows - 1
	target := logical.point_position
	desired := logical.desired_display_column
	viewport := logical.viewport_origin_position
	for _ in 0 ..< repeat_count {
		next_target, next_desired, target_ok, target_failure := page_line_target(
			request.buffer,
			logical,
			target,
			desired,
			rows,
			forward,
			request.profile,
		)
		if !target_ok do return {}, false, native_display_failure(request.command, target_failure)
		next_viewport, _, viewport_ok, viewport_failure := page_line_target(
			request.buffer,
			logical,
			viewport,
			0,
			rows,
			forward,
			request.profile,
		)
		if !viewport_ok do return {}, false, native_display_failure(request.command, viewport_failure)
		if next_target == target && next_viewport == viewport do break
		target = next_target
		desired = next_desired
		viewport = next_viewport
	}
	if target == logical.point_position && viewport == logical.viewport_origin_position {
		return Native_Result{completion = .No_Op}, true, {}
	}
	if target != logical.point_position {
		moved, move_failure := editor_view.move_point(
			request.view_registry,
			request.view,
			target,
			desired,
			.Preserve,
		)
		if !moved do return {}, false, native_view_failure(request.command, move_failure)
	}
	if viewport != logical.viewport_origin_position {
		updated, update_failure := editor_view.set_viewport(
			request.view_registry,
			request.view,
			viewport,
			logical.horizontal_display_column,
		)
		if !updated do return {}, false, native_view_failure(request.command, update_failure)
	}
	return Native_Result{completion = .View_Changed}, true, {}
}

@(private)
page_line_target :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	start: editor.Position,
	desired_column: u32,
	rows: u32,
	forward: bool,
	profile: display.Display_Profile,
) -> (target: editor.Position, desired: u32, ok: bool, failure: display.Failure_Context) {
	probe := logical
	probe.point_position = start
	probe.desired_display_column = desired_column
	target = start
	desired = desired_column
	kind := display.Navigation_Kind.Previous_Line
	if forward do kind = .Next_Line
	for _ in 0 ..< int(rows) {
		next, next_desired, next_ok, next_failure := display.navigation_target(
			buffer,
			probe,
			kind,
			profile,
		)
		if !next_ok do return {}, 0, false, next_failure
		if next == target do break
		target = next
		desired = next_desired
		probe.point_position = next
		probe.desired_display_column = next_desired
	}
	return target, desired, true, {}
}

@(private)
native_insert :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	text: string,
	command_name: string,
	text_limit := u64(interaction.MAX_TEXT_BYTES),
) -> (Native_Result, bool, Failure_Context) {
	if len(text) == 0 {
		return {}, false, Failure_Context{code = .Missing_Text, command = request.command}
	}
	if u64(len(text)) > text_limit {
		return {}, false, Failure_Context {
			code = .Text_Limit,
			command = request.command,
			limit = text_limit,
			actual = u64(len(text)),
		}
	}
	if !utf8.valid_string(text) {
		return {}, false, Failure_Context{code = .Malformed_Text, command = request.command}
	}
	failure := validate_display_request(request, logical, 2, true)
	if failure.code != .None {
		return {}, false, failure
	}
	current_column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		logical.point_position,
		request.profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, false, native_display_failure(request.command, column_failure)
	}
	final_column, width_ok, width_failure := inserted_text_end_column(
		text,
		current_column,
		logical.tab_width,
		request.profile,
	)
	if !width_ok {
		width_failure.command = request.command
		return {}, false, width_failure
	}
	replacement_end := logical.point_position
	overwrite := logical.overwrite_mode || request.replace_text_input
	if request.replace_text_input {
		line, line_ok, line_failure := editor.buffer_line_at_position(
			request.buffer,
			logical.point_position,
		)
		if !line_ok do return {}, false, native_editor_failure(request.command, line_failure)
		working := logical
		input_offset := u64(0)
		for input_offset < u64(len(text)) && replacement_end.byte_offset < line.content_end {
			grapheme, grapheme_ok, grapheme_failure := display.profile_next_grapheme(
				request.profile.unicode,
				text,
				input_offset,
			)
			if !grapheme_ok {
				return {}, false, Failure_Context {
					code = .Display_Failure,
					command = request.command,
					profile_code = grapheme_failure.code,
				}
			}
			next, desired, next_ok, next_failure := display.navigation_target(
				request.buffer,
				working,
				.Next_Grapheme,
				request.profile,
			)
			if !next_ok {
				return {}, false, native_display_failure(request.command, next_failure)
			}
			if next.byte_offset > line.content_end do break
			replacement_end = next
			working.point_position = next
			working.desired_display_column = desired
			input_offset = grapheme.end
		}
	} else if logical.overwrite_mode {
		next, _, next_ok, next_failure := display.navigation_target(
			request.buffer,
			logical,
			.Next_Grapheme,
			request.profile,
		)
		if !next_ok {
			return {}, false, native_display_failure(request.command, next_failure)
		}
		replacement_end = next
	}
	edit_request := request
	if overwrite && edit_request.history_grouping.kind == .Typing_Insert {
		edit_request.history_grouping.kind = .Independent
	}
	return native_edit_publish(
		edit_request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		logical.point_position,
		replacement_end,
		text,
		editor.Byte_Offset(u64(logical.point_position.byte_offset) + u64(len(text))),
		final_column,
		false,
		nil,
	)
}

@(private)
native_insert_indentation :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	policy := logical.indentation_policy.policy
	if len(request.text) != 0 || policy.indent_width == 0 ||
	   policy.indent_width > editor_view.MAX_TAB_WIDTH {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	if policy.representation == .Tabs {
		return native_insert(request, logical, "\t", command_name)
	}
	spaces: [editor_view.MAX_TAB_WIDTH]u8
	for index in 0 ..< int(policy.indent_width) do spaces[index] = ' '
	return native_insert(request, logical, string(spaces[:policy.indent_width]), command_name)
}

@(private)
native_indent_lines :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	outdent: bool,
	command_name: string,
	rigid_columns: u16 = 0,
) -> (Native_Result, bool, Failure_Context) {
	policy := logical.indentation_policy.policy
	if len(request.text) != 0 || policy.indent_width == 0 ||
	   policy.indent_width > editor_view.MAX_TAB_WIDTH {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	start, end, selected, range_ok, range_failure := native_region_text(request, logical)
	if !range_ok do return {}, false, range_failure
	delete(selected, request.temporary_allocator)
	first_line, first_ok, first_failure := editor.buffer_line_at_position(request.buffer, start)
	if !first_ok do return {}, false, native_editor_failure(request.command, first_failure)
	last_line, last_ok, last_failure := editor.buffer_line_at_position(request.buffer, end)
	if !last_ok do return {}, false, native_editor_failure(request.command, last_failure)
	if end.byte_offset == last_line.start && end.byte_offset > first_line.start {
		previous, previous_ok, previous_failure := editor.buffer_position(
			request.buffer,
			editor.Byte_Offset(u64(end.byte_offset) - 1),
		)
		if !previous_ok do return {}, false, native_editor_failure(request.command, previous_failure)
		last_line, last_ok, last_failure = editor.buffer_line_at_position(request.buffer, previous)
		if !last_ok do return {}, false, native_editor_failure(request.command, last_failure)
	}
	line_start, start_ok, start_failure := editor.buffer_position(request.buffer, first_line.start)
	if !start_ok do return {}, false, native_editor_failure(request.command, start_failure)
	line_end, end_ok, end_failure := editor.buffer_position(request.buffer, last_line.next_start)
	if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
	length := u64(line_end.byte_offset) - u64(line_start.byte_offset)
	if length == 0 || length > editor.MAX_REPLACEMENT_BYTES {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.command,
			limit = editor.MAX_REPLACEMENT_BYTES,
			actual = length,
		}
	}
	source, source_error := make([]byte, int(length), request.temporary_allocator)
	if source_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = request.command, actual = length}
	}
	defer delete(source, request.temporary_allocator)
	_, inspected, inspect_failure := editor.buffer_inspect(
		request.buffer,
		line_start.byte_offset,
		line_end.byte_offset,
		source,
	)
	if !inspected do return {}, false, native_editor_failure(request.command, inspect_failure)
	line_count := u64(1)
	for value, index in source {
		if value == '\n' && index + 1 < len(source) do line_count += 1
	}
	indent_width := policy.indent_width
	if rigid_columns > 0 do indent_width = rigid_columns
	output_bytes := length
	if !outdent {
		indent_unit_bytes := u64(indent_width)
		if rigid_columns == 0 && policy.representation == .Tabs do indent_unit_bytes = 1
		indent_bytes := line_count * indent_unit_bytes
		if indent_bytes > editor.MAX_REPLACEMENT_BYTES - length {
			return {}, false, Failure_Context {
				code = .Invalid_Request,
				command = request.command,
				limit = editor.MAX_REPLACEMENT_BYTES,
				actual = length + indent_bytes,
			}
		}
		output_bytes += indent_bytes
	}
	output, output_error := make([]byte, int(output_bytes), request.temporary_allocator)
	if output_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = request.command, actual = output_bytes}
	}
	defer delete(output, request.temporary_allocator)
	read := 0
	written := 0
	line_boundary := true
	for read < len(source) {
		if line_boundary {
			if outdent {
				if source[read] == '\t' {
					read += 1
				} else {
					removed := u16(0)
					for read < len(source) && source[read] == ' ' && removed < indent_width {
						read += 1
						removed += 1
					}
				}
			} else {
				if rigid_columns == 0 && policy.representation == .Tabs {
					output[written] = '\t'
					written += 1
				} else {
					for _ in 0 ..< indent_width {
						output[written] = ' '
						written += 1
					}
				}
			}
			line_boundary = false
			if read >= len(source) do break
		}
		output[written] = source[read]
		line_boundary = source[read] == '\n'
		written += 1
		read += 1
	}
	if outdent && written == len(source) {
		return Native_Result{completion = .No_Op}, true, {}
	}
	return native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		line_start,
		line_end,
		string(output[:written]),
		line_start.byte_offset,
		0,
		false,
		nil,
	)
}

@(private)
native_normalize_indentation :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	target: indentation.Normalization_Target,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	policy := logical.indentation_policy.policy
	if len(request.text) != 0 || policy.indent_width == 0 ||
	   policy.indent_width > editor_view.MAX_TAB_WIDTH {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	selection_start := logical.point_position
	selection_end := logical.point_position
	if request.explicit_range.present {
		selection_start = request.explicit_range.start
		selection_end = request.explicit_range.end
		if selection_start.buffer_id != logical.buffer_id ||
		   selection_end.buffer_id != logical.buffer_id ||
		   selection_start.revision != logical.revision ||
		   selection_end.revision != logical.revision ||
		   selection_start.byte_offset >= selection_end.byte_offset {
			return {}, false, Failure_Context{code = .Region_Unavailable, command = request.command}
		}
	} else if logical.region_active && logical.mark.present {
		selection_end = logical.mark.position
		if selection_end.buffer_id != logical.buffer_id || selection_end.revision != logical.revision {
			return {}, false, Failure_Context{code = .Region_Unavailable, command = request.command}
		}
		if selection_start.byte_offset > selection_end.byte_offset {
			selection_start, selection_end = selection_end, selection_start
		}
	}
	first_line, first_ok, first_failure := editor.buffer_line_at_position(
		request.buffer,
		selection_start,
	)
	if !first_ok do return {}, false, native_editor_failure(request.command, first_failure)
	last_line, last_ok, last_failure := editor.buffer_line_at_position(request.buffer, selection_end)
	if !last_ok do return {}, false, native_editor_failure(request.command, last_failure)
	if selection_end.byte_offset == last_line.start && selection_end.byte_offset > first_line.start {
		previous, previous_ok, previous_failure := editor.buffer_position(
			request.buffer,
			editor.Byte_Offset(u64(selection_end.byte_offset) - 1),
		)
		if !previous_ok do return {}, false, native_editor_failure(request.command, previous_failure)
		last_line, last_ok, last_failure = editor.buffer_line_at_position(request.buffer, previous)
		if !last_ok do return {}, false, native_editor_failure(request.command, last_failure)
	}
	start, start_ok, start_failure := editor.buffer_position(request.buffer, first_line.start)
	if !start_ok do return {}, false, native_editor_failure(request.command, start_failure)
	end, end_ok, end_failure := editor.buffer_position(request.buffer, last_line.next_start)
	if !end_ok do return {}, false, native_editor_failure(request.command, end_failure)
	source_bytes := u64(end.byte_offset) - u64(start.byte_offset)
	if source_bytes > editor.MAX_REPLACEMENT_BYTES {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.command,
			limit = editor.MAX_REPLACEMENT_BYTES,
			actual = source_bytes,
		}
	}
	source, source_error := make([]byte, int(source_bytes), request.temporary_allocator)
	if source_error != nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = request.command,
			actual = source_bytes,
		}
	}
	defer delete(source, request.temporary_allocator)
	_, inspected, inspect_failure := editor.buffer_inspect(
		request.buffer,
		start.byte_offset,
		end.byte_offset,
		source,
	)
	if !inspected do return {}, false, native_editor_failure(request.command, inspect_failure)
	measurement, measured := indentation.normalization_measure(string(source), policy, target)
	if !measured || measurement.required_bytes > editor.MAX_REPLACEMENT_BYTES {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.command,
			limit = editor.MAX_REPLACEMENT_BYTES,
			actual = measurement.required_bytes,
		}
	}
	if !measurement.changed do return Native_Result{completion = .No_Op}, true, {}
	output, output_error := make([]byte, int(measurement.required_bytes), request.temporary_allocator)
	if output_error != nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = request.command,
			actual = measurement.required_bytes,
		}
	}
	defer delete(output, request.temporary_allocator)
	written, changed, normalized := indentation.normalize_leading(
		string(source),
		output,
		policy,
		target,
	)
	assert(normalized && changed && written == len(output))
	if !normalized || !changed || written != len(output) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	return native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		end,
		string(output),
		start.byte_offset,
		0,
		false,
		nil,
	)
}

@(private)
native_delete :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	backward: bool,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	failure := validate_display_request(request, logical, 2, true)
	if failure.code != .None {
		return {}, false, failure
	}
	kind := display.Navigation_Kind.Next_Grapheme
	if backward {
		kind = .Previous_Grapheme
	}
	repeat_count := request.repeat_count
	if repeat_count == 0 do repeat_count = 1
	if repeat_count > interaction.MAX_MODAL_COUNT {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.command,
			limit = interaction.MAX_MODAL_COUNT,
			actual = repeat_count,
		}
	}
	if backward {
		smart_result, smart_ok, smart_failure, smart := native_smart_backspace(
			request,
			logical,
			repeat_count,
			command_name,
		)
		if smart do return smart_result, smart_ok, smart_failure
	}
	working := logical
	target := logical.point_position
	for _ in 0 ..< repeat_count {
		next, desired, target_ok, target_failure := display.navigation_target(
			request.buffer,
			working,
			kind,
			request.profile,
		)
		if !target_ok {
			return {}, false, native_display_failure(request.command, target_failure)
		}
		if next == target do break
		target = next
		working.point_position = next
		working.desired_display_column = desired
	}
	if target == logical.point_position {
		return Native_Result{completion = .No_Op}, true, {}
	}
	final_column := u32(0)
	column_position := logical.point_position
	if backward {
		column_position = target
	}
	column_ok: bool
	column_failure: display.Failure_Context
	final_column, column_ok, column_failure = display.position_display_column(
		request.buffer,
		column_position,
		request.profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, false, native_display_failure(request.command, column_failure)
	}
	start := logical.point_position
	end := target
	if backward {
		start = target
		end = logical.point_position
	}
	result_offset := start.byte_offset
	return native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		end,
		"",
		result_offset,
		final_column,
		false,
		nil,
	)
}

@(private)
native_smart_backspace :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	repeat_count: u64,
	command_name: string,
) -> (result: Native_Result, ok: bool, failure: Failure_Context, handled: bool) {
	line, line_ok, line_failure := editor.buffer_line_at_position(
		request.buffer,
		logical.point_position,
	)
	if !line_ok {
		return {}, false, native_editor_failure(request.command, line_failure), true
	}
	prefix_bytes := u64(logical.point_position.byte_offset) - u64(line.start)
	if prefix_bytes == 0 do return {}, false, {}, false
	if prefix_bytes > editor.MAX_REPLACEMENT_BYTES {
		return {}, false, Failure_Context {
			code = .Invalid_Request,
			command = request.command,
			limit = editor.MAX_REPLACEMENT_BYTES,
			actual = prefix_bytes,
		}, true
	}
	prefix, prefix_error := make([]byte, int(prefix_bytes), request.temporary_allocator)
	if prefix_error != nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = request.command,
			actual = prefix_bytes,
		}, true
	}
	defer delete(prefix, request.temporary_allocator)
	_, inspected, inspect_failure := editor.buffer_inspect(
		request.buffer,
		line.start,
		logical.point_position.byte_offset,
		prefix,
	)
	if !inspected {
		return {}, false, native_editor_failure(request.command, inspect_failure), true
	}
	target := len(prefix)
	for _ in 0 ..< repeat_count {
		plan, planned := indentation.smart_backspace_plan(
			string(prefix[:target]),
			logical.indentation_policy.policy,
		)
		if !planned {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}, true
		}
		if !plan.semantic {
			if target == len(prefix) do return {}, false, {}, false
			break
		}
		target = plan.start
		if target == 0 do break
	}
	start, start_ok, start_failure := editor.buffer_position(
		request.buffer,
		editor.Byte_Offset(u64(line.start) + u64(target)),
	)
	if !start_ok {
		return {}, false, native_editor_failure(request.command, start_failure), true
	}
	final_column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		start,
		request.profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, false, native_display_failure(request.command, column_failure), true
	}
	result, ok, failure = native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		logical.point_position,
		"",
		start.byte_offset,
		final_column,
		false,
		nil,
	)
	return result, ok, failure, true
}

@(private)
native_edit_publish :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	origin: edit_transaction.Origin,
	command_name: string,
	start, end: editor.Position,
	replacement: string,
	result_cursor_offset: editor.Byte_Offset,
	desired_display_column: u32,
	publish_ring: bool,
	ring_reservation: ^kill_ring.Reservation,
) -> (Native_Result, bool, Failure_Context) {
	if request.persistent_allocator.procedure == nil ||
	   request.transaction_id == edit_transaction.Transaction_ID(0) ||
	   request.undo_unit_id == edit_transaction.Undo_Unit_ID(0) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	transaction: edit_transaction.Transaction
	started, begin_failure := edit_transaction.transaction_begin(
		&transaction,
		request.transaction_id,
		request.undo_unit_id,
		request.buffer,
		origin,
		command_name,
		edit_transaction.Allocator_Set {
			persistent = request.persistent_allocator,
			temporary = request.temporary_allocator,
		},
	)
	if !started {
		return {}, false, native_transaction_failure(request.command, begin_failure)
	}
	defer {
		if edit_transaction.transaction_is_valid(&transaction) {
			closed, _ := edit_transaction.transaction_close(&transaction)
			assert(closed)
		}
	}
	applied, apply_failure := edit_transaction.transaction_apply_batch(
		&transaction,
		[]edit_transaction.Base_Splice{{start = start, end = end, replacement = replacement}},
	)
	if !applied {
		return {}, false, native_transaction_failure(request.command, apply_failure)
	}
	target, target_ok, target_failure := edit_transaction.transaction_position(
		&transaction,
		result_cursor_offset,
	)
	if !target_ok {
		return {}, false, native_transaction_failure(request.command, target_failure)
	}
	view_prepared, view_failure := edit_transaction.transaction_prepare_logical_view(
		&transaction,
		request.view_registry,
		request.view,
		target,
		desired_display_column,
		.Deactivate,
	)
	if !view_prepared {
		return {}, false, native_transaction_failure(request.command, view_failure)
	}
	if request.history_store != nil {
		tracked, track_failure := edit_transaction.transaction_track_history(
			&transaction,
			request.history_store,
			request.history_grouping,
		)
		if !tracked {
			return {}, false, native_transaction_failure(request.command, track_failure)
		}
	}
	validated, validation_failure := edit_transaction.transaction_validate(&transaction)
	if !validated {
		return {}, false, native_transaction_failure(request.command, validation_failure)
	}
	transfer: kill_ring.Reservation_Result
	if publish_ring {
		assert(kill_ring.reservation_is_valid(ring_reservation))
		transfer = kill_ring.reservation_commit_reserved(ring_reservation)
	}
	commit, committed, commit_failure := edit_transaction.transaction_commit(
		&transaction,
		request.commit_observer,
	)
	assert(committed, "validated native edit failed during allocation-free publication")
	if !committed {
		return {}, false, native_transaction_failure(request.command, commit_failure)
	}
	finish_committed_view(request, desired_display_column)
	owned_transaction := transaction
	transaction = {}
	return Native_Result {
		completion = .Buffer_Committed,
		transaction = owned_transaction,
		commit = commit,
		transfer = transfer,
	}, true, {}
}

@(private)
native_copy_region :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
) -> (Native_Result, bool, Failure_Context) {
	if request.kill_ring == nil || !kill_ring.ring_is_valid(request.kill_ring) ||
		request.temporary_allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	start, end, text, region_ok, region_failure := native_region_text(request, logical)
	_ = start
	_ = end
	if !region_ok {
		return {}, false, region_failure
	}
	defer delete(text, request.temporary_allocator)
	stats, stats_ok, stats_failure := kill_ring.ring_stats(request.kill_ring)
	if !stats_ok {
		return {}, false, native_kill_ring_failure(request.command, stats_failure)
	}
	reservation: kill_ring.Reservation
	result, reserved, reserve_failure := kill_ring.admission_reserve(
		request.kill_ring,
		&reservation,
		kill_ring.Admission_Request {
			expected_generation = stats.generation,
			kind = .Copy,
			text = string(text),
		},
	)
	if !reserved {
		return {}, false, native_kill_ring_failure(request.command, reserve_failure)
	}
	committed := kill_ring.reservation_commit_reserved(&reservation)
	assert(committed == result)
	return Native_Result{completion = .Text_Retained, transfer = committed}, true, {}
}

@(private)
native_copy_rectangle :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 || request.kill_ring == nil ||
	   !kill_ring.ring_is_valid(request.kill_ring) ||
	   request.temporary_allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	_, ranges, resolved, resolve_failure := display.rectangular_selection_ranges(
		request.buffer, logical, request.profile, request.temporary_allocator,
	)
	if !resolved do return {}, false, native_display_failure(request.command, resolve_failure)
	defer delete(ranges, request.temporary_allocator)
	text, copied, copy_failure := native_rectangle_text(request, ranges)
	if !copied do return {}, false, copy_failure
	defer delete(text, request.temporary_allocator)
	stats, stats_ok, stats_failure := kill_ring.ring_stats(request.kill_ring)
	if !stats_ok do return {}, false, native_kill_ring_failure(request.command, stats_failure)
	reservation: kill_ring.Reservation
	result, reserved, reserve_failure := kill_ring.admission_reserve(
		request.kill_ring,
		&reservation,
		kill_ring.Admission_Request {
			expected_generation = stats.generation,
			kind = .Copy,
			text = string(text),
		},
	)
	if !reserved do return {}, false, native_kill_ring_failure(request.command, reserve_failure)
	committed := kill_ring.reservation_commit_reserved(&reservation)
	assert(committed == result)
	return Native_Result{completion = .Text_Retained, transfer = committed}, true, {}
}

@(private)
native_edit_rectangle :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	replacement: string,
	retain: bool,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if retain && len(request.text) != 0 ||
	   request.persistent_allocator.procedure == nil ||
	   request.temporary_allocator.procedure == nil ||
	   request.transaction_id == edit_transaction.Transaction_ID(0) ||
	   request.undo_unit_id == edit_transaction.Undo_Unit_ID(0) ||
	   !utf8.valid_string(replacement) ||
	   u64(len(replacement)) > interaction.MAX_TEXT_BYTES {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	_, ranges, resolved, resolve_failure := display.rectangular_selection_ranges(
		request.buffer, logical, request.profile, request.temporary_allocator,
	)
	if !resolved do return {}, false, native_display_failure(request.command, resolve_failure)
	defer delete(ranges, request.temporary_allocator)
	splice_count := 0
	for selected in ranges {
		if selected.start.byte_offset < selected.end.byte_offset || len(replacement) > 0 {
			splice_count += 1
		}
	}
	if splice_count == 0 do return Native_Result{completion = .No_Op}, true, {}
	splices, splice_error := make(
		[]edit_transaction.Base_Splice, splice_count, request.temporary_allocator,
	)
	if splice_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = request.command}
	}
	defer delete(splices, request.temporary_allocator)
	splice_index := 0
	for selected in ranges {
		if selected.start.byte_offset == selected.end.byte_offset && len(replacement) == 0 do continue
		splices[splice_index] = {
			start = selected.start,
			end = selected.end,
			replacement = replacement,
		}
		splice_index += 1
	}
	retained_text: []u8
	reservation: kill_ring.Reservation
	if retain {
		if request.kill_ring == nil || !kill_ring.ring_is_valid(request.kill_ring) ||
		   request.kill_sequence_id == 0 || request.event_sequence == 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		copied: bool
		copy_failure: Failure_Context
		retained_text, copied, copy_failure = native_rectangle_text(request, ranges)
		if !copied do return {}, false, copy_failure
		defer delete(retained_text, request.temporary_allocator)
		stats, stats_ok, stats_failure := kill_ring.ring_stats(request.kill_ring)
		if !stats_ok do return {}, false, native_kill_ring_failure(request.command, stats_failure)
		_, reserved, reserve_failure := kill_ring.admission_reserve(
			request.kill_ring,
			&reservation,
			kill_ring.Admission_Request {
				expected_generation = stats.generation,
				kind = .Kill,
				text = string(retained_text),
				kill = {
					sequence_id = request.kill_sequence_id,
					event_sequence = request.event_sequence,
					source_buffer_id = u64(logical.buffer_id),
					start = u64(ranges[0].start.byte_offset),
					end = u64(ranges[len(ranges) - 1].end.byte_offset),
					direction = .Forward,
				},
			},
		)
		if !reserved do return {}, false, native_kill_ring_failure(request.command, reserve_failure)
	}
	defer if kill_ring.reservation_is_valid(&reservation) {
		aborted, _ := kill_ring.reservation_abort(&reservation)
		assert(aborted)
	}
	final_column, column_ok, column_failure := display.position_display_column(
		request.buffer, ranges[0].start, request.profile, logical.tab_width,
	)
	if !column_ok do return {}, false, native_display_failure(request.command, column_failure)
	transaction: edit_transaction.Transaction
	started, begin_failure := edit_transaction.transaction_begin(
		&transaction,
		request.transaction_id,
		request.undo_unit_id,
		request.buffer,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		edit_transaction.Allocator_Set {
			persistent = request.persistent_allocator,
			temporary = request.temporary_allocator,
		},
	)
	if !started do return {}, false, native_transaction_failure(request.command, begin_failure)
	defer if edit_transaction.transaction_is_valid(&transaction) {
		closed, _ := edit_transaction.transaction_close(&transaction)
		assert(closed)
	}
	applied, apply_failure := edit_transaction.transaction_apply_batch(&transaction, splices)
	if !applied do return {}, false, native_transaction_failure(request.command, apply_failure)
	target, target_ok, target_failure := edit_transaction.transaction_position(
		&transaction, ranges[0].start.byte_offset,
	)
	if !target_ok do return {}, false, native_transaction_failure(request.command, target_failure)
	view_prepared, view_failure := edit_transaction.transaction_prepare_logical_view(
		&transaction,
		request.view_registry,
		request.view,
		target,
		final_column,
		.Deactivate,
	)
	if !view_prepared do return {}, false, native_transaction_failure(request.command, view_failure)
	if request.history_store != nil {
		tracked, track_failure := edit_transaction.transaction_track_history(
			&transaction, request.history_store, request.history_grouping,
		)
		if !tracked do return {}, false, native_transaction_failure(request.command, track_failure)
	}
	validated, validation_failure := edit_transaction.transaction_validate(&transaction)
	if !validated do return {}, false, native_transaction_failure(request.command, validation_failure)
	transfer: kill_ring.Reservation_Result
	if retain do transfer = kill_ring.reservation_commit_reserved(&reservation)
	commit, committed, commit_failure := edit_transaction.transaction_commit(
		&transaction, request.commit_observer,
	)
	assert(committed, "validated rectangle edit failed during allocation-free publication")
	if !committed do return {}, false, native_transaction_failure(request.command, commit_failure)
	finish_committed_view(request, final_column)
	owned_transaction := transaction
	transaction = {}
	return Native_Result {
		completion = .Buffer_Committed,
		transaction = owned_transaction,
		commit = commit,
		transfer = transfer,
	}, true, {}
}

@(private)
native_rectangle_text :: proc(
	request: Native_Context,
	ranges: []display.Selection_Range,
) -> (text: []u8, ok: bool, failure: Failure_Context) {
	if len(ranges) == 0 || request.temporary_allocator.procedure == nil {
		return nil, false, Failure_Context{code = .Region_Unavailable, command = request.command}
	}
	bytes := u64(len(ranges) - 1)
	for selected in ranges {
		length := u64(selected.end.byte_offset) - u64(selected.start.byte_offset)
		if length > edit_transaction.MAX_TEXT_BYTES - bytes {
			return nil, false, Failure_Context{code = .Text_Limit, command = request.command, limit = edit_transaction.MAX_TEXT_BYTES, actual = bytes + length}
		}
		bytes += length
	}
	if bytes > u64(max(int)) {
		return nil, false, Failure_Context{code = .Text_Limit, command = request.command, limit = u64(max(int)), actual = bytes}
	}
	allocation_error: runtime.Allocator_Error
	text, allocation_error = make([]u8, int(bytes), request.temporary_allocator)
	if allocation_error != nil {
		return nil, false, Failure_Context{code = .Temporary_Memory_Limit, command = request.command, actual = bytes}
	}
	written := 0
	for selected, index in ranges {
		length := int(u64(selected.end.byte_offset) - u64(selected.start.byte_offset))
		if length > 0 {
			_, inspected, inspect_failure := editor.buffer_inspect(
				request.buffer,
				selected.start.byte_offset,
				selected.end.byte_offset,
				text[written:written + length],
			)
			if !inspected {
				delete(text, request.temporary_allocator)
				return nil, false, native_editor_failure(request.command, inspect_failure)
			}
			written += length
		}
		if index + 1 < len(ranges) {
			text[written] = '\n'
			written += 1
		}
	}
	assert(written == len(text))
	return text, true, {}
}

@(private)
native_remove_region :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	retain: bool,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) != 0 {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	failure := validate_display_request(request, logical, 2, true)
	if failure.code != .None {
		return {}, false, failure
	}
	start, end, text, region_ok, region_failure := native_region_text(request, logical)
	if !region_ok {
		return {}, false, region_failure
	}
	defer delete(text, request.temporary_allocator)
	final_column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		start,
		request.profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, false, native_display_failure(request.command, column_failure)
	}
	reservation: kill_ring.Reservation
	if retain {
		if request.kill_ring == nil || !kill_ring.ring_is_valid(request.kill_ring) ||
			request.kill_sequence_id == 0 || request.event_sequence == 0 {
			return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
		}
		stats, stats_ok, stats_failure := kill_ring.ring_stats(request.kill_ring)
		if !stats_ok {
			return {}, false, native_kill_ring_failure(request.command, stats_failure)
		}
		direction := kill_ring.Kill_Direction.Forward
		if request.explicit_range.present && request.explicit_range.backward ||
		   !request.explicit_range.present &&
		   logical.point_position.byte_offset > logical.mark.position.byte_offset {
			direction = .Backward
		}
		_, reserved, reserve_failure := kill_ring.admission_reserve(
			request.kill_ring,
			&reservation,
			kill_ring.Admission_Request {
				expected_generation = stats.generation,
				kind = .Kill,
				text = string(text),
				kill = {
					sequence_id = request.kill_sequence_id,
					event_sequence = request.event_sequence,
					source_buffer_id = u64(logical.buffer_id),
					start = u64(start.byte_offset),
					end = u64(end.byte_offset),
					direction = direction,
				},
			},
		)
		if !reserved {
			return {}, false, native_kill_ring_failure(request.command, reserve_failure)
		}
	}
	defer {
		if kill_ring.reservation_is_valid(&reservation) {
			aborted, _ := kill_ring.reservation_abort(&reservation)
			assert(aborted)
		}
	}
	ring_participant: ^kill_ring.Reservation = nil
	if retain {
		ring_participant = &reservation
	}
	return native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		end,
		"",
		start.byte_offset,
		final_column,
		retain,
		ring_participant,
	)
}

@(private)
native_replace_region_text :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if len(request.text) == 0 {
		return {}, false, Failure_Context{code = .Missing_Text, command = request.command}
	}
	if len(request.text) > interaction.MAX_TEXT_BYTES {
		return {}, false, Failure_Context {
			code = .Text_Limit,
			command = request.command,
			limit = interaction.MAX_TEXT_BYTES,
			actual = u64(len(request.text)),
		}
	}
	if !utf8.valid_string(request.text) {
		return {}, false, Failure_Context{code = .Malformed_Text, command = request.command}
	}
	failure := validate_display_request(request, logical, 2, true)
	if failure.code != .None do return {}, false, failure
	start, end, previous, region_ok, region_failure := native_region_text(request, logical)
	if !region_ok do return {}, false, region_failure
	defer delete(previous, request.temporary_allocator)
	replacement_text := request.text
	repeated: []u8
	repeat_count := request.repeat_count
	if repeat_count == 0 do repeat_count = 1
	if repeat_count > 1 {
		if repeat_count > u64(interaction.MAX_TEXT_BYTES) / u64(len(request.text)) {
			return {}, false, Failure_Context {
				code = .Text_Limit,
				command = request.command,
				limit = interaction.MAX_TEXT_BYTES,
				actual = u64(len(request.text)) * repeat_count,
			}
		}
		allocation_error: runtime.Allocator_Error
		repeated, allocation_error = make(
			[]u8,
			int(u64(len(request.text)) * repeat_count),
			request.temporary_allocator,
		)
		if allocation_error != nil {
			return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = request.command}
		}
		defer delete(repeated, request.temporary_allocator)
		for index in 0 ..< int(repeat_count) {
			copy(repeated[index * len(request.text):], transmute([]u8)request.text)
		}
		replacement_text = string(repeated)
	}
	start_column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		start,
		request.profile,
		logical.tab_width,
	)
	if !column_ok do return {}, false, native_display_failure(request.command, column_failure)
	final_column, width_ok, width_failure := inserted_text_end_column(
		replacement_text,
		start_column,
		logical.tab_width,
		request.profile,
	)
	if !width_ok {
		width_failure.command = request.command
		return {}, false, width_failure
	}
	return native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		end,
		replacement_text,
		editor.Byte_Offset(u64(start.byte_offset) + u64(len(replacement_text))),
		final_column,
		false,
		nil,
	)
}

@(private)
native_yank :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	rotate: bool,
	command_name: string,
) -> (Native_Result, bool, Failure_Context) {
	if request.kill_ring == nil || !kill_ring.ring_is_valid(request.kill_ring) ||
		request.yank_context == nil || request.temporary_allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	failure := validate_display_request(request, logical, 2, true)
	if failure.code != .None {
		return {}, false, failure
	}
	stats, stats_ok, stats_failure := kill_ring.ring_stats(request.kill_ring)
	if !stats_ok {
		return {}, false, native_kill_ring_failure(request.command, stats_failure)
	}
	start := logical.point_position
	end := logical.point_position
	current_entry := stats.newest
	if rotate {
		ctx := request.yank_context^
		request.yank_context^ = {}
		if !ctx.valid || ctx.view != request.view || ctx.buffer_id != logical.buffer_id ||
			ctx.revision != logical.revision || ctx.ring_generation != stats.generation {
			return {}, false, Failure_Context {
				code = .Kill_Ring_Failure,
				command = request.command,
				kill_ring_code = .Stale_Generation,
				kill_ring_generation = stats.generation,
			}
		}
		start = editor.Position {
			buffer_id = ctx.buffer_id,
			revision = ctx.revision,
			byte_offset = ctx.start,
		}
		end = editor.Position {
			buffer_id = ctx.buffer_id,
			revision = ctx.revision,
			byte_offset = ctx.end,
		}
		current_entry = ctx.entry_id
	}
	if current_entry == kill_ring.Entry_ID(0) {
		return {}, false, Failure_Context {
			code = .Kill_Ring_Failure,
			command = request.command,
			kill_ring_code = .Empty_Ring,
		}
	}
	copied: kill_ring.Entry_Copy
	copied_ok: bool
	copy_failure: kill_ring.Failure_Context
	if rotate {
		copied, copied_ok, copy_failure = kill_ring.rotation_next(
			request.kill_ring,
			kill_ring.Rotation_Request {
				expected_generation = stats.generation,
				current_entry = current_entry,
				work_limit = stats.policy.rotation_work,
				byte_limit = stats.policy.entry_bytes,
			},
			request.temporary_allocator,
		)
	} else {
		copied, copied_ok, copy_failure = kill_ring.entry_copy(
			request.kill_ring,
			kill_ring.Entry_Copy_Request {
				expected_generation = stats.generation,
				entry_id = current_entry,
				byte_limit = stats.policy.entry_bytes,
			},
			request.temporary_allocator,
		)
	}
	if !copied_ok {
		return {}, false, native_kill_ring_failure(request.command, copy_failure)
	}
	defer kill_ring.entry_copy_release(&copied, request.temporary_allocator)
	insert_text := copied.text
	repeated: []u8
	repeat_count := request.repeat_count
	if repeat_count == 0 do repeat_count = 1
	if repeat_count > 1 {
		if len(copied.text) == 0 ||
		   repeat_count > u64(interaction.MAX_TEXT_BYTES) / u64(len(copied.text)) {
			return {}, false, Failure_Context {
				code = .Text_Limit,
				command = request.command,
				limit = interaction.MAX_TEXT_BYTES,
				actual = u64(len(copied.text)) * repeat_count,
			}
		}
		allocation_error: runtime.Allocator_Error
		repeated, allocation_error = make(
			[]u8,
			int(u64(len(copied.text)) * repeat_count),
			request.temporary_allocator,
		)
		if allocation_error != nil {
			return {}, false, Failure_Context{code = .Temporary_Memory_Limit, command = request.command}
		}
		defer delete(repeated, request.temporary_allocator)
		for index in 0 ..< int(repeat_count) {
			copy(repeated[index * len(copied.text):], transmute([]u8)copied.text)
		}
		insert_text = string(repeated)
	}
	start_column, column_ok, column_failure := display.position_display_column(
		request.buffer,
		start,
		request.profile,
		logical.tab_width,
	)
	if !column_ok {
		return {}, false, native_display_failure(request.command, column_failure)
	}
	final_column, width_ok, width_failure := inserted_text_end_column(
		insert_text,
		start_column,
		logical.tab_width,
		request.profile,
	)
	if !width_ok {
		width_failure.command = request.command
		return {}, false, width_failure
	}
	result_end := editor.Byte_Offset(u64(start.byte_offset) + u64(len(insert_text)))
	result, published, publication_failure := native_edit_publish(
		request,
		logical,
		edit_transaction.Origin{kind = .Built_In, descriptor = "native-command"},
		command_name,
		start,
		end,
		insert_text,
		result_end,
		final_column,
		false,
		nil,
	)
	if !published {
		return {}, false, publication_failure
	}
	request.yank_context^ = Yank_Context {
		valid = true,
		view = request.view,
		buffer_id = logical.buffer_id,
		revision = result.commit.result_revision,
		start = start.byte_offset,
		end = result_end,
		ring_generation = stats.generation,
		entry_id = copied.metadata.id,
	}
	return result, true, {}
}

@(private)
native_region_text :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
) -> (start, end: editor.Position, text: []byte, ok: bool, failure: Failure_Context) {
	if request.explicit_range.present {
		start = request.explicit_range.start
		end = request.explicit_range.end
		if start.buffer_id != logical.buffer_id || end.buffer_id != logical.buffer_id ||
		   start.revision != logical.revision || end.revision != logical.revision ||
		   start.byte_offset >= end.byte_offset {
			return {}, {}, nil, false, Failure_Context{code = .Region_Unavailable, command = request.command}
		}
	} else {
		if !logical.region_active || !logical.mark.present ||
		   logical.mark.position.buffer_id != logical.buffer_id ||
		   logical.mark.position.revision != logical.revision {
			return {}, {}, nil, false, Failure_Context{code = .Region_Unavailable, command = request.command}
		}
		start = logical.point_position
		end = logical.mark.position
		if start.byte_offset > end.byte_offset {
			start, end = end, start
		}
	}
	bytes := u64(end.byte_offset) - u64(start.byte_offset)
	if bytes == 0 {
		return {}, {}, nil, false, Failure_Context{code = .Region_Unavailable, command = request.command}
	}
	allocation_error: runtime.Allocator_Error
	text, allocation_error = make([]byte, int(bytes), request.temporary_allocator)
	if allocation_error != nil {
		return {}, {}, nil, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = request.command,
			actual = bytes,
		}
	}
	_, inspected, inspect_failure := editor.buffer_inspect(
		request.buffer,
		start.byte_offset,
		end.byte_offset,
		text,
	)
	if !inspected {
		delete(text, request.temporary_allocator)
		return {}, {}, nil, false, native_editor_failure(request.command, inspect_failure)
	}
	return start, end, text, true, {}
}

@(private)
native_history_navigate :: proc(
	request: Native_Context,
	kind: history.Navigation_Kind,
) -> (Native_Result, bool, Failure_Context) {
	if request.history_store == nil || !history.store_is_valid(request.history_store) ||
	   request.persistent_allocator.procedure == nil || request.temporary_allocator.procedure == nil ||
	   request.transaction_id == edit_transaction.Transaction_ID(0) ||
	   request.undo_unit_id == edit_transaction.Undo_Unit_ID(0) {
		return {}, false, Failure_Context{code = .Invalid_Request, command = request.command}
	}
	result, navigated, navigation_failure := edit_transaction.transaction_history_navigate(
		request.history_store,
		request.buffer,
		kind,
		request.transaction_id,
		request.undo_unit_id,
		edit_transaction.Allocator_Set {
			persistent = request.persistent_allocator,
			temporary = request.temporary_allocator,
		},
		edit_transaction.DEFAULT_LIMITS,
		request.view_registry,
		request.view,
		observer = request.commit_observer,
	)
	if !navigated {
		return {}, false, native_transaction_failure(request.command, navigation_failure)
	}
	if result.outcome != .Applied {
		return Native_Result{completion = .No_Op}, true, {}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(request.view_registry, request.view)
	if !logical_ok {
		return {}, false, native_view_failure(request.command, logical_failure)
	}
	finish_committed_view(request, logical.desired_display_column)
	return Native_Result{completion = .Buffer_Committed}, true, {}
}

@(private)
validate_display_request :: proc(
	request: Native_Context,
	logical: editor_view.Snapshot,
	reserved_view_changes: u64,
	require_temporary_allocator: bool,
) -> Failure_Context {
	if !display.display_profile_is_valid(request.profile) ||
	   display.Display_Profile_ID(u64(logical.display_profile_id)) != request.profile.id {
		return Failure_Context {
			code = .Display_Failure,
			command = request.command,
			display_code = .Invalid_Profile,
		}
	}
	constraints_ok, constraints_failure := display.constraints_are_valid(request.constraints)
	if !constraints_ok {
		return native_display_failure(request.command, constraints_failure)
	}
	if require_temporary_allocator && request.temporary_allocator.procedure == nil {
		return Failure_Context {
			code = .Temporary_Memory_Limit,
			command = request.command,
			limit = editor.MAX_TEMPORARY_BYTES,
		}
	}
	if logical.state_generation > max(u64) - reserved_view_changes {
		return Failure_Context {
			code = .View_Failure,
			command = request.command,
			view_code = .State_Generation_Limit,
			limit = max(u64),
			actual = logical.state_generation + reserved_view_changes,
		}
	}
	return {}
}

@(private)
inserted_text_end_column :: proc(
	text: string,
	start_column: u32,
	tab_width: u16,
	profile: display.Display_Profile,
) -> (column: u32, ok: bool, failure: Failure_Context) {
	column = start_column
	offset := u64(0)
	for offset < u64(len(text)) {
		grapheme, grapheme_ok, grapheme_failure := display.profile_next_grapheme(
			profile.unicode,
			text,
			offset,
		)
		if !grapheme_ok {
			return 0, false, Failure_Context {
				code = .Display_Failure,
				profile_code = grapheme_failure.code,
			}
		}
		width, width_ok, profile_failure := display.profile_cluster_width(
			profile.unicode,
			text[grapheme.start:grapheme.end],
			column,
			tab_width,
		)
		if !width_ok {
			return 0, false, Failure_Context {
				code = .Display_Failure,
				profile_code = profile_failure.code,
			}
		}
		if width.is_line_break {
			column = 0
		} else if u64(column) + u64(width.cells) > u64(max(u32)) {
			return 0, false, Failure_Context {
				code = .Display_Failure,
				display_code = .Work_Limit,
				limit = u64(max(u32)),
				actual = u64(column) + u64(width.cells),
			}
		} else {
			column += u32(width.cells)
		}
		offset = grapheme.end
	}
	return column, true, {}
}

@(private)
Reveal_Plan :: struct {
	origin:     editor.Position,
	horizontal: u32,
	update:     bool,
}

@(private)
cursor_reveal_plan :: proc(
	buffer: ^editor.Buffer,
	logical: editor_view.Snapshot,
	cursor: editor.Position,
	column: u32,
	constraints: display.Viewport_Constraints,
) -> (plan: Reveal_Plan, ok: bool, failure: Failure_Context) {
	cursor_line, cursor_ok, cursor_failure := editor.buffer_line_at_position(buffer, cursor)
	if !cursor_ok {
		return {}, false, native_editor_failure({}, cursor_failure)
	}
	viewport_line, viewport_ok, viewport_failure := editor.buffer_line_at_position(
		buffer,
		logical.viewport_origin_position,
	)
	if !viewport_ok {
		return {}, false, native_editor_failure({}, viewport_failure)
	}
	origin := logical.viewport_origin_position
	if cursor_line.line_index < viewport_line.line_index {
		origin, _, cursor_failure = editor.buffer_position(buffer, cursor_line.start)
	} else if cursor_line.line_index - viewport_line.line_index >= u64(constraints.height_rows) {
		target_line := cursor_line
		for _ in 1 ..< constraints.height_rows {
			if target_line.line_index == 0 {
				break
			}
			probe, probe_ok, probe_failure := editor.buffer_position(
				buffer,
				editor.Byte_Offset(u64(target_line.start) - 1),
			)
			if !probe_ok {
				return {}, false, native_editor_failure({}, probe_failure)
			}
			target_line, probe_ok, probe_failure = editor.buffer_line_at_position(buffer, probe)
			if !probe_ok {
				return {}, false, native_editor_failure({}, probe_failure)
			}
		}
		origin, _, cursor_failure = editor.buffer_position(buffer, target_line.start)
	}
	if cursor_failure.code != .None {
		return {}, false, native_editor_failure({}, cursor_failure)
	}
	horizontal := logical.horizontal_display_column
	if column < horizontal {
		horizontal = column
	} else if u64(column) >= u64(horizontal) + u64(constraints.width_cells) {
		horizontal = u32(u64(column) - u64(constraints.width_cells) + 1)
	}
	return Reveal_Plan {
		origin = origin,
		horizontal = horizontal,
		update = origin != logical.viewport_origin_position ||
		         horizontal != logical.horizontal_display_column,
	}, true, {}
}

@(private)
finish_committed_view :: proc(request: Native_Context, desired_column: u32) {
	logical, logical_ok, _ := editor_view.snapshot(request.view_registry, request.view)
	assert(logical_ok, "published edit left an invalid view")
	plan, planned, _ := cursor_reveal_plan(
		request.buffer,
		logical,
		logical.point_position,
		desired_column,
		request.constraints,
	)
	assert(planned, "published edit could not derive its viewport")
	if plan.update {
		updated, _ := editor_view.set_viewport(
			request.view_registry,
			request.view,
			plan.origin,
			plan.horizontal,
		)
		assert(updated, "published edit could not confirm its viewport")
	}
}

@(private)
native_editor_failure :: proc(
	command: interaction.Command_Handle,
	editor_failure: editor.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .Publication_Failure,
		command = command,
		editor_code = editor_failure.code,
		limit = editor_failure.limit,
		actual = editor_failure.actual,
	}
}

@(private)
native_transaction_failure :: proc(
	command: interaction.Command_Handle,
	transaction_failure: edit_transaction.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .Publication_Failure,
		command = command,
		transaction_code = transaction_failure.code,
		editor_code = transaction_failure.editor_failure.code,
		view_code = transaction_failure.view_failure.code,
		limit = transaction_failure.limit,
		actual = transaction_failure.actual,
	}
}

@(private)
native_kill_ring_failure :: proc(
	command: interaction.Command_Handle,
	ring_failure: kill_ring.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .Kill_Ring_Failure,
		command = command,
		kill_ring_code = ring_failure.code,
		kill_ring_generation = ring_failure.generation,
		limit = ring_failure.maximum,
		actual = ring_failure.actual,
	}
}

@(private)
native_view_failure :: proc(
	command: interaction.Command_Handle,
	view_failure: editor_view.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .View_Failure,
		command = command,
		view_code = view_failure.code,
		editor_code = view_failure.editor_failure.code,
		limit = view_failure.limit,
		actual = view_failure.actual,
	}
}

@(private)
native_display_failure :: proc(
	command: interaction.Command_Handle,
	display_failure: display.Failure_Context,
) -> Failure_Context {
	return Failure_Context {
		code = .Display_Failure,
		command = command,
		display_code = display_failure.code,
		editor_code = display_failure.editor_failure.code,
		limit = display_failure.limit,
		actual = display_failure.actual,
	}
}
