// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../document"
import "../editor"
import "../interaction"
import "../history"
import "../indentation"
import "../kill_ring"
import "../layout"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:testing"

/* Verifies profile selection and modal transitions are canonical native commands. */
@(test)
interaction_profile_commands_use_lifecycle_routes :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "abc\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	cases := []struct {
		name:       string,
		completion: Native_Completion,
		effects:    interaction.Command_Effects,
	} {
		{"select-interaction-profile", .Interaction_Profile_Selection_Requested, {.Lifecycle}},
		{"modal-enter-insert", .No_Op, {.Lifecycle}},
		{"modal-enter-insert-after", .View_Changed, {.View, .Lifecycle}},
		{"modal-enter-replace", .No_Op, {.Lifecycle}},
		{"modal-enter-normal", .No_Op, {.Lifecycle}},
		{"modal-enter-visual-character", .No_Op, {.View, .Lifecycle}},
		{"modal-enter-visual-line", .No_Op, {.View, .Lifecycle}},
		{"modal-enter-insert-line-first", .View_Changed, {.View, .Lifecycle}},
		{"modal-enter-insert-line-end", .View_Changed, {.View, .Lifecycle}},
		{"modal-open-line-below", .Buffer_Committed, {.Buffer, .View, .Lifecycle, .Text_Mutation}},
		{"modal-open-line-above", .Buffer_Committed, {.Buffer, .View, .Lifecycle, .Text_Mutation}},
	}
	for test_case in cases {
		result, executed, failure := execute_named(&fixture, test_case.name)
		testing.expectf(t, executed, "%s failed with %v", test_case.name, failure.code)
		testing.expect_value(t, result.completion, test_case.completion)
		handle, found, _ := interaction.command_lookup(&fixture.command_registry, test_case.name)
		metadata, described, _ := interaction.command_metadata(&fixture.command_registry, handle)
		testing.expect(t, found && described)
		if found && described {
			testing.expect_value(t, metadata.effects, test_case.effects)
		}
		native_result_close(&result)
	}
}

/* Verifies session theme selection is a canonical native interactive command. */
@(test)
select_theme_requests_selection :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, executed, failure := execute_named(&fixture, "select-theme")
	testing.expectf(t, executed, "theme selection command failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.Theme_Selection_Requested)
}

/* Verifies session theme inspection is a canonical native interactive command. */
@(test)
describe_theme_requests_inspection :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, executed, failure := execute_named(&fixture, "describe-theme")
	testing.expectf(t, executed, "theme inspection command failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.Theme_Inspection_Requested)
}

/* Verifies familiar help commands route to bounded editor-owned discovery workflows. */
@(test)
familiar_help_commands_request_discovery :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	cases := [?]struct {
		name:       string,
		completion: Native_Completion,
	} {
		{"help-about-help", .Help_Requested},
		{"apropos-command", .Command_Description_Requested},
		{"info", .Help_Requested},
		{"describe-function", .Command_Description_Requested},
		{"describe-variable", .Help_Requested},
		{"describe-syntax-table", .Describe_Structural_State_Requested},
		{"open-tutorial", .Help_Requested},
	}
	for test_case in cases {
		result, executed, failure := execute_named(&fixture, test_case.name)
		testing.expectf(t, executed, "%s failed with %v", test_case.name, failure.code)
		testing.expect_value(t, result.completion, test_case.completion)
	}
}

/* Verifies the language-state inspector is a canonical native interactive command. */
@(test)
describe_language_requests_inspection :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, executed, failure := execute_named(&fixture, "describe-language-state")
	testing.expectf(t, executed, "language-state command failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.Describe_Language_State_Requested)
}

/* Verifies unsaved-work recovery remains available through the native command catalog. */
@(test)
recover_unsaved_work_requests_recovery :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, executed, failure := execute_named(&fixture, "recover-unsaved-work")
	testing.expectf(t, executed, "recovery command failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.Recovery_Requested)
}

/* Verifies the structural-state inspector is a canonical native interactive command. */
@(test)
describe_structure_requests_inspection :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, executed, failure := execute_named(&fixture, "describe-structural-state")
	testing.expectf(t, executed, "structural-state command failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.Describe_Structural_State_Requested)
}

/* Verifies numeric navigation prompts when absent and moves to exact one-based targets. */
@(test)
numeric_navigation_uses_one_based_targets :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "a\nbb\nccc", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	prompted, prompted_ok, _ := execute_named(&fixture, "goto-line")
	testing.expect(t, prompted_ok)
	testing.expect_value(t, prompted.completion, Native_Completion.Numeric_Navigation_Target_Requested)
	moved, moved_ok, move_failure := execute_named(
		&fixture,
		"goto-line",
		argument_present = true,
		argument = 3,
	)
	testing.expectf(t, moved_ok, "goto-line failed with %v", move_failure.code)
	testing.expect_value(t, moved.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 5, 0, 0, "a\nbb\nccc")
	char_moved, char_ok, char_failure := execute_named(
		&fixture,
		"goto-char",
		argument_present = true,
		argument = 4,
	)
	testing.expectf(t, char_ok, "goto-char failed with %v", char_failure.code)
	testing.expect_value(t, char_moved.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 3, 1, 0, "a\nbb\nccc")
}

/* Verifies language-service commands route through native lifecycle outcomes without text effects. */
@(test)
language_service_commands_use_exact_outcomes :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	cases := []struct{
		name:       string,
		completion: Native_Completion,
		effects:    interaction.Command_Effects,
		requirements: interaction.Command_Requirements,
	} {
		{"list-language-diagnostics", .Language_Diagnostics_Requested, {.View, .Lifecycle}, {.Active_Buffer}},
		{"next-language-diagnostic", .Next_Language_Diagnostic_Requested, {.View, .Lifecycle}, {.Active_Buffer}},
		{"previous-language-diagnostic", .Previous_Language_Diagnostic_Requested, {.View, .Lifecycle}, {.Active_Buffer}},
		{"describe-language-support", .Language_Service_Inspection_Requested, {.Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"describe-language-service", .Language_Service_Inspection_Requested, {.Lifecycle}, {.Active_Buffer, .Active_Document}},
		{"restart-language-service", .Language_Service_Restart_Requested, {.Lifecycle}, {.Active_Buffer, .Active_Document}},
	}
	for test_case in cases {
		before, _, _ := editor.buffer_stats(&fixture.buffer)
		result, executed, failure := execute_named(&fixture, test_case.name)
		after, _, _ := editor.buffer_stats(&fixture.buffer)
		testing.expectf(t, executed, "%s failed with %v", test_case.name, failure.code)
		testing.expect_value(t, result.completion, test_case.completion)
		testing.expect_value(t, after.revision, before.revision)
		handle, found, _ := interaction.command_lookup(&fixture.command_registry, test_case.name)
		metadata, described, _ := interaction.command_metadata(&fixture.command_registry, handle)
		testing.expect(t, found && described)
		if found && described {
			testing.expect_value(t, metadata.effects, test_case.effects)
			testing.expect_value(t, metadata.requirements, test_case.requirements)
		}
	}
}

/* Verifies Gutter numbering controls are canonical view commands. */
@(test)
gutter_numbering_commands_affect_views :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "package main\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	names := [?]string {
		"gutter-toggle-line-numbers",
		"gutter-cycle-line-number-mode",
		"gutter-set-line-numbers-none",
		"gutter-set-line-numbers-absolute",
		"gutter-set-line-numbers-relative",
		"gutter-set-line-numbers-hybrid",
		"gutter-set-numbering-logical",
		"gutter-set-numbering-visual",
		"gutter-toggle-line-number-side",
		"gutter-inspect-numbering",
		"gutter-inspect-markers",
		"gutter-refresh-markers",
		"gutter-invoke-primary-marker-action",
	}
	for name in names {
		result, executed, failure := execute_named(&fixture, name)
		testing.expectf(t, executed, "%s failed with %v", name, failure.code)
		testing.expect_value(t, result.completion, Native_Completion.Gutter_Command_Requested)
		handle, found, _ := interaction.command_lookup(&fixture.command_registry, name)
		metadata, described, _ := interaction.command_metadata(&fixture.command_registry, handle)
		testing.expect(t, found && described)
		if found && described {
			testing.expect_value(t, metadata.effects, interaction.Command_Effects{.View})
			testing.expect_value(t, metadata.requirements, interaction.Command_Requirements{.Active_Buffer})
		}
	}
}

