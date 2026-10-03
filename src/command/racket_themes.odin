// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../hosting"
import "../theme"
import "../ui"
import endian "core:encoding/endian"
import "core:unicode/utf8"
import base_runtime "base:runtime"

/* Racket_Theme_Result reports the final copied selection after one hosted turn. */
Racket_Theme_Result :: struct {
	selection: theme.Selection,
	calls:     u16,
}

@(private)
Racket_Theme_Call :: struct {
	registry:       ^theme.Registry,
	token:          u64,
	last_selection: theme.Selection,
	calls:          u16,
	failure:        theme.Failure,
}

@(private)
Decoded_Theme_Request :: struct {
	expected_scope: bridge.Theme_Scope_Record,
	operation:      bridge.Theme_Capability_Operation,
	provider:       theme.Provider_Handle,
	definition:     theme.Definition_Handle,
	identity:       string,
	display_name:   string,
	provider_name:  string,
	provenance:     string,
	styles:         [theme.MAX_STYLES]ui.Style_Definition,
	style_count:    int,
}

/* racket_theme_turn lends one exact bounded registry capability to Racket. */
racket_theme_turn :: proc(
	racket_runtime: ^hosting.Runtime,
	registry: ^theme.Registry,
	scenario: i32,
) -> (result: Racket_Theme_Result, ok: bool, failure: theme.Failure) {
	if racket_runtime == nil || registry == nil {
		return {}, false, theme.Failure {
			operation = .Inspect,
			code = .Invalid_Registry,
		}
	}
	selection, selected, selection_failure := theme.theme_registry_selection(registry)
	if !selected {
		return {}, false, selection_failure
	}
	token := u64(selection.registry_id) ~ (u64(selection.registry_generation) << 17) ~
	         (u64(selection.selection_generation) << 41)
	if token == 0 do token = 1
	call := Racket_Theme_Call {
		registry = registry,
		token = token,
		last_selection = selection,
	}
	executed, runtime_failure := hosting.runtime_theme_probe(
		racket_runtime,
		scenario,
		token,
		racket_theme_callback,
		&call,
	)
	if !executed {
		racket_theme_restore_after_runtime_failure(&call)
		return {}, false, theme.Failure {
			operation = .Fail,
			code = .Invalid_Registry,
			actual = u64(runtime_failure.code),
		}
	}
	if call.failure.code != .None {
		return {}, false, call.failure
	}
	selection, selected, selection_failure = theme.theme_registry_selection(registry)
	if !selected {
		return {}, false, selection_failure
	}
	return Racket_Theme_Result{selection = selection, calls = call.calls}, true, {}
}

