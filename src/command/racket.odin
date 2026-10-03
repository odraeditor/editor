// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../display"
import "../document"
import "../editor"
import "../editor_session"
import "../hosting"
import "../history"
import "../interaction"
import "../language"
import edit_transaction "../transaction"
import editor_view "../view"
import base_runtime "base:runtime"
import endian "core:encoding/endian"
import "core:strings"

@(private)
RACKET_COMMAND_SCENARIO :: i32(#config(ODRA_RACKET_COMMAND_SCENARIO, 0))

@(private) PERSONAL_COMMAND_MAX_SPLICES :: u64(4_096)
@(private) PERSONAL_COMMAND_MAX_TEXT_BYTES :: u64(8 * 1_024 * 1_024)
@(private) PERSONAL_COMMAND_MAX_TEMPORARY_BYTES :: u64(32 * 1_024 * 1_024)
@(private) PERSONAL_COMMAND_MAX_NESTED_DEPTH :: u64(8)
/* PERSONAL_COMMAND_MAX_RESULT_BYTES bounds one copied programmable result. */
PERSONAL_COMMAND_MAX_RESULT_BYTES :: 8 * 1_024 * 1_024

/* personal_command_transaction_limits narrows native ownership for one personal turn. */
personal_command_transaction_limits :: proc() -> edit_transaction.Limits {
	limits := edit_transaction.DEFAULT_LIMITS
	limits.splices = PERSONAL_COMMAND_MAX_SPLICES
	limits.text_bytes = PERSONAL_COMMAND_MAX_TEXT_BYTES
	limits.temporary_bytes = PERSONAL_COMMAND_MAX_TEMPORARY_BYTES
	limits.nested_command_depth = PERSONAL_COMMAND_MAX_NESTED_DEPTH
	return limits
}

@(private)
Racket_Transaction_Call :: struct {
	registry:            ^bridge.Transaction_Capability_Registry,
	capability:          bridge.Transaction_Capability,
	temporary_allocator: base_runtime.Allocator,
	failure:             bridge.Failure_Context,
	mutations:           u64,
	replacement_bytes:   u64,
	result_cursor:       u64,
	replacement:         [MAX_COMMAND_TEXT_BYTES + 1]u8,
}

/* Racket_Context contains checked owners and borrowed values for one programmable turn. */
Racket_Context :: struct {
	runtime:             ^hosting.Runtime,
	capabilities:        ^bridge.Buffer_Capability_Registry,
	transaction_capabilities: ^bridge.Transaction_Capability_Registry,
	command_registry:    ^interaction.Command_Registry,
	command:             interaction.Command_Handle,
	buffer:              ^editor.Buffer,
	document:            ^document.Document,
	session_owner:       ^editor_session.Session,
	session_handle:      editor_session.Session_Handle,
	view_registry:       ^editor_view.Registry,
	view:                 editor_view.View_Handle,
	profile:              display.Display_Profile,
	constraints:          display.Viewport_Constraints,
	temporary_allocator:  base_runtime.Allocator,
	persistent_allocator: base_runtime.Allocator,
	transaction_id:      edit_transaction.Transaction_ID,
	undo_unit_id:        edit_transaction.Undo_Unit_ID,
	history_store:       ^history.Store,
	commit_observer:     edit_transaction.Commit_Observer,
	personal_selection:  string,
	cancelled:            bool,
	argument_present:     bool,
	argument:             i64,
	repeat_count:         u64,
}

/* racket_command_execute runs one checked Racket view command and publishes at most once. */
racket_command_execute :: proc(
	request: Racket_Context,
) -> (result: Native_Result, ok: bool, failure: Failure_Context) {
	if request.runtime == nil || request.capabilities == nil ||
	   request.transaction_capabilities == nil ||
	   request.command_registry == nil || request.buffer == nil ||
	   request.view_registry == nil {
		return {}, false, Failure_Context{code = .Invalid_Command, command = request.command}
	}
	metadata, metadata_ok, metadata_failure := interaction.command_metadata(
		request.command_registry,
		request.command,
	)
	if !metadata_ok {
		return {}, false, Failure_Context {
			code = .Invalid_Command,
			command = request.command,
			interaction_code = metadata_failure.code,
		}
	}
	if metadata.implementation != .Racket {
		return {}, false, Failure_Context {
			code = .Wrong_Implementation,
			command = request.command,
		}
	}
	dispatch_class, route_operation, route_ok := racket_route_decode(metadata.route)
	if !route_ok || (dispatch_class != .Transaction && dispatch_class != .Personal) {
		return {}, false, Failure_Context {
			code = .Unknown_Native_Command,
			command = request.command,
		}
	}
	if request.cancelled {
		return {}, false, Failure_Context{code = .Cancelled, command = request.command}
	}
	if request.temporary_allocator.procedure == nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = request.command,
			limit = MAX_COMMAND_TEXT_BYTES * 2,
		}
	}
	temporary_probe, temporary_probe_error := make([]u8, 1, request.temporary_allocator)
	if temporary_probe_error != nil {
		return {}, false, Failure_Context {
			code = .Temporary_Memory_Limit,
			command = request.command,
			limit = MAX_COMMAND_TEXT_BYTES * 2,
			actual = 1,
		}
	}
	delete(temporary_probe, request.temporary_allocator)

	logical, logical_ok, logical_failure := editor_view.snapshot(
		request.view_registry,
		request.view,
	)
	if !logical_ok {
		return {}, false, native_view_failure(request.command, logical_failure)
	}
	preflight := validate_racket_view(request, logical)
	if preflight.code != .None {
		return {}, false, preflight
	}
	line, line_ok, line_failure := editor.buffer_line_at_position(
		request.buffer,
		logical.point_position,
	)
	if !line_ok {
		return {}, false, native_editor_failure(request.command, line_failure)
	}
	line_bytes := u64(line.content_end) - u64(line.start)
	if dispatch_class == .Transaction && line_bytes == 0 {
		return Native_Result{completion = .No_Op}, true, {}
	}
	if dispatch_class == .Transaction && line_bytes > MAX_COMMAND_TEXT_BYTES {
		return {}, false, Failure_Context {
			code = .Inspection_Limit,
			command = request.command,
			limit = MAX_COMMAND_TEXT_BYTES,
			actual = line_bytes,
		}
	}

	transaction: edit_transaction.Transaction
	transaction_limits := edit_transaction.DEFAULT_LIMITS
	if dispatch_class == .Personal {
		transaction_limits = personal_command_transaction_limits()
	}
	started, begin_failure := edit_transaction.transaction_begin(
		&transaction,
		request.transaction_id,
		request.undo_unit_id,
		request.buffer,
		edit_transaction.Origin{kind = .Racket, descriptor = "racket-command"},
		metadata.name,
		edit_transaction.Allocator_Set {
			persistent = request.persistent_allocator,
			temporary = request.temporary_allocator,
		},
		transaction_limits,
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
	command_id := u64(request.command.slot) + 1
	capability, acquired, acquire_failure := bridge.transaction_capability_acquire(
		request.transaction_capabilities,
		&transaction,
		request.buffer,
		command_id,
	)
	if !acquired {
		return {}, false, bridge_failure_context(
			Failure_Context{command = request.command},
			acquire_failure,
		)
	}
	call := Racket_Transaction_Call {
		registry = request.transaction_capabilities,
		capability = capability,
		temporary_allocator = request.temporary_allocator,
		result_cursor = u64(logical.point_position.byte_offset),
	}
	executed := false
	runtime_failure: hosting.Failure_Context
	personal_result: []u8
	personal_result_length: u64
	keep_personal_result := false
	defer if personal_result != nil && !keep_personal_result {
		delete(personal_result, request.temporary_allocator)
	}
	if dispatch_class == .Personal {
		personal_result_error: base_runtime.Allocator_Error
		personal_result, personal_result_error = make(
			[]u8,
			PERSONAL_COMMAND_MAX_RESULT_BYTES,
			request.temporary_allocator,
		)
		if personal_result_error != nil {
			return {}, false, Failure_Context {
				code = .Temporary_Memory_Limit,
				command = request.command,
				limit = PERSONAL_COMMAND_MAX_RESULT_BYTES,
			}
		}
		stats, stats_ok, stats_failure := editor.buffer_stats(request.buffer)
		if !stats_ok {
			return {}, false, native_editor_failure(request.command, stats_failure)
		}
		region_present := logical.region_active && logical.mark.present
		region_start, region_end := u64(0), u64(0)
		if region_present {
			point := u64(logical.point_position.byte_offset)
			mark := u64(logical.mark.position.byte_offset)
			region_start = min(point, mark)
			region_end = max(point, mark)
		}
		document_path := ""
		project_root := ""
		roots: editor_session.Root_Batch
		roots_open := false
		defer {
			if roots_open do editor_session.root_batch_close(&roots)
		}
		if request.document != nil {
			status, status_ok, _ := document.document_status(request.document)
			if status_ok && status.has_target {
				document_path = status.target_path
				if request.session_owner != nil {
					listed, roots_ok, _ := editor_session.session_roots(
						request.session_owner,
						request.session_handle,
					)
					if roots_ok {
						roots = listed
						roots_open = true
						for root in roots.descriptors {
							if root.kind == .Project &&
							   racket_path_contains(root.path, document_path) &&
							   len(root.path) > len(project_root) {
								project_root = root.path
							}
						}
					}
				}
			}
		}
		executed, runtime_failure = hosting.runtime_personal_command(
			request.runtime,
			u64(capability),
			command_id,
			metadata.name,
			document_path,
			project_root,
			request.personal_selection,
			u64(request.command.registry_generation),
			u64(route_operation),
			u64(logical.revision),
			u64(logical.point_position.byte_offset),
			region_present,
			region_start,
			region_end,
			u64(line.start),
			u64(line.content_end),
			stats.text_bytes,
			u64(transmute(u8)metadata.effects),
			request.cancelled,
			racket_transaction_callback,
			&call,
			personal_result,
			&personal_result_length,
		)
	} else {
		executed, runtime_failure = hosting.runtime_transaction_command(
			request.runtime,
			RACKET_COMMAND_SCENARIO,
			u64(capability),
			command_id,
			u64(line.start),
			u64(line.content_end),
			metadata.name,
			racket_transaction_callback,
			&call,
		)
	}
	released, release_failure := bridge.transaction_capability_release(
		request.transaction_capabilities,
		&capability,
	)
	if !released {
		return {}, false, bridge_failure_context(
			Failure_Context{command = request.command},
			release_failure,
		)
	}
	if !executed {
		return {}, false, hosting_failure_context(
			Failure_Context{command = request.command},
			runtime_failure,
		)
	}
	if call.failure.code != .None {
		return {}, false, racket_transaction_failure(request.command, call.failure)
	}
	if call.replacement_bytes > MAX_COMMAND_TEXT_BYTES {
		return {}, false, Failure_Context {
			code = .Wrong_Result,
			command = request.command,
			limit = MAX_COMMAND_TEXT_BYTES,
			actual = call.replacement_bytes,
		}
	}
	if call.mutations == 0 {
		if personal_result_length == 0 {
			return Native_Result{completion = .No_Op}, true, {}
		}
		keep_personal_result = true
		return Native_Result {
			completion = .No_Op,
			personal_result = personal_result[:int(personal_result_length)],
			personal_result_allocator = request.temporary_allocator,
		}, true, {}
	}
	replacement_text := string(call.replacement[:call.replacement_bytes])
	final_column, column_ok, column_failure := inserted_text_end_column(
		replacement_text,
		0,
		logical.tab_width,
		request.profile,
	)
	if !column_ok {
		column_failure.command = request.command
		return {}, false, column_failure
	}
	if request.cancelled {
		return {}, false, Failure_Context{code = .Cancelled, command = request.command}
	}

	target, target_ok, target_failure := edit_transaction.transaction_position(
		&transaction,
		editor.Byte_Offset(call.result_cursor),
	)
	if !target_ok {
		return {}, false, native_transaction_failure(request.command, target_failure)
	}
	view_prepared, view_failure := edit_transaction.transaction_prepare_logical_view(
		&transaction,
		request.view_registry,
		request.view,
		target,
		final_column,
		.Deactivate,
	)
	if !view_prepared {
		return {}, false, native_transaction_failure(request.command, view_failure)
	}
	if request.history_store != nil {
		tracked, track_failure := edit_transaction.transaction_track_history(
			&transaction,
			request.history_store,
			history.Grouping_Context{kind = .Independent},
		)
		if !tracked {
			return {}, false, native_transaction_failure(request.command, track_failure)
		}
	}
	validated, validation_failure := edit_transaction.transaction_validate(&transaction)
	if !validated {
		return {}, false, native_transaction_failure(request.command, validation_failure)
	}
	commit, committed, commit_failure := edit_transaction.transaction_commit(
		&transaction,
		request.commit_observer,
	)
	if !committed {
		return {}, false, native_transaction_failure(request.command, commit_failure)
	}
	finish_committed_view(
		Native_Context {
			command = request.command,
			buffer = request.buffer,
			view_registry = request.view_registry,
			view = request.view,
			profile = request.profile,
			constraints = request.constraints,
		},
		final_column,
	)
	owned_transaction := transaction
	transaction = {}
	return Native_Result {
		completion = .Buffer_Committed,
		transaction = owned_transaction,
		commit = commit,
	}, true, {}
}

