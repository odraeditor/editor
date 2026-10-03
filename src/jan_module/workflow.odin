// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_module

import "../editor"
import "../jan_computation"
import "../jan_editing"
import "../jan_output"
import "../jan_planning"
import "../language"
import "../product_module"
import "core:fmt"
import "core:strings"
import "../ui"
import editor_view "../view"

JAN_MODULE_ACTION_OWNER :: u64(0x4F44_5241_4A41_4E00)

Document_Snapshot :: struct {
	storage:  []u8,
	header:   product_module.Document_Snapshot_Header,
	source:   []u8,
	hidden_ranges: []product_module.Document_Range,
	owner:    language.Jan_Structural_Owner,
	analysis: language.Jan_Structural_Analysis,
	scope:    language.Jan_Analysis_Scope,
}

@(private)
workflow_init :: proc(state: ^Module_Instance) -> bool {
	if state == nil do return false
	if state.next_operation_id != 0 do return true
	initialized, _ := jan_editing.editing_configuration_init(
		&state.configuration, 1, 1,
	)
	if !initialized do return false
	planning_initialized, _ := jan_planning.planning_configuration_init(
		&state.planning_configuration, 1, 1,
	)
	if !planning_initialized {
		jan_editing.editing_configuration_close(&state.configuration)
		return false
	}
	workflow_states := [3]jan_planning.Workflow_State_Candidate {
		{name = "TODO", fast_key = 't', presentation = .Todo, log = .None},
		{name = "NEXT", fast_key = 'n', presentation = .Active, log = .None},
		{name = "DONE", finished = true, fast_key = 'd', presentation = .Done, log = .None},
	}
	workflows := [1]jan_planning.Workflow_Candidate {
		{identity = "default", states = workflow_states[:]},
	}
	_, planning_published, _ := jan_planning.planning_configuration_publish(
		&state.planning_configuration,
		{
			generation = 2,
			provider_generation = 1,
			workflows = workflows[:],
		},
	)
	if !planning_published {
		jan_planning.planning_configuration_close(&state.planning_configuration)
		jan_editing.editing_configuration_close(&state.configuration)
		return false
	}
	computation_initialized, _ := jan_computation.computation_configuration_init(
		&state.computation_configuration, 1, 1, 1,
	)
	if !computation_initialized {
		jan_planning.planning_configuration_close(&state.planning_configuration)
		jan_editing.editing_configuration_close(&state.configuration)
		return false
	}
	state.next_operation_id = 1
	state.next_rewrite_id = 1
	state.local_visibility = .Complete_Subtree
	state.global_visibility = .Show_All
	return true
}

@(private)
workflow_close :: proc(state: ^Module_Instance) {
	if state == nil || state.next_operation_id == 0 do return
	jan_computation.computation_configuration_close(&state.computation_configuration)
	jan_planning.planning_configuration_close(&state.planning_configuration)
	jan_editing.editing_configuration_close(&state.configuration)
	state.next_operation_id = 0
	state.next_rewrite_id = 0
	state.surface_target = 0
	state.surface_active = false
	state.surface_point_selection = false
	state.surface_revision = 0
	state.surface_point_count = 0
	state.surface_points = {}
}

@(private)
module_diagnostic :: proc(state: ^Module_Instance, message: string) {
	if state == nil || state.host_call == nil do return
	bytes := transmute([]u8)message
	_ = state.host_call(
		state.capability, .Diagnostic, raw_data(bytes), u64(len(bytes)), nil, 0, nil,
	)
}

@(private)
module_session_request :: proc(
	state: ^Module_Instance,
	action: product_module.Session_Action,
	target: u64,
	payload: string = "",
) -> (product_module.Session_Response, bool) {
	header := product_module.Session_Request_Header {
		schema_version = product_module.SESSION_REQUEST_SCHEMA_VERSION,
		action = action,
		target = target,
		payload_length = u64(len(payload)),
	}
	request, allocation_error := make([]u8, size_of(header) + len(payload))
	if allocation_error != nil do return {}, false
	defer delete(request)
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(request[size_of(header):], transmute([]u8)payload)
	response: product_module.Session_Response
	written: u64
	status := state.host_call(
		state.capability, .Session, raw_data(request), u64(len(request)),
		cast(^u8)rawptr(&response), size_of(response), &written,
	)
	return response, status == .Ok && written == size_of(response)
}

@(private)
workflow_present_surface :: proc(state: ^Module_Instance, title: string, rows: []string) -> bool {
	if state == nil || len(title) == 0 || len(rows) == 0 do return false
	row_count := len(rows) + 1
	text_bytes := len(title)
	for row in rows do text_bytes += len(row)
	header_bytes := size_of(product_module.UI_List_Header)
	rows_bytes := row_count * size_of(product_module.UI_List_Row)
	if u64(header_bytes + rows_bytes + text_bytes) > product_module.MAX_CALL_BYTES do return false
	request, allocation_error := make([]u8, header_bytes + rows_bytes + text_bytes)
	if allocation_error != nil do return false
	defer delete(request)
	state.presentation_generation += 1
	if state.presentation_generation == 0 do state.presentation_generation = 1
	header := product_module.UI_List_Header {
		schema_version = product_module.UI_LIST_SCHEMA_VERSION,
		row_count = u32(row_count),
		presentation_generation = state.presentation_generation,
		current_item = 1,
		viewport_items = u32(row_count),
		selection_owner = u8(ui.Selection_Owner.View),
		text_bytes = u64(text_bytes),
	}
	copy(request[:header_bytes], ([^]u8)(rawptr(&header))[:header_bytes])
	text_offset := 0
	for index in 0 ..< row_count {
		text := title if index == 0 else rows[index - 1]
		row := product_module.UI_List_Row {
			id = u64(index + 1),
			text_offset = u64(text_offset),
			text_length = u32(len(text)),
			icon_role = u8(ui.List_Icon_Role.Textual),
			icon_style_role = u8(ui.Style_Role.List_Normal),
			passive = 1 if index == 0 else 0,
		}
		if index > 0 {
			row.action_owner_id = JAN_MODULE_ACTION_OWNER
			row.action_id = row.id
			row.action_generation = state.presentation_generation
		}
		row_start := header_bytes + index * size_of(product_module.UI_List_Row)
		copy(request[row_start:row_start + size_of(row)], ([^]u8)(rawptr(&row))[:size_of(row)])
		copy(request[header_bytes + rows_bytes + text_offset:], transmute([]u8)text)
		text_offset += len(text)
	}
	if state.host_call(
		state.capability, .UI, raw_data(request), u64(len(request)), nil, 0, nil,
	) != .Ok {
		return false
	}
	response, presented := module_session_request(state, .Present_Surface, 0, "structured-document.results")
	if !presented do return false
	state.surface_target = response.target
	state.surface_active = true
	return true
}

@(private)
workflow_input :: proc(state: ^Module_Instance, input: []u8) -> product_module.Status {
	if state == nil || !state.active || !state.surface_active ||
	   len(input) < size_of(product_module.Input_Request_Header) {
		return .Unavailable
	}
	header := (^product_module.Input_Request_Header)(raw_data(input))
	if header.schema_version != product_module.INPUT_REQUEST_SCHEMA_VERSION ||
	   int(header.text_length) != len(input) - size_of(product_module.Input_Request_Header) {
		return .Invalid_Argument
	}
	if header.kind != .Key do return .Ok
	if header.key_kind == .Enter || header.key_kind == .Escape {
		return workflow_restore_surface(state)
	}
	if header.key_kind == .Unicode_Scalar && header.modifiers == 0 &&
	   (header.scalar == 'q' || header.scalar == 'Q') {
		return workflow_restore_surface(state)
	}
	return .Ok
}

@(private)
workflow_restore_surface :: proc(state: ^Module_Instance) -> product_module.Status {
	if state == nil || !state.surface_active || state.surface_target == 0 do return .Unavailable
	_, restored := module_session_request(state, .Restore_Target, state.surface_target)
	if restored {
		state.surface_target = 0
		state.surface_active = false
		state.surface_point_selection = false
		state.surface_revision = 0
		state.surface_point_count = 0
		state.surface_points = {}
	}
	return .Ok if restored else .Failed
}

