// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym_module_focused

import "../../src/product_module"
import "base:runtime"
import "core:crypto/sha2"
import "core:os"
import "core:testing"

MODULE_PATH :: #config(
	ODRA_MAKSYM_MODULE,
	"../../.build/modules/libodra-maksym.so",
)

Host_Observation :: struct {
	diagnostics: u32,
	ui_calls:    u32,
	rows:        u32,
	notes_seen:  bool,
	renamed_seen: bool,
	present_entry_flags: u64,
	presentation_generation: u64,
	selection_owner: u8,
	alpha_id:     u64,
	beta_id:      u64,
	zeta_id:      u64,
	current_alpha: bool,
	current_beta: bool,
	current_zeta: bool,
	marked_alpha: bool,
	marked_beta: bool,
	marked_zeta: bool,
	open_path_calls: u32,
	present_entry_calls: u32,
	permanent_warning_seen: bool,
	last_diagnostic: [256]u8,
	last_diagnostic_length: int,
	clipboard_text: [4096]u8,
	clipboard_length: int,
	process_command: [4096]u8,
	process_command_length: int,
	process_directory: [4096]u8,
	process_directory_length: int,
	process_action: product_module.Process_Action,
	alpha_visible: bool,
	beta_visible: bool,
	last_opened_path: [4096]u8,
	last_opened_path_length: int,
}

host_observation: Host_Observation

@(test)
/* maksym_module_edits_one_directory_through_the_public_lifecycle verifies the bundled artifact. */
maksym_module_edits_one_directory_through_the_public_lifecycle :: proc(t: ^testing.T) {
	host_observation = {}
	root, root_error := os.make_directory_temp("", "odra-maksym-module-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer delete(root)
	defer os.remove_all(root)
	notes, notes_error := os.join_path({root, "notes.odin"}, context.allocator)
	testing.expect(t, notes_error == nil)
	if notes_error != nil do return
	defer delete(notes)
	testing.expect(t, os.write_entire_file(notes, "package notes\n") == nil)

	artifact := module_artifact(t)
	module_runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&module_runtime, &artifact)
	testing.expectf(t, loaded, "Maksym module load failed with %v", load_failure)
	if !loaded do return
	defer if module_runtime.lifecycle != .Closed {
		_, _ = product_module.close(&module_runtime)
	}
	opened, open_failure := product_module.open(&module_runtime, host_call, 73)
	testing.expectf(t, opened, "Maksym module open failed with %v", open_failure)
	if !opened do return

	_, activated, activation_failure := product_module.call(
		&module_runtime,
		.Activate,
		transmute([]u8)root,
		nil,
	)
	testing.expectf(t, activated, "Maksym activation failed with %v", activation_failure)
	if !activated do return
	_, inspected, inspect_failure := product_module.call(&module_runtime, .Inspect, nil, nil)
	testing.expectf(t, inspected, "Maksym inspection failed with %v", inspect_failure)
	testing.expect(t, host_observation.ui_calls > 0)
	testing.expect(t, host_observation.rows >= 2)
	testing.expect(t, host_observation.notes_seen)

	invoke(t, &module_runtime, "maksym-cycle-sort")
	invoke(t, &module_runtime, "maksym-jump-to-entry")
	text_input(t, &module_runtime, "notes")
	key_input(t, &module_runtime, .Enter)
	scalar_input(t, &module_runtime, 'o', 0)
	testing.expect_value(
		t,
		host_observation.present_entry_flags,
		product_module.SESSION_PRESENT_OTHER_PANE | product_module.SESSION_PRESENT_FOCUS,
	)
	scalar_input(t, &module_runtime, 'o', 1)
	testing.expect_value(
		t,
		host_observation.present_entry_flags,
		product_module.SESSION_PRESENT_OTHER_PANE,
	)
	invoke(t, &module_runtime, "maksym-toggle-editable-listing")
	for _ in 0 ..< len("notes.odin") do key_input(t, &module_runtime, .Delete)
	text_input(t, &module_runtime, "renamed.odin")
	invoke(t, &module_runtime, "maksym-apply-editable-listing")

	renamed, renamed_error := os.join_path({root, "renamed.odin"}, context.allocator)
	testing.expect(t, renamed_error == nil)
	if renamed_error == nil {
		defer delete(renamed)
		testing.expect(t, os.is_file(renamed))
	}
	testing.expect(t, !os.is_file(notes))
	testing.expect(t, host_observation.renamed_seen)

	_, deactivated, deactivation_failure := product_module.call(
		&module_runtime,
		.Deactivate,
		nil,
		nil,
	)
	testing.expectf(t, deactivated, "Maksym deactivation failed with %v", deactivation_failure)
	closed, close_failure := product_module.close(&module_runtime)
	testing.expectf(t, closed, "Maksym module close failed with %v", close_failure)
}