/* Verifies semantic Gutter commands remain discoverable by exact M-x query. */
@(test)
gutter_markers_are_command_candidates :: proc(t: ^testing.T) {
	definitions := native_command_definitions()
	registry: interaction.Command_Registry
	registry_ok, _ := interaction.command_registry_init(&registry, 1, definitions[:], context.allocator)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer interaction.command_registry_close(&registry)
	snapshot: interaction.Resolution_Snapshot
	snapshot_ok, _ := interaction.snapshot_compile(
		&snapshot,
		&registry,
		1,
		interaction.Keymap_Definition {
			registry_generation = 1,
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expect(t, snapshot_ok)
	if !snapshot_ok do return
	defer interaction.snapshot_close(&snapshot)
	catalog, catalog_ok, _ := interaction.command_catalog_build(
		&registry,
		&snapshot,
		interaction.Command_Catalog_Context{active_buffer = true},
		context.allocator,
	)
	testing.expect(t, catalog_ok)
	if !catalog_ok do return
	defer interaction.command_catalog_close(&catalog)
	source, source_ok, _ := interaction.command_candidate_source_build(&catalog, context.allocator)
	testing.expect(t, source_ok)
	if !source_ok do return
	defer interaction.command_candidate_source_close(&source)
	session: interaction.Candidate_Session
	_, session_ok, _ := interaction.candidate_session_init(
		&session,
		interaction.Candidate_Config {
			session_id = 1,
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
		source.definition,
		"gutter-inspect-markers",
	)
	testing.expect(t, session_ok)
	if !session_ok do return
	defer interaction.candidate_session_close(&session)
	view, viewed, _ := interaction.candidate_session_view(&session)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, len(view.rows), 1)
		if len(view.rows) == 1 do testing.expect_value(t, view.rows[0].label, "gutter-inspect-markers")
	}
}

/* Verifies movement and boundary no-ops change only checked view state. */
@(test)
native_movement_preserves_buffer_revision :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "abc\nx\nlong", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)

	result, ok, _ := execute_named(&fixture, "cursor-previous-grapheme")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.No_Op)

	result, ok, _ = execute_named(&fixture, "cursor-line-end")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 3, 3, 0, "abc\nx\nlong")

	result, ok, _ = execute_named(&fixture, "cursor-next-line")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 5, 3, 0, "abc\nx\nlong")

	execute_named(&fixture, "cursor-next-line")
	expect_native_state(t, &fixture, 9, 3, 0, "abc\nx\nlong")
	execute_named(&fixture, "cursor-previous-line")
	expect_native_state(t, &fixture, 5, 3, 0, "abc\nx\nlong")
	execute_named(&fixture, "cursor-line-start")
	expect_native_state(t, &fixture, 4, 0, 0, "abc\nx\nlong")
	right, found, _ := interaction.command_lookup(
		&fixture.command_registry,
		"cursor-next-grapheme",
	)
	testing.expect(t, found)
	request := native_request(&fixture, right)
	request.temporary_allocator = runtime.nil_allocator()
	result, ok, _ = native_command_execute(request)
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 5, 1, 0, "abc\nx\nlong")
}

/* Verifies direct word commands preserve canonical text. */
@(test)
native_word_navigation_preserves_buffer_revision :: proc(t: ^testing.T) {
	contents := "  Żółć,_42\n    value"
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, contents, context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, executed, failure := execute_named(&fixture, "cursor-next-word")
	testing.expectf(t, executed, "next word failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	logical, logical_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, logical_ok)
	if logical_ok {
		testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(len("  Żółć")))
	}
	result, executed, failure = execute_named(&fixture, "cursor-line-first-non-whitespace")
	testing.expectf(t, executed, "first non-whitespace failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	logical, logical_ok, _ = editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, logical_ok)
	if logical_ok {
		testing.expect_value(t, logical.point_position.byte_offset, editor.Byte_Offset(len("  ")))
	}
	stats, stats_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect(t, stats_ok)
	if stats_ok {
		testing.expect_value(t, stats.revision, editor.Revision(0))
	}
}

/* Verifies modal navigation commands publish canonical view-only movement. */
@(test)
modal_navigation_commands_reuse_display_boundaries :: proc(t: ^testing.T) {
	contents := "one two🙂x🙂z"
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, contents, context.allocator) do return
	defer native_fixture_close(t, &fixture)
	result, executed, failure := execute_named(&fixture, "cursor-next-word-start")
	testing.expectf(t, executed, "next word start failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 4, 4, 0, contents)
	result, executed, failure = execute_named(&fixture, "cursor-word-end")
	testing.expectf(t, executed, "word end failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 7, 7, 0, contents)
	result, executed, failure = execute_named(&fixture, "cursor-find-next-character", "🙂")
	testing.expectf(t, executed, "character target failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 12, 10, 0, contents)
	result, executed, failure = execute_named(&fixture, "cursor-buffer-end")
	testing.expectf(t, executed, "buffer end failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, u64(len(contents)), 13, 0, contents)
	result, executed, failure = execute_named(&fixture, "cursor-buffer-start")
	testing.expectf(t, executed, "buffer start failed with %v", failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 0, 0, 0, contents)
	_, executed, failure = execute_named(&fixture, "cursor-find-next-character")
	testing.expect(t, !executed)
	testing.expect_value(t, failure.code, Failure_Code.Missing_Text)
	_, executed, failure = execute_named(&fixture, "cursor-find-next-character", "🙂x")
	testing.expect(t, !executed)
	testing.expect_value(t, failure.code, Failure_Code.Display_Failure)
	testing.expect_value(t, failure.display_code, display.Failure_Code.Invalid_Request)
}

/* Verifies indentation uses resolved width for reversible line-start and mid-line edits. */
@(test)
indentation_is_one_reversible_group :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	policy_set, policy_failure := editor_view.set_layout_policy(
		&fixture.view_registry,
		fixture.view,
		0,
		2,
		editor_view.Display_Profile_ID(1),
	)
	testing.expectf(t, policy_set, "indentation policy setup failed with %v", policy_failure.code)
	if !policy_set do return

	first, first_ok, first_failure := execute_named(&fixture, "insert-indentation")
	testing.expectf(t, first_ok, "first indentation failed with %v", first_failure.code)
	testing.expect_value(t, first.completion, Native_Completion.Buffer_Committed)
	native_result_close(&first)
	second, second_ok, second_failure := execute_named(&fixture, "insert-indentation")
	testing.expectf(t, second_ok, "repeated indentation failed with %v", second_failure.code)
	testing.expect_value(t, second.completion, Native_Completion.Buffer_Committed)
	native_result_close(&second)
	expect_native_state(t, &fixture, 4, 4, 2, "    alpha")

	_, _, _ = execute_named(&fixture, "cursor-line-end")
	middle, middle_ok, middle_failure := execute_named(&fixture, "insert-indentation")
	testing.expectf(t, middle_ok, "mid-line indentation failed with %v", middle_failure.code)
	testing.expect_value(t, middle.completion, Native_Completion.Buffer_Committed)
	native_result_close(&middle)
	expect_native_state(t, &fixture, 11, 11, 3, "    alpha  ")

	undone, undo_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undo_ok, "indentation undo failed with %v", undo_failure.code)
	testing.expect_value(t, undone.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 9, 9, 4, "    alpha")
	redone, redo_ok, redo_failure := execute_named(&fixture, "redo")
	testing.expectf(t, redo_ok, "indentation redo failed with %v", redo_failure.code)
	testing.expect_value(t, redone.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 11, 11, 5, "    alpha  ")
}

/* Verifies indentation representation and logical width remain independent of tab display width. */
@(test)
indentation_uses_the_complete_effective_policy :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	effective := indentation.DEFAULT_EFFECTIVE_POLICY
	effective.policy = {
		representation = .Tabs,
		indent_width = 2,
		display_tab_width = 8,
	}
	effective.scope = .Language
	effective.matcher_kind = .Language
	effective.source_generation = 7
	policy_set, policy_failure := editor_view.set_indentation_policy(
		&fixture.view_registry,
		fixture.view,
		effective,
	)
	testing.expectf(t, policy_set, "effective policy setup failed with %v", policy_failure.code)
	if !policy_set do return

	inserted, inserted_ok, insert_failure := execute_named(&fixture, "insert-indentation")
	testing.expectf(t, inserted_ok, "tab indentation failed with %v", insert_failure.code)
	if inserted_ok do native_result_close(&inserted)
	expect_native_state(t, &fixture, 1, 8, 1, "\talpha")
	logical, inspected, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, inspected)
	testing.expect_value(t, logical.indentation_policy.policy.indent_width, u16(2))
	testing.expect_value(t, logical.tab_width, u16(8))
}

/* Verifies Backspace uses indentation boundaries only before line content. */
@(test)
backspace_is_smart_only_in_leading_indentation :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "      alpha", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	effective := indentation.DEFAULT_EFFECTIVE_POLICY
	effective.policy.indent_width = 4
	policy_set, policy_failure := editor_view.set_indentation_policy(
		&fixture.view_registry,
		fixture.view,
		effective,
	)
	testing.expectf(t, policy_set, "effective policy setup failed with %v", policy_failure.code)
	if !policy_set do return
	indent_point, indent_point_ok, _ := editor.buffer_position(&fixture.buffer, 6)
	testing.expect(t, indent_point_ok)
	point_set, _ := editor_view.set_point(&fixture.view_registry, fixture.view, indent_point)
	testing.expect(t, point_set)

	smart, smart_ok, smart_failure := execute_named(&fixture, "delete-previous-grapheme")
	testing.expectf(t, smart_ok, "smart Backspace failed with %v", smart_failure.code)
	if smart_ok do native_result_close(&smart)
	expect_native_state(t, &fixture, 4, 4, 1, "    alpha")

	undone, undo_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undo_ok, "smart Backspace undo failed with %v", undo_failure.code)
	if undo_ok do native_result_close(&undone)
	content_point, content_point_ok, _ := editor.buffer_position(&fixture.buffer, len("      alpha"))
	testing.expect(t, content_point_ok)
	point_set, _ = editor_view.set_point(&fixture.view_registry, fixture.view, content_point)
	testing.expect(t, point_set)
	ordinary, ordinary_ok, ordinary_failure := execute_named(&fixture, "delete-previous-grapheme")
	testing.expectf(t, ordinary_ok, "ordinary Backspace failed with %v", ordinary_failure.code)
	if ordinary_ok do native_result_close(&ordinary)
	expect_native_state(t, &fixture, len("      alph"), len("      alph"), 3, "      alph")
}