@(private)
workflow_select_surface :: proc(state: ^Module_Instance, item_id: u64) -> product_module.Status {
	if state == nil || !state.surface_active do return .Unavailable
	if !state.surface_point_selection do return workflow_restore_surface(state)
	if item_id < 2 || item_id - 2 >= u64(state.surface_point_count) do return .Invalid_Argument
	request := product_module.Document_Request_Header {
		schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
		action = .Move_Point,
		base_revision = state.surface_revision,
		point = state.surface_points[item_id - 2],
	}
	moved := state.host_call(
		state.capability, .Document, cast(^u8)rawptr(&request), size_of(request), nil, 0, nil,
	) == .Ok
	if !moved {
		module_diagnostic(state, "Jan named target rejected: document changed")
		return .Ok
	}
	_ = workflow_restore_surface(state)
	module_diagnostic(state, "Jan named target visited")
	return .Ok
}

@(private)
document_snapshot_open :: proc(state: ^Module_Instance, snapshot: ^Document_Snapshot) -> bool {
	if state == nil || snapshot == nil do return false
	request := product_module.Document_Request_Header {
		schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
		action = .Inspect,
	}
	storage, allocation_error := make([]u8, int(product_module.MAX_CALL_BYTES))
	if allocation_error != nil do return false
	written: u64
	status := state.host_call(
		state.capability,
		.Document,
		cast(^u8)rawptr(&request),
		size_of(request),
		raw_data(storage),
		u64(len(storage)),
		&written,
	)
	if status != .Ok || written < u64(size_of(product_module.Document_Snapshot_Header)) {
		delete(storage)
		return false
	}
	header := (^product_module.Document_Snapshot_Header)(raw_data(storage))^
	range_bytes := u64(header.hidden_range_count) * u64(size_of(product_module.Document_Range))
	if header.schema_version != product_module.DOCUMENT_REQUEST_SCHEMA_VERSION ||
	   header.hidden_range_count > editor_view.MAX_HIDDEN_RANGES ||
	   header.source_length + range_bytes != written - u64(size_of(header)) {
		delete(storage)
		return false
	}
	hidden_ranges, ranges_error := make([]product_module.Document_Range, int(header.hidden_range_count))
	if ranges_error != nil {
		delete(storage)
		return false
	}
	ranges_owned := true
	defer if ranges_owned && hidden_ranges != nil do delete(hidden_ranges)
	range_start := size_of(header) + int(header.source_length)
	for index in 0 ..< int(header.hidden_range_count) {
		offset := range_start + index * size_of(product_module.Document_Range)
		copy(
			([^]u8)(rawptr(&hidden_ranges[index]))[:size_of(product_module.Document_Range)],
			storage[offset:offset + size_of(product_module.Document_Range)],
		)
	}
	registration, registered := language.factory_bundle_registration(language.FACTORY_JAN_BUNDLE_IDENTITY)
	if !registered {
		delete(storage)
		return false
	}
	configuration := language.jan_factory_configuration(1)
	scope := language.Jan_Analysis_Scope {
		buffer_id = editor.Buffer_ID(header.buffer_id),
		source_revision = editor.Revision(header.revision),
		language = registration.language,
		provider = {registry_id = 1, language_id = registration.language.id, provider_id = 1, provider_generation = 1},
		selection_generation = 1,
		parser_generation = 1,
		grammar_generation = 1,
		configuration = configuration.identity,
		baseline = language.jan_factory_baseline(),
		analysis_generation = 1,
	}
	owner: language.Jan_Structural_Owner
	owner_ok, _ := language.jan_structural_owner_init(&owner, scope.parser_generation)
	if !owner_ok {
		delete(storage)
		return false
	}
	source := storage[size_of(header):size_of(header) + int(header.source_length)]
	analysis, analyzed, _ := language.jan_structural_owner_analyze(&owner, source, scope)
	if !analyzed {
		language.jan_structural_owner_close(&owner)
		delete(storage)
		return false
	}
	snapshot^ = {
		storage = storage,
		header = header,
			source = source,
			hidden_ranges = hidden_ranges,
		owner = owner,
		analysis = analysis,
		scope = scope,
	}
	ranges_owned = false
	return true
}

@(private)
document_snapshot_close :: proc(snapshot: ^Document_Snapshot) {
	if snapshot == nil do return
	if snapshot.analysis.state != nil do language.jan_structural_analysis_close(&snapshot.analysis)
	if snapshot.owner.state != nil do language.jan_structural_owner_close(&snapshot.owner)
	if snapshot.hidden_ranges != nil do delete(snapshot.hidden_ranges)
	if snapshot.storage != nil do delete(snapshot.storage)
	snapshot^ = {}
}

@(private)
editing_scope :: proc(state: ^Module_Instance, snapshot: ^Document_Snapshot) -> (jan_editing.Scope, bool) {
	descriptor, configured := jan_editing.editing_configuration_inspect(&state.configuration)
	if !configured do return {}, false
	return {
		analysis = snapshot.scope,
		view_handle = {registry_id = 1, view_id = 1, generation = 1},
		view_state_generation = snapshot.header.view_generation,
		visibility_generation = editor_view.Visibility_Generation(snapshot.header.visibility_generation),
		configuration_generation = descriptor.generation,
		provider_generation = descriptor.provider_generation,
	}, true
}

@(private)
document_move_point :: proc(state: ^Module_Instance, snapshot: ^Document_Snapshot, point: editor.Byte_Offset) -> bool {
	request := product_module.Document_Request_Header {
		schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
		action = .Move_Point,
		base_revision = snapshot.header.revision,
		point = u64(point),
	}
	return state.host_call(
		state.capability, .Document,
		cast(^u8)rawptr(&request), size_of(request),
		nil, 0, nil,
	) == .Ok
}

@(private)
document_apply_plan :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	plan: ^language.Jan_Rewrite_Plan,
) -> bool {
	batch := language.jan_rewrite_plan_transaction_batch(plan)
	if len(batch) == 0 do return false
	text_bytes: u64
	for splice in batch do text_bytes += u64(len(splice.replacement))
	row_bytes := u64(len(batch)) * u64(size_of(product_module.Document_Splice))
	total := u64(size_of(product_module.Document_Request_Header)) + row_bytes + text_bytes
	if total > product_module.MAX_CALL_BYTES || total > u64(max(int)) do return false
	request, allocation_error := make([]u8, int(total))
	if allocation_error != nil do return false
	defer delete(request)
	header := product_module.Document_Request_Header {
		schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
		action = .Apply_Rewrite,
		base_revision = snapshot.header.revision,
		point = snapshot.header.point,
		count = u32(len(batch)),
		payload_length = row_bytes + text_bytes,
	}
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	text_cursor := u64(0)
	text_start := u64(size_of(header)) + row_bytes
	for splice, index in batch {
		row := product_module.Document_Splice {
			start = u64(splice.start.byte_offset),
			end = u64(splice.end.byte_offset),
			text_offset = text_cursor,
			text_length = u64(len(splice.replacement)),
		}
		row_start := size_of(header) + index * size_of(product_module.Document_Splice)
		copy(request[row_start:row_start + size_of(row)], ([^]u8)(rawptr(&row))[:size_of(row)])
		copy(request[int(text_start + text_cursor):], transmute([]u8)splice.replacement)
		text_cursor += u64(len(splice.replacement))
	}
	return state.host_call(
		state.capability, .Document, raw_data(request), u64(len(request)), nil, 0, nil,
	) == .Ok
}

@(private)
document_apply_splice :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	start, end: u64,
	replacement: string,
) -> bool {
	if state == nil || snapshot == nil || start > end || end > u64(len(snapshot.source)) do return false
	row_bytes := size_of(product_module.Document_Splice)
	total := size_of(product_module.Document_Request_Header) + row_bytes + len(replacement)
	if u64(total) > product_module.MAX_CALL_BYTES do return false
	request, allocation_error := make([]u8, total)
	if allocation_error != nil do return false
	defer delete(request)
	header := product_module.Document_Request_Header {
		schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
		action = .Apply_Rewrite,
		base_revision = snapshot.header.revision,
		point = start + u64(len(replacement)),
		count = 1,
		payload_length = u64(row_bytes + len(replacement)),
	}
	row := product_module.Document_Splice {
		start = start,
		end = end,
		text_length = u64(len(replacement)),
	}
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	copy(
		request[size_of(header):size_of(header) + row_bytes],
		([^]u8)(rawptr(&row))[:row_bytes],
	)
	copy(request[size_of(header) + row_bytes:], transmute([]u8)replacement)
	return state.host_call(
		state.capability, .Document, raw_data(request), u64(len(request)), nil, 0, nil,
	) == .Ok
}