@(test)
/* maksym_module_selects_stable_resource_rows_across_sort_edit_and_refresh verifies exact row authority. */
maksym_module_selects_stable_resource_rows_across_sort_edit_and_refresh :: proc(t: ^testing.T) {
	host_observation = {}
	root, root_error := os.make_directory_temp("", "odra-maksym-selection-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer delete(root)
	defer os.remove_all(root)
	alpha, alpha_error := os.join_path({root, "alpha.odin"}, context.allocator)
	zeta, zeta_error := os.join_path({root, "zeta"}, context.allocator)
	testing.expect(t, alpha_error == nil && zeta_error == nil)
	if alpha_error != nil || zeta_error != nil do return
	defer delete(alpha)
	defer delete(zeta)
	testing.expect(t, os.write_entire_file(alpha, "package alpha\n") == nil)
	testing.expect(t, os.make_directory(zeta) == nil)

	artifact := module_artifact(t)
	module_runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&module_runtime, &artifact)
	testing.expectf(t, loaded, "Maksym module load failed with %v", load_failure)
	if !loaded do return
	defer if module_runtime.lifecycle != .Closed do _, _ = product_module.close(&module_runtime)
	opened, open_failure := product_module.open(&module_runtime, host_call, 73)
	testing.expectf(t, opened, "Maksym module open failed with %v", open_failure)
	if !opened do return
	_, activated, activation_failure := product_module.call(
		&module_runtime, .Activate, transmute([]u8)root, nil,
	)
	testing.expectf(t, activated, "Maksym activation failed with %v", activation_failure)
	if !activated do return
	testing.expect_value(t, host_observation.selection_owner, u8(1))
	alpha_id := host_observation.alpha_id
	zeta_id := host_observation.zeta_id
	testing.expect(t, alpha_id > 1 && zeta_id > 1 && alpha_id != zeta_id)

	invoke(t, &module_runtime, "maksym-cycle-sort")
	testing.expect_value(t, host_observation.alpha_id, alpha_id)
	testing.expect_value(t, host_observation.zeta_id, zeta_id)
	testing.expect(t, select_item(t, &module_runtime, zeta_id))
	testing.expect(t, host_observation.current_zeta)
	scalar_input(t, &module_runtime, 'm', 0)
	testing.expect(t, host_observation.marked_zeta)
	testing.expect_value(t, host_observation.open_path_calls, u32(0))
	testing.expect_value(t, host_observation.present_entry_calls, u32(0))

	testing.expect(t, select_item(t, &module_runtime, alpha_id))
	invoke(t, &module_runtime, "maksym-mark-entry")
	testing.expect(t, host_observation.marked_alpha && host_observation.marked_zeta)
	invoke(t, &module_runtime, "maksym-toggle-editable-listing")
	testing.expect(t, host_observation.marked_alpha && host_observation.marked_zeta)
	testing.expect(t, host_observation.current_alpha)
	for _ in 0 ..< len("alpha.odin") do key_input(t, &module_runtime, .Delete)
	text_input(t, &module_runtime, "beta.odin")
	invoke(t, &module_runtime, "maksym-apply-editable-listing")
	beta, beta_error := os.join_path({root, "beta.odin"}, context.allocator)
	testing.expect(t, beta_error == nil)
	if beta_error != nil do return
	defer delete(beta)
	testing.expect(t, os.is_file(beta) && os.is_dir(zeta))
	testing.expect_value(t, host_observation.zeta_id, zeta_id)
	beta_id := host_observation.beta_id
	testing.expect_value(t, beta_id, alpha_id)
	testing.expect(t, host_observation.marked_beta && host_observation.marked_zeta)

	gamma, gamma_error := os.join_path({root, "żółw.odin"}, context.allocator)
	testing.expect(t, gamma_error == nil)
	if gamma_error != nil do return
	defer delete(gamma)
	testing.expect(t, os.write_entire_file(gamma, "package turtle\n") == nil)
	invoke(t, &module_runtime, "maksym-refresh")
	testing.expect_value(t, host_observation.zeta_id, zeta_id)
	testing.expect_value(t, host_observation.beta_id, beta_id)
	testing.expect(t, host_observation.marked_beta && host_observation.marked_zeta)
	testing.expect(t, select_item(t, &module_runtime, beta_id))
	testing.expect(t, host_observation.current_beta)

	testing.expect(t, os.remove(beta) == nil)
	invoke(t, &module_runtime, "maksym-refresh")
	testing.expect(t, !host_observation.marked_beta && host_observation.marked_zeta)
	_, stale_status := select_item_status(&module_runtime, beta_id)
	testing.expect_value(t, stale_status, product_module.Status.Stale)
	testing.expect_value(t, host_observation.open_path_calls, u32(0))
	testing.expect_value(t, host_observation.present_entry_calls, u32(0))
}

