// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_module_focused

import "../../src/interaction"
import "../../src/product_module"
import "base:runtime"
import "core:crypto/sha2"
import "core:os"
import "core:testing"

MODULE_PATH :: #config(
	ODRA_KSAWERY_MODULE,
	"../../.build/ksawery-module/libodra-ksawery.so",
)

Host_Observation :: struct {
	diagnostic_calls: u32,
	ui_calls:         u32,
	ui_bytes:         u64,
	ui_rows:          u32,
	first_item:       u64,
	changed_item:     u64,
	status_failed:    bool,
	changed_path_seen: bool,
	status_seen: bool,
	dispatcher_seen: bool,
	diff_family_seen: bool,
	rebase_family_seen: bool,
	merge_family_seen: bool,
	remote_family_seen: bool,
	clone_family_seen: bool,
	advanced_family_seen: bool,
	raw_command_seen: bool,
	raw_template_seen: bool,
	ignore_path_seen: bool,
	target_family_seen: bool,
	discard_prompt_seen: bool,
	stashes_seen: bool,
	worktrees_seen: bool,
	reflog_seen: bool,
	blame_seen: bool,
	inspection_ready: bool,
}

host_observation: Host_Observation

@(test)
/* ksawery_module_runs_git_status_across_reusable_public_lifecycle verifies the real module artifact. */
ksawery_module_runs_git_status_across_reusable_public_lifecycle :: proc(t: ^testing.T) {
	repository, directory_error := os.make_directory_temp(
		"",
		"odra-ksawery-module-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer delete(repository)
	defer os.remove_all(repository)
	testing.expect(t, run(repository, "git", "init", "--quiet"))
	testing.expect(t, run(repository, "git", "config", "user.name", "Odra Test"))
	testing.expect(t, run(repository, "git", "config", "user.email", "odra@example.invalid"))
	path, path_error := os.join_path({repository, "change.txt"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "module boundary baseline\n") == nil)
	testing.expect(t, run(repository, "git", "add", "--", "change.txt"))
	testing.expect(t, run(repository, "git", "commit", "--quiet", "-m", "baseline"))
	testing.expect(t, os.write_entire_file(path, "module boundary checkpoint\n") == nil)
	testing.expect(t, run(repository, "git", "stash", "push", "--quiet", "-m", "checkpoint"))
	testing.expect(t, os.write_entire_file(path, "module boundary changed\n") == nil)

	artifact := module_artifact(t)
	runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&runtime, &artifact)
	testing.expectf(t, loaded, "Ksawery module load failed with %v", load_failure)
	if !loaded do return
	defer if runtime.lifecycle != .Closed {
		_, _ = product_module.close(&runtime)
	}
	opened, open_failure := product_module.open(&runtime, host_call, 41)
	testing.expectf(t, opened, "Ksawery module open failed with %v", open_failure)
	if !opened do return
	configuration_header := product_module.Configuration_Request_Header {
		schema_version = product_module.CONFIGURATION_REQUEST_SCHEMA_VERSION,
		disposition = .Confirmed,
		generation = 1,
	}
	configuration := ([^]u8)(rawptr(&configuration_header))[:size_of(configuration_header)]
	_, configured, configuration_failure := product_module.call(
		&runtime,
		.Configure,
		configuration,
		nil,
	)
	testing.expectf(t, configured, "module configuration failed with %v", configuration_failure)
	if !configured do return

	for activation_index in 0 ..< 2 {
		written, activated, activation_failure := product_module.call(
			&runtime,
			.Activate,
			transmute([]u8)repository,
			nil,
		)
		testing.expectf(t, activated, "activation %d failed with %v", activation_index, activation_failure)
		testing.expect_value(t, written, 0)
		if !activated do return
		_, initially_inspected, initial_inspect_failure := product_module.call(&runtime, .Inspect, nil, nil)
		testing.expectf(t, initially_inspected, "initial inspection %d failed with %v", activation_index, initial_inspect_failure)
		if !initially_inspected do return

		host_observation = {}
		for _ in 0 ..< 2_000 {
			changed: [1]u8
			step_written, stepped, step_failure := product_module.call(&runtime, .Step, nil, changed[:])
			testing.expectf(t, stepped, "Ksawery module step failed with %v", step_failure)
			if !stepped do return
			testing.expect_value(t, step_written, 1)
			_, inspected, inspect_failure := product_module.call(&runtime, .Inspect, nil, nil)
			testing.expectf(t, inspected, "Ksawery module inspection failed with %v", inspect_failure)
			if !inspected do return
			if host_observation.status_failed || host_observation.changed_path_seen {
				break
			}
		}
		testing.expect(t, host_observation.ui_calls > 0)
		testing.expect(t, host_observation.ui_bytes > 0)
		testing.expect(t, host_observation.ui_rows > 0)
		testing.expect(t, host_observation.first_item > 0)
		testing.expect(t, !host_observation.status_failed)
		testing.expect(t, host_observation.changed_path_seen)
		testing.expect(t, host_observation.changed_item > 0)
		input := product_module.Input_Request_Header {
			schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
			kind = .Key,
			key_kind = .Down,
		}
		input_bytes := ([^]u8)(rawptr(&input))[:size_of(input)]
		_, dispatched, input_failure := product_module.call(
			&runtime,
			.Input,
			input_bytes,
			nil,
		)
		testing.expectf(t, dispatched, "input %d failed with %v", activation_index, input_failure)
		if !dispatched do return
		_, inspected, inspect_failure := product_module.call(&runtime, .Inspect, nil, nil)
		testing.expectf(t, inspected, "post-input inspection %d failed with %v", activation_index, inspect_failure)
		if !inspected do return

		selection := product_module.Selection_Request {
			schema_version = product_module.UI_LIST_SCHEMA_VERSION,
			item_id = host_observation.changed_item,
		}
		selection_bytes := ([^]u8)(rawptr(&selection))[:size_of(selection)]
		_, selected, selection_failure := product_module.call(
			&runtime,
			.Select,
			selection_bytes,
			nil,
		)
		testing.expectf(
			t,
			selected,
			"selection %d for item %d failed with %v",
			activation_index,
			host_observation.changed_item,
			selection_failure,
		)
		if activation_index == 0 {
			testing.expect(t, send_key(&runtime, '?'))
			testing.expect(t, inspect_runtime(&runtime))
			testing.expect(t, host_observation.dispatcher_seen)
			testing.expect(t, send_key(&runtime, 'g', {.Control}))
			testing.expect(t, inspect_runtime(&runtime))
			testing.expect(t, host_observation.status_seen)

			families := [?]struct {key: rune, seen: ^bool}{
				{key = 'd', seen = &host_observation.diff_family_seen},
				{key = 'r', seen = &host_observation.rebase_family_seen},
				{key = 'm', seen = &host_observation.merge_family_seen},
				{key = 'M', seen = &host_observation.remote_family_seen},
				{key = 'C', seen = &host_observation.clone_family_seen},
			}
			for family in families {
				testing.expect(t, send_key(&runtime, family.key))
				testing.expect(t, inspect_runtime(&runtime))
				testing.expect(t, family.seen^)
				testing.expect(t, send_key(&runtime, 'q'))
			}

			advanced_workflows := [?]struct {
				family:   rune,
				action:   rune,
				template: string,
			}{
				{family = 'C', action = 'C', template = "clone "},
				{family = 'I', action = 'I', template = "init "},
				{family = 'o', action = 'l', template = "submodule status "},
				{family = 'O', action = 'a', template = "subtree add "},
				{family = 'T', action = 'p', template = "notes prune"},
				{family = 'w', action = 'p', template = "apply "},
				{family = 'W', action = 'c', template = "format-patch "},
				{family = '>', action = 'e', template = "sparse-checkout init --cone"},
			}
			for workflow in advanced_workflows {
				host_observation.advanced_family_seen = false
				host_observation.raw_command_seen = false
				host_observation.raw_template_seen = false
				testing.expect(t, send_key(&runtime, workflow.family))
				testing.expect(t, inspect_runtime(&runtime))
				testing.expect(t, host_observation.advanced_family_seen)
				testing.expect(t, send_key(&runtime, workflow.action))
				testing.expect(t, inspect_runtime(&runtime))
				testing.expect(t, host_observation.raw_command_seen)
				testing.expectf(t, host_observation.raw_template_seen,
				                "advanced workflow %c %c did not prepare %s",
				                workflow.family, workflow.action, workflow.template)
				testing.expect(t, send_key(&runtime, 'g', {.Control}))
			}

			host_observation.ignore_path_seen = false
			testing.expect(t, send_key(&runtime, 'i'))
			testing.expect(t, send_key(&runtime, 't'))
			testing.expect(t, host_observation.ignore_path_seen)
			testing.expect(t, send_key(&runtime, 'q'))

			testing.expect(t, send_key(&runtime, 'x'))
			testing.expect(t, inspect_runtime(&runtime))
			testing.expect(t, host_observation.target_family_seen)
			testing.expect(t, send_key(&runtime, 'd'))
			testing.expect(t, inspect_runtime(&runtime))
			testing.expect(t, host_observation.discard_prompt_seen)
			testing.expect(t, send_key(&runtime, 'n'))
			testing.expect(t, inspect_runtime(&runtime))
			testing.expect(t, host_observation.status_seen)

			inspection_routes := [?]struct {
				family:  rune,
				action:  rune,
				surface: Inspection_Surface,
			}{
				{family = 'z', action = 'z', surface = .Stashes},
				{family = 'Z', action = 'Z', surface = .Worktrees},
				{family = 'l', action = 'r', surface = .Reflog},
				{family = 'B', action = 'b', surface = .Blame},
			}
			for route in inspection_routes {
				testing.expect(t, send_key(&runtime, route.family))
				testing.expect(t, send_key(&runtime, route.action))
				testing.expectf(t, step_until_inspection_surface(&runtime, route.surface),
				                "inspection surface %v did not open", route.surface)
				testing.expect(t, send_key(&runtime, 'q'))
			}
		}

		_, invoked, invocation_failure := product_module.call(
			&runtime,
			.Invoke,
			transmute([]u8)string("component-next-row"),
			nil,
		)
		testing.expectf(t, invoked, "invocation %d failed with %v", activation_index, invocation_failure)
		if !invoked do return
		if activation_index == 0 {
			close_input := product_module.Input_Request_Header {
				schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
				kind = .Key,
				key_kind = .Unicode_Scalar,
				scalar = 'q',
			}
			close_bytes := ([^]u8)(rawptr(&close_input))[:size_of(close_input)]
			_, closed_from_input, close_input_failure := product_module.call(
				&runtime,
				.Input,
				close_bytes,
				nil,
			)
			testing.expectf(t, closed_from_input, "input close failed with %v", close_input_failure)
			if !closed_from_input do return
			_, inactive_inspected, inactive_failure := product_module.call(&runtime, .Inspect, nil, nil)
			testing.expect(t, !inactive_inspected)
			testing.expect_value(t, inactive_failure.status, product_module.Status.Unavailable)
			testing.expect_value(t, runtime.lifecycle, product_module.Lifecycle.Active)
		} else {
			_, deactivated, deactivation_failure := product_module.call(&runtime, .Deactivate, nil, nil)
			testing.expectf(t, deactivated, "deactivation %d failed with %v", activation_index, deactivation_failure)
			if !deactivated do return
		}
		_, invoked, _ = product_module.call(
			&runtime,
			.Invoke,
			transmute([]u8)string("result-refresh"),
			nil,
		)
		testing.expect(t, !invoked)
	}

	closed, close_failure := product_module.close(&runtime)
	testing.expectf(t, closed, "Ksawery module close failed with %v", close_failure)
	inspection, inspected := product_module.inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.lifecycle, product_module.Lifecycle.Closed)
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
	if capability != 41 || input_length > product_module.MAX_CALL_BYTES {
		return .Denied
	}
	if input_length > 0 && input == nil do return .Invalid_Argument
	if output_length != nil do output_length^ = 0
	switch operation {
	case .Diagnostic:
		host_observation.diagnostic_calls += 1
	case .UI:
		if input_length < u64(size_of(product_module.UI_List_Header)) {
			return .Invalid_Argument
		}
		header := (^product_module.UI_List_Header)(rawptr(input))
		row_bytes := u64(header.row_count) * u64(size_of(product_module.UI_List_Row))
		if header.schema_version != product_module.UI_LIST_SCHEMA_VERSION || header.row_count == 0 ||
		   row_bytes > input_length - u64(size_of(product_module.UI_List_Header)) ||
		   header.text_bytes != input_length - u64(size_of(product_module.UI_List_Header)) - row_bytes {
			return .Invalid_Argument
		}
		first_item: u64
		dispatcher_call := false
		current_seen := false
		current_passive := false
		text := ([^]u8)(rawptr(input))[
			int(size_of(product_module.UI_List_Header) + row_bytes):int(input_length)
		]
		host_observation.inspection_ready = false
		for index in 0 ..< int(header.row_count) {
			row := (^product_module.UI_List_Row)(rawptr(
				uintptr(input) + uintptr(size_of(product_module.UI_List_Header)) +
				uintptr(index * size_of(product_module.UI_List_Row)),
			))
			if row.id == 0 || row.text_length == 0 ||
			   row.text_offset + u64(row.text_length) > header.text_bytes {
				return .Invalid_Argument
			}
			dispatcher_call = dispatcher_call || row.id >> 56 == 0xCD
			if index == int(header.current_item) {
				current_seen = true
				current_passive = row.passive == 1
			}
			row_text := string(text[int(row.text_offset):int(row.text_offset) + int(row.text_length)])
			if row.passive == 0 && text_contains(row_text, "change.txt") {
				host_observation.changed_item = row.id
			}
			host_observation.status_seen = host_observation.status_seen ||
			                               text_contains(row_text, "Ksawery Status")
			host_observation.dispatcher_seen = host_observation.dispatcher_seen ||
			                                   text_contains(row_text, "Ksawery Commands")
			host_observation.diff_family_seen = host_observation.diff_family_seen ||
			                                    text_contains(row_text, "Ksawery Diff")
			host_observation.rebase_family_seen = host_observation.rebase_family_seen ||
			                                      text_contains(row_text, "Ksawery Rebase")
			host_observation.merge_family_seen = host_observation.merge_family_seen ||
			                                     text_contains(row_text, "Ksawery Merge")
			host_observation.remote_family_seen = host_observation.remote_family_seen ||
			                                      text_contains(row_text, "Ksawery Remote")
			host_observation.clone_family_seen = host_observation.clone_family_seen ||
			                                     text_contains(row_text, "Ksawery Clone")
			host_observation.advanced_family_seen = host_observation.advanced_family_seen ||
			                                        text_contains(row_text, "Ksawery Clone") ||
			                                        text_contains(row_text, "Ksawery Ignore") ||
			                                        text_contains(row_text, "Ksawery Init") ||
			                                        text_contains(row_text, "Ksawery Submodule") ||
			                                        text_contains(row_text, "Ksawery Subtree") ||
			                                        text_contains(row_text, "Ksawery Notes") ||
			                                        text_contains(row_text, "Ksawery Apply patches") ||
			                                        text_contains(row_text, "Ksawery Format patches") ||
			                                        text_contains(row_text, "Ksawery Sparse checkout")
			host_observation.raw_command_seen = host_observation.raw_command_seen ||
			                                    text_contains(row_text, "Ksawery Raw Repository Command")
			host_observation.raw_template_seen = host_observation.raw_template_seen ||
			                                     text_contains(row_text, "clone ") ||
			                                     text_contains(row_text, "init ") ||
			                                     text_contains(row_text, "submodule status ") ||
			                                     text_contains(row_text, "subtree add ") ||
			                                     text_contains(row_text, "notes prune") ||
			                                     text_contains(row_text, "apply ") ||
			                                     text_contains(row_text, "format-patch ") ||
			                                     text_contains(row_text, "sparse-checkout init --cone")
			host_observation.target_family_seen = host_observation.target_family_seen ||
			                                      text_contains(row_text, "Ksawery Target actions")
			host_observation.discard_prompt_seen = host_observation.discard_prompt_seen ||
			                                       text_contains(row_text, "Discard working-tree changes")
			host_observation.stashes_seen = host_observation.stashes_seen || row_text == "Ksawery Stashes"
			host_observation.worktrees_seen = host_observation.worktrees_seen || row_text == "Ksawery Worktrees"
			host_observation.reflog_seen = host_observation.reflog_seen || row_text == "Ksawery Reflog"
			host_observation.blame_seen = host_observation.blame_seen || row_text == "Ksawery Blame"
			host_observation.inspection_ready = host_observation.inspection_ready ||
			                                    text_contains(row_text, "Actions:")
			host_observation.status_failed = host_observation.status_failed ||
			                                 text_contains(row_text, "Status observation failed")
			host_observation.changed_path_seen = host_observation.changed_path_seen ||
			                                    text_contains(row_text, "change.txt")
			if first_item == 0 && row.passive == 0 && row.id > u64(max(u32)) do first_item = row.id
		}
		if dispatcher_call &&
		   (!current_seen || current_passive || header.first_visible_item > u32(header.current_item) ||
		    header.viewport_items == 0) {
			return .Invalid_Argument
		}
		host_observation.ui_calls += 1
		host_observation.ui_bytes = input_length
		host_observation.ui_rows = header.row_count
		if first_item > 0 do host_observation.first_item = first_item
	case .Session:
		if input_length < u64(size_of(product_module.Session_Request_Header)) || output_length == nil {
			return .Invalid_Argument
		}
		header := (^product_module.Session_Request_Header)(rawptr(input))
		if header.schema_version != product_module.SESSION_REQUEST_SCHEMA_VERSION ||
		   output == nil || output_capacity < u64(size_of(product_module.Session_Response)) {
			return .Invalid_Argument
		}
		response := (^product_module.Session_Response)(rawptr(output))
		response^ = {}
		if header.action == .Present_Surface do response.target = 7
		if header.action == .Open_Path {
			response.target = 8
			payload := ([^]u8)(rawptr(input))[size_of(product_module.Session_Request_Header):int(input_length)]
			host_observation.ignore_path_seen = host_observation.ignore_path_seen ||
			                                    text_contains(string(payload), ".gitignore")
		}
		output_length^ = u64(size_of(product_module.Session_Response))
	case .Command, .Prompt, .Tree_UI, .Process, .Provider, .Clipboard, .Filesystem, .Workspace, .Document:
	case .Invalid:
		return .Invalid_Argument
	}
	return .Ok
}