@(private)
workflow_invoke :: proc(state: ^Module_Instance, input: []u8) -> product_module.Status {
	if len(input) < size_of(product_module.Invocation_Request_Header) do return .Invalid_Argument
	header := (^product_module.Invocation_Request_Header)(raw_data(input))
	if header.schema_version != product_module.INVOCATION_REQUEST_SCHEMA_VERSION ||
	   header.name_length == 0 || size_of(product_module.Invocation_Request_Header) + int(header.name_length) != len(input) {
		return .Invalid_Argument
	}
	name := string(input[size_of(product_module.Invocation_Request_Header):])
	if !strings.has_prefix(name, "jan-") do return .Unavailable
	snapshot: Document_Snapshot
	if !document_snapshot_open(state, &snapshot) {
		module_diagnostic(state, "Jan command rejected: active structured document is unavailable")
		return .Ok
	}
	defer document_snapshot_close(&snapshot)
	return workflow_dispatch(state, &snapshot, name)
}

@(private)
workflow_dispatch :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	route: string,
) -> product_module.Status {
	scope, scoped := editing_scope(state, snapshot)
	if !scoped do return .Failed
	operation_id := jan_editing.Operation_ID(state.next_operation_id)
	state.next_operation_id += 1
	if route == "jan-context-meta-up" || route == "jan-context-meta-down" {
		if _, source_found, _ := jan_computation.babel_source_block_at(
			string(snapshot.source), int(snapshot.header.point),
		); source_found {
			if route == "jan-context-meta-up" {
				module_diagnostic(state, "Jan session unavailable: no adapter session is configured; source preserved")
			} else {
				module_diagnostic(state, "Jan session unavailable: no adapter session is configured; source preserved")
			}
			return .Ok
		}
		structural_route := "jan-move-subtree-up"
		if route == "jan-context-meta-down" do structural_route = "jan-move-subtree-down"
		return workflow_rewrite(state, snapshot, scope, structural_route, operation_id)
	}
	if result, handled := workflow_babel_utility(state, snapshot, route); handled do return result
	if kind, navigation := navigation_kind(route); navigation {
		request := jan_editing.Navigation_Request {
			scope = scope,
			kind = kind,
			point = {
				buffer_id = snapshot.scope.buffer_id,
				revision = snapshot.scope.source_revision,
				byte_offset = editor.Byte_Offset(snapshot.header.point),
			},
		}
		result, resolved, failure := jan_editing.navigation_resolve(
			&snapshot.analysis, u64(len(snapshot.source)), request,
		)
		if !resolved {
			module_diagnostic(state, fmt.tprintf("Jan navigation rejected: %v", failure.code))
		} else if result.status == .No_Target {
			module_diagnostic(state, "Jan navigation: no target")
		} else if document_move_point(state, snapshot, result.position.byte_offset) {
			module_diagnostic(state, fmt.tprintf("Jan navigation: %v offset=%d", kind, result.position.byte_offset))
		} else {
			module_diagnostic(state, "Jan navigation rejected: document changed")
		}
		return .Ok
	}
	if route_changes_source(route) {
		return workflow_rewrite(state, snapshot, scope, route, operation_id)
	}
	if route == "jan-toggle-drawer" || route == "jan-cycle" || route == "jan-global-cycle" ||
	   route == "jan-show-overview" || route == "jan-show-contents" || route == "jan-show-all" {
		return workflow_visibility(state, snapshot, scope, route, operation_id)
	}
	switch route {
	case "jan-inspect-syntax":
		nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
		target, found := deepest_node(nodes, editor.Byte_Offset(snapshot.header.point))
		if found {
			module_diagnostic(state, fmt.tprintf("Jan syntax: node=%v depth=%d", target.kind, target.structural_depth))
		} else {
			module_diagnostic(state, "Jan syntax: no structural node at point")
		}
	case "jan-lint", "jan-lint-refresh":
		module_diagnostic(state, fmt.tprintf("Jan lint: recoveries=%d", len(language.jan_structural_analysis_recoveries(&snapshot.analysis))))
	case "jan-language-status":
		module_diagnostic(state, "Jan language: structured analysis is available")
	case "jan-present":
		module_diagnostic(state, "Jan presentation: terminal-source=true")
	case "jan-inspect-availability":
		records := language.jan_capability_availability()
		available, unavailable := 0, 0
		for record in records {
			if record.available do available += 1
			if !record.available do unavailable += 1
		}
		module_diagnostic(
			state,
			fmt.tprintf(
				"Jan availability: operational=%d optional-unavailable=%d future-stage=0 total=%d",
				available, unavailable, len(records),
			),
		)
	case "jan-context-action":
		if _, source_found, _ := jan_computation.babel_source_block_at(
			string(snapshot.source), int(snapshot.header.point),
		); source_found {
			workflow_report_execution_feedback(state, snapshot, "jan-execute")
		} else if workflow_toggle_checkbox(state, snapshot, false) {
			return .Ok
		} else {
			module_diagnostic(state, "Jan context: no deterministic action at point")
		}
	case "jan-planning-status":
		descriptor, ok := jan_planning.planning_configuration_inspect(&state.planning_configuration)
		if ok {
			records := jan_planning.planning_capability_availability(
				descriptor.provider_generation, false, false,
			)
			available, unavailable := planning_availability_counts(records[:])
			module_diagnostic(
				state,
				fmt.tprintf(
					"Jan planning: generation=%d provider=%d available=%d optional-unavailable=%d workflows=%d",
					descriptor.generation, descriptor.provider_generation, available, unavailable,
					descriptor.workflow_count,
				),
			)
		}
	case "jan-agenda", "jan-agenda-refresh":
		workflow_present_agenda(state, snapshot)
	case "jan-computation-status":
		descriptor, ok := jan_computation.computation_configuration_inspect(&state.computation_configuration)
		if ok {
			records := jan_computation.computation_capability_availability({language_ready = true})
			available, unavailable := computation_availability_counts(records[:])
			module_diagnostic(
				state,
				fmt.tprintf(
					"Jan computation: generation=%d adapters=%d policies=%d available=%d optional-unavailable=%d",
					descriptor.generation, descriptor.adapter_count, descriptor.policy_count,
					available, unavailable,
				),
			)
		}
	case "jan-table-debug-formula":
		workflow_present_formula(state, snapshot)
	case "jan-output-status", "jan-provider-status", "jan-extension-status":
		label := "output"
		if route == "jan-provider-status" do label = "providers"
		if route == "jan-extension-status" do label = "extensions"
		module_diagnostic(
			state,
			fmt.tprintf(
				"Jan %s: native=5 optional-unavailable=12 provider-generation=1 extension-generation=0 source-preserved=true",
				label,
			),
		)
	case "jan-export", "jan-export-normalized-jan", "jan-export-plain-text", "jan-export-html", "jan-export-markdown":
		workflow_render_native(state, snapshot, route)
	case "jan-execute", "jan-execute-subtree", "jan-execute-buffer", "jan-execute-batch", "jan-call":
		workflow_report_execution_feedback(state, snapshot, route)
	case "jan-help-at-point":
		nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
		target, found := deepest_node(nodes, editor.Byte_Offset(snapshot.header.point))
		if found do module_diagnostic(state, fmt.tprintf("Jan help: node=%v", target.kind))
		else do module_diagnostic(state, "Jan help: no structured node at point")
	case:
		module_diagnostic(state, "Jan command is unavailable in the active module generation")
	}
	return .Ok
}

@(private)
workflow_report_execution_feedback :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	route: string,
) {
	code := jan_computation.Failure_Code.Unavailable
	if route == "jan-execute" || route == "jan-call" {
		_, found, failure := jan_computation.babel_source_block_at(
			string(snapshot.source), int(snapshot.header.point),
		)
		if !found {
			code = .Malformed
			if failure == .No_Source_Block do code = .Invalid_Request
		}
	}
	feedback := jan_computation.execution_feedback_from_failure(code)
	module_diagnostic(
		state,
		fmt.tprintf(
			"Jan execution: outcome=%v detail=%s source-preserved=%v",
			feedback.kind, feedback.message, feedback.source_preserved,
		),
	)
}