@(test)
/* maksym_module_applies_checked_target_operations verifies prompts, resources, and outcomes. */
maksym_module_applies_checked_target_operations :: proc(t: ^testing.T) {
	host_observation = {}
	root, root_error := os.make_directory_temp("", "odra-maksym-operations-*", context.allocator)
	copy_root, copy_error := os.make_directory_temp("", "odra-maksym-copy-*", context.allocator)
	move_root, move_error := os.make_directory_temp("", "odra-maksym-move-*", context.allocator)
	testing.expect(t, root_error == nil && copy_error == nil && move_error == nil)
	if root_error != nil || copy_error != nil || move_error != nil do return
	defer {delete(move_root); delete(copy_root); delete(root)}
	defer {os.remove_all(move_root); os.remove_all(copy_root); os.remove_all(root)}
	alpha, _ := os.join_path({root, "alpha.odin"}, context.allocator)
	beta, _ := os.join_path({root, "beta.odin"}, context.allocator)
	defer {delete(beta); delete(alpha)}
	testing.expect(t, os.write_entire_file(alpha, "package alpha\n") == nil)
	testing.expect(t, os.write_entire_file(beta, "package beta\n") == nil)

	artifact := module_artifact(t)
	module_runtime: product_module.Runtime
	loaded, _ := product_module.load(&module_runtime, &artifact)
	testing.expect(t, loaded)
	if !loaded do return
	defer if module_runtime.lifecycle != .Closed do _, _ = product_module.close(&module_runtime)
	opened, _ := product_module.open(&module_runtime, host_call, 73)
	testing.expect(t, opened)
	if !opened do return
	_, activated, _ := product_module.call(&module_runtime, .Activate, transmute([]u8)root, nil)
	testing.expect(t, activated)
	if !activated do return

	alpha_id := host_observation.alpha_id
	beta_id := host_observation.beta_id
	invoke(t, &module_runtime, "maksym-filter-name")
	text_input(t, &module_runtime, "alpha")
	key_input(t, &module_runtime, .Enter)
	testing.expect(t, host_observation.alpha_visible && !host_observation.beta_visible)
	invoke(t, &module_runtime, "maksym-clear-filter")
	testing.expect(t, host_observation.alpha_visible && host_observation.beta_visible)
	alpha_id = host_observation.alpha_id
	beta_id = host_observation.beta_id
	testing.expect(t, select_item(t, &module_runtime, alpha_id))
	invoke(t, &module_runtime, "maksym-find-file-relative")
	text_input(t, &module_runtime, "alpha.odin")
	key_input(t, &module_runtime, .Enter)
	testing.expect_value(
		t,
		string(host_observation.last_opened_path[:host_observation.last_opened_path_length]),
		alpha,
	)
	invoke(t, &module_runtime, "maksym-copy-names")
	testing.expect_value(
		t,
		string(host_observation.clipboard_text[:host_observation.clipboard_length]),
		"alpha.odin",
	)
	invoke(t, &module_runtime, "maksym-copy-absolute-paths")
	testing.expect_value(
		t,
		string(host_observation.clipboard_text[:host_observation.clipboard_length]),
		alpha,
	)
	invoke(t, &module_runtime, "maksym-describe-entry-type")
	testing.expect(t, text_contains(
		string(host_observation.last_diagnostic[:host_observation.last_diagnostic_length]),
		"regular file",
	))
	invoke(t, &module_runtime, "maksym-shell-command")
	text_input(t, &module_runtime, "printf checked")
	key_input(t, &module_runtime, .Enter)
	testing.expect_value(t, host_observation.process_action, product_module.Process_Action.Shell)
	testing.expect_value(
		t,
		string(host_observation.process_directory[:host_observation.process_directory_length]),
		root,
	)
	testing.expect(t, text_contains(
		string(host_observation.process_command[:host_observation.process_command_length]),
		"alpha.odin'",
	))
	invoke(t, &module_runtime, "maksym-copy-targets")
	text_input(t, &module_runtime, copy_root)
	key_input(t, &module_runtime, .Enter)
	copied_alpha, _ := os.join_path({copy_root, "alpha.odin"}, context.allocator)
	defer delete(copied_alpha)
	testing.expectf(t, os.is_file(copied_alpha) && os.is_file(alpha), "%s", string(host_observation.last_diagnostic[:host_observation.last_diagnostic_length]))
	invoke(t, &module_runtime, "maksym-copy-targets")
	text_input(t, &module_runtime, copy_root)
	key_input(t, &module_runtime, .Enter)
	testing.expect(t, text_contains(
		string(host_observation.last_diagnostic[:host_observation.last_diagnostic_length]),
		"Copied 0 of 1",
	))
	testing.expect(t, os.is_file(copied_alpha) && os.is_file(alpha))
	invoke(t, &module_runtime, "maksym-rename-pattern")
	text_input(t, &module_runtime, "alpha")
	key_input(t, &module_runtime, .Enter)
	text_input(t, &module_runtime, "gamma")
	key_input(t, &module_runtime, .Enter)
	scalar_input(t, &module_runtime, 'y', 0)
	gamma, _ := os.join_path({root, "gamma.odin"}, context.allocator)
	defer delete(gamma)
	testing.expect(t, os.is_file(gamma) && !os.is_file(alpha))

	testing.expect(t, select_item(t, &module_runtime, beta_id))
	invoke(t, &module_runtime, "maksym-move-targets")
	text_input(t, &module_runtime, move_root)
	key_input(t, &module_runtime, .Enter)
	moved_beta, _ := os.join_path({move_root, "beta.odin"}, context.allocator)
	defer delete(moved_beta)
	testing.expectf(t, os.is_file(moved_beta) && !os.is_file(beta), "%s", string(host_observation.last_diagnostic[:host_observation.last_diagnostic_length]))

	testing.expect(t, select_item(t, &module_runtime, alpha_id))
	invoke(t, &module_runtime, "maksym-move-targets")
	text_input(t, &module_runtime, "renamed.odin")
	key_input(t, &module_runtime, .Enter)
	renamed, _ := os.join_path({root, "renamed.odin"}, context.allocator)
	defer delete(renamed)
	testing.expect(t, os.is_file(renamed) && !os.is_file(alpha))
	testing.expect(t, host_observation.renamed_seen)

	invoke(t, &module_runtime, "maksym-delete-targets")
	testing.expect(t, host_observation.permanent_warning_seen)
	scalar_input(t, &module_runtime, 'y', 0)
	testing.expect(t, !os.is_file(renamed))

	invoke(t, &module_runtime, "maksym-create-directory")
	text_input(t, &module_runtime, "created")
	key_input(t, &module_runtime, .Enter)
	created, _ := os.join_path({root, "created"}, context.allocator)
	defer delete(created)
	testing.expect(t, os.is_dir(created))
}