Inspection_Surface :: enum u8 {
	Invalid,
	Stashes,
	Worktrees,
	Reflog,
	Blame,
}

step_until_inspection_surface :: proc(
	runtime: ^product_module.Runtime,
	surface: Inspection_Surface,
) -> bool {
	for _ in 0 ..< 2_000 {
		changed: [1]u8
		_, stepped, _ := product_module.call(runtime, .Step, nil, changed[:])
		if !stepped || !inspect_runtime(runtime) do return false
		switch surface {
		case .Stashes:
			if host_observation.stashes_seen && host_observation.inspection_ready do return true
		case .Worktrees:
			if host_observation.worktrees_seen && host_observation.inspection_ready do return true
		case .Reflog:
			if host_observation.reflog_seen && host_observation.inspection_ready do return true
		case .Blame:
			if host_observation.blame_seen && host_observation.inspection_ready do return true
		case .Invalid:
			return false
		}
	}
	return false
}

send_key :: proc(
	runtime: ^product_module.Runtime,
	key: rune,
	modifiers: interaction.Modifiers = {},
) -> bool {
	input := product_module.Input_Request_Header {
		schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
		kind = .Key,
		key_kind = .Unicode_Scalar,
		scalar = i32(key),
		modifiers = transmute(u8)modifiers,
	}
	input_bytes := ([^]u8)(rawptr(&input))[:size_of(input)]
	_, dispatched, _ := product_module.call(runtime, .Input, input_bytes, nil)
	return dispatched
}