@(private)
racket_theme_callback :: proc "c" (
	user_data: rawptr,
	kind: hosting.Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	context = base_runtime.default_context()
	call := (^Racket_Theme_Call)(user_data)
	if call == nil || kind != .Theme || generation == 0 || token != call.token ||
	   domain_context != 0 || arg0 != 0 || arg1 != 0 || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil ||
	   input_length > u64(max(int)) || output_capacity > u64(max(int)) {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	input_bytes: []u8
	if input_length > 0 {
		if input == nil do return 2
		input_bytes = ([^]u8)(input)[:int(input_length)]
	}
	destination: []u8
	if output_capacity > 0 {
		if output == nil do return 2
		destination = ([^]u8)(output)[:int(output_capacity)]
	}
	op := bridge.Theme_Capability_Operation(operation)
	if op < .Scope || op > .Teardown do return 2
	inspection, inspected, inspect_failure := theme.theme_registry_inspect(call.registry)
	if !inspected {
		return racket_theme_reject(call, inspect_failure, failure_code, limit, actual)
	}
	call.calls += 1
	if call.calls > inspection.limits.operations_per_turn {
		return racket_theme_reject(
			call,
			theme.Failure {
				operation = racket_theme_native_operation(op),
				code = .Operation_Limit,
				limit = u64(inspection.limits.operations_per_turn),
				actual = u64(call.calls),
			},
			failure_code,
			limit,
			actual,
		)
	}
	current := inspection.selection
	call.last_selection = current
	if op == .Scope {
		if input_length != 0 || output_capacity != bridge.THEME_SCOPE_RECORD_BYTES do return 2
		written, encoded := racket_theme_encode_scope(destination, current, generation)
		if !encoded do return 2
		output_length^ = written
		return 0
	}
	if input_length < bridge.THEME_SCOPE_RECORD_BYTES do return 2
	expected, decoded := racket_theme_decode_scope(input_bytes)
	if !decoded do return 2
	access := racket_theme_access(op)
	if access == 0 || !racket_theme_scope_matches(expected, current, generation) ||
	   (expected.access & access) == 0 {
		return racket_theme_reject(
			call,
			theme.Failure {
				operation = racket_theme_native_operation(op),
				code = .Stale_Selection,
			},
			failure_code,
			limit,
			actual,
		)
	}
	if op == .Inspect {
		if input_length != bridge.THEME_SCOPE_RECORD_BYTES do return 2
		written, encoded, encode_failure := racket_theme_encode_snapshot(
			destination, call, current, generation, nil,
		)
		if !encoded {
			return racket_theme_reject(call, encode_failure, failure_code, limit, actual)
		}
		output_length^ = written
		return 0
	}
	request, request_ok := racket_theme_decode_request(input_bytes, op, current)
	if !request_ok do return 2
	if op == .Inspect_Definition {
		view, viewed, view_failure := theme.theme_registry_definition(
			call.registry, request.definition,
		)
		if !viewed {
			return racket_theme_reject(call, view_failure, failure_code, limit, actual)
		}
		written, encoded, encode_failure := racket_theme_encode_snapshot(
			destination, call, current, generation, &view,
		)
		if !encoded {
			return racket_theme_reject(call, encode_failure, failure_code, limit, actual)
		}
		output_length^ = written
		return 0
	}
	previous := current.active
	definition := request.definition
	final := current
	mutation_ok := false
	mutation_failure: theme.Failure
	switch op {
	case .Propose:
		proposal := racket_theme_native_proposal(&request)
		definition, mutation_ok, mutation_failure = theme.theme_registry_propose(
			call.registry, current.registry_generation, proposal,
		)
	case .Confirm:
		definition, mutation_ok, mutation_failure = theme.theme_registry_confirm(
			call.registry, current.registry_generation, request.definition,
		)
	case .Select:
		final, mutation_ok, mutation_failure = theme.theme_registry_select(
			call.registry, current, request.definition,
		)
	case .Replace:
		proposal := racket_theme_native_proposal(&request)
		final, definition, mutation_ok, mutation_failure = theme.theme_registry_replace(
			call.registry, current, request.definition, proposal,
		)
	case .Restore:
		final, mutation_ok, mutation_failure = theme.theme_registry_restore(call.registry, current)
		definition = final.active
	case .Select_Baseline:
		final, mutation_ok, mutation_failure = theme.theme_registry_select_baseline(
			call.registry, current,
		)
		definition = final.active
	case .Teardown:
		final, mutation_ok, mutation_failure = theme.theme_registry_close_provider(
			call.registry, current, request.provider,
		)
		definition = final.active
	case .Scope, .Inspect, .Inspect_Definition:
		return 2
	}
	if !mutation_ok {
		return racket_theme_reject(call, mutation_failure, failure_code, limit, actual)
	}
	if op == .Propose || op == .Confirm {
		final, mutation_ok, mutation_failure = theme.theme_registry_selection(call.registry)
		if !mutation_ok {
			return racket_theme_reject(call, mutation_failure, failure_code, limit, actual)
		}
	}
	written, encoded := racket_theme_encode_outcome(
		destination, call, op, previous, definition, final, generation,
	)
	if !encoded do return 2
	call.last_selection = final
	output_length^ = written
	return 0
}

@(private)
racket_theme_decode_request :: proc(
	input: []u8,
	operation: bridge.Theme_Capability_Operation,
	current: theme.Selection,
) -> (request: Decoded_Theme_Request, ok: bool) {
	if len(input) < int(bridge.THEME_PROPOSAL_HEADER_BYTES) do return {}, false
	request.expected_scope, ok = racket_theme_decode_scope(input)
	if !ok || read_theme_u64(input, 144) != u64(operation) do return {}, false
	request.operation = operation
	request.provider = theme.Provider_Handle {
		registry_id = current.registry_id,
		provider_id = theme.Provider_ID(read_theme_u64(input, 152)),
		provider_generation = theme.Provider_Generation(read_theme_u64(input, 160)),
	}
	request.definition = theme.Definition_Handle {
		registry_id = current.registry_id,
		provider_id = request.provider.provider_id,
		provider_generation = request.provider.provider_generation,
		definition_id = theme.Definition_ID(read_theme_u64(input, 168)),
		definition_generation = theme.Definition_Generation(read_theme_u64(input, 176)),
	}
	style_count := read_theme_u64(input, 248)
	text_bytes := read_theme_u64(input, 256)
	required, width_ok := bridge.theme_proposal_record_bytes(style_count, text_bytes)
	if !width_ok || required != u64(len(input)) do return {}, false
	style_end := bridge.THEME_PROPOSAL_HEADER_BYTES +
	             style_count * bridge.THEME_STYLE_RECORD_BYTES
	identity_offset := read_theme_u64(input, 184)
	identity_bytes := read_theme_u64(input, 192)
	display_offset := read_theme_u64(input, 200)
	display_bytes := read_theme_u64(input, 208)
	provider_offset := read_theme_u64(input, 216)
	provider_bytes := read_theme_u64(input, 224)
	provenance_offset := read_theme_u64(input, 232)
	provenance_bytes := read_theme_u64(input, 240)
	if identity_offset != style_end || display_offset != identity_offset + identity_bytes ||
	   provider_offset != display_offset + display_bytes ||
	   provenance_offset != provider_offset + provider_bytes ||
	   provenance_offset + provenance_bytes != required ||
	   identity_bytes + display_bytes + provider_bytes + provenance_bytes != text_bytes {
		return {}, false
	}
	request.identity = string(input[int(identity_offset):int(identity_offset + identity_bytes)])
	request.display_name = string(input[int(display_offset):int(display_offset + display_bytes)])
	request.provider_name = string(input[int(provider_offset):int(provider_offset + provider_bytes)])
	request.provenance = string(input[int(provenance_offset):int(provenance_offset + provenance_bytes)])
	if !utf8.valid_string(request.identity) || !utf8.valid_string(request.display_name) ||
	   !utf8.valid_string(request.provider_name) || !utf8.valid_string(request.provenance) {
		return {}, false
	}
	request.style_count = int(style_count)
	for index in 0..<request.style_count {
		offset := int(bridge.THEME_PROPOSAL_HEADER_BYTES) +
		          index * int(bridge.THEME_STYLE_RECORD_BYTES)
		style, style_ok := racket_theme_decode_style(input, offset)
		if !style_ok do return {}, false
		request.styles[index] = style
	}
	if operation != .Propose && operation != .Replace &&
	   (style_count != 0 || text_bytes != 0) {
		return {}, false
	}
	return request, true
}

@(private)
racket_theme_decode_style :: proc(input: []u8, offset: int) -> (style: ui.Style_Definition, ok: bool) {
	values: [10]u64
	for &item, index in values do item = read_theme_u64(input, offset + index * 8)
	if values[0] > u64(max(u8)) || values[1] > 1 || values[5] > 1 ||
	   values[2] > 255 || values[3] > 255 ||
	   values[4] > 255 || values[6] > 255 || values[7] > 255 || values[8] > 255 ||
	   values[9] > u64(max(u8)) {
		return {}, false
	}
	style = ui.Style_Definition {
		role = ui.Style_Role(values[0]),
		foreground = {
			present = values[1] == 1,
			color = {red = u8(values[2]), green = u8(values[3]), blue = u8(values[4])},
		},
		background = {
			present = values[5] == 1,
			color = {red = u8(values[6]), green = u8(values[7]), blue = u8(values[8])},
		},
		attributes = transmute(ui.Style_Attributes)u8(values[9]),
	}
	return style, ui.style_definition_is_valid(style)
}

@(private)
racket_theme_native_proposal :: proc(request: ^Decoded_Theme_Request) -> theme.Definition_Proposal {
	return theme.Definition_Proposal {
		identity = request.identity,
		display_name = request.display_name,
		provider_name = request.provider_name,
		provenance = request.provenance,
		styles = request.styles[:request.style_count],
	}
}

@(private)
racket_theme_encode_scope :: proc(
	destination: []u8,
	selection: theme.Selection,
	capability_generation: u64,
) -> (written: u64, ok: bool) {
	if len(destination) < int(bridge.THEME_SCOPE_RECORD_BYTES) do return 0, false
	values := [?]u64 {
		bridge.THEME_CAPABILITY_SCHEMA_VERSION,
		0xff,
		u64(selection.registry_id),
		u64(selection.registry_generation),
		u64(selection.selection_generation),
		u64(selection.active.provider_id),
		u64(selection.active.provider_generation),
		u64(selection.active.definition_id),
		u64(selection.active.definition_generation),
		u64(selection.fallback.provider_id),
		u64(selection.fallback.provider_generation),
		u64(selection.fallback.definition_id),
		u64(selection.fallback.definition_generation),
		u64(selection.baseline.provider_id),
		u64(selection.baseline.provider_generation),
		u64(selection.baseline.definition_id),
		u64(selection.baseline.definition_generation),
		capability_generation,
	}
	for item, index in values do write_theme_u64(destination, index * 8, item)
	return bridge.THEME_SCOPE_RECORD_BYTES, true
}

@(private)
racket_theme_decode_scope :: proc(input: []u8) -> (scope: bridge.Theme_Scope_Record, ok: bool) {
	if len(input) < int(bridge.THEME_SCOPE_RECORD_BYTES) do return {}, false
	fields := (^bridge.Theme_Scope_Record)(&scope)
	values := ([^]u64)(fields)[:18]
	for &item, index in values do item = read_theme_u64(input, index * 8)
	return scope, true
}

@(private)
racket_theme_scope_matches :: proc(
	expected: bridge.Theme_Scope_Record,
	current: theme.Selection,
	capability_generation: u64,
) -> bool {
	return expected.schema_version == bridge.THEME_CAPABILITY_SCHEMA_VERSION &&
	       expected.access == 0xff && expected.registry_id == u64(current.registry_id) &&
	       expected.registry_generation == u64(current.registry_generation) &&
	       expected.selection_generation == u64(current.selection_generation) &&
	       racket_theme_scope_handle_matches(expected, 0, current.active) &&
	       racket_theme_scope_handle_matches(expected, 1, current.fallback) &&
	       racket_theme_scope_handle_matches(expected, 2, current.baseline) &&
	       expected.capability_generation == capability_generation
}

@(private)
racket_theme_scope_handle_matches :: proc(
	scope: bridge.Theme_Scope_Record,
	which: int,
	handle: theme.Definition_Handle,
) -> bool {
	values := [3][4]u64 {
		{scope.active_provider_id, scope.active_provider_generation,
		 scope.active_definition_id, scope.active_definition_generation},
		{scope.fallback_provider_id, scope.fallback_provider_generation,
		 scope.fallback_definition_id, scope.fallback_definition_generation},
		{scope.baseline_provider_id, scope.baseline_provider_generation,
		 scope.baseline_definition_id, scope.baseline_definition_generation},
	}
	return values[which] == [4]u64 {
		u64(handle.provider_id), u64(handle.provider_generation),
		u64(handle.definition_id), u64(handle.definition_generation),
	}
}

@(private)
racket_theme_encode_outcome :: proc(
	destination: []u8,
	call: ^Racket_Theme_Call,
	operation: bridge.Theme_Capability_Operation,
	previous, definition: theme.Definition_Handle,
	selection: theme.Selection,
	capability_generation: u64,
) -> (written: u64, ok: bool) {
	if len(destination) != int(bridge.THEME_OUTCOME_RECORD_BYTES) do return 0, false
	_, scope_ok := racket_theme_encode_scope(destination, selection, capability_generation)
	if !scope_ok do return 0, false
	inspection, inspected, _ := theme.theme_registry_inspect(call.registry)
	if !inspected do return 0, false
	values := [?]u64 {
		u64(operation),
		u64(selection.state),
		u64(previous != selection.active || operation == .Propose || operation == .Confirm),
		u64(previous.provider_id),
		u64(previous.provider_generation),
		u64(previous.definition_id),
		u64(previous.definition_generation),
		u64(definition.provider_id),
		u64(definition.provider_generation),
		u64(definition.definition_id),
		u64(definition.definition_generation),
		u64(selection.active == selection.fallback),
		u64(selection.active == selection.baseline),
		inspection.usage.retained_definition_bytes,
		u64(call.calls),
	}
	for item, index in values do write_theme_u64(destination, 144 + index * 8, item)
	return bridge.THEME_OUTCOME_RECORD_BYTES, true
}

@(private)
racket_theme_encode_snapshot :: proc(
	destination: []u8,
	call: ^Racket_Theme_Call,
	selection: theme.Selection,
	capability_generation: u64,
	single: ^theme.Definition_View,
) -> (written: u64, ok: bool, failure: theme.Failure) {
	inspection, inspected, inspect_failure := theme.theme_registry_inspect(call.registry)
	if !inspected do return 0, false, inspect_failure
	provider_count := u64(inspection.usage.providers)
	definition_count := u64(inspection.usage.definitions)
	if single != nil {
		provider_count = 1
		definition_count = 1
	}
	style_count: u64
	text_bytes: u64
	if single != nil {
		provider, provider_ok, provider_failure := theme.theme_registry_provider(
			call.registry, single.descriptor.provider,
		)
		if !provider_ok do return 0, false, provider_failure
		style_count = u64(len(single.styles))
		text_bytes = u64(len(theme.provider_name_string(&provider.name)) +
		                 len(theme.theme_name_string(&single.descriptor.identity)) +
		                 len(theme.display_name_string(&single.descriptor.display_name)) +
		                 len(theme.provenance_text_string(&single.descriptor.provenance)))
	} else {
		for index in 0..<inspection.usage.providers {
			provider, provider_ok, provider_failure := theme.theme_registry_provider_at(
				call.registry, index,
			)
			if !provider_ok do return 0, false, provider_failure
			text_bytes += u64(len(theme.provider_name_string(&provider.name)))
		}
		for index in 0..<inspection.usage.definitions {
			view, view_ok, view_failure := theme.theme_registry_definition_at(call.registry, index)
			if !view_ok do return 0, false, view_failure
			style_count += u64(len(view.styles))
			text_bytes += u64(len(theme.theme_name_string(&view.descriptor.identity)) +
			                 len(theme.display_name_string(&view.descriptor.display_name)) +
			                 len(theme.provenance_text_string(&view.descriptor.provenance)))
		}
	}
	diagnostic_count: u64
	diagnostic_bytes: u64
	diagnostic_text := ""
	if inspection.latest_failure.code != .None {
		diagnostic_count = 1
		diagnostic_text = theme.failure_code_diagnostic(inspection.latest_failure.code)
		diagnostic_bytes = u64(len(diagnostic_text))
	}
	required, width_ok := bridge.theme_snapshot_record_bytes(
		provider_count, definition_count, style_count, diagnostic_count,
		text_bytes, diagnostic_bytes,
	)
	if !width_ok || required > u64(len(destination)) {
		return 0, false, theme.Failure {
			operation = .Inspect,
			code = .Inspection_Limit,
			limit = u64(len(destination)),
			actual = required,
		}
	}
	for &byte in destination[:int(required)] do byte = 0
	_, scope_ok := racket_theme_encode_scope(destination, selection, capability_generation)
	if !scope_ok do return 0, false, theme.Failure{operation = .Inspect, code = .Invalid_Registry}
	racket_theme_encode_usage(destination, 144, inspection.usage, call.calls)
	racket_theme_encode_limits(destination, 200, inspection.limits)
	header_values := [?]u64 {
		provider_count, definition_count, style_count, diagnostic_count,
		text_bytes, diagnostic_bytes,
	}
	for item, index in header_values do write_theme_u64(destination, 312 + index * 8, item)
	provider_base := bridge.THEME_SNAPSHOT_HEADER_BYTES
	definition_base := provider_base + provider_count * bridge.THEME_PROVIDER_RECORD_BYTES
	style_base := definition_base + definition_count * bridge.THEME_DEFINITION_RECORD_BYTES
	diagnostic_base := style_base + style_count * bridge.THEME_STYLE_RECORD_BYTES
	text_cursor := diagnostic_base + diagnostic_count * bridge.THEME_DIAGNOSTIC_RECORD_BYTES
	diagnostic_text_offset := text_cursor + text_bytes
	definition_cursor: u64
	style_cursor: u64
	if single != nil {
		provider, _, _ := theme.theme_registry_provider(call.registry, single.descriptor.provider)
		name := theme.provider_name_string(&provider.name)
		racket_theme_encode_provider(destination, int(provider_base), provider, text_cursor, 0, 1)
		copy(destination[int(text_cursor):], transmute([]u8)name)
		text_cursor += u64(len(name))
		racket_theme_encode_definition(
			destination, int(definition_base), single.descriptor,
			text_cursor, 0,
		)
		text_cursor = racket_theme_copy_definition_text(destination, text_cursor, single.descriptor)
		for style in single.styles {
			racket_theme_encode_style(destination, int(style_base + style_cursor * 80), style)
			style_cursor += 1
		}
	} else {
		for provider_index in 0..<inspection.usage.providers {
			provider, _, _ := theme.theme_registry_provider_at(call.registry, provider_index)
			provider_definition_count: u64
			for definition_index in 0..<inspection.usage.definitions {
				view, _, _ := theme.theme_registry_definition_at(call.registry, definition_index)
				if view.descriptor.provider == provider.handle do provider_definition_count += 1
			}
			name := theme.provider_name_string(&provider.name)
			racket_theme_encode_provider(
				destination,
				int(provider_base + u64(provider_index) * bridge.THEME_PROVIDER_RECORD_BYTES),
				provider,
				text_cursor,
				definition_cursor,
				provider_definition_count,
			)
			copy(destination[int(text_cursor):], transmute([]u8)name)
			text_cursor += u64(len(name))
			for definition_index in 0..<inspection.usage.definitions {
				view, _, _ := theme.theme_registry_definition_at(call.registry, definition_index)
				if view.descriptor.provider != provider.handle do continue
				racket_theme_encode_definition(
					destination,
					int(definition_base + definition_cursor * bridge.THEME_DEFINITION_RECORD_BYTES),
					view.descriptor,
					text_cursor,
					style_cursor,
				)
				text_cursor = racket_theme_copy_definition_text(destination, text_cursor, view.descriptor)
				for style in view.styles {
					racket_theme_encode_style(
						destination,
						int(style_base + style_cursor * bridge.THEME_STYLE_RECORD_BYTES),
						style,
					)
					style_cursor += 1
				}
				definition_cursor += 1
			}
		}
	}
	if diagnostic_count == 1 {
		racket_theme_encode_diagnostic(
			destination, int(diagnostic_base), inspection.latest_failure,
			diagnostic_text_offset, diagnostic_bytes,
		)
		copy(destination[int(diagnostic_text_offset):], transmute([]u8)diagnostic_text)
	}
	return required, true, {}
}

@(private)
racket_theme_encode_usage :: proc(
	destination: []u8, offset: int, usage: theme.Resource_Usage, calls: u16,
) {
	values := [?]u64 {
		u64(usage.providers), u64(usage.definitions), usage.retained_definition_bytes,
		usage.inspection_bytes, usage.preparation_peak_bytes, u64(calls), 1,
	}
	for item, index in values do write_theme_u64(destination, offset + index * 8, item)
}

@(private)
racket_theme_encode_limits :: proc(
	destination: []u8, offset: int, limits: theme.Resource_Limits,
) {
	values := [?]u64 {
		u64(limits.providers), u64(limits.definitions), u64(limits.theme_identity_bytes),
		u64(limits.display_name_bytes), u64(limits.provider_name_bytes),
		u64(limits.provenance_bytes), u64(limits.styles), limits.retained_definition_bytes,
		limits.proposal_bytes, u64(limits.operations_per_turn), limits.inspection_bytes,
		limits.preparation_bytes, limits.diagnostic_bytes, u64(limits.concurrent_hosted_turns),
	}
	for item, index in values do write_theme_u64(destination, offset + index * 8, item)
}

@(private)
racket_theme_encode_provider :: proc(
	destination: []u8, offset: int, provider: theme.Provider_Descriptor,
	name_offset, first_definition, definition_count: u64,
) {
	provider_name := provider.name
	name := theme.provider_name_string(&provider_name)
	values := [?]u64 {
		u64(provider.handle.provider_id), u64(provider.handle.provider_generation),
		u64(provider.kind), u64(provider.state), name_offset, u64(len(name)),
		first_definition, definition_count,
	}
	for item, index in values do write_theme_u64(destination, offset + index * 8, item)
}

@(private)
racket_theme_encode_definition :: proc(
	destination: []u8, offset: int, definition: theme.Definition_Descriptor,
	text_offset, first_style: u64,
) {
	descriptor := definition
	identity := theme.theme_name_string(&descriptor.identity)
	display_name := theme.display_name_string(&descriptor.display_name)
	provenance := theme.provenance_text_string(&descriptor.provenance)
	display_offset := text_offset + u64(len(identity))
	provenance_offset := display_offset + u64(len(display_name))
	values := [?]u64 {
		u64(definition.handle.provider_id), u64(definition.handle.provider_generation),
		u64(definition.handle.definition_id), u64(definition.handle.definition_generation),
		u64(definition.state), text_offset, u64(len(identity)), display_offset,
		u64(len(display_name)), provenance_offset, u64(len(provenance)), first_style,
		u64(definition.style_count), definition.retained_bytes,
	}
	for item, index in values do write_theme_u64(destination, offset + index * 8, item)
}

@(private)
racket_theme_copy_definition_text :: proc(
	destination: []u8, cursor: u64, definition: theme.Definition_Descriptor,
) -> u64 {
	descriptor := definition
	parts := [?]string {
		theme.theme_name_string(&descriptor.identity),
		theme.display_name_string(&descriptor.display_name),
		theme.provenance_text_string(&descriptor.provenance),
	}
	current := cursor
	for part in parts {
		copy(destination[int(current):], transmute([]u8)part)
		current += u64(len(part))
	}
	return current
}

@(private)
racket_theme_encode_style :: proc(destination: []u8, offset: int, style: ui.Style_Definition) {
	values := [?]u64 {
		u64(style.role), u64(style.foreground.present), u64(style.foreground.color.red),
		u64(style.foreground.color.green), u64(style.foreground.color.blue),
		u64(style.background.present), u64(style.background.color.red),
		u64(style.background.color.green), u64(style.background.color.blue),
		u64(transmute(u8)style.attributes),
	}
	for item, index in values do write_theme_u64(destination, offset + index * 8, item)
}

@(private)
racket_theme_encode_diagnostic :: proc(
	destination: []u8, offset: int, failure: theme.Failure,
	message_offset, message_bytes: u64,
) {
	values := [?]u64 {
		u64(failure.operation), u64(failure.code), u64(failure.provider.provider_id),
		u64(failure.provider.provider_generation), u64(failure.definition.definition_id),
		u64(failure.definition.definition_generation), 0, 0, failure.limit, failure.actual,
		message_offset, message_bytes,
	}
	for item, index in values do write_theme_u64(destination, offset + index * 8, item)
}

@(private)
racket_theme_restore_after_runtime_failure :: proc(call: ^Racket_Theme_Call) {
	selection, selected, _ := theme.theme_registry_selection(call.registry)
	if !selected || selection.active == selection.fallback do return
	provider_handle := theme.Provider_Handle {
		registry_id = selection.registry_id,
		provider_id = selection.active.provider_id,
		provider_generation = selection.active.provider_generation,
	}
	provider, provider_ok, _ := theme.theme_registry_provider(call.registry, provider_handle)
	if provider_ok && provider.kind == .Racket {
		_, _, _ = theme.theme_registry_fail_provider(call.registry, selection, provider_handle)
	}
}

@(private)
racket_theme_access :: proc(operation: bridge.Theme_Capability_Operation) -> u64 {
	access: bridge.Theme_Capability_Access
	switch operation {
	case .Inspect, .Inspect_Definition: access = .Inspect
	case .Propose: access = .Propose
	case .Confirm: access = .Confirm
	case .Select: access = .Select
	case .Replace: access = .Replace
	case .Restore: access = .Restore
	case .Select_Baseline: access = .Select_Baseline
	case .Teardown: access = .Teardown
	case .Scope: return 0
	}
	return u64(1) << (u64(access) - 1)
}

@(private)
racket_theme_native_operation :: proc(operation: bridge.Theme_Capability_Operation) -> theme.Operation {
	switch operation {
	case .Propose: return .Propose
	case .Confirm: return .Confirm
	case .Select: return .Select
	case .Replace: return .Replace
	case .Restore: return .Restore
	case .Select_Baseline: return .Select_Baseline
	case .Teardown: return .Close_Provider
	case .Scope, .Inspect, .Inspect_Definition: return .Inspect
	}
	return .Inspect
}

@(private)
racket_theme_reject :: proc(
	call: ^Racket_Theme_Call,
	failure: theme.Failure,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32 {
	call.failure = failure
	failure_code^ = u32(failure.code)
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
read_theme_u64 :: proc(input: []u8, offset: int) -> u64 {
	value, ok := endian.get_u64(input[offset:], .Little)
	assert(ok)
	return value
}

@(private)
write_theme_u64 :: proc(destination: []u8, offset: int, value: u64) {
	written := endian.put_u64(destination[offset:], .Little, value)
	assert(written)
}
