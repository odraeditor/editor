// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* JAN_COMPUTATION_COMMAND_COUNT is the complete Computable Documents public catalog. */
JAN_COMPUTATION_COMMAND_COUNT :: 40

/* jan_computation_command_definitions returns every public computation identity. */
jan_computation_command_definitions :: proc() -> [JAN_COMPUTATION_COMMAND_COUNT]interaction.Command_Definition {
	return {
		jan_computation_edit_definition(.Jan_Table_Recalculate, "jan-table-recalculate", "Recalculate the current Jan table through its exact dependency graph."),
		jan_computation_edit_definition(.Jan_Table_Recalculate_All, "jan-table-recalculate-all", "Recalculate every admitted table in deterministic dependency order."),
		jan_computation_view_definition(.Jan_Table_Debug_Formula, "jan-table-debug-formula", "Inspect the current formula without changing its table."),
		jan_computation_lifecycle_definition(.Jan_Table_Plot, "jan-table-plot", "Render a bounded text plot or request an admitted graphical plot."),
		jan_computation_edit_definition(.Jan_Execute, "jan-execute", "Execute the current source owner through explicit authority."),
		jan_computation_edit_definition(.Jan_Execute_Subtree, "jan-execute-subtree", "Execute admitted source owners in the current subtree."),
		jan_computation_edit_definition(.Jan_Execute_Buffer, "jan-execute-buffer", "Execute admitted source owners in the current buffer."),
		jan_computation_edit_definition(.Jan_Call, "jan-call", "Invoke the current named Jan call through explicit authority."),
		jan_computation_edit_definition(.Jan_Result_Remove, "jan-result-remove", "Remove only the result owned by the current source or call."),
		jan_computation_view_definition(.Jan_Result_Inspect, "jan-result-inspect", "Inspect typed result provenance and accounting."),
		jan_computation_view_definition(.Jan_Edit_Source, "jan-edit-source", "Open the current source body in a focused language view."),
		jan_computation_edit_definition(.Jan_Return_From_Source, "jan-return-from-source", "Publish a revalidated focused source edit to its owner."),
		jan_computation_lifecycle_definition(.Jan_Tangle, "jan-tangle", "Prepare and publish admitted tangle targets for the current scope."),
		jan_computation_lifecycle_definition(.Jan_Tangle_File, "jan-tangle-file", "Prepare and publish admitted tangle targets for the current document."),
		jan_computation_view_definition(.Jan_Noweb_Inspect, "jan-noweb-inspect", "Inspect the effective noweb graph and expansion chain."),
		jan_computation_lifecycle_definition(.Jan_Library_Load, "jan-library-load", "Load definitions from an explicitly admitted Jan library."),
		jan_computation_global_edit_definition(.Jan_Execute_Batch, "jan-execute-batch", "Execute an explicit bounded batch in deterministic order."),
		jan_computation_global_definition(.Jan_Session_List, "jan-session-list", "List bounded execution-session records."),
		jan_computation_global_definition(.Jan_Session_Inspect, "jan-session-inspect", "Inspect one explicit execution session."),
		jan_computation_global_definition(.Jan_Session_Close, "jan-session-close", "Close one explicit execution session and report cleanup."),
		jan_computation_global_definition(.Jan_Cache_Inspect, "jan-cache-inspect", "Inspect execution-cache keys and outcomes."),
		jan_computation_global_definition(.Jan_Cache_Evict, "jan-cache-evict", "Evict one cache-owned entry without changing document results."),
		jan_computation_global_definition(.Jan_Cache_Clear, "jan-cache-clear", "Clear bounded cache-owned entries without changing documents."),
		jan_computation_view_definition(.Jan_Open_Result, "jan-open-result", "Move to and inspect the result owned by the current source block."),
		jan_computation_view_definition(.Jan_Load_In_Session, "jan-load-in-session", "Load the current source block into its associated execution session."),
		jan_computation_view_definition(.Jan_Pop_To_Session, "jan-pop-to-session", "Display the execution session associated with the current source block."),
		jan_computation_view_definition(.Jan_Expand_Source, "jan-expand-source", "Preview the expanded current source block without executing it."),
		jan_computation_view_definition(.Jan_Goto_Source_Head, "jan-goto-source-head", "Move to the beginning of the current source block."),
		jan_computation_view_definition(.Jan_Goto_Named_Source, "jan-goto-named-source", "Select and visit a named source block."),
		jan_computation_view_definition(.Jan_Goto_Named_Result, "jan-goto-named-result", "Select and visit a named source result."),
		jan_computation_edit_definition(.Jan_Demarcate_Source, "jan-demarcate-source", "Split the current source block at point."),
		jan_computation_view_definition(.Jan_Check_Source, "jan-check-source", "Check whether the current source block is valid and executable."),
		jan_computation_edit_definition(.Jan_Insert_Header_Argument, "jan-insert-header-argument", "Insert or update an argument on the current source block."),
		jan_computation_view_definition(.Jan_View_Source_Info, "jan-view-source-info", "Display resolved information for the current source block."),
		jan_computation_view_definition(.Jan_Switch_To_Session_With_Code, "jan-switch-to-session-with-code", "Display the current source in its associated execution session."),
		jan_computation_view_definition(.Jan_Source_Hash, "jan-source-hash", "Calculate the effective current source block hash."),
		jan_computation_view_definition(.Jan_Babel_Help, "jan-babel-help", "Display the active Jan Babel command family."),
		jan_computation_edit_definition(.Jan_Context_Meta_Up, "jan-context-meta-up", "Load source into its session or move the current subtree up."),
		jan_computation_edit_definition(.Jan_Context_Meta_Down, "jan-context-meta-down", "Display the source session or move the current subtree down."),
		jan_computation_global_definition(.Jan_Computation_Status, "jan-computation-status", "Inspect Computable Documents capabilities, generations, limits, and failures."),
	}
}

@(private)
jan_computation_view_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description)
}

@(private)
jan_computation_lifecycle_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description)
}

@(private)
jan_computation_global_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description, {})
}

@(private)
jan_computation_global_edit_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.Buffer, .View, .Lifecycle, .Text_Mutation}, description, {})
}

@(private)
jan_computation_edit_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.Buffer, .View, .Lifecycle, .Text_Mutation}, description)
}
