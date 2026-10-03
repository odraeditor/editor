// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek_module_focused

import "../../src/product_module"
import "../../src/darek"
import "../../src/darek_module"
import "../../src/filesystem"
import "../../src/ui"
import "base:runtime"
import "core:crypto/sha2"
import "core:fmt"
import "core:os"
import "core:testing"

MODULE_PATH :: #config(ODRA_DAREK_MODULE, "../../.build/modules/libodra-darek.so")

Host_Observation :: struct {
	diagnostics: u32,
	tree_calls:  u32,
	rows:        u32,
	nested_seen: bool,
	hidden_seen: bool,
	nested_id:   u64,
	nested_icon_role: u8,
	symbol_seen: bool,
	symbol_id: u64,
	current_id:  u64,
	session_calls: u32,
	position_calls: u32,
	provider_calls: u32,
	process_calls: u32,
	process_directory: [4096]u8,
	process_directory_length: int,
	process_command: [256]u8,
	process_command_length: int,
	bulk_calls: u32,
	bulk_directory: [4096]u8,
	bulk_directory_length: int,
	navigation_calls: u32,
	clipboard_calls: u32,
	retained_text: [4096]u8,
	retained_length: int,
}

host_observation: Host_Observation

@(test)
/* darek_module_publishes_and_navigates_one_public_tree_panel verifies the bundled artifact. */
darek_module_publishes_and_navigates_one_public_tree_panel :: proc(t: ^testing.T) {
	host_observation = {}
	root, root_error := os.make_directory_temp("", "odra-darek-module-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer delete(root)
	defer os.remove_all(root)
	nested, nested_error := os.join_path({root, "nested.odin"}, context.allocator)
	alpha, alpha_error := os.join_path({root, "alpha.txt"}, context.allocator)
	hidden, hidden_error := os.join_path({root, ".hidden"}, context.allocator)
	testing.expect(t, nested_error == nil && alpha_error == nil && hidden_error == nil)
	if nested_error != nil || alpha_error != nil || hidden_error != nil do return
	defer { delete(hidden); delete(alpha); delete(nested) }
	testing.expect(t, os.write_entire_file(nested, "package nested\n") == nil)
	testing.expect(t, os.write_entire_file(alpha, "alpha\n") == nil)
	testing.expect(t, os.write_entire_file(hidden, "hidden\n") == nil)
	observation, observed, _ := filesystem.directory_observe(
		root, 1, {persistent = context.allocator, temporary = context.temp_allocator}, true,
	)
	testing.expect(t, observed)
	if !observed do return
	defer _, _ = filesystem.directory_batch_close(&observation)
	nested_resource: filesystem.Resource_ID
	for descriptor in observation.descriptors {
		if descriptor.name == "nested.odin" do nested_resource = descriptor.identity
	}
	testing.expect(t, filesystem.resource_id_valid(nested_resource))

	artifact := module_artifact(t)
	module_runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&module_runtime, &artifact)
	testing.expectf(t, loaded, "Darek module load failed with %v", load_failure)
	if !loaded do return
	defer if module_runtime.lifecycle != .Closed do _, _ = product_module.close(&module_runtime)
	opened, open_failure := product_module.open(&module_runtime, host_call, 91)
	testing.expectf(t, opened, "Darek module open failed with %v", open_failure)
	if !opened do return
	payload := fmt.tprintf("project\nDarek Test\t%s", root)
	_, activated, activation_failure := product_module.call(
		&module_runtime, .Activate, transmute([]u8)payload, nil,
	)
	testing.expectf(
		t,
		activated,
		"Darek activation failed with %v after %d tree calls and %d rows",
		activation_failure,
		host_observation.tree_calls,
		host_observation.rows,
	)
	if !activated do return
	testing.expect(t, host_observation.tree_calls > 0)
	testing.expect(t, host_observation.rows >= 3)
	testing.expect(t, host_observation.nested_seen)
	selection := product_module.Selection_Request {
		schema_version = product_module.UI_TREE_PANEL_SCHEMA_VERSION,
		item_id = host_observation.nested_id,
	}
	_, selected, selection_failure := product_module.call(
		&module_runtime,
		.Select,
		([^]u8)(rawptr(&selection))[:size_of(selection)],
		nil,
	)
	testing.expectf(t, selected, "Darek selection failed with %v", selection_failure)
	testing.expect_value(t, host_observation.current_id, host_observation.nested_id)
	testing.expect_value(t, host_observation.session_calls, u32(0))
	invoke(t, &module_runtime, "darek-toggle-hidden-files")
	testing.expect(t, host_observation.hidden_seen)
	invoke(t, &module_runtime, "darek-toggle-hidden-files")
	testing.expect(t, !host_observation.hidden_seen)
	annotate(t, &module_runtime, 7, nested_resource, .Modified, .Error, false)
	testing.expect_value(t, host_observation.nested_icon_role, u8(ui.Tree_Icon_Role.Failure))
	configure(t, &module_runtime, .Annotations_Unavailable, 8, nil)
	testing.expect(t, host_observation.nested_icon_role != u8(ui.Tree_Icon_Role.Failure))
	invoke(t, &module_runtime, "darek-structure-action")
	testing.expect(t, host_observation.symbol_seen)
	testing.expect_value(t, host_observation.provider_calls, u32(1))
	selection.item_id = host_observation.symbol_id
	_, symbol_selected, _ := product_module.call(
		&module_runtime,
		.Select,
		([^]u8)(rawptr(&selection))[:size_of(selection)],
		nil,
	)
	testing.expect(t, symbol_selected)
	invoke(t, &module_runtime, "darek-visit-action")
	testing.expect_value(t, host_observation.position_calls, u32(1))
	selection.item_id = host_observation.nested_id
	_, nested_selected, _ := product_module.call(
		&module_runtime,
		.Select,
		([^]u8)(rawptr(&selection))[:size_of(selection)],
		nil,
	)
	testing.expect(t, nested_selected)
	invoke(t, &module_runtime, "darek-shell-command")
	input_text(t, &module_runtime, "pwd")
	input_key(t, &module_runtime, .Enter)
	testing.expect_value(t, host_observation.process_calls, u32(1))
	testing.expect_value(
		t,
		string(host_observation.process_directory[:host_observation.process_directory_length]),
		root,
	)
	testing.expect_value(
		t,
		string(host_observation.process_command[:host_observation.process_command_length]),
		"pwd",
	)
	invoke(t, &module_runtime, "darek-shell-command-project")
	input_text(t, &module_runtime, "ls")
	input_key(t, &module_runtime, .Enter)
	testing.expect_value(t, host_observation.process_calls, u32(2))
	invoke(t, &module_runtime, "darek-bulk-actions")
	testing.expect_value(t, host_observation.bulk_calls, u32(1))
	testing.expect_value(
		t,
		string(host_observation.bulk_directory[:host_observation.bulk_directory_length]),
		root,
	)
	invoke(t, &module_runtime, "darek-context-actions")
	testing.expect_value(t, host_observation.navigation_calls, u32(1))
	invoke(t, &module_runtime, "darek-toggle-file-watch")
	configure(t, &module_runtime, .Watch_Activity, 1, nil)
	invoke(t, &module_runtime, "darek-refresh")
	configure(t, &module_runtime, .Watch_Restart, 2, nil)
	stale_watch := configuration_header(.Watch_Activity, 1, 0)
	_, stale_watch_ok, stale_watch_failure := product_module.call(
		&module_runtime, .Configure,
		([^]u8)(rawptr(&stale_watch))[:size_of(stale_watch)], nil,
	)
	testing.expect(t, !stale_watch_ok)
	testing.expect_value(t, stale_watch_failure.status, product_module.Status.Stale)
	invoke(t, &module_runtime, "darek-select-sort")
	testing.expect_value(t, host_observation.current_id, host_observation.nested_id)
	invoke(t, &module_runtime, "darek-filter")
	input_text(t, &module_runtime, "nested")
	input_key(t, &module_runtime, .Enter)
	testing.expect_value(t, host_observation.rows, u32(2))
	testing.expect_value(t, host_observation.current_id, host_observation.nested_id)
	stale_selection := product_module.Selection_Request {
		schema_version = product_module.UI_TREE_PANEL_SCHEMA_VERSION,
		item_id = max(u64),
	}
	_, stale_selected, stale_failure := product_module.call(
		&module_runtime,
		.Select,
		([^]u8)(rawptr(&stale_selection))[:size_of(stale_selection)],
		nil,
	)
	testing.expect(t, !stale_selected)
	testing.expect_value(t, stale_failure.status, product_module.Status.Stale)
	testing.expect_value(t, host_observation.current_id, host_observation.nested_id)
	invoke(t, &module_runtime, "darek-copy-absolute-path")
	testing.expect_value(t, host_observation.clipboard_calls, u32(1))
	testing.expect_value(t, string(host_observation.retained_text[:host_observation.retained_length]), nested)
	invoke(t, &module_runtime, "darek-toggle-peek")
	invalid_payload := "directory\ninvalid"
	_, rejected, _ := product_module.call(
		&module_runtime, .Activate, transmute([]u8)invalid_payload, nil,
	)
	testing.expect(t, !rejected)
	_, retained, retained_failure := product_module.call(&module_runtime, .Inspect, nil, nil)
	testing.expectf(t, retained, "Darek lost the confirmed instance after rejection: %v", retained_failure)
	_, deactivated, deactivation_failure := product_module.call(&module_runtime, .Deactivate, nil, nil)
	testing.expectf(t, deactivated, "Darek deactivation failed with %v", deactivation_failure)
	_, inactive, inactive_failure := product_module.call(&module_runtime, .Inspect, nil, nil)
	testing.expect(t, !inactive)
	testing.expect_value(t, inactive_failure.status, product_module.Status.Unavailable)
	_, recovered, recovery_failure := product_module.call(
		&module_runtime, .Activate, transmute([]u8)payload, nil,
	)
	testing.expectf(t, recovered, "Darek recovery failed with %v", recovery_failure)
}