@(private)
racket_path_contains :: proc(root, candidate: string) -> bool {
	if len(root) == 0 || len(candidate) == 0 do return false
	if root == candidate do return true
	if root == "/" do return strings.has_prefix(candidate, "/")
	return len(candidate) > len(root) && strings.has_prefix(candidate, root) &&
	       candidate[len(root)] == '/'
}

@(private)
racket_transaction_callback :: proc "c" (
	user_data: rawptr,
	kind: hosting.Scoped_Capability_Kind,
	generation, token, command_id: u64,
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
	call := (^Racket_Transaction_Call)(user_data)
	if call == nil || kind != .Transaction || generation == 0 ||
	   token != u64(call.capability) || output_length == nil ||
	   value == nil || failure_code == nil || limit == nil || actual == nil {
		return 2
	}
	output_length^ = 0
	value^ = 0
	failure_code^ = 0
	limit^ = 0
	actual^ = 0
	call.failure = {}
	ok := false
	failure: bridge.Failure_Context
	switch bridge.Transaction_Operation(operation) {
	case .Inspect:
		if (output == nil && output_capacity != 0) || output_capacity > u64(max(int)) {
			return 2
		}
		destination: []u8
		if output_capacity != 0 {
			destination = ([^]u8)(output)[:int(output_capacity)]
		}
		copied: u64
		copied, ok, failure = bridge.transaction_capability_inspect(
			call.registry,
			call.capability,
			command_id,
			arg0,
			arg1,
			destination,
		)
		output_length^ = copied
	case .Batch:
		record_bytes, record_bytes_ok := checked_mul_u64(
			arg0,
			bridge.TRANSACTION_EDIT_RECORD_BYTES,
		)
		if !record_bytes_ok || record_bytes != arg1 || record_bytes > input_length ||
		   arg0 > u64(max(int)) || input_length > u64(max(int)) ||
		   (input == nil && input_length != 0) {
			return racket_transaction_callback_reject(call, failure_code, limit, actual, .Malformed_Record)
		}
		records, allocation_error := make(
			[]bridge.Transaction_Edit_Record,
			int(arg0),
			call.temporary_allocator,
		)
		if allocation_error != nil {
			return racket_transaction_callback_reject(
				call, failure_code, limit, actual, .Temporary_Memory_Limit,
			)
		}
		defer delete(records, call.temporary_allocator)
		bytes := ([^]u8)(input)[:int(input_length)]
		for &record, index in records {
			offset := u64(index) * bridge.TRANSACTION_EDIT_RECORD_BYTES
			record.start = read_little_u64(bytes, offset)
			record.end = read_little_u64(bytes, offset + 8)
			record.replacement_offset = read_little_u64(bytes, offset + 16)
			record.replacement_bytes = read_little_u64(bytes, offset + 24)
		}
		replacements := bytes[record_bytes:]
		ok, failure = bridge.transaction_capability_apply_batch(
			call.registry,
			call.capability,
			command_id,
			records,
			replacements,
			call.temporary_allocator,
		)
		if ok {
			call.mutations += arg0
		}
	case .Splice:
		if (input == nil && input_length != 0) || input_length > u64(max(int)) {
			return 2
		}
		replacement := ""
		if input_length != 0 {
			replacement = string(([^]u8)(input)[:int(input_length)])
		}
		ok, failure = bridge.transaction_capability_splice(
			call.registry,
			call.capability,
			command_id,
			arg0,
			arg1,
			replacement,
		)
		if ok {
			call.mutations += 1
			call.replacement_bytes = input_length
			call.result_cursor = arg0 + input_length
			if input_length <= u64(len(call.replacement)) {
				copy(call.replacement[:input_length], transmute([]u8)replacement)
			}
		}
	case .Nested_Begin:
		if (input == nil && input_length != 0) || input_length > u64(max(int)) {
			return 2
		}
		origin_kind: edit_transaction.Origin_Kind
		switch arg0 {
		case 1: origin_kind = .Built_In
		case 2: origin_kind = .Racket
		case 3: origin_kind = .Language_Tool
		case 4: origin_kind = .External_Proposal
		case: return 2
		}
		command := ""
		if input_length != 0 {
			command = string(([^]u8)(input)[:int(input_length)])
		}
		nested: bridge.Nested_Transaction_Capability
		nested, ok, failure = bridge.transaction_capability_nested_begin(
			call.registry,
			call.capability,
			command_id,
			edit_transaction.Origin{kind = origin_kind, descriptor = "racket-facade"},
			command,
		)
		value^ = u64(nested)
	case .Nested_Succeed, .Nested_Fail:
		disposition := edit_transaction.Nested_Failure_Disposition.Invalid
		succeeded := operation == i32(bridge.Transaction_Operation.Nested_Succeed)
		if !succeeded {
			switch arg1 {
			case 1: disposition = .Handled
			case 2: disposition = .Unhandled
			case: return 2
			}
		}
		ok, failure = bridge.transaction_capability_nested_finish(
			call.registry,
			call.capability,
			command_id,
			bridge.Nested_Transaction_Capability(arg0),
			disposition,
			succeeded,
		)
	case .Abort:
		ok, failure = bridge.transaction_capability_request_abort(
			call.registry,
			call.capability,
			command_id,
		)
	case .Jan_Analyze:
		if (input == nil && input_length != 0) || input_length > u64(max(int)) ||
		   (output == nil && output_capacity != 0) || output_capacity > u64(max(int)) {
			return 2
		}
		source: []u8
		if input_length != 0 {
			source = ([^]u8)(input)[:int(input_length)]
		}
		destination: []u8
		if output_capacity != 0 {
			destination = ([^]u8)(output)[:int(output_capacity)]
		}
		encoded: u64
		encoded, ok, failure = racket_jan_analysis_encode(
			source,
			destination,
			command_id,
			call.temporary_allocator,
		)
		output_length^ = encoded
	case:
		return 2
	}
	if ok {
		return 0
	}
	call.failure = failure
	failure_code^ = u32(racket_transaction_failure_code(failure))
	limit^ = failure.limit
	actual^ = failure.actual
	return 1
}

