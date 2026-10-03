// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import "../editor"
import "../editor_session"
import "../language_service"
import "../ui"
import "base:runtime"
import "core:fmt"

/* LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID identifies the built-in service inspection owner. */
LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID :: ui.Owner_ID(10_009)
/* LANGUAGE_SERVICE_INSPECTION_UI_MODEL_ID identifies the built-in service inspection model. */
LANGUAGE_SERVICE_INSPECTION_UI_MODEL_ID :: ui.Model_ID(10_009)
/* LANGUAGE_SERVICE_INSPECTION_UI_TARGET_GENERATION identifies the inspection target contract. */
LANGUAGE_SERVICE_INSPECTION_UI_TARGET_GENERATION :: u64(1)
/* LANGUAGE_SERVICE_INSPECTION_CLOSE_ACTION identifies the read-only inspection row action. */
LANGUAGE_SERVICE_INSPECTION_CLOSE_ACTION :: ui.List_Action_ID(1)
/* LANGUAGE_SERVICE_INSPECTION_BASE_ROWS is the fixed service summary size. */
LANGUAGE_SERVICE_INSPECTION_BASE_ROWS :: 22
/* LANGUAGE_SERVICE_INSPECTION_ROW_BYTES bounds one copied formatted inspection row. */
LANGUAGE_SERVICE_INSPECTION_ROW_BYTES :: 512

@(private)
Language_Service_Inspection_Workflow_State :: struct {
	rows:                  []string,
	storage:               []u8,
	allocator:             runtime.Allocator,
	ready:                 bool,
	return_target:         editor_session.Visible_Target,
	position:              ui.List_View_Position,
	model_generation:      u64,
	next_model_generation: u64,
}

// Language_Service_Inspection_Visible_Target returns the stable inspection UI identity.
Language_Service_Inspection_Visible_Target :: proc() -> editor_session.Visible_Target {
	return {
		kind = .UI_Root,
		ui = {
			owner_id = u64(LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID),
			model_id = u64(LANGUAGE_SERVICE_INSPECTION_UI_MODEL_ID),
			generation = LANGUAGE_SERVICE_INSPECTION_UI_TARGET_GENERATION,
		},
	}
}

// Language_Service_Inspection_Workflow_Reset releases copied inspection state.
Language_Service_Inspection_Workflow_Reset :: proc(
	state: ^Language_Service_Inspection_Workflow_State,
) {
	if state == nil do return
	next_generation := state.next_model_generation
	if state.rows != nil do delete(state.rows, state.allocator)
	if state.storage != nil do delete(state.storage, state.allocator)
	state^ = {}
	state.next_model_generation = next_generation
}

// Language_Service_Inspection_Workflow_Advance_Generation advances the copied model identity.
Language_Service_Inspection_Workflow_Advance_Generation :: proc(
	state: ^Language_Service_Inspection_Workflow_State,
) -> bool {
	if state == nil || state.next_model_generation == max(u64) do return false
	state.next_model_generation += 1
	state.model_generation = state.next_model_generation
	return true
}

// Language_Service_Inspection_Workflow_Prepare normalizes list state for one viewport.
Language_Service_Inspection_Workflow_Prepare :: proc(
	state: ^Language_Service_Inspection_Workflow_State,
	viewport_items: u32,
) -> (bool, ui.Failure) {
	if state == nil || !state.ready || len(state.rows) == 0 || state.model_generation == 0 ||
	   viewport_items == 0 || viewport_items > ui.MAX_LIST_ITEMS {
		return false, ui.Failure{operation = .Prepare, code = .Invalid_List_View}
	}
	if state.position.presentation_generation == 0 {
		state.position = {
			presentation_generation = 1,
			selection_owner = .View,
			viewport_items = viewport_items,
		}
	} else {
		state.position.viewport_items = viewport_items
		state.position.current_item = min(state.position.current_item, i32(len(state.rows) - 1))
		state.position.first_visible_item = min(
			state.position.first_visible_item,
			u32(len(state.rows) - 1),
		)
	}
	return true, {}
}

// Language_Service_Inspection_Workflow_Move applies bounded inspection navigation.
Language_Service_Inspection_Workflow_Move :: proc(
	state: ^Language_Service_Inspection_Workflow_State,
	delta: i32,
) -> (changed, ok: bool, failure: ui.Failure) {
	if state == nil || !state.ready {
		return false, false, ui.Failure{operation = .Navigate, code = .Invalid_List_View}
	}
	next: ui.List_View_State
	next, changed, ok, failure = ui.list_view_move_current(
		{
			present = true,
			item_count = u32(len(state.rows)),
			position = state.position,
		},
		delta,
	)
	if ok do state.position = next.position
	return
}