invoke :: proc(t: ^testing.T, module_runtime: ^product_module.Runtime, name: string) {
	_, invoked, failure := product_module.call(
		module_runtime,
		.Invoke,
		transmute([]u8)name,
		nil,
	)
	testing.expectf(t, invoked, "Maksym command %s failed with %v", name, failure)
}

key_input :: proc(t: ^testing.T, module_runtime: ^product_module.Runtime, key: product_module.Key_Kind) {
	header := product_module.Input_Request_Header {
		schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
		kind = .Key,
		key_kind = key,
	}
	request := ([^]u8)(rawptr(&header))[:size_of(header)]
	_, accepted, failure := product_module.call(module_runtime, .Input, request, nil)
	testing.expectf(t, accepted, "Maksym key input failed with %v", failure)
}

scalar_input :: proc(
	t: ^testing.T,
	module_runtime: ^product_module.Runtime,
	scalar: rune,
	modifiers: u8,
) {
	header := product_module.Input_Request_Header {
		schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
		kind = .Key,
		key_kind = .Unicode_Scalar,
		modifiers = modifiers,
		scalar = i32(scalar),
	}
	request := ([^]u8)(rawptr(&header))[:size_of(header)]
	_, accepted, failure := product_module.call(module_runtime, .Input, request, nil)
	testing.expectf(t, accepted, "Maksym scalar input failed with %v", failure)
}