@(private)
RACKET_JAN_ANALYSIS_MAGIC :: u64(0x4f4452414a414e31)
@(private)
RACKET_JAN_ANALYSIS_VERSION :: u64(1)
@(private)
RACKET_JAN_ANALYSIS_HEADER_BYTES :: u64(64)

@(private)
racket_jan_analysis_encode :: proc(
	source, destination: []u8,
	command_id: u64,
	allocator: base_runtime.Allocator,
) -> (written: u64, ok: bool, failure: bridge.Failure_Context) {
	if command_id == 0 || allocator.procedure == nil {
		return 0, false, bridge.Failure_Context{code = .Invalid_Capability}
	}
	language_name: language.Language_Name
	language_name.length = u16(copy(language_name.bytes[:], "jan"))
	configuration := language.jan_factory_configuration(1)
	scope := language.Jan_Analysis_Scope {
		buffer_id = editor.Buffer_ID(command_id),
		source_revision = 1,
		language = {id = 1, generation = 1, name = language_name},
		provider = {
			registry_id = 1,
			language_id = 1,
			provider_id = 1,
			provider_generation = 1,
		},
		selection_generation = 1,
		parser_generation = 1,
		grammar_generation = 1,
		configuration = configuration.identity,
		baseline = language.jan_factory_baseline(),
		analysis_generation = language.Jan_Analysis_Generation(command_id),
	}
	owner: language.Jan_Structural_Owner
	initialized, jan_failure := language.jan_structural_owner_init(&owner, 1, allocator)
	if !initialized {
		return 0, false, racket_jan_analysis_failure(jan_failure)
	}
	defer language.jan_structural_owner_close(&owner)
	limits := language.DEFAULT_JAN_RESOURCE_LIMITS
	limits.source_bytes = min(limits.source_bytes, max(u64(1), u64(len(source))))
	analysis: language.Jan_Structural_Analysis
	analyzed: bool
	analysis, analyzed, jan_failure = language.jan_structural_owner_analyze(
		&owner,
		source,
		scope,
		limits,
		allocator,
	)
	if !analyzed {
		return 0, false, racket_jan_analysis_failure(jan_failure)
	}
	defer language.jan_structural_analysis_close(&analysis)
	nodes := language.jan_structural_analysis_nodes(&analysis)
	attributes := language.jan_structural_analysis_attributes(&analysis)
	recoveries := language.jan_structural_analysis_recoveries(&analysis)
	indexes := language.jan_structural_analysis_indexes(&analysis)
	required := RACKET_JAN_ANALYSIS_HEADER_BYTES
	addition_ok := true
	for node in nodes {
		required, addition_ok = racket_checked_add_u64(
			required,
			80 + u64(node.kind_text.length),
		)
		if !addition_ok do return 0, false, bridge.Failure_Context{code = .Inspection_Limit}
	}
	for attribute in attributes {
		required, addition_ok = racket_checked_add_u64(
			required,
			48 + u64(attribute.name.length) + u64(attribute.value.length),
		)
		if !addition_ok do return 0, false, bridge.Failure_Context{code = .Inspection_Limit}
	}
	recovery_bytes, recovery_ok := checked_mul_u64(u64(len(recoveries)), 32)
	index_bytes, index_ok := checked_mul_u64(u64(len(indexes)), 40)
	if !recovery_ok || !index_ok {
		return 0, false, bridge.Failure_Context{code = .Inspection_Limit}
	}
	required, addition_ok = racket_checked_add_u64(required, recovery_bytes)
	if addition_ok do required, addition_ok = racket_checked_add_u64(required, index_bytes)
	if !addition_ok || required > u64(len(destination)) {
		return 0, false, bridge.Failure_Context {
			code = .Inspection_Limit,
			limit = u64(len(destination)),
			actual = required,
		}
	}
	cursor := 0
	racket_jan_put_words(destination, &cursor, []u64 {
		RACKET_JAN_ANALYSIS_MAGIC,
		RACKET_JAN_ANALYSIS_VERSION,
		u64(len(source)),
		u64(scope.analysis_generation),
		u64(len(nodes)),
		u64(len(attributes)),
		u64(len(recoveries)),
		u64(len(indexes)),
	})
	for node in nodes {
		racket_jan_put_words(destination, &cursor, []u64 {
			u64(node.id), u64(node.parent_id), u64(node.layer), u64(node.kind),
			u64(node.range.start), u64(node.range.end),
			u64(node.structural_depth), u64(node.inline_depth),
			u64(node.attribute_count), u64(node.kind_text.length),
		})
		kind_text := node.kind_text
		cursor += copy(destination[cursor:], kind_text.bytes[:int(kind_text.length)])
	}
	for attribute in attributes {
		racket_jan_put_words(destination, &cursor, []u64 {
			u64(attribute.node_id), u64(attribute.kind),
			u64(attribute.range.start), u64(attribute.range.end),
			u64(attribute.name.length), u64(attribute.value.length),
		})
		name := attribute.name
		value := attribute.value
		cursor += copy(destination[cursor:], name.bytes[:int(name.length)])
		cursor += copy(destination[cursor:], value.bytes[:int(value.length)])
	}
	for recovery in recoveries {
		racket_jan_put_words(destination, &cursor, []u64 {
			u64(recovery.node_id), u64(recovery.code),
			u64(recovery.range.start), u64(recovery.range.end),
		})
	}
	for fact in indexes {
		racket_jan_put_words(destination, &cursor, []u64 {
			u64(fact.id), u64(fact.kind), u64(fact.node_id),
			u64(fact.range.start), u64(fact.range.end),
		})
	}
	assert(u64(cursor) == required)
	return required, true, {}
}

