// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_module_focused

import "../../src/product_module"
import "base:runtime"
import "core:crypto/sha2"
import "core:os"
import "core:strings"
import "core:testing"

MODULE_PATH :: #config(ODRA_JAN_MODULE, "../../.build/modules/libodra-jan.so")

SOURCE :: "* Alpha\nbody\n* Beta\n"
BABEL_SOURCE :: "* Computation\n#+name: sample\n#+begin_src racket\n(displayln 1)\n#+end_src\n\n#+RESULTS: sample\n: 1\n"
CHECKBOX_SOURCE :: "* Tasks\n- [ ] Compare movement commands\n"

Observation :: struct {
	diagnostics: u32,
	rewrites:    u32,
	visibility_replacements: u32,
	hidden_start: u64,
	hidden_end:   u64,
	start:       u64,
	end:         u64,
	replacement: [128]u8,
	replacement_length: int,
	moved_point: u64,
	diagnostic: [512]u8,
	diagnostic_length: int,
}

observation: Observation
active_source := SOURCE
active_point: u64
active_mark: u64
active_flags: u32

@(test)
/* jan_module_analyzes_and_rewrites_through_public_document_capabilities verifies isolation. */
jan_module_analyzes_and_rewrites_through_public_document_capabilities :: proc(t: ^testing.T) {
	observation = {}
	active_source = SOURCE
	active_point = 0
	active_mark = 0
	active_flags = 0
	artifact := module_artifact(t)
	module_runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&module_runtime, &artifact)
	testing.expectf(t, loaded, "Jan module load failed with %v", load_failure)
	if !loaded do return
	defer if module_runtime.lifecycle != .Closed do _, _ = product_module.close(&module_runtime)
	opened, open_failure := product_module.open(&module_runtime, host_call, 73)
	testing.expectf(t, opened, "Jan module open failed with %v", open_failure)
	if !opened do return
	_, activated, activation_failure := product_module.call(&module_runtime, .Activate, nil, nil)
	testing.expectf(t, activated, "Jan module activation failed with %v", activation_failure)
	if !activated do return
	invoke(t, &module_runtime, "jan-language-status")
	invoke(t, &module_runtime, "jan-cycle")
	invoke(t, &module_runtime, "jan-insert-heading-after")
	testing.expect(t, observation.diagnostics >= 3)
	testing.expect_value(t, observation.rewrites, u32(1))
	testing.expect_value(t, observation.visibility_replacements, u32(1))
	testing.expect_value(t, observation.hidden_start, u64(8))
	testing.expect_value(t, observation.hidden_end, u64(13))
	testing.expect_value(t, observation.start, u64(13))
	testing.expect_value(t, observation.end, u64(13))
	testing.expect_value(
		t,
		string(observation.replacement[:observation.replacement_length]),
		"* Heading\n",
	)
	_, deactivated, deactivation_failure := product_module.call(
		&module_runtime, .Deactivate, nil, nil,
	)
	testing.expectf(t, deactivated, "Jan module deactivation failed with %v", deactivation_failure)
	_, inactive, inactive_failure := product_module.call(&module_runtime, .Inspect, nil, nil)
	testing.expect(t, !inactive)
	testing.expect_value(t, inactive_failure.status, product_module.Status.Unavailable)
	_, recovered, recovery_failure := product_module.call(&module_runtime, .Activate, nil, nil)
	testing.expectf(t, recovered, "Jan module recovery failed with %v", recovery_failure)
	if recovered {
		diagnostics_before := observation.diagnostics
		invoke(t, &module_runtime, "jan-language-status")
		testing.expect_value(t, observation.diagnostics, diagnostics_before + 1)
	}
}

@(test)
/* Jan Babel commands preserve source and distinguish unavailable execution from valid utilities. */
jan_module_babel_utilities_are_adapter_independent :: proc(t: ^testing.T) {
	observation = {}
	active_source = BABEL_SOURCE
	active_point = u64(len("* Computation\n#+name: sample\n#+begin_src racket\n"))
	active_mark = 0
	active_flags = 0
	defer {
		active_source = SOURCE
		active_point = 0
		active_mark = 0
		active_flags = 0
	}
	artifact := module_artifact(t)
	module_runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&module_runtime, &artifact)
	testing.expectf(t, loaded, "Jan module load failed with %v", load_failure)
	if !loaded do return
	defer if module_runtime.lifecycle != .Closed do _, _ = product_module.close(&module_runtime)
	opened, open_failure := product_module.open(&module_runtime, host_call, 73)
	testing.expectf(t, opened, "Jan module open failed with %v", open_failure)
	if !opened do return
	_, activated, activation_failure := product_module.call(&module_runtime, .Activate, nil, nil)
	testing.expectf(t, activated, "Jan module activation failed with %v", activation_failure)
	if !activated do return
	invoke(t, &module_runtime, "jan-check-source")
	diagnostic := string(observation.diagnostic[:observation.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "valid=true"))
	testing.expect(t, strings.contains(diagnostic, "adapter=unavailable"))
	invoke(t, &module_runtime, "jan-open-result")
	testing.expect_value(t, observation.moved_point, u64(len("* Computation\n#+name: sample\n#+begin_src racket\n(displayln 1)\n#+end_src\n\n")))
	invoke(t, &module_runtime, "jan-source-hash")
	diagnostic = string(observation.diagnostic[:observation.diagnostic_length])
	testing.expect(t, strings.has_prefix(diagnostic, "Jan source hash: "))
	invoke(t, &module_runtime, "jan-execute")
	diagnostic = string(observation.diagnostic[:observation.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "outcome=Adapter_Unavailable"))
	testing.expect(t, strings.contains(diagnostic, "no adapter is configured"))
	testing.expect(t, strings.contains(diagnostic, "source-preserved=true"))
	invoke(t, &module_runtime, "jan-context-meta-up")
	diagnostic = string(observation.diagnostic[:observation.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "no adapter session is configured"))
	active_point = 0
	invoke(t, &module_runtime, "jan-execute")
	diagnostic = string(observation.diagnostic[:observation.diagnostic_length])
	testing.expect(t, strings.contains(diagnostic, "outcome=Malformed_Source"))
}