text_input :: proc(t: ^testing.T, module_runtime: ^product_module.Runtime, text: string) {
	header := product_module.Input_Request_Header {
		schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
		kind = .Text_Commit,
		text_length = u32(len(text)),
	}
	request: [size_of(product_module.Input_Request_Header) + 256]u8
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], transmute([]u8)text)
	_, accepted, failure := product_module.call(
		module_runtime,
		.Input,
		request[:size_of(header) + len(text)],
		nil,
	)
	testing.expectf(t, accepted, "Maksym text input failed with %v", failure)
}

select_item_status :: proc(
	module_runtime: ^product_module.Runtime,
	item_id: u64,
) -> (bool, product_module.Status) {
	selection := product_module.Selection_Request {
		schema_version = product_module.UI_LIST_SCHEMA_VERSION,
		item_id = item_id,
	}
	_, selected, failure := product_module.call(
		module_runtime,
		.Select,
		([^]u8)(rawptr(&selection))[:size_of(selection)],
		nil,
	)
	return selected, failure.status
}

select_item :: proc(t: ^testing.T, module_runtime: ^product_module.Runtime, item_id: u64) -> bool {
	selected, status := select_item_status(module_runtime, item_id)
	testing.expectf(t, selected, "Maksym item %d selection failed with %v", item_id, status)
	return selected
}