@(private)
racket_jan_put_words :: proc(destination: []u8, cursor: ^int, words: []u64) {
	assert(cursor != nil)
	for word in words {
		assert(cursor^ >= 0 && cursor^ + 8 <= len(destination))
		assert(endian.put_u64(destination[cursor^:], .Little, word))
		cursor^ += 8
	}
}

@(private)
racket_checked_add_u64 :: proc(left, right: u64) -> (u64, bool) {
	if right > max(u64) - left do return 0, false
	return left + right, true
}

@(private)
racket_jan_analysis_failure :: proc(failure: language.Jan_Failure) -> bridge.Failure_Context {
	result := bridge.Failure_Context{limit = failure.limit, actual = failure.actual}
	#partial switch failure.code {
	case .Malformed: result.code = .Malformed_Text
	case .Limited, .Timeout: result.code = .Inspection_Limit
	case .Cancelled: result.code = .Cancelled
	case .Allocation_Failed: result.code = .Temporary_Memory_Limit
	case: result.code = .Malformed_Record
	}
	return result
}

@(private)
racket_transaction_callback_reject :: proc(
	call: ^Racket_Transaction_Call,
	failure_code: ^u32,
	limit, actual: ^u64,
	code: bridge.Failure_Code,
) -> i32 {
	call.failure = bridge.Failure_Context{code = code}
	failure_code^ = u32(racket_transaction_failure_code(call.failure))
	limit^ = call.failure.limit
	actual^ = call.failure.actual
	return 1
}