@(private)
language_service_inspection_row :: proc(
	state: ^Language_Service_Inspection_Workflow_State,
	index: int,
	format: string,
	args: ..any,
) {
	storage := state.storage[
		index * LANGUAGE_SERVICE_INSPECTION_ROW_BYTES:(index + 1) * LANGUAGE_SERVICE_INSPECTION_ROW_BYTES
	]
	state.rows[index] = fmt.bprintf(storage, format, ..args)
}

// Language_Service_Inspection_Workflow_Capture copies bounded runtime and catalog rows.
Language_Service_Inspection_Workflow_Capture :: proc(
	state: ^Language_Service_Inspection_Workflow_State,
	workflow: ^Language_Service_Workflow_State,
	buffer: ^editor.Buffer,
	allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
) -> bool {
	if state == nil || !Language_Service_Workflow_Is_Live(workflow) || buffer == nil ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return false
	}
	Language_Service_Inspection_Workflow_Reset(state)
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return false
	registry, registry_ok := language_service.provider_registry_inspect(&workflow.registry)
	if !registry_ok do return false
	catalog: language_service.Service_Catalog_Inspection
	catalog_ok, _ := language_service.service_catalog_inspect(&workflow.catalog, &catalog)
	if !catalog_ok do return false
	index, session_found := Language_Service_Workflow_Session_For_Buffer(workflow, stats.buffer_id)
	definition_handle := registry.active
	if session_found do definition_handle = workflow.sessions[index].definition
	definition, definition_ok, definition_failure := language_service.provider_registry_definition(
		&workflow.registry,
		definition_handle,
	)
	document_rows := 0
	if session_found do document_rows = len(workflow.sessions[index].documents)
	catalog_rows := int(catalog.definition_count) + int(catalog.selection_count) + int(catalog.conflict_count)
	row_count := LANGUAGE_SERVICE_INSPECTION_BASE_ROWS + catalog_rows + document_rows
	rows, rows_error := make([]string, row_count, allocator)
	if rows_error != nil do return false
	storage, storage_error := make(
		[]u8,
		row_count * LANGUAGE_SERVICE_INSPECTION_ROW_BYTES,
		allocator,
	)
	if storage_error != nil {
		delete(rows, allocator)
		return false
	}
	state.rows = rows
	state.storage = storage
	state.allocator = allocator
	active_name := "unavailable"
	provider_kind := language_service.Provider_Kind.Invalid
	provider_state := language_service.Provider_State.Invalid
	provider_capabilities := language_service.Capabilities{}
	definition_source := language_service.Service_Contribution_Source.Invalid
	definition_scope := ""
	definition_provenance := "unavailable"
	executable := "unavailable"
	resolved_executable := "unavailable"
	executable_availability := language_service.Executable_Availability.Unknown
	executable_source := language_service.Executable_Source.Invalid
	root_policy := language_service.Root_Policy.Invalid
	arguments: []string
	environment_entries := 0
	languages: []string
	requested_capabilities := language_service.Capabilities{}
	feature_policy := language_service.Service_Features{}
	preferred_encoding := language_service.Position_Encoding.Invalid
	preferred_sync := language_service.Synchronization_Mode.None
	limits := language_service.DEFAULT_LIMITS
	deadlines := language_service.DEFAULT_DEADLINES
	restart := language_service.DEFAULT_RESTART_POLICY
	active_sessions := 0
	initializing_sessions := 0
	failed_sessions := 0
	for owner in workflow.sessions {
		if !owner.live do continue
		switch owner.phase {
		case .Active:       active_sessions += 1
		case .Initializing: initializing_sessions += 1
		case .Failed:       failed_sessions += 1
		case .None:
		}
	}
	for catalog_definition_index in 0 ..< int(catalog.definition_count) {
		catalog_definition := &catalog.definitions[catalog_definition_index]
		if catalog_definition.definition != definition_handle do continue
		definition_source = catalog_definition.scope.source
		definition_scope = language_service.service_scope_text_view(&catalog_definition.scope.name)
		definition_provenance = language_service.service_provenance_text_view(
			&catalog_definition.provenance,
		)
		break
	}
	if definition_ok {
		active_name = definition.name
		provider_kind = definition.provider.kind
		provider_state = definition.provider.state
		provider_capabilities = definition.provider.capabilities
		executable = definition.executable
		if len(definition.resolved_executable) > 0 do resolved_executable = definition.resolved_executable
		executable_availability = definition.executable_availability
		executable_source = definition.executable_source
		root_policy = definition.root_policy
		arguments = definition.arguments
		environment_entries = len(definition.environment)
		languages = definition.languages
		requested_capabilities = definition.definition.requested_capabilities
		feature_policy = definition.feature_policy
		preferred_encoding = definition.definition.preferred_encoding
		preferred_sync = definition.definition.preferred_sync
		limits = definition.definition.limits
		deadlines = definition.definition.deadlines
		restart = definition.definition.restart
	}
	language_service_inspection_row(state, 0, "Registry: id=%d@%d selection=%d active=%d@%d factory=%d@%d", registry.handle.id, registry.handle.generation, registry.selection_generation, registry.active.id, registry.active.generation, registry.factory.id, registry.factory.generation)
	language_service_inspection_row(state, 1, "Provider: name=%s kind=%v state=%v capabilities=%v source=%v scope=%q provenance=%q", active_name, provider_kind, provider_state, provider_capabilities, definition_source, definition_scope, definition_provenance)
	language_service_inspection_row(state, 2, "Executable: requested=%q resolved=%q availability=%v source=%v arguments=%v environment=%d values=redacted package-artifact=%q distributed-artifact=%q", executable, resolved_executable, executable_availability, executable_source, arguments, environment_entries, definition.package_artifact, definition.distributed_artifact)
	language_service_inspection_row(state, 3, "Definition: root-policy=%v languages=%v requested=%v features=%v", root_policy, languages, requested_capabilities, feature_policy)
	language_service_inspection_row(state, 4, "Preferences: position-encoding=%v synchronization=%v", preferred_encoding, preferred_sync)
	language_service_inspection_row(state, 5, "Workflow sessions: total=%d active=%d initializing=%d failed=%d; registry definitions=%d providers=%d retained=%d", active_sessions + initializing_sessions + failed_sessions, active_sessions, initializing_sessions, failed_sessions, registry.usage.service_definitions, registry.usage.providers, registry.usage.retained_bytes)
	language_service_inspection_row(state, 6, "Registry failure: code=%v resource=%v limit=%d actual=%d", registry.latest_failure.code, registry.latest_failure.resource, registry.latest_failure.limit, registry.latest_failure.actual)
	language_service_inspection_row(state, 7, "Definition failure: code=%v resource=%v", definition_failure.code, definition_failure.resource)
	language_service_inspection_row(state, 18, "Catalog: id=%d generation=%d language-generation=%d definitions=%d selections=%d", catalog.catalog_id, catalog.catalog_generation, catalog.language_generation, catalog.definition_count, catalog.selection_count)
	language_service_inspection_row(state, 19, "Catalog sources: confirmed=%d conflicts=%d participants=%d", catalog.source_count, catalog.conflict_count, catalog.participant_count)
	language_service_inspection_row(state, 21, "Catalog rejection: code=%v field=%v source=%v generation=%d limit=%d actual=%d", catalog.latest_rejection.code, catalog.latest_rejection.field, catalog.latest_rejection.source, catalog.latest_rejection.source_generation, catalog.latest_rejection.limit, catalog.latest_rejection.actual)
	if session_found {
		owner := &workflow.sessions[index]
		process, process_ok := language_service.process_session_inspect(&owner.process)
		synchronization, synchronization_ok := language_service.document_synchronizer_inspect(&owner.synchronizer)
		diagnostics, diagnostics_ok := language_service.diagnostic_store_inspect(&owner.diagnostics)
		health := language_service.Health.Stopped
		process_state := language_service.Process_State.None
		process_id := i64(0)
		restart_count := u8(0)
		process_usage := language_service.Resource_Usage{}
		process_failure := language_service.Failure_Context{}
		if process_ok {
			health = process.session.health
			process_state = process.process.state
			process_id = process.process.os_process_id
			restart_count = process.session.automatic_restarts
			process_usage = process.usage
			process_failure = process.failure
		}
		language_service_inspection_row(state, 8, "Session: phase=%v reconciliation=%v id=%d@%d health=%v project=%d@%d membership=%d@%d", owner.phase, owner.reconciliation, owner.handle.id, owner.handle.generation, health, owner.project.id, owner.project.generation, owner.membership.id, owner.membership.generation)
		language_service_inspection_row(state, 9, "Process: state=%v pid=%d restarts=%d/%d stderr-bytes=%d", process_state, process_id, restart_count, restart.automatic_restarts, process_usage.standard_error_bytes)
		language_service_inspection_row(state, 10, "Protocol: capabilities=%v features=%v encoding=%v synchronization=%v", process.session.capabilities, owner.active_features, process.session.position_encoding, process.session.synchronization_mode)
		if synchronization_ok {
			language_service_inspection_row(state, 11, "Documents: count=%d revoked=%v queue=%d bytes=%d", synchronization.documents, synchronization.revoked, synchronization.queue_depth, synchronization.queue_bytes)
		} else {
			language_service_inspection_row(state, 11, "Documents: unavailable")
		}
		if diagnostics_ok {
			language_service_inspection_row(state, 12, "Diagnostics: generations=%d current=%d server-versioned=%d receipt-bound=%d bytes=%d", diagnostics.generations, diagnostics.diagnostics, diagnostics.server_versioned, diagnostics.receipt_bound, diagnostics.diagnostic_bytes)
			language_service_inspection_row(state, 13, "Diagnostic severity: errors=%d warnings=%d information=%d hints=%d", diagnostics.errors, diagnostics.warnings, diagnostics.information, diagnostics.hints)
		} else {
			language_service_inspection_row(state, 12, "Diagnostics: unavailable")
			language_service_inspection_row(state, 13, "Diagnostic severity: unavailable")
		}
		language_service_inspection_row(state, 14, "Resources: queue=%d/%d diagnostics=%d/%d retained=%d", process_usage.queue_depth, process_usage.queue_bytes, diagnostics.diagnostics, diagnostics.diagnostic_bytes, process_usage.retained_bytes + diagnostics.retained_bytes)
		language_service_inspection_row(state, 15, "Failures: workflow=%v session=%v process=%v synchronization=%v diagnostics=%v", workflow.latest_failure.code, owner.latest_failure.code, process_failure.code, synchronization.latest_failure.code, diagnostics.latest_failure.code)
		stderr_text := ""
		stderr_storage: []u8
		if process_ok && process_usage.standard_error_bytes > 0 && process_usage.standard_error_bytes <= limits.standard_error_bytes {
			stderr_error: runtime.Allocator_Error
			stderr_storage, stderr_error = make([]u8, int(process_usage.standard_error_bytes), temporary_allocator)
			if stderr_error == nil {
				count, copied := language_service.process_session_copy_stderr(&owner.process, stderr_storage)
				if copied do stderr_text = string(stderr_storage[:count])
			}
		}
		language_service_inspection_row(state, 16, "Standard error: %q", stderr_text)
		if stderr_storage != nil do delete(stderr_storage, temporary_allocator)
		language_service_inspection_row(state, 17, "Policy: documents=%d diagnostics=%d queue-bytes=%d stderr-bytes=%d work=%d retained=%d init-ns=%d request-ns=%d shutdown-ns=%d restart-stability-ns=%d", limits.documents_per_session, limits.diagnostics_per_project, limits.queue_bytes, limits.standard_error_bytes, limits.work_bytes_per_turn, limits.retained_bytes, deadlines.initialization_ns, deadlines.request_ns, deadlines.shutdown_ns, restart.stability_ns)
		language_service_inspection_row(state, 20, "Catalog session key: language=%d@%d definition=%d@%d catalog=%d root=%q", owner.language.id, owner.language.generation, owner.definition.id, owner.definition.generation, owner.catalog_generation, owner.root)
		catalog_row := LANGUAGE_SERVICE_INSPECTION_BASE_ROWS
		for definition_index in 0 ..< int(catalog.definition_count) {
			catalog_definition := &catalog.definitions[definition_index]
			language_service_inspection_row(state, catalog_row, "Catalog definition %d: identity=%q handle=%d@%d source=%v scope=%q source-generation=%d enabled=%v default=%v languages=%d provenance=%q", definition_index + 1, language_service.service_identity_text_view(&catalog_definition.identity), catalog_definition.definition.id, catalog_definition.definition.generation, catalog_definition.scope.source, language_service.service_scope_text_view(&catalog_definition.scope.name), catalog_definition.source_generation, catalog_definition.policy.enabled, catalog_definition.policy.default_selection, catalog_definition.language_count, language_service.service_provenance_text_view(&catalog_definition.provenance))
			catalog_row += 1
		}
		for selection_index in 0 ..< int(catalog.selection_count) {
			catalog_selection := &catalog.selections[selection_index]
			language_service_inspection_row(state, catalog_row, "Catalog explicit selection %d: language=%d@%d identity=%q source=%v scope=%q source-generation=%d", selection_index + 1, catalog_selection.language.id, catalog_selection.language.generation, language_service.service_identity_text_view(&catalog_selection.service_identity), catalog_selection.scope.source, language_service.service_scope_text_view(&catalog_selection.scope.name), catalog_selection.source_generation)
			catalog_row += 1
		}
		for conflict_index in 0 ..< int(catalog.conflict_count) {
			catalog_conflict := &catalog.conflicts[conflict_index]
			language_service_inspection_row(state, catalog_row, "Catalog conflict %d: kind=%v identity=%q participants=%d fallback=%d@%d", conflict_index + 1, catalog_conflict.kind, language_service.service_identity_text_view(&catalog_conflict.identity), catalog_conflict.participants.count, catalog_conflict.fallback.id, catalog_conflict.fallback.generation)
			catalog_row += 1
		}
		for binding, binding_index in owner.documents {
			descriptor, described, _ := language_service.document_synchronizer_binding(
				&owner.synchronizer,
				binding.binding,
			)
			uri, uri_ok, _ := language_service.document_synchronizer_uri(
				&owner.synchronizer,
				binding.binding,
			)
			if described && uri_ok {
				language_service_inspection_row(state, LANGUAGE_SERVICE_INSPECTION_BASE_ROWS + catalog_rows + binding_index, "Document %d: buffer=%d document=%d state=%v revision=%d version=%d sync-generation=%d uri=%q", binding_index + 1, descriptor.buffer_identity, descriptor.document_identity, descriptor.state, descriptor.canonical_revision, descriptor.document_version, descriptor.synchronization_generation, uri)
			} else {
				language_service_inspection_row(state, LANGUAGE_SERVICE_INSPECTION_BASE_ROWS + catalog_rows + binding_index, "Document %d: unavailable", binding_index + 1)
			}
		}
	} else {
		for row in 8 ..< 18 {
			language_service_inspection_row(state, row, "Service session: unavailable; workflow failure=%v", workflow.latest_failure.code)
		}
		language_service_inspection_row(state, 20, "Catalog session key: unavailable")
		catalog_row := LANGUAGE_SERVICE_INSPECTION_BASE_ROWS
		for definition_index in 0 ..< int(catalog.definition_count) {
			catalog_definition := &catalog.definitions[definition_index]
			language_service_inspection_row(state, catalog_row, "Catalog definition %d: identity=%q handle=%d@%d source=%v scope=%q source-generation=%d enabled=%v default=%v languages=%d provenance=%q", definition_index + 1, language_service.service_identity_text_view(&catalog_definition.identity), catalog_definition.definition.id, catalog_definition.definition.generation, catalog_definition.scope.source, language_service.service_scope_text_view(&catalog_definition.scope.name), catalog_definition.source_generation, catalog_definition.policy.enabled, catalog_definition.policy.default_selection, catalog_definition.language_count, language_service.service_provenance_text_view(&catalog_definition.provenance))
			catalog_row += 1
		}
		for selection_index in 0 ..< int(catalog.selection_count) {
			catalog_selection := &catalog.selections[selection_index]
			language_service_inspection_row(state, catalog_row, "Catalog explicit selection %d: language=%d@%d identity=%q source=%v scope=%q source-generation=%d", selection_index + 1, catalog_selection.language.id, catalog_selection.language.generation, language_service.service_identity_text_view(&catalog_selection.service_identity), catalog_selection.scope.source, language_service.service_scope_text_view(&catalog_selection.scope.name), catalog_selection.source_generation)
			catalog_row += 1
		}
		for conflict_index in 0 ..< int(catalog.conflict_count) {
			catalog_conflict := &catalog.conflicts[conflict_index]
			language_service_inspection_row(state, catalog_row, "Catalog conflict %d: kind=%v identity=%q participants=%d fallback=%d@%d", conflict_index + 1, catalog_conflict.kind, language_service.service_identity_text_view(&catalog_conflict.identity), catalog_conflict.participants.count, catalog_conflict.fallback.id, catalog_conflict.fallback.generation)
			catalog_row += 1
		}
	}
	state.ready = true
	return true
}

// Language_Service_Inspection_List_Definitions projects copied rows into UI definitions.
Language_Service_Inspection_List_Definitions :: proc(
	state: ^Language_Service_Inspection_Workflow_State,
	allocator: runtime.Allocator,
) -> ([]ui.List_Item_Definition, bool) {
	if state == nil || !state.ready || len(state.rows) == 0 || allocator.procedure == nil {
		return nil, false
	}
	items, allocation_error := make([]ui.List_Item_Definition, len(state.rows), allocator)
	if allocation_error != nil do return nil, false
	for row, index in state.rows {
		items[index] = {
			id = ui.List_Item_ID(index + 1),
			text = row,
			action = {
				owner_id = LANGUAGE_SERVICE_INSPECTION_UI_OWNER_ID,
				action_id = LANGUAGE_SERVICE_INSPECTION_CLOSE_ACTION,
				generation = state.model_generation,
			},
		}
	}
	return items, true
}