/* Verifies explicit normalization is line-scoped, atomic, and reversible. */
@(test)
indentation_normalization_is_atomic_and_reversible :: proc(t: ^testing.T) {
	contents := "\talpha  beta\n      gamma\n"
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, contents, context.allocator) do return
	defer native_fixture_close(t, &fixture)
	effective := indentation.DEFAULT_EFFECTIVE_POLICY
	effective.policy = {
		representation = .Spaces,
		indent_width = 4,
		display_tab_width = 8,
	}
	policy_set, policy_failure := editor_view.set_indentation_policy(
		&fixture.view_registry,
		fixture.view,
		effective,
	)
	testing.expectf(t, policy_set, "effective policy setup failed with %v", policy_failure.code)
	if !policy_set do return

	spaces, spaces_ok, spaces_failure := execute_named(&fixture, "normalize-indentation-to-spaces")
	testing.expectf(t, spaces_ok, "space normalization failed with %v", spaces_failure.code)
	if spaces_ok do native_result_close(&spaces)
	space_contents := "    alpha  beta\n      gamma\n"
	expect_native_state(t, &fixture, 0, 0, 1, space_contents)

	start, start_ok, _ := editor.buffer_position(&fixture.buffer, 0)
	end, end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len(space_contents)))
	testing.expect(t, start_ok && end_ok)
	tabs, tabs_ok, tabs_failure := execute_named(
		&fixture,
		"normalize-indentation-to-tabs",
		"",
		{present = true, start = start, end = end},
	)
	testing.expectf(t, tabs_ok, "tab normalization failed with %v", tabs_failure.code)
	if tabs_ok do native_result_close(&tabs)
	tab_contents := "\talpha  beta\n\t  gamma\n"
	expect_native_state(t, &fixture, 0, 0, 2, tab_contents)

	undone, undo_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undo_ok, "normalization undo failed with %v", undo_failure.code)
	if undo_ok do native_result_close(&undone)
	expect_native_state(t, &fixture, 0, 0, 3, space_contents)
	redone, redo_ok, redo_failure := execute_named(&fixture, "redo")
	testing.expectf(t, redo_ok, "normalization redo failed with %v", redo_failure.code)
	if redo_ok do native_result_close(&redone)
	expect_native_state(t, &fixture, 0, 0, 4, tab_contents)
}

/* Verifies profile-neutral line indentation uses one explicit-range transaction. */
@(test)
logical_line_indentation_is_atomic_and_reversible :: proc(t: ^testing.T) {
	contents := "a\n  b\n\tc\n"
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, contents, context.allocator) do return
	defer native_fixture_close(t, &fixture)
	policy_set, policy_failure := editor_view.set_layout_policy(
		&fixture.view_registry,
		fixture.view,
		0,
		2,
		editor_view.Display_Profile_ID(1),
	)
	testing.expectf(t, policy_set, "indentation policy setup failed with %v", policy_failure.code)
	if !policy_set do return
	start, start_ok, _ := editor.buffer_position(&fixture.buffer, 0)
	end, end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("a\n  b\n")))
	testing.expect(t, start_ok && end_ok)
	if !start_ok || !end_ok do return
	explicit := Native_Explicit_Range{present = true, start = start, end = end}

	indented, indent_ok, indent_failure := execute_named(&fixture, "indent-lines", "", explicit)
	testing.expectf(t, indent_ok, "line indentation failed with %v", indent_failure.code)
	if indent_ok do native_result_close(&indented)
	expect_native_state(t, &fixture, 0, 0, 1, "  a\n    b\n\tc\n")

	undone, undo_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undo_ok, "line indentation undo failed with %v", undo_failure.code)
	if undo_ok do native_result_close(&undone)
	expect_native_state(t, &fixture, 0, 0, 2, contents)

	start, start_ok, _ = editor.buffer_position(&fixture.buffer, 0)
	end, end_ok, _ = editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len(contents)))
	testing.expect(t, start_ok && end_ok)
	if !start_ok || !end_ok do return
	explicit = {present = true, start = start, end = end}
	outdented, outdent_ok, outdent_failure := execute_named(&fixture, "outdent-lines", "", explicit)
	testing.expectf(t, outdent_ok, "line outdentation failed with %v", outdent_failure.code)
	if outdent_ok do native_result_close(&outdented)
	expect_native_state(t, &fixture, 0, 0, 3, "a\nb\nc\n")
}

/* Verifies insertion, line break, and deletion publish complete grapheme-aware edits. */
@(test)
edits_publish_revision_and_cursor :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "a é🙂\nZ", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)

	execute_named(&fixture, "cursor-next-grapheme")
	execute_named(&fixture, "cursor-next-grapheme")
	execute_named(&fixture, "cursor-next-grapheme")
	expect_native_state(t, &fixture, 5, 3, 0, "a é🙂\nZ")

	result, ok, _ := execute_named(&fixture, "delete-previous-grapheme")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Buffer_Committed)
	testing.expect_value(t, result.commit.base_revision, editor.Revision(0))
	testing.expect_value(t, result.commit.result_revision, editor.Revision(1))
	testing.expect(t, result.commit.logical_view.present)
	native_result_close(&result)
	expect_native_state(t, &fixture, 2, 2, 1, "a 🙂\nZ")

	result, ok, _ = execute_named(&fixture, "delete-next-grapheme")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Buffer_Committed)
	native_result_close(&result)
	expect_native_state(t, &fixture, 2, 2, 2, "a \nZ")

	result, ok, _ = execute_named(&fixture, "insert-line-break")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Buffer_Committed)
	native_result_close(&result)
	expect_native_state(t, &fixture, 3, 0, 3, "a \n\nZ")

	result, ok, _ = execute_named(&fixture, "insert-text", "界")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Buffer_Committed)
	native_result_close(&result)
	expect_native_state(t, &fixture, 6, 2, 4, "a \n界\nZ")
}

/* Verifies modal named-slot paste inserts after the current grapheme through ordinary history. */
@(test)
insert_text_after_point_is_reversible :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "ab", context.allocator) do return
	defer native_fixture_close(t, &fixture)

	inserted, inserted_ok, insert_failure := execute_named(
		&fixture,
		"insert-text-after-point",
		"界",
	)
	testing.expectf(t, inserted_ok, "insert after point failed with %v", insert_failure.code)
	if inserted_ok do native_result_close(&inserted)
	expect_native_state(t, &fixture, len("a界"), 3, 1, "a界b")

	undone, undone_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone_ok, "insert after point undo failed with %v", undo_failure.code)
	if undone_ok do native_result_close(&undone)
	expect_native_state(t, &fixture, 0, 0, 2, "ab")
}

/* Verifies direct overwrite remains view-local and replaces one complete grapheme. */
@(test)
overwrite_replaces_one_grapheme :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "é🙂x", context.allocator) do return
	defer native_fixture_close(t, &fixture)

	toggled, toggled_ok, toggle_failure := execute_named(&fixture, "toggle-overwrite-mode")
	testing.expectf(t, toggled_ok, "overwrite toggle failed with %v", toggle_failure.code)
	testing.expect_value(t, toggled.completion, Native_Completion.View_Changed)
	state, state_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, state_ok)
	if state_ok {
		testing.expect(t, state.overwrite_mode)
		next, _, next_ok, _ := display.navigation_target(
			&fixture.buffer,
			state,
			.Next_Grapheme,
			display.terminal_unicode17_profile(),
		)
		testing.expect(t, next_ok)
		if next_ok {
			testing.expect_value(t, next.byte_offset, editor.Byte_Offset(len("é")))
		}
	}

	replaced, replaced_ok, replace_failure := execute_named(&fixture, "insert-text", "界")
	testing.expectf(t, replaced_ok, "overwrite insert failed with %v", replace_failure.code)
	testing.expect_value(t, replaced.completion, Native_Completion.Buffer_Committed)
	native_result_close(&replaced)
	expect_native_state(t, &fixture, len("界"), 2, 1, "界🙂x")

	undone, undone_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone_ok, "overwrite undo failed with %v", undo_failure.code)
	testing.expect_value(t, undone.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 0, 0, 2, "é🙂x")
	state, state_ok, _ = editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, state_ok)
	if state_ok {
		testing.expect(t, state.overwrite_mode)
	}

	redone, redone_ok, redo_failure := execute_named(&fixture, "redo")
	testing.expectf(t, redone_ok, "overwrite redo failed with %v", redo_failure.code)
	testing.expect_value(t, redone.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, len("界"), 2, 3, "界🙂x")

	_, toggled_ok, toggle_failure = execute_named(&fixture, "toggle-overwrite-mode")
	testing.expectf(t, toggled_ok, "overwrite toggle failed with %v", toggle_failure.code)
	inserted, inserted_ok, insert_failure := execute_named(&fixture, "insert-text", "a")
	testing.expectf(t, inserted_ok, "ordinary insert failed with %v", insert_failure.code)
	native_result_close(&inserted)
	expect_native_state(t, &fixture, len("界a"), 3, 4, "界a🙂x")
}