@(private)
racket_transaction_failure_code :: proc(failure: bridge.Failure_Context) -> edit_transaction.Failure_Code {
	if failure.code == .Transaction_Failure {
		return failure.transaction_code
	}
	#partial switch failure.code {
	case .Temporary_Memory_Limit: return .Temporary_Memory_Limit
	case .Cancelled: return .Cancelled
	case .Malformed_Text: return .Malformed_UTF8
	case .Malformed_Record: return .Changeset_Mismatch
	case .Wrong_Thread, .Reentrant_Call: return .Reentrant_Mutation
	case: return .Invalid_State
	}
}

@(private)
racket_transaction_failure :: proc(
	command: interaction.Command_Handle,
	failure: bridge.Failure_Context,
) -> Failure_Context {
	result := bridge_failure_context(Failure_Context{command = command}, failure)
	result.transaction_code = racket_transaction_failure_code(failure)
	#partial switch result.transaction_code {
	case .Malformed_UTF8: result.code = .Malformed_Text
	case .Temporary_Memory_Limit: result.code = .Temporary_Memory_Limit
	case .Text_Limit: result.code = .Text_Limit
	case .Cancelled: result.code = .Cancelled
	case: result.code = .Publication_Failure
	}
	return result
}

@(private)
read_little_u64 :: proc(bytes: []u8, offset: u64) -> u64 {
	assert(offset <= u64(len(bytes)) && u64(len(bytes)) - offset >= 8)
	result := u64(0)
	for index in 0 ..< 8 {
		result |= u64(bytes[offset + u64(index)]) << (u64(index) * 8)
	}
	return result
}

@(private)
checked_mul_u64 :: proc(left, right: u64) -> (u64, bool) {
	if left != 0 && right > max(u64) / left {
		return 0, false
	}
	return left * right, true
}

@(private)
validate_racket_view :: proc(
	request: Racket_Context,
	logical: editor_view.Snapshot,
) -> Failure_Context {
	stats, stats_ok, stats_failure := editor.buffer_stats(request.buffer)
	if !stats_ok {
		return native_editor_failure(request.command, stats_failure)
	}
	if stats.buffer_id != logical.buffer_id || stats.revision != logical.revision {
		return Failure_Context {
			code = .View_Failure,
			command = request.command,
			view_code = .Editor_Failure,
			editor_code = .Stale_Revision,
		}
	}
	native_request := Native_Context {
		command = request.command,
		temporary_allocator = request.temporary_allocator,
		profile = request.profile,
		constraints = request.constraints,
	}
	return validate_display_request(native_request, logical, 2, true)
}

@(private)
bytes_equal :: proc(left, right: []u8) -> bool {
	if len(left) != len(right) {
		return false
	}
	for value, index in left {
		if value != right[index] {
			return false
		}
	}
	return true
}