@(private)
workflow_babel_utility :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	route: string,
) -> (product_module.Status, bool) {
	switch route {
	case "jan-open-result", "jan-expand-source", "jan-goto-source-head",
	     "jan-demarcate-source", "jan-check-source", "jan-insert-header-argument",
	     "jan-view-source-info", "jan-source-hash":
	case "jan-goto-named-source":
		return workflow_present_named_babel_targets(state, snapshot, false), true
	case "jan-goto-named-result":
		return workflow_present_named_babel_targets(state, snapshot, true), true
	case "jan-babel-help":
		return workflow_present_babel_help(state), true
	case "jan-load-in-session", "jan-pop-to-session", "jan-switch-to-session-with-code":
		module_diagnostic(state, "Jan session unavailable: no adapter session is configured; source preserved")
		return .Ok, true
	case:
		return .Unavailable, false
	}
	source := string(snapshot.source)
	block, found, failure := jan_computation.babel_source_block_at(source, int(snapshot.header.point))
	if !found {
		module_diagnostic(
			state,
			fmt.tprintf("Jan Babel rejected: source block unavailable code=%v source-preserved=true", failure),
		)
		return .Ok, true
	}
	switch route {
	case "jan-open-result":
		result, result_found := jan_computation.babel_result_after_block(source, block)
		if !result_found {
			module_diagnostic(state, "Jan result unavailable: current source block has no adjacent result")
			return .Ok, true
		}
		if document_move_point(state, snapshot, editor.Byte_Offset(result)) {
			module_diagnostic(state, "Jan result visited")
		} else {
			module_diagnostic(state, "Jan result rejected: document changed")
		}
	case "jan-expand-source":
		body := source[block.body_start:block.body_end]
		if strings.contains(body, "<<") {
			module_diagnostic(state, "Jan expansion unavailable: unresolved noweb references require an admitted library")
			return .Ok, true
		}
		rows := [1]string{body}
		if workflow_present_surface(state, "Jan Expanded Source", rows[:]) {
			module_diagnostic(state, fmt.tprintf("Jan expansion: bytes=%d references=0", len(body)))
		} else {
			module_diagnostic(state, "Jan expansion rejected: result surface is unavailable")
		}
	case "jan-goto-source-head":
		if document_move_point(state, snapshot, editor.Byte_Offset(block.start)) {
			module_diagnostic(state, "Jan source block head visited")
		} else {
			module_diagnostic(state, "Jan source navigation rejected: document changed")
		}
	case "jan-demarcate-source":
		storage: [jan_computation.MAX_BABEL_UTILITY_TEXT]u8
		insertion, prepared, prepare_failure := jan_computation.babel_demarcation_text(
			source, block, int(snapshot.header.point), storage[:],
		)
		if !prepared {
			module_diagnostic(state, fmt.tprintf("Jan source split rejected: code=%v", prepare_failure))
			return .Ok, true
		}
		if document_apply_splice(state, snapshot, snapshot.header.point, snapshot.header.point, insertion) {
			module_diagnostic(state, "Jan source block split committed as one undo unit")
		} else {
			module_diagnostic(state, "Jan source split rejected: document changed")
		}
	case "jan-check-source":
		module_diagnostic(
			state,
			fmt.tprintf(
				"Jan source check: valid=true language=%s adapter=unavailable executable=false source-preserved=true",
				source[block.language_start:block.language_end],
			),
		)
	case "jan-insert-header-argument":
		if snapshot.header.flags & product_module.DOCUMENT_SNAPSHOT_REGION_ACTIVE == 0 {
			module_diagnostic(state, "Jan header argument rejected: select an explicit :key value first")
			return .Ok, true
		}
		selection_start := min(snapshot.header.point, snapshot.header.mark)
		selection_end := max(snapshot.header.point, snapshot.header.mark)
		if selection_start >= selection_end || selection_end > u64(len(source)) {
			module_diagnostic(state, "Jan header argument rejected: active selection is invalid")
			return .Ok, true
		}
		storage: [4_096]u8
		argument, prepared, prepare_failure := jan_computation.babel_header_argument_insertion(
			source[selection_start:selection_end], storage[:],
		)
		if !prepared {
			module_diagnostic(state, fmt.tprintf("Jan header argument rejected: code=%v", prepare_failure))
			return .Ok, true
		}
		if document_apply_splice(state, snapshot, u64(block.header_end), u64(block.header_end), argument) {
			module_diagnostic(state, "Jan header argument committed as one undo unit")
		} else {
			module_diagnostic(state, "Jan header argument rejected: document changed")
		}
	case "jan-view-source-info":
		workflow_present_babel_info(state, snapshot, block)
	case "jan-source-hash":
		hash, hashed := jan_computation.babel_source_hash(source, block)
		if hashed {
			module_diagnostic(state, fmt.tprintf("Jan source hash: %x", hash))
		} else {
			module_diagnostic(state, "Jan source hash unavailable: malformed source block")
		}
	}
	return .Ok, true
}

@(private)
workflow_present_named_babel_targets :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	results: bool,
) -> product_module.Status {
	source := string(snapshot.source)
	rows: [256]string
	points: [256]u64
	count := 0
	for count < len(rows) {
		target: jan_computation.Babel_Named_Target
		found := false
		if results {
			target, found = jan_computation.babel_named_result_at(source, count)
		} else {
			target, found = jan_computation.babel_named_source_at(source, count)
		}
		if !found do break
		rows[count] = source[target.name_start:target.name_end]
		points[count] = u64(target.target)
		count += 1
	}
	if count == 0 {
		module_diagnostic(state, "Jan named target unavailable: no matching definitions")
		return .Ok
	}
	title := "Jan Named Results" if results else "Jan Named Source Blocks"
	if !workflow_present_surface(state, title, rows[:count]) {
		module_diagnostic(state, "Jan named target rejected: selection surface is unavailable")
		return .Ok
	}
	state.surface_point_selection = true
	state.surface_revision = snapshot.header.revision
	state.surface_point_count = u16(count)
	copy(state.surface_points[:count], points[:count])
	module_diagnostic(state, fmt.tprintf("Jan named target selection: count=%d", count))
	return .Ok
}

@(private)
workflow_present_babel_info :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	block: jan_computation.Babel_Source_Block,
) {
	source := string(snapshot.source)
	result_offset, has_result := jan_computation.babel_result_after_block(source, block)
	hash, hashed := jan_computation.babel_source_hash(source, block)
	_ = result_offset
	storage: [4][256]u8
	rows := [4]string {
		fmt.bprintf(storage[0][:], "Language: %s", source[block.language_start:block.language_end]),
		fmt.bprintf(storage[1][:], "Source range: %d..%d", block.start, block.end),
		fmt.bprintf(storage[2][:], "Body bytes: %d; adjacent result: %v", block.body_end - block.body_start, has_result),
		fmt.bprintf(storage[3][:], "Effective hash: %x", hash if hashed else 0),
	}
	if !workflow_present_surface(state, "Jan Source Block Info", rows[:]) {
		module_diagnostic(state, "Jan source info rejected: result surface is unavailable")
		return
	}
	module_diagnostic(state, "Jan source info presented")
}

@(private)
workflow_present_babel_help :: proc(state: ^Module_Instance) -> product_module.Status {
	rows := [22]string {
		"C-c C-v p  Previous source block", "C-c C-v n  Next source block",
		"C-c C-v e  Execute at point", "C-c C-v o  Open result",
		"C-c C-v v  Expand source", "C-c C-v u  Go to source head",
		"C-c C-v g  Go to named source", "C-c C-v r  Go to named result",
		"C-c C-v b  Execute buffer", "C-c C-v s  Execute subtree",
		"C-c C-v d  Split source block", "C-c C-v t  Tangle scope",
		"C-c C-v f  Tangle file", "C-c C-v c  Check source",
		"C-c C-v j  Insert header argument", "C-c C-v l  Load in session",
		"C-c C-v i  Load library", "C-c C-v I  View source info",
		"C-c C-v z  Switch to session with code", "C-c C-v a  Source hash",
		"C-c C-v h  Babel help", "C-c C-v x  Edit source",
	}
	if !workflow_present_surface(state, "Jan Babel Bindings", rows[:]) {
		module_diagnostic(state, "Jan Babel help rejected: result surface is unavailable")
		return .Ok
	}
	module_diagnostic(state, "Jan Babel help presented")
	return .Ok
}