/* Verifies modal replacement consumes matching graphemes without crossing a line end. */
@(test)
replace_text_input_is_unicode_safe_and_line_bounded :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "é🙂x\nz", context.allocator) do return
	defer native_fixture_close(t, &fixture)

	replaced, replaced_ok, replace_failure := execute_named(
		&fixture,
		"insert-text",
		"界a",
		{},
		true,
	)
	testing.expectf(t, replaced_ok, "replace input failed with %v", replace_failure.code)
	if replaced_ok do native_result_close(&replaced)
	expect_native_state(t, &fixture, len("界a"), 3, 1, "界ax\nz")

	undone, undone_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone_ok, "replace undo failed with %v", undo_failure.code)
	if undone_ok do native_result_close(&undone)
	expect_native_state(t, &fixture, 0, 0, 2, "é🙂x\nz")

	redone, redone_ok, redo_failure := execute_named(&fixture, "redo")
	testing.expectf(t, redone_ok, "replace redo failed with %v", redo_failure.code)
	if redone_ok do native_result_close(&redone)
	expect_native_state(t, &fixture, len("界a"), 3, 3, "界ax\nz")

	line_end, line_end_ok, _ := editor.buffer_position(&fixture.buffer, editor.Byte_Offset(len("界ax")))
	testing.expect(t, line_end_ok)
	if !line_end_ok do return
	point_set, _ := editor_view.set_point(&fixture.view_registry, fixture.view, line_end)
	testing.expect(t, point_set)
	inserted, inserted_ok, insert_failure := execute_named(
		&fixture,
		"insert-text",
		"!",
		{},
		true,
	)
	testing.expectf(t, inserted_ok, "line-end replace input failed with %v", insert_failure.code)
	if inserted_ok do native_result_close(&inserted)
	expect_native_state(t, &fixture, len("界ax!"), 5, 4, "界ax!\nz")

	malformed := []byte{0xff}
	_, malformed_ok, malformed_failure := execute_named(
		&fixture,
		"insert-text",
		string(malformed),
		{},
		true,
	)
	testing.expect(t, !malformed_ok)
	testing.expect_value(t, malformed_failure.code, Failure_Code.Malformed_Text)
	expect_native_state(t, &fixture, len("界ax!"), 5, 4, "界ax!\nz")
}

/* Verifies semantic modal repeat replays insertion through one reversible transaction. */
@(test)
modal_repeat_replays_insert_semantics_through_history :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "one two", context.allocator) do return
	defer native_fixture_close(t, &fixture)

	repeated, repeated_ok, repeat_failure := execute_modal_repeat(
		&fixture,
		.Insert_Text,
		.Modal_Enter_Insert_After,
		"X",
	)
	testing.expectf(t, repeated_ok, "modal repeat failed with %v", repeat_failure.code)
	if repeated_ok do native_result_close(&repeated)
	expect_native_state(t, &fixture, 2, 2, 1, "oXne two")

	undone, undone_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undone_ok, "modal repeat undo failed with %v", undo_failure.code)
	if undone_ok do native_result_close(&undone)
	expect_native_state(t, &fixture, 0, 0, 2, "one two")

	redone, redone_ok, redo_failure := execute_named(&fixture, "redo")
	testing.expectf(t, redone_ok, "modal repeat redo failed with %v", redo_failure.code)
	if redone_ok do native_result_close(&redone)
	expect_native_state(t, &fixture, 2, 2, 3, "oXne two")
}

/* Verifies rectangle transfer and batch editing remain one reversible transaction. */
@(test)
rectangle_commands_copy_edit_and_restore_atomically :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "abcd\nxy\nαβγδ\n", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	anchor, anchor_ok, _ := editor.buffer_position(&fixture.buffer, 1)
	cursor, cursor_ok, _ := editor.buffer_position(&fixture.buffer, 10)
	testing.expect(t, anchor_ok && cursor_ok)
	selected, select_failure := editor_view.select_range(
		&fixture.view_registry,
		fixture.view,
		anchor,
		cursor,
		1,
		.Rectangle,
		.Grapheme,
	)
	testing.expectf(t, selected, "rectangle selection failed with %v", select_failure.code)

	copied, copy_ok, copy_failure := execute_named(&fixture, "copy-rectangle")
	testing.expectf(t, copy_ok, "rectangle copy failed with %v", copy_failure.code)
	testing.expect_value(t, copied.completion, Native_Completion.Text_Retained)
	ring_stats, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	expect_ring_text(t, &fixture.kill_ring, ring_stats.newest, "b\ny\nβ")

	killed, kill_ok, kill_failure := execute_named(&fixture, "kill-rectangle")
	testing.expectf(t, kill_ok, "rectangle kill failed with %v", kill_failure.code)
	if kill_ok do native_result_close(&killed)
	expect_native_state(t, &fixture, 1, 1, 1, "acd\nx\nαγδ\n")

	undone, undo_ok, undo_failure := execute_named(&fixture, "undo")
	testing.expectf(t, undo_ok, "rectangle undo failed with %v", undo_failure.code)
	if undo_ok do native_result_close(&undone)
	expect_native_state(t, &fixture, 10, 1, 2, "abcd\nxy\nαβγδ\n")
	restored, restored_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, restored_ok && restored.region_active)
	testing.expect_value(t, restored.selection_shape, editor.Selection_Shape.Rectangle)

	replaced, replace_ok, replace_failure := execute_named(
		&fixture, "replace-rectangle-text", "Z",
	)
	testing.expectf(t, replace_ok, "rectangle replacement failed with %v", replace_failure.code)
	if replace_ok do native_result_close(&replaced)
	expect_native_state(t, &fixture, 1, 1, 3, "aZcd\nxZ\nαZγδ\n")
}

/* Verifies page navigation moves point and viewport with one logical line of context. */
@(test)
native_page_navigation_moves_by_viewport_rows :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "0\n1\n2\n3\n4\n5", context.allocator) do return
	defer native_fixture_close(t, &fixture)

	next, next_found, _ := interaction.command_lookup(&fixture.command_registry, "scroll-next-page")
	previous, previous_found, _ := interaction.command_lookup(&fixture.command_registry, "scroll-previous-page")
	testing.expect(t, next_found && previous_found)
	if !next_found || !previous_found do return

	next_request := native_request(&fixture, next)
	next_request.constraints.height_rows = 3
	previous_request := native_request(&fixture, previous)
	previous_request.constraints.height_rows = 3
	result, moved, move_failure := native_command_execute(previous_request)
	testing.expectf(t, moved, "initial previous page failed with %v", move_failure.code)
	testing.expect_value(t, result.completion, Native_Completion.No_Op)

	result, moved, move_failure = native_command_execute(next_request)
	testing.expectf(t, moved, "next page failed with %v", move_failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 4, 0, 0, "0\n1\n2\n3\n4\n5")
	state, state_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, state_ok)
	if state_ok {
		testing.expect_value(t, state.viewport_origin_position.byte_offset, editor.Byte_Offset(4))
	}

	result, moved, move_failure = native_command_execute(previous_request)
	testing.expectf(t, moved, "previous page failed with %v", move_failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	expect_native_state(t, &fixture, 0, 0, 0, "0\n1\n2\n3\n4\n5")
}

/* Verifies recenter changes only the viewport and places point on its middle row. */
@(test)
native_recenter_centers_point_without_moving_it :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "0\n1\n2\n3\n4\n5", context.allocator) do return
	defer native_fixture_close(t, &fixture)
	point, point_ok, _ := editor.buffer_position(&fixture.buffer, 8)
	if !point_ok do return
	moved, move_failure := editor_view.set_point(&fixture.view_registry, fixture.view, point)
	testing.expectf(t, moved, "point setup failed with %v", move_failure.code)

	recenter, found, _ := interaction.command_lookup(&fixture.command_registry, "recenter")
	testing.expect(t, found)
	if !found do return
	request := native_request(&fixture, recenter)
	request.constraints.height_rows = 5
	request.constraints.width_cells = 80
	result, executed, execution_failure := native_command_execute(request)
	testing.expectf(t, executed, "recenter failed with %v", execution_failure.code)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	state, state_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, state_ok)
	if state_ok {
		testing.expect_value(t, state.point_position.byte_offset, editor.Byte_Offset(8))
		testing.expect_value(t, state.viewport_origin_position.byte_offset, editor.Byte_Offset(4))
		testing.expect_value(t, state.horizontal_display_column, u32(0))
	}
}