inspect_runtime :: proc(runtime: ^product_module.Runtime) -> bool {
	_, inspected, _ := product_module.call(runtime, .Inspect, nil, nil)
	return inspected
}

text_contains :: proc "contextless" (text, fragment: string) -> bool {
	if len(fragment) == 0 do return true
	if len(fragment) > len(text) do return false
	for offset in 0 ..= len(text) - len(fragment) {
		if text[offset:offset + len(fragment)] == fragment do return true
	}
	return false
}

run :: proc(directory: string, command: ..string) -> bool {
	state, stdout, stderr, process_error := os.process_exec(
		os.Process_Desc{working_dir = directory, command = command},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	return process_error == nil && state.exited && state.success
}

module_artifact :: proc(t: ^testing.T) -> product_module.Artifact {
	content, read_error := os.read_entire_file(MODULE_PATH, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(content)
	artifact: product_module.Artifact
	artifact.identity_length = u16(copy(artifact.identity[:], "odra.ksawery"))
	artifact.version_length = u16(copy(artifact.version[:], "1.0.0"))
	artifact.path_length = u16(copy(artifact.path[:], string(MODULE_PATH)))
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, content)
	sha2.final(&ctx, artifact.digest[:])
	artifact.size = u64(len(content))
	artifact.entrypoint_length = u16(copy(
		artifact.entrypoint[:],
		"odra_product_module_entrypoint",
	))
	artifact.abi_minimum = product_module.ABI_VERSION
	artifact.abi_maximum = product_module.ABI_VERSION
	artifact.role = .Source_Control
	return artifact
}