@(private)
document_replace_visibility :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	ranges: []product_module.Document_Range,
) -> bool {
	payload_bytes := len(ranges) * size_of(product_module.Document_Range)
	request, allocation_error := make([]u8, size_of(product_module.Document_Request_Header) + payload_bytes)
	if allocation_error != nil do return false
	defer delete(request)
	header := product_module.Document_Request_Header {
		schema_version = product_module.DOCUMENT_REQUEST_SCHEMA_VERSION,
		action = .Replace_Visibility,
		base_revision = snapshot.header.revision,
		count = u32(len(ranges)),
		payload_length = u64(payload_bytes),
	}
	copy(request[:size_of(header)], ([^]u8)(rawptr(&header))[:size_of(header)])
	for hidden, index in ranges {
		row := hidden
		offset := size_of(header) + index * size_of(product_module.Document_Range)
		copy(request[offset:offset + size_of(row)], ([^]u8)(rawptr(&row))[:size_of(row)])
	}
	return state.host_call(
		state.capability, .Document, raw_data(request), u64(len(request)), nil, 0, nil,
	) == .Ok
}

@(private)
workflow_visibility :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	scope: jan_editing.Scope,
	route: string,
	operation_id: jan_editing.Operation_ID,
) -> product_module.Status {
	_ = scope
	_ = operation_id
	if route == "jan-toggle-drawer" {
		return workflow_drawer_visibility(state, snapshot)
	}
	nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
	ranges, allocation_error := make(
		[dynamic]product_module.Document_Range,
		0,
		min(len(nodes) + len(snapshot.hidden_ranges) * 2, int(editor_view.MAX_HIDDEN_RANGES)),
	)
	if allocation_error != nil do return .Failed
	defer delete(ranges)
	next := jan_editing.Visibility_State.Invalid
	if route == "jan-cycle" {
		next_ok: bool
		next, next_ok = jan_editing.local_visibility_next(state.local_visibility)
		if !next_ok do return .Failed
		heading, found := target_node_on_line(
			nodes, snapshot.source, editor.Byte_Offset(snapshot.header.point), .Heading,
		)
		if !found {
			module_diagnostic(state, "Jan cycle: no heading at point")
			return .Ok
		}
		if !visibility_retain_outside_subtree(&ranges, snapshot.hidden_ranges, heading.range.start, heading.range.end) ||
		   !visibility_derive_local(&ranges, nodes, snapshot.source, heading, next) {
			module_diagnostic(state, "Jan visibility rejected: hidden range limit")
			return .Ok
		}
	} else {
		switch route {
		case "jan-global-cycle":
			next_ok: bool
			next, next_ok = jan_editing.global_visibility_next(state.global_visibility)
			if !next_ok do return .Failed
		case "jan-show-overview": next = .Overview
		case "jan-show-contents": next = .Contents
		case "jan-show-all": next = .Show_All
		case: return .Invalid_Argument
		}
		if !visibility_derive_global(&ranges, nodes, snapshot.source, next) {
			module_diagnostic(state, "Jan visibility rejected: hidden range limit")
			return .Ok
		}
	}
	if !document_replace_visibility(state, snapshot, ranges[:]) {
		module_diagnostic(state, "Jan visibility rejected: document changed")
		return .Ok
	}
	if route == "jan-cycle" do state.local_visibility = next
	else do state.global_visibility = next
	module_diagnostic(state, fmt.tprintf("Jan visibility: %v ranges=%d", next, len(ranges)))
	return .Ok
}

@(private)
workflow_drawer_visibility :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
) -> product_module.Status {
	nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
	drawer, found := target_node_on_line(
		nodes, snapshot.source, editor.Byte_Offset(snapshot.header.point), .Drawer,
	)
	property, property_found := target_node_on_line(
		nodes, snapshot.source, editor.Byte_Offset(snapshot.header.point), .Property_Drawer,
	)
	if property_found && (!found || property.range.end - property.range.start < drawer.range.end - drawer.range.start) {
		drawer = property
		found = true
	}
	if !found {
		module_diagnostic(state, "Jan drawer visibility: no drawer at point")
		return .Ok
	}
	start := visibility_line_end(snapshot.source, drawer.range.start, drawer.range.end)
	end := visibility_last_line_start(snapshot.source, drawer.range.start, drawer.range.end)
	if start >= end {
		module_diagnostic(state, "Jan drawer visibility: drawer has no foldable body")
		return .Ok
	}
	ranges, allocation_error := make(
		[dynamic]product_module.Document_Range,
		0,
		min(len(snapshot.hidden_ranges) + 1, int(editor_view.MAX_HIDDEN_RANGES)),
	)
	if allocation_error != nil do return .Failed
	defer delete(ranges)
	folded := false
	for hidden in snapshot.hidden_ranges {
		if hidden.start == u64(start) && hidden.end == u64(end) {
			folded = true
			continue
		}
		if hidden.start < u64(drawer.range.end) && hidden.end > u64(drawer.range.start) {
			module_diagnostic(state, "Jan drawer visibility rejected: target overlaps another hidden range")
			return .Ok
		}
		if !visibility_append(&ranges, hidden.start, hidden.end) do return .Failed
	}
	if !folded && !visibility_append(&ranges, u64(start), u64(end)) do return .Failed
	if !document_replace_visibility(state, snapshot, ranges[:]) {
		module_diagnostic(state, "Jan drawer visibility rejected: document changed")
		return .Ok
	}
	next := jan_editing.Visibility_State.Drawer_Visible if folded else .Drawer_Folded
	module_diagnostic(state, fmt.tprintf("Jan drawer visibility: %v ranges=%d", next, len(ranges)))
	return .Ok
}

@(private)
visibility_retain_outside_subtree :: proc(
	ranges: ^[dynamic]product_module.Document_Range,
	retained: []product_module.Document_Range,
	start, end: editor.Byte_Offset,
) -> bool {
	for hidden in retained {
		if hidden.end <= u64(start) || hidden.start >= u64(end) {
			if !visibility_append(ranges, hidden.start, hidden.end) do return false
			continue
		}
		if hidden.start < u64(start) && !visibility_append(ranges, hidden.start, u64(start)) {
			return false
		}
		if hidden.end > u64(end) && !visibility_append(ranges, u64(end), hidden.end) {
			return false
		}
	}
	return true
}

@(private)
visibility_derive_local :: proc(
	ranges: ^[dynamic]product_module.Document_Range,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	heading: language.Jan_Node_Record,
	selected: jan_editing.Visibility_State,
) -> bool {
	if selected == .Complete_Subtree do return true
	header_end := visibility_line_end(source, heading.range.start, heading.range.end)
	if selected == .Heading_Only {
		return visibility_append(ranges, u64(header_end), u64(heading.range.end))
	}
	cursor := header_end
	for node in nodes {
		if node.kind != .Heading || node.parent_id != heading.id do continue
		if node.range.start > cursor &&
		   !visibility_append(ranges, u64(cursor), u64(node.range.start)) {
			return false
		}
		child_header_end := visibility_line_end(source, node.range.start, node.range.end)
		cursor = max(cursor, child_header_end)
		next_child_start := node.range.end
		for sibling in nodes {
			if sibling.kind == .Heading && sibling.parent_id == heading.id &&
			   sibling.range.start > node.range.start && sibling.range.start < next_child_start {
				next_child_start = sibling.range.start
			}
		}
		if next_child_start > cursor &&
		   !visibility_append(ranges, u64(cursor), u64(next_child_start)) {
			return false
		}
		cursor = max(cursor, next_child_start)
	}
	return cursor >= heading.range.end ||
	       visibility_append(ranges, u64(cursor), u64(heading.range.end))
}

