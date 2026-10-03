// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* JAN_PLANNING_COMMAND_COUNT is the complete Planning and Agenda public catalog. */
JAN_PLANNING_COMMAND_COUNT :: 71

/* jan_planning_command_definitions returns every public Planning and Agenda identity. */
jan_planning_command_definitions :: proc() -> [JAN_PLANNING_COMMAND_COUNT]interaction.Command_Definition {
	return {
		jan_planning_edit_definition(.Jan_Todo, "jan-todo", "Move the current heading through its admitted task workflow."),
		jan_planning_edit_definition(.Jan_Set_Priority, "jan-set-priority", "Set the current heading priority."),
		jan_planning_edit_definition(.Jan_Toggle_Checkbox, "jan-toggle-checkbox", "Cycle the current compatible checkbox."),
		jan_planning_edit_definition(.Jan_Update_Statistics, "jan-update-statistics", "Update derived checkbox statistics at the current owner."),
		jan_planning_edit_definition(.Jan_Set_Tags, "jan-set-tags", "Set locally stored tags on the current heading."),
		jan_planning_edit_definition(.Jan_Set_Property, "jan-set-property", "Set one locally owned Jan property."),
		jan_planning_view_definition(.Jan_Property_Search, "jan-property-search", "Search headings by effective property values."),
		jan_planning_view_definition(.Jan_Column_View, "jan-column-view", "Present a bounded property-backed Jan column view."),
		jan_planning_edit_definition(.Jan_Timestamp, "jan-timestamp", "Insert or edit a compatible Jan timestamp."),
		jan_planning_edit_definition(.Jan_Schedule, "jan-schedule", "Set or clear the current heading schedule."),
		jan_planning_edit_definition(.Jan_Deadline, "jan-deadline", "Set or clear the current heading deadline."),
		jan_planning_edit_definition(.Jan_Clock_In, "jan-clock-in", "Start a durable clock for the current heading."),
		jan_planning_edit_definition(.Jan_Clock_Out, "jan-clock-out", "Stop the active durable clock."),
		jan_planning_edit_definition(.Jan_Clock_Cancel, "jan-clock-cancel", "Cancel the active durable clock without publishing elapsed time."),
		jan_planning_edit_definition(.Jan_Clock_Switch, "jan-clock-switch", "Stop the active clock and start another exact target."),
		jan_planning_edit_definition(.Jan_Clock_Resume, "jan-clock-resume", "Resume a prior exact clock target."),
		jan_planning_view_definition(.Jan_Clock_Report, "jan-clock-report", "Present a bounded Jan clock report."),
		jan_planning_edit_definition(.Jan_Set_Effort, "jan-set-effort", "Set the current heading effort value."),
		jan_planning_lifecycle_definition(.Jan_Timer_Start, "jan-timer-start", "Start a relative Jan timer."),
		jan_planning_lifecycle_definition(.Jan_Timer_Pause, "jan-timer-pause", "Pause the active relative Jan timer."),
		jan_planning_lifecycle_definition(.Jan_Timer_Resume, "jan-timer-resume", "Resume the paused relative Jan timer."),
		jan_planning_lifecycle_definition(.Jan_Timer_Stop, "jan-timer-stop", "Stop the active relative Jan timer."),
		jan_planning_lifecycle_definition(.Jan_Timer_Reset, "jan-timer-reset", "Reset the active relative Jan timer."),
		jan_planning_edit_definition(.Jan_Refile, "jan-refile", "Move the current complete subtree to a checked destination."),
		jan_planning_edit_definition(.Jan_Copy_Subtree, "jan-copy-subtree", "Copy the current complete subtree to a checked destination."),
		jan_planning_edit_definition(.Jan_Archive_Subtree, "jan-archive-subtree", "Archive the current subtree through its configured owner."),
		jan_planning_edit_definition(.Jan_Toggle_Archive, "jan-toggle-archive", "Toggle compatible in-place archive state."),
		jan_planning_edit_definition(.Jan_Restore_Archive, "jan-restore-archive", "Restore an archived subtree to its checked origin."),
		jan_planning_lifecycle_definition(.Jan_Visit_Archive_Origin, "jan-visit-archive-origin", "Visit the recorded source of an archived subtree."),
		jan_planning_global_definition(.Jan_Capture, "jan-capture", "Start a bounded Jan capture session."),
		jan_planning_edit_definition(.Jan_Capture_Finalize, "jan-capture-finalize", "Finalize the active capture at its exact destination."),
		jan_planning_lifecycle_definition(.Jan_Capture_Abort, "jan-capture-abort", "Abort the active capture and discard its draft."),
		jan_planning_lifecycle_definition(.Jan_Store_Link, "jan-store-link", "Store one checked Jan link candidate."),
		jan_planning_edit_definition(.Jan_Attach, "jan-attach", "Attach a resource and publish a compatible checked link."),
		jan_planning_lifecycle_definition(.Jan_Attachment_Open, "jan-attachment-open", "Open the selected attachment through its resource owner."),
		jan_planning_lifecycle_definition(.Jan_Attachment_Reveal, "jan-attachment-reveal", "Reveal the selected attachment through Maksym."),
		jan_planning_view_definition(.Jan_Attachment_List, "jan-attachment-list", "List bounded attachments for the current heading."),
		jan_planning_edit_definition(.Jan_Attachment_Rename, "jan-attachment-rename", "Rename one attachment and its compatible source link."),
		jan_planning_edit_definition(.Jan_Attachment_Delete, "jan-attachment-delete", "Delete one attachment and its compatible source link."),
		jan_planning_edit_definition(.Jan_Attachment_Synchronize, "jan-attachment-synchronize", "Synchronize attachments through their configured resource owner."),
		jan_planning_global_definition(.Jan_Feed_Refresh, "jan-feed-refresh", "Refresh admitted feeds explicitly and retain bounded unseen entries."),
		jan_planning_global_definition(.Jan_Agenda, "jan-agenda", "Open the Jan agenda dispatcher."),
		jan_planning_view_definition(.Jan_Agenda_Refresh, "jan-agenda-refresh", "Refresh the active agenda from admitted sources."),
		jan_planning_view_definition(.Jan_Agenda_Next_Entry, "jan-agenda-next-entry", "Move to the next agenda entry."),
		jan_planning_view_definition(.Jan_Agenda_Previous_Entry, "jan-agenda-previous-entry", "Move to the previous agenda entry."),
		jan_planning_view_definition(.Jan_Agenda_Next_Date, "jan-agenda-next-date", "Move to the next represented agenda date."),
		jan_planning_view_definition(.Jan_Agenda_Previous_Date, "jan-agenda-previous-date", "Move to the previous represented agenda date."),
		jan_planning_lifecycle_definition(.Jan_Agenda_Reveal_Source, "jan-agenda-reveal-source", "Reveal the exact source represented by the current agenda row."),
		jan_planning_view_definition(.Jan_Agenda_Set_Span, "jan-agenda-set-span", "Change the active agenda date span."),
		jan_planning_view_definition(.Jan_Agenda_Toggle_Follow, "jan-agenda-toggle-follow", "Toggle agenda source-follow behavior."),
		jan_planning_view_definition(.Jan_Agenda_Filter, "jan-agenda-filter", "Apply a bounded local agenda filter."),
		jan_planning_view_definition(.Jan_Agenda_Change_Presentation, "jan-agenda-change-presentation", "Change grouping, sorting, grid, or prefix presentation."),
		jan_planning_edit_definition(.Jan_Agenda_Todo, "jan-agenda-todo", "Change task state at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Set_Priority, "jan-agenda-set-priority", "Set priority at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Set_Tags, "jan-agenda-set-tags", "Set tags at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Set_Property, "jan-agenda-set-property", "Set a property at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Schedule, "jan-agenda-schedule", "Set schedule at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Deadline, "jan-agenda-deadline", "Set deadline at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Set_Effort, "jan-agenda-set-effort", "Set effort at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Clock_In, "jan-agenda-clock-in", "Start a clock at the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Clock_Out, "jan-agenda-clock-out", "Stop the clock represented by the agenda row."),
		jan_planning_edit_definition(.Jan_Agenda_Refile, "jan-agenda-refile", "Refile the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Archive, "jan-agenda-archive", "Archive the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Capture, "jan-agenda-capture", "Capture relative to the exact agenda source target."),
		jan_planning_edit_definition(.Jan_Agenda_Delete, "jan-agenda-delete", "Delete the exact agenda source target through its canonical owner."),
		jan_planning_edit_definition(.Jan_Agenda_Apply_Selection, "jan-agenda-apply-selection", "Apply one checked operation to an explicit agenda selection."),
		jan_planning_lifecycle_definition(.Jan_Agenda_Calendar, "jan-agenda-calendar", "Invoke calendar navigation from the active agenda date."),
		jan_planning_lifecycle_definition(.Jan_Agenda_Export, "jan-agenda-export", "Hand the current immutable agenda result to Jan export."),
		jan_planning_view_definition(.Jan_Agenda_Quit, "jan-agenda-quit", "Quit the active agenda while retaining its surface."),
		jan_planning_lifecycle_definition(.Jan_Agenda_Close, "jan-agenda-close", "Close the active agenda surface."),
		jan_planning_global_definition(.Jan_Planning_Status, "jan-planning-status", "Inspect Planning and Agenda capabilities, generations, recovery, and failures."),
	}
}

@(private)
jan_planning_view_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description)
}

@(private)
jan_planning_lifecycle_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description)
}

@(private)
jan_planning_global_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description, {})
}

@(private)
jan_planning_edit_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.Buffer, .View, .Lifecycle, .Text_Mutation}, description)
}