/* Verifies split, spatial focus, close, and keep-only commands mutate one checked layout. */
@(test)
pane_commands_apply_layout_changes :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha\nbeta", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	layout_registry: layout.Registry
	layout_ok, layout_failure := layout.registry_init(
		&layout_registry,
		layout.Owner_ID(81),
		layout.Layout_ID(81),
		&fixture.view_registry,
		fixture.view,
		layout.Geometry_Request{rows = 12, columns = 40},
	)
	testing.expectf(t, layout_ok, "layout setup failed with %v", layout_failure.code)
	if !layout_ok {
		return
	}
	defer layout.registry_close(&layout_registry)

	result, split_below_ok, _ := execute_layout_named(&fixture, &layout_registry, "split-pane-below")
	testing.expect(t, split_below_ok)
	testing.expect_value(t, result.completion, Native_Completion.View_Changed)
	right_result, split_right_ok, _ := execute_layout_named(&fixture, &layout_registry, "split-pane-right")
	testing.expect(t, split_right_ok)
	testing.expect_value(t, right_result.completion, Native_Completion.View_Changed)
	handle, _, _ := layout.registry_handle(&layout_registry)
	three_panes, _, _ := layout.registry_snapshot(&layout_registry, handle)
	testing.expect_value(t, three_panes.pane_count, u16(3))
	vertical_result, vertical_ok, _ := execute_layout_named(
		&fixture,
		&layout_registry,
		"enlarge-pane-vertically",
	)
	testing.expect(t, vertical_ok)
	testing.expect_value(t, vertical_result.completion, Native_Completion.View_Changed)
	horizontal_result, horizontal_ok, _ := execute_layout_named(
		&fixture,
		&layout_registry,
		"enlarge-pane-horizontally",
	)
	testing.expect(t, horizontal_ok)
	testing.expect_value(t, horizontal_result.completion, Native_Completion.View_Changed)
	shrink_result, shrink_ok, _ := execute_layout_named(
		&fixture,
		&layout_registry,
		"shrink-pane-horizontally",
	)
	testing.expect(t, shrink_ok)
	testing.expect_value(t, shrink_result.completion, Native_Completion.View_Changed)
	balance_result, balance_ok, _ := execute_layout_named(
		&fixture,
		&layout_registry,
		"balance-panes",
	)
	testing.expect(t, balance_ok)
	testing.expect_value(t, balance_result.completion, Native_Completion.View_Changed)
	area_result, area_ok, _ := execute_layout_named(
		&fixture,
		&layout_registry,
		"balance-pane-areas",
	)
	testing.expect(t, area_ok)
	testing.expect_value(t, area_result.completion, Native_Completion.View_Changed)
	handle, _, _ = layout.registry_handle(&layout_registry)
	directional_snapshot, _, _ := layout.registry_snapshot(&layout_registry, handle)
	top_left, top_right, bottom: layout.Node_Descriptor
	for index in 0 ..< int(directional_snapshot.node_count) {
		candidate := directional_snapshot.nodes[index]
		if candidate.kind != .Pane do continue
		if bottom.pane.pane_id == layout.Pane_ID(0) ||
		   candidate.geometry.outer.row > bottom.geometry.outer.row {
			bottom = candidate
		}
	}
	for index in 0 ..< int(directional_snapshot.node_count) {
		candidate := directional_snapshot.nodes[index]
		if candidate.kind != .Pane || candidate.geometry.outer.row >= bottom.geometry.outer.row do continue
		if top_left.pane.pane_id == layout.Pane_ID(0) ||
		   candidate.geometry.outer.column < top_left.geometry.outer.column {
			top_left = candidate
		}
		if top_right.pane.pane_id == layout.Pane_ID(0) ||
		   candidate.geometry.outer.column > top_right.geometry.outer.column {
			top_right = candidate
		}
	}
	directional_cases := [4]struct {
		name: string,
		source: layout.Pane_ID,
	} {
		{"focus-pane-left", top_right.pane.pane_id},
		{"focus-pane-up", bottom.pane.pane_id},
		{"focus-pane-down", top_left.pane.pane_id},
		{"focus-pane-right", top_left.pane.pane_id},
	}
	for test_case in directional_cases {
		handle, _, _ = layout.registry_handle(&layout_registry)
		current, _, _ := layout.registry_snapshot(&layout_registry, handle)
		source := native_test_pane_handle(&current, test_case.source)
		_, positioned, position_failure := layout.registry_focus(
			&layout_registry,
			source,
		)
		testing.expectf(t, positioned, "%s source focus failed with %v", test_case.name, position_failure.code)
		directional, direction_ok, direction_failure := execute_layout_named(
			&fixture,
			&layout_registry,
			test_case.name,
		)
		testing.expectf(t, direction_ok, "%s failed with %v", test_case.name, direction_failure.code)
		testing.expectf(
			t,
			directional.completion == .View_Changed,
			"%s returned %v",
			test_case.name,
			directional.completion,
		)
	}
	handle, _, _ = layout.registry_handle(&layout_registry)
	current, _, _ := layout.registry_snapshot(&layout_registry, handle)
	_, _, _ = layout.registry_focus(&layout_registry, native_test_pane_handle(&current, top_right.pane.pane_id))
	no_right, no_right_ok, no_right_failure := execute_layout_named(
		&fixture,
		&layout_registry,
		"focus-pane-right",
	)
	testing.expectf(t, no_right_ok, "right boundary failed with %v", no_right_failure.code)
	testing.expect_value(t, no_right.completion, Native_Completion.No_Op)

	focus_result, focused, _ := execute_layout_named(&fixture, &layout_registry, "focus-next-pane")
	testing.expect(t, focused)
	testing.expect_value(t, focus_result.completion, Native_Completion.View_Changed)
	_, closed, _ := execute_layout_named(&fixture, &layout_registry, "close-pane")
	testing.expect(t, closed)
	handle, _, _ = layout.registry_handle(&layout_registry)
	two_panes, _, _ := layout.registry_snapshot(&layout_registry, handle)
	testing.expect_value(t, two_panes.pane_count, u16(2))

	keep_result, kept, _ := execute_layout_named(&fixture, &layout_registry, "keep-only-pane")
	testing.expect(t, kept)
	testing.expect_value(t, keep_result.completion, Native_Completion.View_Changed)
	handle, _, _ = layout.registry_handle(&layout_registry)
	one_pane, _, _ := layout.registry_snapshot(&layout_registry, handle)
	testing.expect_value(t, one_pane.pane_count, u16(1))
	no_focus_result, no_focus_change, _ := execute_layout_named(&fixture, &layout_registry, "focus-next-pane")
	testing.expect(t, no_focus_change)
	testing.expect_value(t, no_focus_result.completion, Native_Completion.No_Op)
}

@(private)
native_test_pane_handle :: proc(snapshot: ^layout.Snapshot, pane_id: layout.Pane_ID) -> layout.Pane_Handle {
	for index in 0 ..< int(snapshot.node_count) {
		candidate := snapshot.nodes[index]
		if candidate.kind == .Pane && candidate.pane.pane_id == pane_id do return candidate.pane
	}
	return {}
}

/* Verifies deletion boundaries, cancellation, exit, and invalid text remain explicit. */
@(test)
completion_rejection_is_deterministic :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "text", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)

	result, ok, _ := execute_named(&fixture, "delete-previous-grapheme")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.No_Op)
	expect_native_state(t, &fixture, 0, 0, 0, "text")

	result, ok, _ = execute_named(&fixture, "keyboard-quit")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Pending_Input_Cancelled)
	result, ok, _ = execute_named(&fixture, "request-editor-exit")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Exit_Requested)
	result, ok, _ = execute_named(&fixture, "find-file")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Find_File_Requested)
	result, ok, _ = execute_named(&fixture, "find-alternate-file")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Find_Alternate_File_Requested)
	result, ok, _ = execute_named(&fixture, "write-file")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Write_File_Requested)
	result, ok, _ = execute_named(&fixture, "save-some-buffers")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Save_Some_Buffers_Requested)
	result, ok, _ = execute_named(&fixture, "insert-file")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Insert_File_Requested)
	result, ok, _ = execute_named(&fixture, "next-buffer")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Next_Buffer_Requested)
	result, ok, _ = execute_named(&fixture, "previous-buffer")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Previous_Buffer_Requested)
	result, ok, _ = execute_named(&fixture, "switch-to-buffer")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Switch_To_Buffer_Requested)
	result, ok, _ = execute_named(&fixture, "find-file-other-pane")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Find_File_Other_Pane_Requested)
	result, ok, _ = execute_named(&fixture, "switch-to-buffer-other-pane")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Switch_To_Buffer_Other_Pane_Requested)
	result, ok, _ = execute_named(&fixture, "display-buffer-other-pane")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Display_Buffer_Other_Pane_Requested)
	result, ok, _ = execute_named(&fixture, "list-buffers")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.List_Buffers_Requested)
	result, ok, _ = execute_named(&fixture, "reload-interaction-profile")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Interaction_Profile_Reload_Requested)
	legacy_names := [?]string {
		"project-register",
		"project-add-directory",
		"project-remove-directory",
		"project-list-directories",
		"project-find-directory",
	}
	for name in legacy_names {
		_, found, _ := interaction.command_lookup(&fixture.command_registry, name)
		testing.expectf(t, !found, "legacy command remains registered: %s", name)
	}
	result, ok, _ = execute_named(&fixture, "project-promote")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Project_Promote_Requested)
	result, ok, _ = execute_named(&fixture, "project-unregister")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Project_Unregister_Requested)
	result, ok, _ = execute_named(&fixture, "workspace-add-project")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Workspace_Add_Project_Requested)
	result, ok, _ = execute_named(&fixture, "workspace-remove-project")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Workspace_Remove_Project_Requested)
	result, ok, _ = execute_named(&fixture, "workspace-unregister")
	testing.expect(t, ok)
	testing.expect_value(t, result.completion, Native_Completion.Workspace_Unregister_Requested)
	maksym_commands := [?]string {
		"maksym-open-directory",
		"maksym-open-directory-other-pane",
		"maksym-open-directory-below",
		"maksym-open-directory-right",
		"maksym-open-containing-directory",
		"maksym-open-containing-directory-other-pane",
		"maksym-next-entry",
		"maksym-previous-entry",
		"maksym-parent-directory",
		"maksym-jump-to-entry",
		"maksym-open-entry",
		"maksym-open-entry-other-pane",
		"maksym-display-entry-other-pane",
		"maksym-refresh",
		"maksym-toggle-editable-listing",
		"maksym-apply-editable-listing",
		"maksym-cancel-editable-listing",
		"maksym-editable-next-line",
		"maksym-editable-previous-line",
	}
	for name in maksym_commands {
		result, ok, _ = execute_named(&fixture, name)
		testing.expectf(t, ok, "%s was unavailable", name)
		if ok do testing.expect_value(t, result.completion, Native_Completion.Maksym_Command_Requested)
	}
	darek_commands := [?]string {
		"darek-toggle",
		"darek-select",
		"darek-focus-toggle",
		"darek-show-directory",
		"darek-find-current-file",
		"darek-show-current-project",
		"darek-next-node",
		"darek-previous-node",
		"darek-next-sibling",
		"darek-previous-sibling",
		"darek-next-project",
		"darek-previous-project",
		"darek-move-project-up",
		"darek-move-project-down",
		"darek-project-add",
		"darek-project-remove",
		"darek-project-rename",
		"darek-project-collapse",
		"darek-project-collapse-others",
		"darek-workspace-switch",
		"darek-workspace-next",
		"darek-root-parent",
		"darek-root-current-directory",
		"darek-parent-node",
		"darek-structure-action",
		"darek-visit-action",
		"darek-open",
		"darek-open-split-below",
		"darek-open-split-right",
		"darek-open-and-hide",
		"darek-open-mru-pane",
		"darek-open-external",
		"darek-create-file",
		"darek-create-directory",
		"darek-rename-node",
		"darek-move-node",
		"darek-copy-node",
		"darek-delete-node",
		"darek-copy-absolute-path",
		"darek-copy-project-relative-path",
		"darek-copy-project-root",
		"darek-copy-name",
		"darek-collapse-or-parent",
		"darek-collapse-parent",
		"darek-collapse-all-projects",
		"darek-refresh",
		"darek-toggle-peek",
		"darek-other-pane-next-line",
		"darek-other-pane-previous-line",
		"darek-other-pane-next-page",
		"darek-other-pane-previous-page",
		"darek-toggle-file-follow",
		"darek-panel-left",
		"darek-panel-right",
		"darek-decrease-width",
		"darek-increase-width",
		"darek-fit-width",
		"darek-toggle-extra-width",
		"darek-toggle-width-lock",
		"darek-toggle-directory-compression",
		"darek-narrow-current-project",
		"darek-show-all-projects",
		"darek-help",
		"darek-help-advanced",
		"darek-hide",
		"darek-close",
	}
	for name in darek_commands {
		result, ok, _ = execute_named(&fixture, name)
		testing.expectf(t, ok, "%s was unavailable", name)
		if ok do testing.expect_value(t, result.completion, Native_Completion.Darek_Command_Requested)
	}

	failure: Failure_Context
	_, ok, failure = execute_named(&fixture, "insert-text")
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Missing_Text)
	expect_native_state(t, &fixture, 0, 0, 0, "text")

	handle, found, _ := interaction.command_lookup(&fixture.command_registry, "cursor-next-grapheme")
	testing.expect(t, found)
	handle.registry_generation = interaction.Registry_Generation(2)
	request := native_request(&fixture, handle)
	_, ok, failure = native_command_execute(request)
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Command)
	testing.expect_value(t, failure.interaction_code, interaction.Failure_Code.Invalid_Command)
	expect_native_state(t, &fixture, 0, 0, 0, "text")
}