host_call :: proc "c" (
	capability: u64,
	operation: product_module.Host_Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if capability != 73 || input_length > product_module.MAX_CALL_BYTES {
		return .Denied
	}
	if input_length > 0 && input == nil do return .Invalid_Argument
	if output_length != nil do output_length^ = 0
	switch operation {
	case .Diagnostic:
		host_observation.diagnostics += 1
		message := string(([^]u8)(rawptr(input))[:int(input_length)])
		host_observation.last_diagnostic = {}
		host_observation.last_diagnostic_length = copy(host_observation.last_diagnostic[:], message)
		host_observation.permanent_warning_seen = host_observation.permanent_warning_seen ||
			text_contains(message, "Recovery is unavailable")
	case .UI:
		if input_length < u64(size_of(product_module.UI_List_Header)) do return .Invalid_Argument
		header := (^product_module.UI_List_Header)(rawptr(input))
		row_bytes := u64(header.row_count) * u64(size_of(product_module.UI_List_Row))
		if header.schema_version != product_module.UI_LIST_SCHEMA_VERSION ||
		   row_bytes > input_length - u64(size_of(product_module.UI_List_Header)) ||
		   header.text_bytes != input_length - u64(size_of(product_module.UI_List_Header)) - row_bytes {
			return .Invalid_Argument
		}
		text := ([^]u8)(rawptr(input))[
			int(size_of(product_module.UI_List_Header) + row_bytes):int(input_length)
		]
		host_observation.presentation_generation = header.presentation_generation
		host_observation.selection_owner = header.selection_owner
		host_observation.current_alpha = false
		host_observation.current_beta = false
		host_observation.current_zeta = false
		host_observation.marked_alpha = false
		host_observation.marked_beta = false
		host_observation.marked_zeta = false
		host_observation.alpha_visible = false
		host_observation.beta_visible = false
		for index in 0 ..< int(header.row_count) {
			row := (^product_module.UI_List_Row)(rawptr(
				uintptr(input) + uintptr(size_of(product_module.UI_List_Header)) +
					uintptr(index * size_of(product_module.UI_List_Row)),
			))
			if row.id == 0 || row.text_offset + u64(row.text_length) > header.text_bytes {
				return .Invalid_Argument
			}
			row_text := string(text[int(row.text_offset):int(row.text_offset) + int(row.text_length)])
			host_observation.notes_seen = host_observation.notes_seen || text_contains(row_text, "notes.odin")
			host_observation.renamed_seen = host_observation.renamed_seen || text_contains(row_text, "renamed.odin")
			if text_contains(row_text, "alpha.odin") {
				host_observation.alpha_visible = true
				host_observation.alpha_id = row.id
				host_observation.current_alpha = index == int(header.current_item)
				host_observation.marked_alpha = text_starts_with(row_text, "* ")
			}
			if text_contains(row_text, "beta.odin") {
				host_observation.beta_visible = true
				host_observation.beta_id = row.id
				host_observation.current_beta = index == int(header.current_item)
				host_observation.marked_beta = text_starts_with(row_text, "* ")
			}
			if text_contains(row_text, "zeta") {
				host_observation.zeta_id = row.id
				host_observation.current_zeta = index == int(header.current_item)
				host_observation.marked_zeta = text_starts_with(row_text, "* ")
			}
		}
		host_observation.ui_calls += 1
		host_observation.rows = header.row_count
	case .Session:
		if input_length < u64(size_of(product_module.Session_Request_Header)) || output_length == nil ||
		   output == nil || output_capacity < u64(size_of(product_module.Session_Response)) {
			return .Invalid_Argument
		}
		response := (^product_module.Session_Response)(rawptr(output))
		response^ = {}
		header := (^product_module.Session_Request_Header)(rawptr(input))
		if header.action == .Present_Surface do response.target = 17
		if header.action == .Open_Path {
			response.target = 19
			host_observation.open_path_calls += 1
			payload_start := size_of(product_module.Session_Request_Header)
			if header.payload_length <= u64(len(host_observation.last_opened_path)) &&
			   header.payload_length == input_length - u64(payload_start) {
				host_observation.last_opened_path_length = copy(
					host_observation.last_opened_path[:],
					([^]u8)(rawptr(input))[payload_start:int(input_length)],
				)
			}
		}
		if header.action == .Present_Entry {
			host_observation.present_entry_flags = header.flags
			host_observation.present_entry_calls += 1
		}
		output_length^ = u64(size_of(product_module.Session_Response))
	case .Process:
		if input_length < u64(size_of(product_module.Process_Request_Header)) do return .Invalid_Argument
		header := (^product_module.Process_Request_Header)(rawptr(input))
		content_length := u64(header.working_directory_length) + u64(header.command_length)
		if header.schema_version != product_module.PROCESS_REQUEST_SCHEMA_VERSION ||
		   content_length != input_length - u64(size_of(product_module.Process_Request_Header)) ||
		   int(header.working_directory_length) > len(host_observation.process_directory) ||
		   int(header.command_length) > len(host_observation.process_command) {
			return .Invalid_Argument
		}
		directory_start := size_of(product_module.Process_Request_Header)
		command_start := directory_start + int(header.working_directory_length)
		host_observation.process_directory_length = copy(
			host_observation.process_directory[:],
			([^]u8)(rawptr(input))[directory_start:command_start],
		)
		host_observation.process_command_length = copy(
			host_observation.process_command[:],
			([^]u8)(rawptr(input))[command_start:int(input_length)],
		)
		host_observation.process_action = header.action
	case .Clipboard:
		if input_length == 0 || input_length > u64(len(host_observation.clipboard_text)) {
			return .Invalid_Argument
		}
		host_observation.clipboard_length = copy(
			host_observation.clipboard_text[:],
			([^]u8)(rawptr(input))[:int(input_length)],
		)
	case .Command, .Prompt, .Tree_UI, .Provider, .Filesystem, .Workspace, .Document:
	case .Invalid:
		return .Invalid_Argument
	}
	return .Ok
}

text_contains :: proc "contextless" (text, fragment: string) -> bool {
	if len(fragment) == 0 do return true
	if len(fragment) > len(text) do return false
	for offset in 0 ..= len(text) - len(fragment) {
		if text[offset:offset + len(fragment)] == fragment do return true
	}
	return false
}

text_starts_with :: proc "contextless" (text, prefix: string) -> bool {
	return len(prefix) <= len(text) && text[:len(prefix)] == prefix
}

module_artifact :: proc(t: ^testing.T) -> product_module.Artifact {
	content, read_error := os.read_entire_file(MODULE_PATH, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(content)
	artifact: product_module.Artifact
	artifact.identity_length = u16(copy(artifact.identity[:], "odra.maksym"))
	artifact.version_length = u16(copy(artifact.version[:], "1.0.0"))
	artifact.path_length = u16(copy(artifact.path[:], string(MODULE_PATH)))
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, content)
	sha2.final(&ctx, artifact.digest[:])
	artifact.size = u64(len(content))
	artifact.entrypoint_length = u16(copy(artifact.entrypoint[:], "odra_product_module_entrypoint"))
	artifact.abi_minimum = product_module.ABI_VERSION
	artifact.abi_maximum = product_module.ABI_VERSION
	artifact.role = .File_Management
	return artifact
}