configuration_header :: proc(
	kind: darek_module.Presentation_Update_Kind,
	generation: u64,
	record_count: u32,
) -> darek_module.Presentation_Update_Header {
	return {
		schema_version = darek_module.PRESENTATION_PROVIDER_SCHEMA_VERSION,
		kind = kind,
		provider_generation = generation,
		record_count = record_count,
	}
}

configure :: proc(
	t: ^testing.T,
	module_runtime: ^product_module.Runtime,
	kind: darek_module.Presentation_Update_Kind,
	generation: u64,
	records: []darek_module.Presentation_Annotation,
) {
	header := configuration_header(kind, generation, u32(len(records)))
	request: [size_of(darek_module.Presentation_Update_Header) + size_of(darek_module.Presentation_Annotation)]u8
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	if len(records) > 0 {
		copy(
			request[size_of(header):],
			([^]u8)(raw_data(records))[:len(records) * size_of(darek_module.Presentation_Annotation)],
		)
	}
	_, configured, failure := product_module.call(
		module_runtime, .Configure,
		request[:size_of(header) + len(records) * size_of(darek_module.Presentation_Annotation)], nil,
	)
	testing.expectf(t, configured, "Darek presentation configuration failed with %v", failure)
}

annotate :: proc(
	t: ^testing.T,
	module_runtime: ^product_module.Runtime,
	generation: u64,
	resource: filesystem.Resource_ID,
	version_control: darek.Version_Control_State,
	diagnostic: darek.Diagnostic_State,
	ignored: bool,
) {
	annotations := [1]darek_module.Presentation_Annotation {{
		resource = {provider = resource.provider, device = resource.device, inode = resource.inode},
		version_control = u8(version_control),
		diagnostic = u8(diagnostic),
		flags = darek_module.PRESENTATION_ANNOTATION_IGNORED if ignored else 0,
	}}
	configure(t, module_runtime, .Annotations, generation, annotations[:])
}