@(private)
visibility_derive_global :: proc(
	ranges: ^[dynamic]product_module.Document_Range,
	nodes: []language.Jan_Node_Record,
	source: []u8,
	selected: jan_editing.Visibility_State,
) -> bool {
	if selected == .Show_All do return true
	for node in nodes {
		if node.kind != .Heading do continue
		if selected == .Overview && node.structural_depth != 1 do continue
		start := visibility_line_end(source, node.range.start, node.range.end)
		end := node.range.end
		if selected == .Contents {
			for next in nodes {
				if next.kind == .Heading && next.range.start > node.range.start && next.range.start < end {
					end = next.range.start
				}
			}
		}
		if !visibility_append(ranges, u64(start), u64(end)) do return false
	}
	return true
}

@(private)
visibility_append :: proc(
	ranges: ^[dynamic]product_module.Document_Range,
	start, end: u64,
) -> bool {
	if start >= end do return true
	if len(ranges^) >= int(editor_view.MAX_HIDDEN_RANGES) do return false
	_, append_error := append(ranges, product_module.Document_Range{start = start, end = end})
	return append_error == nil
}

@(private)
visibility_line_end :: proc(
	source: []u8,
	start, end: editor.Byte_Offset,
) -> editor.Byte_Offset {
	cursor := int(start)
	limit := min(int(end), len(source))
	for cursor < limit && source[cursor] != '\r' && source[cursor] != '\n' do cursor += 1
	if cursor < limit && source[cursor] == '\r' do cursor += 1
	if cursor < limit && source[cursor] == '\n' do cursor += 1
	return editor.Byte_Offset(cursor)
}

@(private)
visibility_last_line_start :: proc(
	source: []u8,
	start, end: editor.Byte_Offset,
) -> editor.Byte_Offset {
	if end <= start do return start
	cursor := min(int(end), len(source))
	if cursor > int(start) && source[cursor - 1] == '\n' do cursor -= 1
	if cursor > int(start) && source[cursor - 1] == '\r' do cursor -= 1
	for cursor > int(start) && source[cursor - 1] != '\n' && source[cursor - 1] != '\r' do cursor -= 1
	return editor.Byte_Offset(cursor)
}

@(private)
workflow_present_agenda :: proc(state: ^Module_Instance, snapshot: ^Document_Snapshot) {
	nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
	attributes := language.jan_structural_analysis_attributes(&snapshot.analysis)
	task_count := jan_planning.agenda_document_row_count(nodes, attributes)
	if task_count == 0 {
		module_diagnostic(state, "Jan agenda: no task entries in the current source")
		return
	}
	storage, storage_error := make([][512]u8, task_count)
	rows, rows_error := make([]string, task_count)
	if storage_error != nil || rows_error != nil {
		if storage != nil do delete(storage)
		if rows != nil do delete(rows)
		module_diagnostic(state, "Jan agenda rejected: result storage is unavailable")
		return
	}
	defer delete(storage)
	defer delete(rows)
	timestamp_count := 0
	for index in 0 ..< task_count {
		row, projected := jan_planning.agenda_document_row(nodes, attributes, snapshot.source, index)
		if !projected {
			module_diagnostic(state, "Jan agenda rejected: source projection failed")
			return
		}
		annotation := row.planning if row.has_planning else row.task_state
		if row.has_planning do timestamp_count += 1
		rows[index] = fmt.bprintf(storage[index][:], "%s  %s", row.heading, annotation)
	}
	heading_count := node_kind_count(nodes, .Heading)
	module_diagnostic(
		state,
		fmt.tprintf(
			"Jan agenda: sources=1 headings=%d tasks=%d timestamps=%d revision=%d",
			heading_count, task_count, timestamp_count, snapshot.scope.source_revision,
		),
	)
	if !workflow_present_surface(state, "Jan Agenda", rows) {
		module_diagnostic(state, "Jan agenda rejected: result surface is unavailable")
	}
}

@(private)
workflow_present_formula :: proc(state: ^Module_Instance, snapshot: ^Document_Snapshot) {
	inspection: jan_computation.Formula_Source_Inspection
	inspected, failure := jan_computation.inspect_formula_source(
		&inspection,
		&snapshot.analysis,
		snapshot.source,
		editor.Byte_Offset(snapshot.header.point),
	)
	if !inspected {
		module_diagnostic(
			state,
			fmt.tprintf(
				"Jan formula inspection unavailable: code=%v field=%v source-preserved=true",
				failure.code, failure.field,
			),
		)
		return
	}
	defer jan_computation.formula_source_inspection_close(&inspection)
	view, viewed := jan_computation.formula_source_inspection_view(&inspection)
	if !viewed {
		module_diagnostic(state, "Jan formula inspection unavailable: source-preserved=true")
		return
	}
	row_count := len(view.trace) + 1
	storage, storage_error := make([][512]u8, row_count)
	rows, rows_error := make([]string, row_count)
	if storage_error != nil || rows_error != nil {
		if storage != nil do delete(storage)
		if rows != nil do delete(rows)
		return
	}
	defer delete(storage)
	defer delete(rows)
	value_storage: [64]u8
	value, formatted := jan_computation.format_cell_value(view.value, {kind = .General}, value_storage[:])
	if !formatted do value = "unavailable"
	rows[0] = fmt.bprintf(storage[0][:], "%s = %s  result=%s", view.target, view.expression, value)
	for step, index in view.trace {
		step_value_storage: [64]u8
		step_value, step_formatted := jan_computation.format_cell_value(
			step.value, {kind = .General}, step_value_storage[:],
		)
		if !step_formatted do step_value = "unavailable"
		rows[index + 1] = fmt.bprintf(
			storage[index + 1][:],
			"Step %d: %v -> %s",
			step.step + 1, step.instruction, step_value,
		)
	}
	module_diagnostic(
		state,
		fmt.tprintf(
			"Jan computation: tables=%d formula-forms=%d revision=%d command=Jan_Table_Debug_Formula",
			node_kind_count(language.jan_structural_analysis_nodes(&snapshot.analysis), .Pipe_Table),
			index_kind_count(language.jan_structural_analysis_indexes(&snapshot.analysis), .Formula),
			snapshot.scope.source_revision,
		),
	)
	if !workflow_present_surface(state, "Jan Formula Trace", rows) {
		module_diagnostic(state, "Jan formula inspection rejected: result surface is unavailable")
	}
}

@(private)
workflow_render_native :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	route: string,
) {
	backend := jan_output.Native_Backend.Normalized_Jan
	switch route {
	case "jan-export-plain-text": backend = .Plain_Text
	case "jan-export-html": backend = .Html
	case "jan-export-markdown": backend = .Markdown
	case "jan-export", "jan-export-normalized-jan":
	case:
		module_diagnostic(state, "Jan export rejected: unsupported native backend")
		return
	}
	fragments := [1]jan_output.Native_Fragment{{kind = .Text, text = string(snapshot.source)}}
	blocks := [1]jan_output.Native_Block{{kind = .Paragraph, fragment_count = 1}}
	destination: [4_096]u8
	operation_id := jan_output.Operation_ID(state.next_operation_id)
	state.next_operation_id += 1
	result, rendered, failure := jan_output.render_native_backend(
		operation_id,
		backend,
		{language = "jan", blocks = blocks[:], fragments = fragments[:]},
		{encoding = .Utf_8, full_document = true, unsupported = .Plain_Text_With_Warning},
		destination[:],
	)
	if !rendered {
		module_diagnostic(
			state,
			fmt.tprintf(
				"Jan export rejected: backend=%v code=%v limit=%d actual=%d source-preserved=true",
				backend, failure.code, failure.limit, failure.actual,
			),
		)
		return
	}
	module_diagnostic(
		state,
		fmt.tprintf(
			"Jan export: backend=%v bytes=%d diagnostics=%d revision=%d source-preserved=true",
			backend, result.byte_count, result.diagnostic_count, snapshot.scope.source_revision,
		),
	)
}

@(private)
planning_availability_counts :: proc(
	records: []jan_planning.Availability_Record,
) -> (available, unavailable: int) {
	for record in records {
		if record.state == .Available do available += 1
		if record.state == .Unavailable do unavailable += 1
	}
	return
}

@(private)
computation_availability_counts :: proc(
	records: []jan_computation.Availability_Record,
) -> (available, unavailable: int) {
	for record in records {
		if record.state == .Available do available += 1
		if record.state == .Unavailable do unavailable += 1
	}
	return
}