/* Verifies semantic region commands retain mark across movement and deactivation. */
@(test)
region_commands_keep_point_and_mark :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "abc", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)

	marked, marked_ok, _ := execute_named(&fixture, "set-mark-command")
	testing.expect(t, marked_ok)
	testing.expect_value(t, marked.completion, Native_Completion.View_Changed)
	execute_named(&fixture, "cursor-next-grapheme")
	execute_named(&fixture, "cursor-next-grapheme")
	active, active_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, active_ok)
	testing.expect(t, active.mark.present && active.region_active)
	testing.expect_value(t, active.point_position.byte_offset, editor.Byte_Offset(2))
	testing.expect_value(t, active.mark.position.byte_offset, editor.Byte_Offset(0))

	quit, quit_ok, _ := execute_named(&fixture, "keyboard-quit")
	testing.expect(t, quit_ok)
	testing.expect_value(t, quit.completion, Native_Completion.View_Changed)
	inactive, inactive_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, inactive_ok)
	testing.expect(t, inactive.mark.present && !inactive.region_active)

	exchanged, exchanged_ok, _ := execute_named(&fixture, "exchange-point-and-mark")
	testing.expect(t, exchanged_ok)
	testing.expect_value(t, exchanged.completion, Native_Completion.View_Changed)
	swapped, swapped_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, swapped_ok)
	testing.expect(t, swapped.region_active)
	testing.expect_value(t, swapped.point_position.byte_offset, editor.Byte_Offset(0))
	testing.expect_value(t, swapped.mark.position.byte_offset, editor.Byte_Offset(2))

	deactivated, deactivated_ok, _ := execute_named(&fixture, "deactivate-mark")
	testing.expect(t, deactivated_ok)
	testing.expect_value(t, deactivated.completion, Native_Completion.View_Changed)
	inserted, inserted_ok, _ := execute_named(&fixture, "insert-text", "z")
	testing.expect(t, inserted_ok)
	native_result_close(&inserted)
	final, final_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, final_ok)
	testing.expect(t, final.mark.present && !final.region_active)
	testing.expect_value(t, final.point_position.byte_offset, editor.Byte_Offset(1))
}

/* Verifies copy, delete, and kill preserve their distinct ring and history effects. */
@(test)
region_transfer_coordinates_state :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "alpha beta", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	execute_named(&fixture, "set-mark-command")
	for _ in 0 ..< 5 {
		execute_named(&fixture, "cursor-next-grapheme")
	}

	copied, copy_ok, copy_failure := execute_named(&fixture, "copy-region")
	testing.expectf(t, copy_ok, "copy failed with %v", copy_failure.code)
	testing.expect_value(t, copied.completion, Native_Completion.Text_Retained)
	expect_native_state(t, &fixture, 5, 5, 0, "alpha beta")
	ring_stats, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	testing.expect_value(t, ring_stats.usage.retained_entries, u64(1))
	expect_ring_text(t, &fixture.kill_ring, ring_stats.newest, "alpha")
	history_stats, _, _ := history.store_stats(&fixture.history)
	testing.expect_value(t, history_stats.usage.retained_nodes, u64(1))

	deleted, delete_ok, delete_failure := execute_named(&fixture, "delete-region")
	testing.expectf(t, delete_ok, "delete region failed with %v", delete_failure.code)
	testing.expect_value(t, deleted.completion, Native_Completion.Buffer_Committed)
	native_result_close(&deleted)
	expect_native_state(t, &fixture, 0, 0, 1, " beta")
	after_delete, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	testing.expect_value(t, after_delete, ring_stats)

	undo, undo_ok, _ := execute_named(&fixture, "undo")
	testing.expect(t, undo_ok)
	testing.expect_value(t, undo.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 5, 5, 2, "alpha beta")
	restored, _, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, restored.region_active && restored.mark.present)

	killed, kill_ok, kill_failure := execute_named(&fixture, "kill-region")
	testing.expectf(t, kill_ok, "kill region failed with %v", kill_failure.code)
	testing.expect_value(t, killed.completion, Native_Completion.Buffer_Committed)
	testing.expect(t, killed.transfer.entry.id != kill_ring.Entry_ID(0))
	native_result_close(&killed)
	expect_native_state(t, &fixture, 0, 0, 3, " beta")
	after_kill, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	testing.expect_value(t, after_kill.usage.retained_entries, u64(2))
	expect_ring_text(t, &fixture.kill_ring, after_kill.newest, "alpha")
	history_stats, _, _ = history.store_stats(&fixture.history)
	testing.expect_value(t, history_stats.current_revision, editor.Revision(3))
}

/* Verifies inactive and empty regions reject without changing text, ring, view, or history. */
@(test)
region_transfer_rejects_missing_ranges :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "text", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	before_ring, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	_, copied, failure := execute_named(&fixture, "copy-region")
	testing.expect(t, !copied)
	testing.expect_value(t, failure.code, Failure_Code.Region_Unavailable)
	execute_named(&fixture, "set-mark-command")
	killed: bool
	_, killed, failure = execute_named(&fixture, "kill-region")
	testing.expect(t, !killed)
	testing.expect_value(t, failure.code, Failure_Code.Region_Unavailable)
	after_ring, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	testing.expect_value(t, after_ring, before_ring)
	expect_native_state(t, &fixture, 0, 0, 0, "text")
	history_stats, _, _ := history.store_stats(&fixture.history)
	testing.expect_value(t, history_stats.usage.retained_nodes, u64(1))
}

/* Verifies yank inserts newest text and immediate yank-pop replaces only that range. */
@(test)
yank_rotation_is_reversible :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, ">", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	test_ring_admit(t, &fixture.kill_ring, "older")
	test_ring_admit(t, &fixture.kill_ring, "newest")
	before_ring, _, _ := kill_ring.ring_stats(&fixture.kill_ring)

	yanked, yank_ok, yank_failure := execute_named(&fixture, "yank")
	testing.expectf(t, yank_ok, "yank failed with %v", yank_failure.code)
	testing.expect(t, fixture.yank_context.valid)
	native_result_close(&yanked)
	expect_native_state(t, &fixture, 6, 6, 1, "newest>")

	rotated, rotate_ok, rotate_failure := execute_named(&fixture, "yank-pop")
	testing.expectf(t, rotate_ok, "yank-pop failed with %v", rotate_failure.code)
	native_result_close(&rotated)
	expect_native_state(t, &fixture, 5, 5, 2, "older>")
	after_rotation, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	testing.expect_value(t, after_rotation, before_ring)

	undo, undo_ok, _ := execute_named(&fixture, "undo")
	testing.expect(t, undo_ok)
	testing.expect_value(t, undo.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 6, 6, 3, "newest>")
	testing.expect(t, !fixture.yank_context.valid)
	redo, redo_ok, _ := execute_named(&fixture, "redo")
	testing.expect(t, redo_ok)
	testing.expect_value(t, redo.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 5, 5, 4, "older>")
	_, rotate_ok, rotate_failure = execute_named(&fixture, "yank-pop")
	testing.expect(t, !rotate_ok)
	testing.expect_value(t, rotate_failure.code, Failure_Code.Kill_Ring_Failure)
}

