// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* INTERACTION_COMMAND_COUNT is the internal semantic command set for contextual maps. */
INTERACTION_COMMAND_COUNT :: 99

/* interaction_command_definitions declares prompt actions routed by contextual keymaps. */
interaction_command_definitions :: proc() -> [INTERACTION_COMMAND_COUNT]interaction.Command_Definition {
	return {
		interaction_text_definition(
			.Prompt_Insert_Text,
			"prompt-insert-text",
			"Append normalized text to the active prompt.",
		),
		interaction_action_definition(
			.Prompt_Delete_Previous,
			"prompt-delete-previous",
			"Delete the previous prompt text scalar or skip the current replacement.",
		),
		interaction_action_definition(.Prompt_Accept, "prompt-accept", "Accept the active prompt value."),
		{
			name = "context-cancel",
			route = contextual_route(.Cancel),
			implementation = .Native,
			invocation = .Cancellation,
			text_requirement = .Prohibited,
			effects = {.View},
			description = "Cancel the active contextual interaction.",
			provenance = contextual_command_provenance(),
		},
		interaction_action_definition(.Search_History_Newer, "search-history-newer", "Recall a newer compatible search query."),
		interaction_action_definition(.Search_History_Older, "search-history-older", "Recall an older compatible search query."),
		interaction_action_definition(.Search_History_Complete, "search-history-complete", "Complete from compatible search history."),
		interaction_action_definition(.Search_Extend_Textual, "search-extend-textual", "Extend search from nearby text."),
		interaction_action_definition(.Search_Extend_Structural, "search-extend-structural", "Extend search from a nearby structural unit."),
		interaction_action_definition(.Search_Extend_Transferred, "search-extend-transferred", "Extend search from retained text."),
		interaction_action_definition(.Search_Toggle_Case, "search-toggle-case", "Toggle search case sensitivity."),
		interaction_action_definition(.Search_Toggle_Pattern, "search-toggle-pattern", "Toggle literal and regular-expression search."),
		interaction_action_definition(.Search_Toggle_Word, "search-toggle-word", "Toggle word-boundary matching."),
		interaction_action_definition(.Search_Toggle_Symbol, "search-toggle-symbol", "Toggle symbol-boundary matching."),
		interaction_action_definition(.Search_Toggle_Whitespace, "search-toggle-whitespace", "Toggle flexible whitespace matching."),
		interaction_action_definition(.Search_Materialize, "search-materialize-results", "Materialize the active search as a result set."),
		interaction_action_definition(.Prompt_Choice_1, "prompt-choice-1", "Select contextual choice one."),
		interaction_action_definition(.Prompt_Choice_2, "prompt-choice-2", "Select contextual choice two."),
		interaction_action_definition(.Prompt_Choice_3, "prompt-choice-3", "Select contextual choice three."),
		interaction_action_definition(.Prompt_Choice_4, "prompt-choice-4", "Select contextual choice four."),
		interaction_action_definition(
			.Query_Replace_And_Exit,
			"query-replace-and-exit",
			"Replace the current match and finish query replacement.",
		),
		interaction_action_definition(.Query_Quit, "query-quit", "Finish query replacement without another edit."),
		interaction_action_definition(.Component_Previous_Row, "component-previous-row", "Select the previous component row."),
		interaction_action_definition(.Component_Next_Row, "component-next-row", "Select the next component row."),
		interaction_action_definition(.Component_Activate_Current, "component-activate-current", "Activate the current component row."),
		interaction_action_definition(.Component_Mark_Save, "component-mark-save", "Mark the current buffer for saving."),
		interaction_action_definition(.Component_Mark_Kill, "component-mark-kill", "Mark the current buffer for closure."),
		interaction_action_definition(.Component_Unmark, "component-unmark", "Remove the current buffer mark."),
		interaction_action_definition(.Component_Execute, "component-execute", "Execute marked component actions."),
		interaction_action_definition(.Component_Close, "component-close", "Close the active component interaction."),
		interaction_text_definition(
			.Component_Query_Text,
			"component-query-text",
			"Append normalized text to the active component query.",
		),
		interaction_action_definition(
			.Component_Query_Delete_Previous,
			"component-query-delete-previous",
			"Delete the previous scalar from the active component query.",
		),
		interaction_action_definition(
			.Component_Complete_Current,
			"component-complete-current",
			"Complete the current component row without activating it.",
		),
		interaction_action_definition(.Result_First, "result-first", "Select the first result."),
		interaction_action_definition(.Result_Last, "result-last", "Select the last result."),
		interaction_action_definition(.Result_Refresh, "result-refresh", "Refresh the current result set."),
		interaction_action_definition(.Result_Edit, "result-edit", "Enter editable result mode."),
		interaction_action_definition(.Result_Apply, "result-apply", "Apply staged result edits."),
		interaction_action_definition(.Ksawery_Mark, "ksawery-mark", "Add the selected repository target to the current group."),
		interaction_action_definition(.Ksawery_Unmark, "ksawery-unmark", "Remove the selected repository target from the current group."),
		interaction_action_definition(.Ksawery_Clear_Marks, "ksawery-clear-marks", "Clear the current repository target group."),
		interaction_action_definition(.Ksawery_Stage, "ksawery-stage", "Stage the selected repository target or compatible group."),
		interaction_action_definition(.Ksawery_Unstage, "ksawery-unstage", "Unstage the selected repository target or compatible group."),
		interaction_action_definition(.Ksawery_Discard, "ksawery-discard", "Discard the selected tracked working-tree path after confirmation."),
		interaction_action_definition(.Ksawery_Commit, "ksawery-commit", "Compose a checked normal repository commit."),
		interaction_action_definition(.Ksawery_Amend, "ksawery-amend", "Compose a confirmed replacement of the observed repository HEAD."),
		interaction_action_definition(.Ksawery_Fixup, "ksawery-fixup", "Create a non-rewriting fixup commit for the selected exact revision."),
		interaction_action_definition(.Ksawery_Sequence, "ksawery-sequence", "Inspect the active repository sequence in the current Ksawery session."),
		interaction_action_definition(.Ksawery_History, "ksawery-history", "Open bounded repository history in the current Ksawery session."),
		interaction_action_definition(.Ksawery_History_Next, "ksawery-history-next-page", "Load the next bounded repository history page."),
		interaction_action_definition(.Ksawery_Refs, "ksawery-refs", "Open bounded repository refs in the current Ksawery session."),
		interaction_action_definition(.Ksawery_Stashes, "ksawery-stashes", "Open checked repository stashes in the current Ksawery session."),
		interaction_action_definition(.Ksawery_Worktrees, "ksawery-worktrees", "Open checked linked worktrees in the current Ksawery session."),
		interaction_action_definition(.Ksawery_Blame, "ksawery-blame", "Attribute the selected repository path to bounded exact commits."),
		interaction_action_definition(.Ksawery_Reflog, "ksawery-reflog", "Open bounded checked repository reflog entries."),
		interaction_action_definition(.Ksawery_Processes, "ksawery-processes", "Inspect bounded repository processes in the current Ksawery session."),
		interaction_action_definition(.Ksawery_Providers, "ksawery-providers", "Inspect active and retained Ksawery extension provider state."),
		interaction_action_definition(.Ksawery_Provider_Reload, "ksawery-provider-reload", "Reload personal configuration and atomically replace its Ksawery provider generation."),
		interaction_action_definition(.Ksawery_Provider_Disable, "ksawery-provider-disable", "Disable the active personal Ksawery provider and restore built-in fallback behavior."),
		interaction_action_definition(.Ksawery_Raw_Command, "ksawery-raw-command", "Compose one separately confirmed raw Git or shell command in the current Ksawery session."),
		interaction_action_definition(.Ksawery_Fetch, "ksawery-fetch", "Fetch the selected checked repository remote."),
		interaction_action_definition(.Ksawery_Push, "ksawery-push", "Confirm and push one exact tracked repository branch."),
		interaction_action_definition(.Ksawery_Branch_Create, "ksawery-branch-create", "Create one confirmed local branch at the checked repository HEAD."),
		interaction_action_definition(.Ksawery_Branch_Switch, "ksawery-branch-switch", "Switch to one confirmed exact local branch when repository and editor state are safe."),
		interaction_action_definition(.Ksawery_Branch_Rename, "ksawery-branch-rename", "Rename one confirmed exact local branch."),
		interaction_action_definition(.Ksawery_Branch_Delete, "ksawery-branch-delete", "Delete one confirmed exact merged local branch without force."),
		interaction_action_definition(.Ksawery_Tag_Create, "ksawery-tag-create", "Create one confirmed lightweight local tag at the selected exact commit."),
		interaction_action_definition(.Ksawery_Tag_Delete, "ksawery-tag-delete", "Delete one confirmed exact local tag."),
		interaction_action_definition(.Ksawery_Merge_Fast_Forward, "ksawery-merge-fast-forward", "Merge the selected exact ref only when it can fast-forward."),
		interaction_action_definition(.Ksawery_Merge, "ksawery-merge", "Merge the selected exact ref while allowing a merge commit."),
		interaction_action_definition(.Ksawery_Merge_No_Fast_Forward, "ksawery-merge-no-fast-forward", "Merge the selected exact ref through a required merge commit."),
		interaction_action_definition(.Ksawery_Merge_Continue, "ksawery-merge-continue", "Continue the checked active merge after all conflicts are resolved."),
		interaction_action_definition(.Ksawery_Merge_Abort, "ksawery-merge-abort", "Abort the checked active merge after exact confirmation."),
		interaction_action_definition(.Ksawery_Rebase, "ksawery-rebase", "Replay the checked current branch onto the selected exact base."),
		interaction_action_definition(.Ksawery_Rebase_Autosquash, "ksawery-rebase-autosquash", "Review and apply an exact bounded autosquash plan onto the selected base."),
		interaction_action_definition(.Ksawery_Rebase_Continue, "ksawery-rebase-continue", "Continue the checked active rebase after all conflicts are resolved."),
		interaction_action_definition(.Ksawery_Rebase_Skip, "ksawery-rebase-skip", "Skip the exact current replay step after confirmation."),
		interaction_action_definition(.Ksawery_Rebase_Abort, "ksawery-rebase-abort", "Abort the checked active rebase after exact confirmation."),
		interaction_action_definition(.Ksawery_Sequence_Mark, "ksawery-sequence-mark", "Append the selected exact History commit and chosen merge mainline to the ordered sequence set."),
		interaction_action_definition(.Ksawery_Sequence_Unmark, "ksawery-sequence-unmark", "Remove the selected exact History commit from the ordered sequence set."),
		interaction_action_definition(.Ksawery_Cherry_Pick, "ksawery-cherry-pick", "Confirm and cherry-pick the marked exact History commits in order."),
		interaction_action_definition(.Ksawery_Cherry_Pick_Continue, "ksawery-cherry-pick-continue", "Continue the checked active cherry-pick and its retained ordered set."),
		interaction_action_definition(.Ksawery_Cherry_Pick_Skip, "ksawery-cherry-pick-skip", "Skip the checked cherry-pick step and continue its retained ordered set."),
		interaction_action_definition(.Ksawery_Cherry_Pick_Abort, "ksawery-cherry-pick-abort", "Abort the checked active cherry-pick after exact confirmation."),
		interaction_action_definition(.Ksawery_Revert, "ksawery-revert", "Confirm and revert the marked exact History commits in order."),
		interaction_action_definition(.Ksawery_Revert_Continue, "ksawery-revert-continue", "Continue the checked active revert and its retained ordered set."),
		interaction_action_definition(.Ksawery_Revert_Skip, "ksawery-revert-skip", "Skip the checked revert step and continue its retained ordered set."),
		interaction_action_definition(.Ksawery_Revert_Abort, "ksawery-revert-abort", "Abort the checked active revert after exact confirmation."),
		interaction_action_definition(.Ksawery_Bisect_Good, "ksawery-bisect-good", "Mark an exact good boundary or classify the current bisect candidate as good."),
		interaction_action_definition(.Ksawery_Bisect_Bad, "ksawery-bisect-bad", "Mark the exact bad boundary or classify the current bisect candidate as bad."),
		interaction_action_definition(.Ksawery_Bisect_Start, "ksawery-bisect-start", "Start manual bisect from the checked exact bad and good boundaries."),
		interaction_action_definition(.Ksawery_Bisect_Skip, "ksawery-bisect-skip", "Skip classification of the checked current bisect candidate."),
		interaction_action_definition(.Ksawery_Bisect_Reset, "ksawery-bisect-reset", "Reset the checked active bisect to its verified origin."),
		interaction_action_definition(.Ksawery_Conflict_Mark, "ksawery-conflict-mark-resolved", "Stage the exact saved text result for the selected conflict."),
		interaction_action_definition(.Ksawery_Conflict_Assist, "ksawery-conflict-assist", "Inspect the selected conflict with the configured assistance provider."),
		interaction_action_definition(.Ksawery_Conflict_Use_Base, "ksawery-conflict-use-base", "Replace the selected conflict with its complete base side after confirmation."),
		interaction_action_definition(.Ksawery_Conflict_Use_Current, "ksawery-conflict-use-current", "Replace the selected conflict with its complete current side after confirmation."),
		interaction_action_definition(.Ksawery_Conflict_Use_Applied, "ksawery-conflict-use-applied", "Replace the selected conflict with its complete applied side after confirmation."),
		interaction_action_definition(.Ksawery_Conflict_Delete, "ksawery-conflict-delete", "Record a resolved deletion for the selected conflict after confirmation."),
	}
}

@(private)
interaction_action_definition :: proc(
	route: Contextual_Route,
	name, description: string,
) -> interaction.Command_Definition {
	return interaction.Command_Definition {
		name = name,
		route = contextual_route(route),
		implementation = .Native,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		effects = {.View},
		description = description,
		provenance = contextual_command_provenance(),
	}
}

@(private)
interaction_text_definition :: proc(
	route: Contextual_Route,
	name, description: string,
) -> interaction.Command_Definition {
	return interaction.Command_Definition {
		name = name,
		route = contextual_route(route),
		implementation = .Native,
		invocation = .Text_Input,
		text_requirement = .Required,
		effects = {.View},
		description = description,
		provenance = contextual_command_provenance(),
	}
}

@(private)
contextual_command_provenance :: proc() -> interaction.Definition_Provenance {
	return interaction.Definition_Provenance {
		provider = "odra-native",
		source = "src/command/contextual.odin",
	}
}