@(private)
node_kind_count :: proc(nodes: []language.Jan_Node_Record, kind: language.Jan_Node_Kind) -> int {
	count := 0
	for node in nodes do if node.kind == kind do count += 1
	return count
}

@(private)
index_kind_count :: proc(indexes: []language.Jan_Index_Fact, kind: language.Jan_Index_Kind) -> int {
	count := 0
	for index in indexes do if index.kind == kind do count += 1
	return count
}

@(private)
workflow_rewrite :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	scope: jan_editing.Scope,
	route: string,
	operation_id: jan_editing.Operation_ID,
) -> product_module.Status {
	if route == "jan-todo" do return workflow_todo(state, snapshot)
	if route == "jan-toggle-checkbox" {
		_ = workflow_toggle_checkbox(state, snapshot, true)
		return .Ok
	}
	plan: language.Jan_Rewrite_Plan
	planned := false
	failure: jan_editing.Failure
	nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
	rewrite_id := language.Jan_Rewrite_Generation(state.next_rewrite_id)
	state.next_rewrite_id += 1
	point := editor.Byte_Offset(snapshot.header.point)
	if kind, matched := heading_kind(route); matched {
		target_kind := language.Jan_Node_Kind.Heading
		if kind == .List_Item_To_Heading do target_kind = .List_Item
		target, found := target_node(nodes, point, target_kind)
		if found {
			planned, failure = jan_editing.heading_edit_plan_prepare(
				&plan, &snapshot.analysis, snapshot.source,
				{
					operation_id = operation_id, scope = scope, kind = kind,
					target_id = target.id, rewrite_generation = rewrite_id,
					text = "Heading", split_offset = point,
				},
			)
		}
	} else if kind, list_matched := list_kind(route); list_matched {
		target, found := target_node(nodes, point, .List_Item)
		if found {
			planned, failure = jan_editing.list_edit_plan_prepare(
				&plan, &snapshot.analysis, snapshot.source,
				{
					operation_id = operation_id, scope = scope, kind = kind,
					target_id = target.id, rewrite_generation = rewrite_id,
					bullet = .Unordered_Dash, text = "item", indent_width = 2,
				},
			)
		}
	} else if kind, structure_matched := structure_kind(route); structure_matched {
		target, found := deepest_node(nodes, point)
		if found {
			request := jan_editing.Structure_Edit_Request {
				operation_id = operation_id, scope = scope, kind = kind,
				target_id = target.id, rewrite_generation = rewrite_id,
				template = .Source_Block, name = "src", arguments = "odin", body = "",
			}
		if route == "jan-insert-drawer" {
				request.template = .Drawer
				request.name = "NOTES"
				request.arguments = ""
			}
			planned, failure = jan_editing.structure_edit_plan_prepare(
				&plan, &snapshot.analysis, snapshot.source, request,
			)
		}
	} else if kind, table_matched := table_kind(route); table_matched {
		target, found := deepest_node(nodes, point)
		if found {
			planned, failure = jan_editing.table_edit_plan_prepare(
				&plan, &snapshot.analysis, snapshot.source,
				{
					operation_id = operation_id, scope = scope, kind = kind,
					target_id = target.id, rewrite_generation = rewrite_id,
					rows = 2, columns = 2,
				},
			)
		}
	} else if kind, footnote_matched := footnote_kind(route); footnote_matched {
		target, found := deepest_node(nodes, point)
		if found {
			planned, failure = jan_editing.footnote_edit_plan_prepare(
				&plan, &snapshot.analysis, snapshot.source,
				{
					operation_id = operation_id, scope = scope, kind = kind,
					target_id = target.id, rewrite_generation = rewrite_id,
					name = "note", text = "Footnote",
				},
			)
		}
	} else if route == "jan-indent" {
		planned, failure = jan_editing.hard_indentation_plan_prepare(
			&plan, &snapshot.analysis, snapshot.source, scope, nodes[0].range, rewrite_id, 2,
		)
	}
	if !planned {
		module_diagnostic(state, fmt.tprintf("Jan rewrite rejected: %v", failure.code))
		return .Ok
	}
	defer language.jan_rewrite_plan_close(&plan)
	if !document_apply_plan(state, snapshot, &plan) {
		module_diagnostic(state, "Jan rewrite rejected: transaction publication failed")
		return .Ok
	}
	module_diagnostic(state, "Jan rewrite committed as one undo unit")
	return .Ok
}

@(private)
workflow_toggle_checkbox :: proc(
	state: ^Module_Instance,
	snapshot: ^Document_Snapshot,
	report_missing: bool,
) -> bool {
	nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
	item, found := target_node_on_line(
		nodes, snapshot.source, editor.Byte_Offset(snapshot.header.point), .List_Item,
	)
	if !found {
		if report_missing do module_diagnostic(state, "Jan checkbox: no list item at point")
		return false
	}
	start := int(item.range.start)
	end := min(int(item.range.end), len(snapshot.source))
	for end > start && snapshot.source[end - 1] == '\n' do end -= 1
	if end - start < 3 {
		if report_missing do module_diagnostic(state, "Jan checkbox: no compatible checkbox at point")
		return false
	}
	for index in start ..< end - 2 {
		if snapshot.source[index] != '[' || snapshot.source[index + 2] != ']' do continue
		current := snapshot.source[index + 1]
		next := u8('X')
		from := "unchecked"
		if current == 'X' || current == 'x' {
			next = ' '
			from = "checked"
		} else if current == '-' {
			from = "intermediate"
		} else if current != ' ' {
			continue
		}
		if !document_apply_splice(
			state, snapshot, u64(index + 1), u64(index + 2), string([]u8{next}),
		) {
			module_diagnostic(state, "Jan checkbox rejected: transaction publication failed")
			return true
		}
		to := "checked" if next == 'X' else "unchecked"
		module_diagnostic(state, fmt.tprintf("Jan checkbox: %s -> %s", from, to))
		return true
	}
	if report_missing do module_diagnostic(state, "Jan checkbox: no compatible checkbox at point")
	return false
}

@(private)
workflow_todo :: proc(state: ^Module_Instance, snapshot: ^Document_Snapshot) -> product_module.Status {
	nodes := language.jan_structural_analysis_nodes(&snapshot.analysis)
	heading, found := target_node_on_line(
		nodes, snapshot.source, editor.Byte_Offset(snapshot.header.point), .Heading,
	)
	if !found {
		module_diagnostic(state, "Jan task: no heading at point")
		return .Ok
	}
	state_text := ""
	for attribute in language.jan_structural_analysis_attributes(&snapshot.analysis) {
		if attribute.node_id == heading.id && attribute_name_matches(attribute.name, "task-state") &&
		   attribute.range.start >= heading.range.start && attribute.range.end <= heading.range.end {
			state_text = string(snapshot.source[int(attribute.range.start):int(attribute.range.end)])
			break
		}
	}
	if len(state_text) == 0 {
		module_diagnostic(state, "Jan task: heading has no configured task state")
		return .Ok
	}
	descriptor, configured := jan_planning.planning_configuration_inspect(&state.planning_configuration)
	if !configured do return .Failed
	plan: language.Jan_Rewrite_Plan
	transition, planned, failure := jan_planning.task_transition_plan_prepare(
		&plan, &snapshot.analysis, snapshot.source, &state.planning_configuration,
		{
			operation_id = jan_planning.Operation_ID(state.next_operation_id),
			scope = {
				analysis = snapshot.scope,
				source_bytes = u64(len(snapshot.source)),
				configuration_generation = descriptor.generation,
				provider_generation = descriptor.provider_generation,
				source_set = 1,
			},
			target = {node_id = heading.id, kind = heading.kind, range = heading.range},
			workflow = "default",
			current_state = state_text,
			direction = .Forward,
			rewrite_generation = language.Jan_Rewrite_Generation(state.next_rewrite_id),
		},
	)
	state.next_operation_id += 1
	state.next_rewrite_id += 1
	if !planned {
		module_diagnostic(state, fmt.tprintf("Jan task rejected: %v", failure.code))
		return .Ok
	}
	defer language.jan_rewrite_plan_close(&plan)
	if !document_apply_plan(state, snapshot, &plan) {
		module_diagnostic(state, "Jan task rejected: transaction publication failed")
		return .Ok
	}
	module_diagnostic(state, fmt.tprintf("Jan task: %s -> %s committed as one undo unit", transition.from, transition.to))
	return .Ok
}