/* Verifies another command invalidates yank rotation before it can replace text. */
@(test)
yank_rotation_rejects_intervening_command :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "x", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	test_ring_admit(t, &fixture.kill_ring, "one")
	test_ring_admit(t, &fixture.kill_ring, "two")
	yanked, yank_ok, _ := execute_named(&fixture, "yank")
	testing.expect(t, yank_ok)
	native_result_close(&yanked)
	execute_named(&fixture, "cursor-next-grapheme")
	testing.expect(t, !fixture.yank_context.valid)
	_, rotated, failure := execute_named(&fixture, "yank-pop")
	testing.expect(t, !rotated)
	testing.expect_value(t, failure.code, Failure_Code.Kill_Ring_Failure)
	expect_native_state(t, &fixture, 4, 4, 1, "twox")
}

/* Verifies a changed ring generation consumes and rejects the pending rotation chain. */
@(test)
native_yank_rotation_consumes_stale_ring_context :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "x", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	test_ring_admit(t, &fixture.kill_ring, "one")
	yanked, yank_ok, _ := execute_named(&fixture, "yank")
	testing.expect(t, yank_ok)
	native_result_close(&yanked)
	testing.expect(t, fixture.yank_context.valid)
	test_ring_admit(t, &fixture.kill_ring, "two")
	_, rotated, failure := execute_named(&fixture, "yank-pop")
	testing.expect(t, !rotated)
	testing.expect_value(t, failure.code, Failure_Code.Kill_Ring_Failure)
	testing.expect(t, !fixture.yank_context.valid)
	expect_native_state(t, &fixture, 3, 3, 1, "onex")
}

/* Verifies semantic native undo and redo traverse one grouped typing unit. */
@(test)
native_history_commands_reverse_grouped_typing :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	root_undo, root_undo_ok, _ := execute_named(&fixture, "undo")
	testing.expect(t, root_undo_ok)
	testing.expect_value(t, root_undo.completion, Native_Completion.No_Op)
	first, first_ok, _ := execute_named(&fixture, "insert-text", "a")
	native_result_close(&first)
	second, second_ok, _ := execute_named(&fixture, "insert-text", "界")
	native_result_close(&second)
	testing.expect(t, first_ok && second_ok)
	stats, _, _ := history.store_stats(&fixture.history)
	testing.expect_value(t, stats.usage.retained_nodes, u64(2))
	testing.expect_value(t, stats.usage.retained_records, u64(2))
	expect_native_state(t, &fixture, 4, 3, 2, "a界")

	undo, undo_ok, _ := execute_named(&fixture, "undo")
	testing.expect(t, undo_ok)
	testing.expect_value(t, undo.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 0, 0, 3, "")
	redo, redo_ok, _ := execute_named(&fixture, "redo")
	testing.expect(t, redo_ok)
	testing.expect_value(t, redo.completion, Native_Completion.Buffer_Committed)
	expect_native_state(t, &fixture, 4, 3, 4, "a界")
	leaf_redo, leaf_redo_ok, _ := execute_named(&fixture, "redo")
	testing.expect(t, leaf_redo_ok)
	testing.expect_value(t, leaf_redo.completion, Native_Completion.No_Op)
}

/* Verifies the checked native save command publishes the associated document revision. */
@(test)
save_publishes_associated_documents :: proc(t: ^testing.T) {
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "old", context.allocator) {
		return
	}
	defer native_fixture_close(t, &fixture)
	directory, directory_error := os.make_directory_temp("", "odra-command-save-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil {
		return
	}
	fixture.directory = directory
	path, path_error := os.join_path({directory, "document.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil {
		return
	}
	fixture.file_path = path
	testing.expect(t, os.write_entire_file(path, "old") == nil)
	prepared: document.Prepared_Open
	prepared_ok, prepare_failure := document.open_prepare(
		&prepared,
		document.Open_Request {
			document_id = document.Document_ID(91),
			buffer_id = editor.Buffer_ID(81),
			has_path = true,
			path = path,
			encoding = .UTF8,
		},
		document.Allocator_Set{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, prepared_ok, "document prepare failed with %v", prepare_failure.code)
	if !prepared_ok {
		return
	}
	committed, commit_failure := document.prepared_open_commit(
		&prepared,
		&fixture.document,
		editor.Revision(0),
	)
	testing.expectf(t, committed, "document commit failed with %v", commit_failure.code)
	if !committed {
		document.prepared_open_abort(&prepared)
		return
	}
	testing.expect(t, os.write_entire_file(path, "external replacement") == nil)

	inserted, insert_ok, _ := execute_named(&fixture, "insert-text", "new ")
	testing.expect(t, insert_ok && inserted.completion == .Buffer_Committed)
	native_result_close(&inserted)
	result, saved, failure := execute_named(&fixture, "save-associated-document")
	testing.expectf(t, saved, "native save failed with %v/%v", failure.code, failure.document_code)
	testing.expect_value(t, result.completion, Native_Completion.Document_Saved)
	testing.expect_value(t, result.save.publication, document.Publication_State.Published_Durable)
	testing.expect_value(t, result.save.saved_revision, editor.Revision(1))
	testing.expect(t, result.save.external_change_observed)
	contents, read_error := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_error == nil)
	if read_error == nil {
		testing.expect_value(t, string(contents), "new old")
	}
}

/* Verifies splice allocation failure preserves canonical text, revision, and view state. */
@(test)
edit_alloc_failure_preserves_state :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Native_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "stable", native_failing_allocator(&failing)) {
		return
	}
	failing.fail_after = failing.successful_allocations
	_, ok, failure := execute_named(&fixture, "insert-text", "x")
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Publication_Failure)
	testing.expect_value(t, failure.transaction_code, edit_transaction.Failure_Code.Persistent_Memory_Limit)
	expect_native_state(t, &fixture, 0, 0, 0, "stable")
	native_fixture_close(t, &fixture)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies a transaction fault after ring reservation aborts the unpublished entry. */
@(test)
kill_publish_failure_preserves_state :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	failing := Native_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	fixture: Native_Fixture
	if !native_fixture_init(t, &fixture, "stable", native_failing_allocator(&failing)) {
		return
	}
	execute_named(&fixture, "set-mark-command")
	for _ in 0 ..< 6 {
		execute_named(&fixture, "cursor-next-grapheme")
	}
	before_ring, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	failing.fail_after = failing.successful_allocations + 1
	_, killed, failure := execute_named(&fixture, "kill-region")
	testing.expect(t, !killed)
	testing.expect_value(t, failure.code, Failure_Code.Publication_Failure)
	after_ring, _, _ := kill_ring.ring_stats(&fixture.kill_ring)
	testing.expect_value(t, after_ring, before_ring)
	expect_native_state(t, &fixture, 6, 6, 0, "stable")
	native_fixture_close(t, &fixture)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(private)
Native_Fixture :: struct {
	buffer:           editor.Buffer,
	document:         document.Document,
	view_registry:    editor_view.Registry,
	history:          history.Store,
	location_history: Location_History,
	kill_ring:        kill_ring.Ring,
	view:             editor_view.View_Handle,
	command_registry: interaction.Command_Registry,
	directory:        string,
	file_path:        string,
	allocator:        runtime.Allocator,
	next_transaction_id: u64,
	next_undo_unit_id:   u64,
	yank_context:        Yank_Context,
}