@(test)
/* Direct and contextual checkbox actions publish the same exact source edit. */
jan_module_checkbox_actions_publish_one_rewrite :: proc(t: ^testing.T) {
	observation = {}
	active_source = CHECKBOX_SOURCE
	active_point = 15
	active_mark = 0
	active_flags = 0
	defer {
		active_source = SOURCE
		active_point = 0
		active_mark = 0
		active_flags = 0
	}
	artifact := module_artifact(t)
	module_runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&module_runtime, &artifact)
	testing.expectf(t, loaded, "Jan module load failed with %v", load_failure)
	if !loaded do return
	defer if module_runtime.lifecycle != .Closed do _, _ = product_module.close(&module_runtime)
	opened, open_failure := product_module.open(&module_runtime, host_call, 73)
	testing.expectf(t, opened, "Jan module open failed with %v", open_failure)
	if !opened do return
	_, activated, activation_failure := product_module.call(&module_runtime, .Activate, nil, nil)
	testing.expectf(t, activated, "Jan module activation failed with %v", activation_failure)
	if !activated do return
	commands := [2]string{"jan-toggle-checkbox", "jan-context-action"}
	points := [7]u64{8, 9, 10, 11, 12, 14, u64(len(CHECKBOX_SOURCE) - 1)}
	for command_name in commands {
		for point in points {
			active_point = point
			observation.rewrites = 0
			observation.replacement_length = 0
			invoke(t, &module_runtime, command_name)
			testing.expect_value(t, observation.rewrites, u32(1))
			testing.expect_value(t, observation.start, u64(11))
			testing.expect_value(t, observation.end, u64(12))
			testing.expect_value(
				t,
				string(observation.replacement[:observation.replacement_length]),
				"X",
			)
		}
		active_point = 0
		observation.rewrites = 0
		invoke(t, &module_runtime, command_name)
		testing.expect_value(t, observation.rewrites, u32(0))
	}
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
	testing.expectf(t, invoked, "Jan command %s failed with %v", name, failure)
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
	if capability != 73 || input_length > product_module.MAX_CALL_BYTES do return .Denied
	if output_length != nil do output_length^ = 0
	switch operation {
	case .Diagnostic:
		observation.diagnostics += 1
		observation.diagnostic_length = copy(
			observation.diagnostic[:],
			([^]u8)(rawptr(input))[:int(input_length)],
		)
		return .Ok
	case .Document:
		if input == nil || input_length < u64(size_of(product_module.Document_Request_Header)) {
			return .Invalid_Argument
		}
		header := (^product_module.Document_Request_Header)(rawptr(input))
		switch header.action {
		case .Inspect:
			required := u64(size_of(product_module.Document_Snapshot_Header) + len(active_source))
			if output == nil || output_length == nil || output_capacity < required do return .Limit
			snapshot := product_module.Document_Snapshot_Header {
				schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
				buffer_id = 1,
				revision = 1,
				point = active_point,
				mark = active_mark,
				flags = active_flags,
				view_generation = 1,
				visibility_generation = 1,
				source_length = u64(len(active_source)),
			}
			bytes := ([^]u8)(rawptr(output))[:int(required)]
			copy(bytes[:size_of(snapshot)], ([^]u8)(rawptr(&snapshot))[:size_of(snapshot)])
			copy(bytes[size_of(snapshot):], active_source)
			output_length^ = required
			return .Ok
		case .Apply_Rewrite:
			if header.count != 1 do return .Invalid_Argument
			payload := ([^]u8)(rawptr(input))[size_of(product_module.Document_Request_Header):int(input_length)]
			row := (^product_module.Document_Splice)(raw_data(payload))
			row_bytes := size_of(product_module.Document_Splice)
			text := payload[row_bytes:]
			if row.text_offset + row.text_length > u64(len(text)) do return .Invalid_Argument
			observation.start = row.start
			observation.end = row.end
			observation.replacement_length = copy(
				observation.replacement[:],
				text[int(row.text_offset):int(row.text_offset + row.text_length)],
			)
			observation.rewrites += 1
			return .Ok
		case .Replace_Visibility:
			if header.count != 1 || header.payload_length != size_of(product_module.Document_Range) {
				return .Invalid_Argument
			}
			payload := ([^]u8)(rawptr(input))[size_of(product_module.Document_Request_Header):int(input_length)]
			range := (^product_module.Document_Range)(raw_data(payload))
			observation.hidden_start = range.start
			observation.hidden_end = range.end
			observation.visibility_replacements += 1
			return .Ok
		case .Move_Point:
			observation.moved_point = header.point
			return .Ok
		case .Invalid:
			return .Invalid_Argument
		}
	case .Command, .Prompt, .Session, .UI, .Process, .Provider, .Tree_UI,
	     .Clipboard, .Filesystem, .Workspace:
		return .Unavailable
	case .Invalid:
		return .Invalid_Argument
	}
	return .Invalid_Argument
}

module_artifact :: proc(t: ^testing.T) -> product_module.Artifact {
	content, read_error := os.read_entire_file(MODULE_PATH, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(content)
	artifact: product_module.Artifact
	artifact.identity_length = u16(copy(artifact.identity[:], "odra.jan"))
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
	artifact.role = .Structured_Document
	return artifact
}