@(private)
target_node :: proc(nodes: []language.Jan_Node_Record, point: editor.Byte_Offset, kind: language.Jan_Node_Kind) -> (language.Jan_Node_Record, bool) {
	target: language.Jan_Node_Record
	for node in nodes {
		if node.kind != kind || point < node.range.start || point > node.range.end do continue
		if target.id == 0 || node.range.end - node.range.start < target.range.end - target.range.start do target = node
	}
	return target, target.id != 0
}

@(private)
target_node_on_line :: proc(
	nodes: []language.Jan_Node_Record,
	source: []u8,
	point: editor.Byte_Offset,
	kind: language.Jan_Node_Kind,
) -> (language.Jan_Node_Record, bool) {
	if target, found := target_node(nodes, point, kind); found do return target, true
	line_start := min(int(point), len(source))
	line_end := line_start
	for line_start > 0 && source[line_start - 1] != '\n' && source[line_start - 1] != '\r' do line_start -= 1
	for line_end < len(source) && source[line_end] != '\n' && source[line_end] != '\r' do line_end += 1
	if line_start == line_end do return {}, false
	target: language.Jan_Node_Record
	for node in nodes {
		if node.kind != kind || node.range.start >= editor.Byte_Offset(line_end) ||
		   node.range.end <= editor.Byte_Offset(line_start) {
			continue
		}
		if target.id == 0 || node.range.end - node.range.start < target.range.end - target.range.start do target = node
	}
	return target, target.id != 0
}

@(private)
deepest_node :: proc(nodes: []language.Jan_Node_Record, point: editor.Byte_Offset) -> (language.Jan_Node_Record, bool) {
	target: language.Jan_Node_Record
	for node in nodes {
		if point < node.range.start || point > node.range.end do continue
		if target.id == 0 || node.inline_depth > target.inline_depth ||
		   node.inline_depth == target.inline_depth && node.structural_depth >= target.structural_depth {
			target = node
		}
	}
	return target, target.id != 0
}

@(private)
attribute_name_matches :: proc(name: language.Jan_Attribute_Name, expected: string) -> bool {
	if int(name.length) != len(expected) do return false
	for value, index in transmute([]u8)expected {
		if name.bytes[index] != value do return false
	}
	return true
}

@(private)
navigation_kind :: proc(route: string) -> (jan_editing.Navigation_Kind, bool) {
	switch route {
	case "jan-next-heading": return .Next_Visible_Heading, true
	case "jan-previous-heading": return .Previous_Visible_Heading, true
	case "jan-next-same-level-heading": return .Next_Same_Level_Heading, true
	case "jan-previous-same-level-heading": return .Previous_Same_Level_Heading, true
	case "jan-parent-heading": return .Parent_Heading, true
	case "jan-first-child-heading": return .First_Child_Heading, true
	case "jan-subtree-start": return .Subtree_Start, true
	case "jan-subtree-end": return .Subtree_End, true
	case "jan-next-structural-element": return .Next_Structural_Element, true
	case "jan-previous-structural-element": return .Previous_Structural_Element, true
	case "jan-next-list-item": return .Next_List_Item, true
	case "jan-previous-list-item": return .Previous_List_Item, true
	case "jan-next-table-row": return .Next_Table_Row, true
	case "jan-previous-table-row": return .Previous_Table_Row, true
	case "jan-next-table-cell": return .Next_Table_Cell, true
	case "jan-previous-table-cell": return .Previous_Table_Cell, true
	case "jan-next-drawer": return .Next_Drawer, true
	case "jan-previous-drawer": return .Previous_Drawer, true
	case "jan-next-block": return .Next_Block, true
	case "jan-previous-block": return .Previous_Block, true
	case "jan-next-footnote": return .Next_Footnote, true
	case "jan-previous-footnote": return .Previous_Footnote, true
	case: return .Invalid, false
	}
}

@(private)
heading_kind :: proc(route: string) -> (jan_editing.Heading_Edit_Kind, bool) {
	switch route {
	case "jan-insert-heading-before": return .Insert_Before, true
	case "jan-insert-heading-after": return .Insert_After, true
	case "jan-insert-heading-below": return .Insert_Below, true
	case "jan-split-heading": return .Split, true
	case "jan-promote-heading": return .Promote_Heading, true
	case "jan-demote-heading": return .Demote_Heading, true
	case "jan-move-subtree-up": return .Move_Up, true
	case "jan-move-subtree-down": return .Move_Down, true
	case "jan-clone-subtree": return .Clone_Subtree, true
	case "jan-kill-subtree": return .Kill_Subtree, true
	case "jan-sort-child-headings": return .Sort_Children, true
	case "jan-heading-to-list-item": return .Heading_To_List_Item, true
	case "jan-list-item-to-heading": return .List_Item_To_Heading, true
	case: return .Invalid, false
	}
}

@(private)
list_kind :: proc(route: string) -> (jan_editing.List_Edit_Kind, bool) {
	switch route {
	case "jan-insert-list-item-before": return .Insert_Before, true
	case "jan-insert-list-item-after": return .Insert_After, true
	case "jan-delete-list-item": return .Delete_Item, true
	case "jan-promote-list-item": return .Promote_Item, true
	case "jan-demote-list-item": return .Demote_Item, true
	case "jan-move-list-item-up": return .Move_Up, true
	case "jan-move-list-item-down": return .Move_Down, true
	case "jan-duplicate-list-item": return .Duplicate_Item, true
	case "jan-sort-list-items": return .Sort_Items, true
	case "jan-cycle-list-bullet": return .Select_Bullet, true
	case "jan-repair-list-indentation": return .Repair_Indentation, true
	case: return .Invalid, false
	}
}

@(private)
structure_kind :: proc(route: string) -> (jan_editing.Structure_Edit_Kind, bool) {
	switch route {
	case "jan-insert-drawer", "jan-insert-block", "jan-expand-template": return .Insert_After, true
	case "jan-move-structure-up": return .Move_Up, true
	case "jan-move-structure-down": return .Move_Down, true
	case "jan-delete-structure": return .Delete, true
	case: return .Invalid, false
	}
}

@(private)
table_kind :: proc(route: string) -> (jan_editing.Table_Edit_Kind, bool) {
	switch route {
	case "jan-create-table": return .Create, true
	case "jan-insert-table-row": return .Insert_Row_After, true
	case "jan-delete-table-row": return .Delete_Row, true
	case "jan-move-table-row-up": return .Move_Row_Up, true
	case "jan-move-table-row-down": return .Move_Row_Down, true
	case "jan-duplicate-table-row": return .Duplicate_Row, true
	case "jan-insert-table-column": return .Insert_Column_After, true
	case "jan-delete-table-column": return .Delete_Column, true
	case "jan-move-table-column-left": return .Move_Column_Left, true
	case "jan-move-table-column-right": return .Move_Column_Right, true
	case "jan-duplicate-table-column": return .Duplicate_Column, true
	case "jan-insert-table-separator": return .Insert_Separator_After, true
	case "jan-delete-table-separator": return .Delete_Separator, true
	case: return .Invalid, false
	}
}

@(private)
footnote_kind :: proc(route: string) -> (jan_editing.Footnote_Edit_Kind, bool) {
	switch route {
	case "jan-create-footnote": return .Create_Definition, true
	case "jan-normalize-footnote": return .Normalize_Inline, true
	case "jan-renumber-footnotes": return .Renumber_Local, true
	case "jan-move-footnote-up": return .Move_Definition_Up, true
	case "jan-move-footnote-down": return .Move_Definition_Down, true
	case: return .Invalid, false
	}
}

@(private)
route_changes_source :: proc(route: string) -> bool {
	_, heading := heading_kind(route)
	_, list := list_kind(route)
	_, structure := structure_kind(route)
	_, table := table_kind(route)
	_, footnote := footnote_kind(route)
	return heading || list || structure || table || footnote ||
	       route == "jan-indent" || route == "jan-todo" || route == "jan-toggle-checkbox"
}