input_text :: proc(t: ^testing.T, module_runtime: ^product_module.Runtime, value: string) {
	header := product_module.Input_Request_Header {
		schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
		kind = .Text_Commit,
		text_length = u32(len(value)),
	}
	request: [size_of(product_module.Input_Request_Header) + 128]u8
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], value)
	_, accepted, failure := product_module.call(
		module_runtime, .Input, request[:size_of(header) + len(value)], nil,
	)
	testing.expectf(t, accepted, "Darek text input failed with %v", failure)
}

input_key :: proc(t: ^testing.T, module_runtime: ^product_module.Runtime, key: product_module.Key_Kind) {
	header := product_module.Input_Request_Header {
		schema_version = product_module.INPUT_REQUEST_SCHEMA_VERSION,
		kind = .Key,
		key_kind = key,
	}
	_, accepted, failure := product_module.call(
		module_runtime, .Input, ([^]u8)(rawptr(&header))[:size_of(header)], nil,
	)
	testing.expectf(t, accepted, "Darek key input failed with %v", failure)
}

invoke :: proc(t: ^testing.T, module_runtime: ^product_module.Runtime, name: string) {
	header := product_module.Invocation_Request_Header {
		schema_version = product_module.INVOCATION_REQUEST_SCHEMA_VERSION,
		provider = 1,
		operation = 1,
		name_length = u32(len(name)),
	}
	request: [size_of(product_module.Invocation_Request_Header) + 128]u8
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], name)
	_, invoked, failure := product_module.call(
		module_runtime, .Invoke, request[:size_of(header) + len(name)], nil,
	)
	testing.expectf(t, invoked, "Darek command %s failed with %v", name, failure)
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
	if capability != 91 || input_length > product_module.MAX_CALL_BYTES do return .Denied
	if input_length > 0 && input == nil do return .Invalid_Argument
	if output_length != nil do output_length^ = 0
	switch operation {
	case .Diagnostic: host_observation.diagnostics += 1
	case .Tree_UI:
		if input_length < u64(size_of(product_module.UI_Tree_Panel_Header)) do return .Invalid_Argument
		header := (^product_module.UI_Tree_Panel_Header)(rawptr(input))
		row_bytes := u64(header.row_count) * u64(size_of(product_module.UI_Tree_Panel_Row))
		if header.schema_version != product_module.UI_TREE_PANEL_SCHEMA_VERSION ||
		   row_bytes > input_length - u64(size_of(product_module.UI_Tree_Panel_Header)) ||
		   header.text_bytes != input_length - u64(size_of(product_module.UI_Tree_Panel_Header)) - row_bytes {
			return .Invalid_Argument
		}
		text := ([^]u8)(rawptr(input))[int(size_of(product_module.UI_Tree_Panel_Header) + row_bytes):int(input_length)]
		host_observation.hidden_seen = false
		for index in 0 ..< int(header.row_count) {
			row := (^product_module.UI_Tree_Panel_Row)(rawptr(uintptr(input) + uintptr(size_of(product_module.UI_Tree_Panel_Header)) + uintptr(index * size_of(product_module.UI_Tree_Panel_Row))))
			if row.text_offset + u64(row.text_length) > header.text_bytes do return .Invalid_Argument
			row_text := string(text[int(row.text_offset):int(row.text_offset) + int(row.text_length)])
			host_observation.nested_seen = host_observation.nested_seen || row_text == "nested.odin"
			host_observation.hidden_seen = host_observation.hidden_seen || row_text == ".hidden"
			host_observation.symbol_seen = host_observation.symbol_seen || row_text == "nested_proc"
			if row_text == "nested.odin" do host_observation.nested_id = row.id
			if row_text == "nested_proc" do host_observation.symbol_id = row.id
			if row_text == "nested.odin" do host_observation.nested_icon_role = row.icon_role
			if i32(index) == header.current_item do host_observation.current_id = row.id
		}
		host_observation.tree_calls += 1
		host_observation.rows = header.row_count
	case .Session:
		host_observation.session_calls += 1
		if input_length < u64(size_of(product_module.Session_Request_Header)) do return .Invalid_Argument
		header := (^product_module.Session_Request_Header)(rawptr(input))
		if header.action == .Open_Path || header.action == .Present_Position {
			if output == nil || output_capacity < u64(size_of(product_module.Session_Response)) || output_length == nil {
				return .Limit
			}
			response := product_module.Session_Response{target = 7}
			copy(
				([^]u8)(rawptr(output))[:size_of(response)],
				([^]u8)(rawptr(&response))[:size_of(response)],
			)
			output_length^ = u64(size_of(response))
			if header.action == .Present_Position do host_observation.position_calls += 1
			return .Ok
		}
		return .Unavailable
	case .Provider:
		if input_length < u64(size_of(product_module.Provider_Request_Header)) || output == nil || output_length == nil {
			return .Invalid_Argument
		}
		provider_header := (^product_module.Provider_Request_Header)(rawptr(input))
		service_start := size_of(product_module.Provider_Request_Header)
		name_start := service_start + int(provider_header.service_length)
		service := string(([^]u8)(rawptr(input))[service_start:name_start])
		if service != "language.document-symbols" do return .Unavailable
		name := "nested_proc"
		response_header := product_module.Symbol_Provider_Response_Header {
			schema_version = product_module.SYMBOL_PROVIDER_RESPONSE_SCHEMA_VERSION,
			complete = 1,
			provider_generation = 1,
			source_revision = 12,
			record_count = 1,
			text_bytes = u32(len(name)),
		}
		record := product_module.Symbol_Provider_Record {
			id = 1,
			start = 8,
			end = 19,
			name_length = u16(len(name)),
		}
		total := size_of(response_header) + size_of(record) + len(name)
		if output_capacity < u64(total) do return .Limit
		bytes := ([^]u8)(rawptr(output))[:total]
		copy(bytes[:size_of(response_header)], ([^]u8)(rawptr(&response_header))[:size_of(response_header)])
		copy(bytes[size_of(response_header):size_of(response_header) + size_of(record)], ([^]u8)(rawptr(&record))[:size_of(record)])
		copy(bytes[size_of(response_header) + size_of(record):], name)
		output_length^ = u64(total)
		host_observation.provider_calls += 1
	case .Process:
		if input_length < u64(size_of(product_module.Process_Request_Header)) do return .Invalid_Argument
		header := (^product_module.Process_Request_Header)(rawptr(input))
		content := ([^]u8)(rawptr(input))[size_of(product_module.Process_Request_Header):int(input_length)]
		if int(header.working_directory_length) + int(header.command_length) != len(content) {
			return .Invalid_Argument
		}
		host_observation.process_directory_length = copy(
			host_observation.process_directory[:], content[:header.working_directory_length],
		)
		host_observation.process_command_length = copy(
			host_observation.process_command[:], content[header.working_directory_length:],
		)
		host_observation.process_calls += 1
	case .Command:
		if input_length < u64(size_of(product_module.Command_Request_Header)) do return .Invalid_Argument
		header := (^product_module.Command_Request_Header)(rawptr(input))
		if header.action == .Present_Navigation {
			host_observation.navigation_calls += 1
			return .Ok
		}
		if header.action != .Present_File_Management do return .Ok
		payload := ([^]u8)(rawptr(input))[size_of(product_module.Command_Request_Header):int(input_length)]
		host_observation.bulk_directory_length = copy(host_observation.bulk_directory[:], payload)
		host_observation.bulk_calls += 1
	case .Clipboard:
		if input_length == 0 || input_length > u64(len(host_observation.retained_text)) {
			return .Invalid_Argument
		}
		host_observation.retained_length = copy(
			host_observation.retained_text[:], ([^]u8)(rawptr(input))[:int(input_length)],
		)
		host_observation.clipboard_calls += 1
	case .Prompt, .UI, .Filesystem, .Workspace, .Document:
	case .Invalid: return .Invalid_Argument
	}
	return .Ok
}

module_artifact :: proc(t: ^testing.T) -> product_module.Artifact {
	content, read_error := os.read_entire_file(MODULE_PATH, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(content)
	artifact: product_module.Artifact
	artifact.identity_length = u16(copy(artifact.identity[:], "odra.darek"))
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
	artifact.role = .Workspace_Hierarchy
	return artifact
}