@(private)
native_fixture_init :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	text: string,
	buffer_allocator: runtime.Allocator,
) -> bool {
	buffer_ok, buffer_failure := editor.buffer_init(
		&fixture.buffer,
		editor.Buffer_ID(81),
		text,
		editor.Allocator_Set {
			persistent = buffer_allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expectf(t, buffer_ok, "buffer setup failed: %v", buffer_failure.code)
	if !buffer_ok {
		return false
	}
	fixture.allocator = buffer_allocator
	fixture.next_transaction_id = 1
	fixture.next_undo_unit_id = 1
	history_ok, history_failure := history.store_init(
		&fixture.history,
		history.Store_ID(81),
		editor.Buffer_ID(81),
		editor.Revision(0),
		history.Allocator_Set{persistent = buffer_allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, history_ok, "history setup failed: %v", history_failure.code)
	if !history_ok {
		editor.buffer_close(&fixture.buffer)
		return false
	}
	ring_ok, ring_failure := kill_ring.ring_init(
		&fixture.kill_ring,
		kill_ring.Ring_ID(81),
		kill_ring.Allocator_Set{persistent = buffer_allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, ring_ok, "kill ring setup failed: %v", ring_failure.code)
	if !ring_ok {
		history.store_close(&fixture.history)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	registry_ok, registry_failure := editor_view.registry_init(
		&fixture.view_registry,
		editor_view.Registry_ID(82),
		context.allocator,
	)
	testing.expectf(t, registry_ok, "view registry setup failed: %v", registry_failure.code)
	if !registry_ok {
		kill_ring.ring_close(&fixture.kill_ring)
		history.store_close(&fixture.history)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	view_ok: bool
	fixture.view, view_ok, registry_failure = editor_view.create(
		&fixture.view_registry,
		&fixture.buffer,
	)
	testing.expectf(t, view_ok, "view setup failed: %v", registry_failure.code)
	if !view_ok {
		editor_view.registry_close(&fixture.view_registry)
		kill_ring.ring_close(&fixture.kill_ring)
		history.store_close(&fixture.history)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	definitions := native_command_definitions()
	commands_ok, command_failure := interaction.command_registry_init(
		&fixture.command_registry,
		interaction.Registry_Generation(1),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, commands_ok, "command registry setup failed: %v", command_failure.code)
	if !commands_ok {
		editor_view.close(&fixture.view_registry, &fixture.view)
		editor_view.registry_close(&fixture.view_registry)
		kill_ring.ring_close(&fixture.kill_ring)
		history.store_close(&fixture.history)
		editor.buffer_close(&fixture.buffer)
		return false
	}
	return true
}

@(private)
native_fixture_close :: proc(t: ^testing.T, fixture: ^Native_Fixture) {
	commands_closed, _ := interaction.command_registry_close(&fixture.command_registry)
	view_closed, _ := editor_view.close(&fixture.view_registry, &fixture.view)
	views_closed, _ := editor_view.registry_close(&fixture.view_registry)
	if fixture.document.state != nil {
		document.document_close(&fixture.document)
	}
	history_closed, _ := history.store_close(&fixture.history)
	ring_closed, _ := kill_ring.ring_close(&fixture.kill_ring)
	buffer_closed, _ := editor.buffer_close(&fixture.buffer)
	testing.expect(t, commands_closed && view_closed && views_closed && history_closed && ring_closed && buffer_closed)
	if len(fixture.directory) > 0 {
		os.remove_all(fixture.directory)
	}
	if len(fixture.file_path) > 0 {
		delete(fixture.file_path)
	}
	if len(fixture.directory) > 0 {
		delete(fixture.directory)
	}
}

@(private)
execute_named :: proc(
	fixture: ^Native_Fixture,
	name: string,
	text := "",
	explicit: Native_Explicit_Range = {},
	replace_text_input := false,
	argument_present := false,
	argument: i64 = 0,
) -> (Native_Result, bool, Failure_Context) {
	handle, found, lookup_failure := interaction.command_lookup(&fixture.command_registry, name)
	if !found {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			interaction_code = lookup_failure.code,
		}
	}
	request := native_request(fixture, handle)
	request.text = text
	request.explicit_range = explicit
	request.replace_text_input = replace_text_input
	request.argument_present = argument_present
	request.argument = argument
	request.history_store = &fixture.history
	request.kill_ring = &fixture.kill_ring
	request.kill_sequence_id = 1
	request.event_sequence = u64(request.transaction_id)
	request.yank_context = &fixture.yank_context
	kind := history.Grouping_Kind.Independent
	if name == "insert-text" || name == "insert-indentation" {
		kind = .Typing_Insert
	} else if name == "delete-previous-grapheme" {
		kind = .Typing_Backspace
	}
	request.history_grouping = history.Grouping_Context {
		kind = kind,
		view_id = fixture.view.view_id,
		view_generation = fixture.view.generation,
		continuity = 1,
		event_sequence = u64(request.transaction_id),
		monotonic_milliseconds = u64(request.transaction_id) * 10,
	}
	return native_command_execute(request)
}

@(private)
execute_modal_repeat :: proc(
	fixture: ^Native_Fixture,
	route: Native_Route,
	entry_route: Native_Route,
	text: string,
) -> (Native_Result, bool, Failure_Context) {
	handle, found, lookup_failure := interaction.command_lookup(
		&fixture.command_registry, "modal-repeat-last-change",
	)
	if !found {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			interaction_code = lookup_failure.code,
		}
	}
	request := native_request(fixture, handle)
	request.text = text
	request.replay_route = route
	request.replay_entry_route = entry_route
	request.repeat_count = 1
	request.history_store = &fixture.history
	request.kill_ring = &fixture.kill_ring
	request.kill_sequence_id = 1
	request.event_sequence = u64(request.transaction_id)
	request.yank_context = &fixture.yank_context
	request.history_grouping = history.Grouping_Context {
		kind = .Independent,
		view_id = fixture.view.view_id,
		view_generation = fixture.view.generation,
		continuity = 1,
		event_sequence = u64(request.transaction_id),
		monotonic_milliseconds = u64(request.transaction_id) * 10,
	}
	return native_command_execute(request)
}

@(private)
execute_layout_named :: proc(
	fixture: ^Native_Fixture,
	layout_registry: ^layout.Registry,
	name: string,
) -> (Native_Result, bool, Failure_Context) {
	command_handle, found, lookup_failure := interaction.command_lookup(&fixture.command_registry, name)
	if !found {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			interaction_code = lookup_failure.code,
		}
	}
	layout_handle, handle_ok, layout_failure := layout.registry_handle(layout_registry)
	if !handle_ok {
		return {}, false, native_layout_failure(command_handle, layout_failure)
	}
	snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(layout_registry, layout_handle)
	if !snapshot_ok {
		return {}, false, native_layout_failure(command_handle, snapshot_failure)
	}
	active, active_ok := native_layout_active_node(snapshot)
	if !active_ok {
		return {}, false, Failure_Context{code = .Layout_Failure, command = command_handle}
	}
	request := native_request(fixture, command_handle)
	request.view = active.view
	request.layout_registry = layout_registry
	return native_command_execute(request)
}

@(private)
expect_ring_text :: proc(
	t: ^testing.T,
	ring: ^kill_ring.Ring,
	entry_id: kill_ring.Entry_ID,
	expected: string,
) {
	stats, stats_ok, _ := kill_ring.ring_stats(ring)
	testing.expect(t, stats_ok)
	copied, copied_ok, failure := kill_ring.entry_copy(
		ring,
		kill_ring.Entry_Copy_Request {
			expected_generation = stats.generation,
			entry_id = entry_id,
			byte_limit = stats.policy.entry_bytes,
		},
		context.temp_allocator,
	)
	testing.expectf(t, copied_ok, "ring copy failed with %v", failure.code)
	if !copied_ok {
		return
	}
	defer kill_ring.entry_copy_release(&copied, context.temp_allocator)
	testing.expect_value(t, copied.text, expected)
}

@(private)
test_ring_admit :: proc(t: ^testing.T, ring: ^kill_ring.Ring, text: string) {
	stats, stats_ok, _ := kill_ring.ring_stats(ring)
	testing.expect(t, stats_ok)
	reservation: kill_ring.Reservation
	_, reserved, failure := kill_ring.admission_reserve(
		ring,
		&reservation,
		kill_ring.Admission_Request {
			expected_generation = stats.generation,
			kind = .Copy,
			text = text,
		},
	)
	testing.expectf(t, reserved, "ring admission failed with %v", failure.code)
	if reserved {
		kill_ring.reservation_commit_reserved(&reservation)
	}
}

@(private)
native_request :: proc(
	fixture: ^Native_Fixture,
	handle: interaction.Command_Handle,
) -> Native_Context {
	request := Native_Context {
		registry = &fixture.command_registry,
		command = handle,
		buffer = &fixture.buffer,
		document = &fixture.document,
		view_registry = &fixture.view_registry,
		view = fixture.view,
		profile = display.terminal_unicode17_profile(),
		constraints = display.Viewport_Constraints{width_cells = 80, height_rows = 24},
		temporary_allocator = context.temp_allocator,
		persistent_allocator = fixture.allocator,
		transaction_id = edit_transaction.Transaction_ID(fixture.next_transaction_id),
		undo_unit_id = edit_transaction.Undo_Unit_ID(fixture.next_undo_unit_id),
		location_history = &fixture.location_history,
	}
	fixture.next_transaction_id += 1
	fixture.next_undo_unit_id += 1
	return request
}

@(private)
expect_native_state :: proc(
	t: ^testing.T,
	fixture: ^Native_Fixture,
	offset, desired_column, revision: u64,
	expected_text: string,
) {
	logical, logical_ok, _ := editor_view.snapshot(&fixture.view_registry, fixture.view)
	testing.expect(t, logical_ok)
	testing.expect_value(t, u64(logical.point_position.byte_offset), offset)
	testing.expect_value(t, u64(logical.desired_display_column), desired_column)
	testing.expect_value(t, u64(logical.revision), revision)
	stats, stats_ok, _ := editor.buffer_stats(&fixture.buffer)
	testing.expect(t, stats_ok)
	testing.expect_value(t, u64(stats.revision), revision)
	observed := make([]u8, int(stats.text_bytes), context.temp_allocator)
	defer delete(observed, context.temp_allocator)
	_, inspected, _ := editor.buffer_inspect(
		&fixture.buffer,
		editor.Byte_Offset(0),
		editor.Byte_Offset(stats.text_bytes),
		observed,
	)
	testing.expect(t, inspected)
	testing.expect_value(t, string(observed), expected_text)
}

@(private)
Native_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
native_failing_allocator :: proc(data: ^Native_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = native_failing_allocator_proc,
		data = data,
	}
}

@(private)
native_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Native_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
