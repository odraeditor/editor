// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../command"
import "../completion"
import "../document"
import "../editor"
import "../editor_session"
import "../interaction"
import "../language"
import "../language_service"
import edit_transaction "../transaction"
import editor_view "../view"
import "base:runtime"
import "core:fmt"

@(private)
Completion_Workflow_Target :: struct {
	entry:     editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
	view:      editor_view.View_Handle,
}

@(private)
Completion_Workflow_Pending :: struct {
	active:            bool,
	manual:            bool,
	trigger:           completion.Trigger_Kind,
	trigger_character: completion.Text,
	target:            Completion_Workflow_Target,
}

@(private)
Completion_Service_Context :: struct {
	owner:        ^Language_Service_Workflow_Session,
	document:     ^Language_Service_Workflow_Document,
	descriptor:   language_service.Document_Binding_Descriptor,
	capabilities: language_service.Capability_Values,
}

@(private)
Completion_Workflow_State :: struct {
	registry:              completion.Role_Registry,
	composition:           completion.Composition_Scope,
	controller:            completion.Controller,
	exchange:              language_service.Completion_Exchange,
	exchange_live:         bool,
	dispatch_pending:      bool,
	pending:               Completion_Workflow_Pending,
	target:                Completion_Workflow_Target,
	context_map:           command.Completion_Context_Map,
	configuration:         Completion_Configuration_State,
	next_session_id:       completion.Session_ID,
	next_session_generation: completion.Session_Generation,
	next_request_id:       completion.Request_ID,
	next_request_generation: completion.Request_Generation,
	controller_generation: completion.Controller_Generation,
	presentation_generation: u64,
	popup_generation:      u64,
	detail_open:           bool,
	latest_completion_failure: completion.Failure,
	latest_service_failure: language_service.Failure_Context,
	allocator:             runtime.Allocator,
	initialized:           bool,
	closed:                bool,
}

@(private)
completion_workflow_init :: proc(
	workflow: ^Completion_Workflow_State,
	configuration: Completion_Configuration_State,
	allocator := context.allocator,
	controller_generation := completion.Controller_Generation(1),
) -> bool {
	if workflow == nil || allocator.procedure == nil || controller_generation == 0 {
		return false
	}
	workflow^ = {}
	factory := completion.factory_configuration()
	factory.enabled = configuration.enabled
	factory.session = configuration.session
	factory.limits = configuration.limits
	if !completion.factory_configuration_is_valid(factory) {
		return false
	}
	registry_ready, registry_failure := completion.registry_init(
		&workflow.registry,
		completion.Role_Registry_ID(1),
		configuration.limits,
		allocator,
	)
	if !registry_ready {
		workflow.latest_completion_failure = registry_failure
		return false
	}
	scope, scoped, scope_failure := completion.registry_scope(&workflow.registry)
	if !scoped {
		workflow.latest_completion_failure = scope_failure
		completion.registry_close(&workflow.registry)
		return false
	}
	configured, configuration_ok, configuration_failure := completion.registry_configure(
		&workflow.registry,
		scope,
		factory,
	)
	if !configuration_ok {
		workflow.latest_completion_failure = configuration_failure
		completion.registry_close(&workflow.registry)
		return false
	}
	controller_ready, controller_failure := completion.controller_init(
		&workflow.controller,
		completion.Controller_ID(1),
		controller_generation,
		configured,
		configuration.limits,
		allocator,
		configuration.session,
	)
	if !controller_ready {
		workflow.latest_completion_failure = controller_failure
		completion.registry_close(&workflow.registry)
		return false
	}
	if !command.completion_context_map_init(&workflow.context_map) {
		completion.controller_close(&workflow.controller)
		completion.registry_close(&workflow.registry)
		return false
	}
	workflow.composition = configured
	workflow.configuration = configuration
	workflow.next_session_id = 1
	workflow.next_session_generation = 1
	workflow.next_request_id = 1
	workflow.next_request_generation = 1
	workflow.controller_generation = controller_generation
	workflow.presentation_generation = 1
	workflow.popup_generation = 1
	workflow.allocator = allocator
	workflow.initialized = true
	return true
}

@(private)
completion_workflow_close :: proc(workflow: ^Completion_Workflow_State) -> bool {
	if !completion_workflow_is_live(workflow) do return false
	completion_workflow_end_session(workflow, nil, false)
	if workflow.controller.state != nil do completion.controller_close(&workflow.controller)
	if workflow.registry.state != nil do completion.registry_close(&workflow.registry)
	workflow.initialized = false
	workflow.closed = true
	return true
}

@(private)
completion_workflow_prepare_reconfiguration :: proc(
	workflow: ^Completion_Workflow_State,
	configuration: Completion_Configuration_State,
) -> (candidate: Completion_Workflow_State, ok: bool) {
	if !completion_workflow_is_live(workflow) ||
	   workflow.controller_generation == completion.Controller_Generation(max(u64)) {
		return {}, false
	}
	if !completion_workflow_init(
		&candidate,
		configuration,
		workflow.allocator,
		workflow.controller_generation + 1,
	) {
		return {}, false
	}
	candidate.next_session_id = workflow.next_session_id
	candidate.next_session_generation = workflow.next_session_generation
	candidate.next_request_id = workflow.next_request_id
	candidate.next_request_generation = workflow.next_request_generation
	candidate.presentation_generation = workflow.presentation_generation
	candidate.popup_generation = workflow.popup_generation
	return candidate, true
}

@(private)
completion_workflow_publish_reconfiguration :: proc(
	workflow: ^Completion_Workflow_State,
	candidate: ^Completion_Workflow_State,
) -> bool {
	if !completion_workflow_is_live(workflow) || !completion_workflow_is_live(candidate) {
		return false
	}
	completion_workflow_close(workflow)
	workflow^ = candidate^
	candidate^ = {}
	return true
}

@(private)
completion_workflow_request :: proc(
	workflow: ^Completion_Workflow_State,
	entry: editor_session.Entry_Handle,
	buffer: ^editor.Buffer,
	view: editor_view.View_Handle,
	trigger: completion.Trigger_Kind,
	trigger_character := completion.Text{},
	manual := false,
) -> bool {
	if !completion_workflow_is_live(workflow) || buffer == nil ||
	   !workflow.configuration.enabled || trigger == .Invalid {
		return false
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok || !editor_session.entry_handle_is_valid(entry) || view.view_id == 0 {
		return false
	}
	completion_workflow_end_session(workflow, nil, false)
	workflow.pending = {
		active = true,
		manual = manual,
		trigger = trigger,
		trigger_character = trigger_character,
		target = {entry = entry, buffer_id = stats.buffer_id, view = view},
	}
	workflow.target = workflow.pending.target
	return true
}

@(private)
completion_workflow_step :: proc(
	commands: ^Command_Context,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
) -> bool {
	if commands == nil || !completion_workflow_is_live(commands.completion_workflow) {
		return false
	}
	workflow := commands.completion_workflow
	changed := false
	if workflow.exchange_live {
		state, polled, poll_failure := language_service.completion_exchange_poll(
			&workflow.exchange,
			language_service_workflow_now_ns(commands.language_service_workflow),
		)
		if polled && state == .Timed_Out {
			workflow.latest_service_failure = poll_failure
			_, workflow.latest_completion_failure = completion.controller_fail(
				&workflow.controller,
				{operation = .Fail, code = .Provider_Unavailable},
			)
			language_service.completion_exchange_close(&workflow.exchange)
			workflow.exchange_live = false
			workflow.dispatch_pending = false
			changed = true
		}
	}
	if workflow.pending.active {
		access, accessible, _ := editor_session.session_entry_access(
			session_owner,
			workflow.pending.target.entry,
		)
		if !accessible {
			workflow.pending = {}
			return true
		}
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !borrowed || entry.buffer == nil || entry.view_registry == nil {
			workflow.pending = {}
			return true
		}
		started, waiting := completion_workflow_start_pending(
			commands,
			entry,
			workflow.pending,
		)
		if started {
			workflow.pending = {}
			changed = true
		} else if !waiting {
			if workflow.pending.manual {
				command_context_set_diagnostic(commands, "Completion unavailable for current document")
			}
			workflow.pending = {}
			changed = true
		}
	}
	if workflow.dispatch_pending {
		dispatched, waiting := completion_workflow_dispatch_current(commands)
		if dispatched {
			workflow.dispatch_pending = false
			changed = true
		} else if !waiting {
			completion_workflow_end_session(workflow, nil, false)
			changed = true
		}
	}
	if changed && !completion_workflow_has_interaction(workflow) {
		completion_workflow_deactivate_map(commands, .Invalidated)
	}
	return changed
}

@(private)
completion_workflow_start_pending :: proc(
	commands: ^Command_Context,
	entry: editor_session.Entry_Borrow,
	pending: Completion_Workflow_Pending,
) -> (started: bool, waiting: bool) {
	workflow := commands.completion_workflow
	service, service_ready, service_waiting := completion_service_context(
		commands.language_service_workflow,
		pending.target.buffer_id,
	)
	if !service_ready do return false, service_waiting
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	logical, logical_ok, _ := editor_view.snapshot(entry.view_registry, pending.target.view)
	status, status_ok, _ := document.document_status(entry.document)
	language_inspection, _, _, language_ok := syntax_workflow_inspect_buffer(
		commands.syntax_workflow,
		entry.buffer,
	)
	if !stats_ok || !logical_ok || !status_ok || !language_ok || !entry.has_document ||
	   u64(stats.revision) != service.descriptor.transmitted_revision {
		return false, true
	}
	text, copied := language_service_workflow_copy_buffer(entry.buffer, workflow.allocator)
	if !copied do return false, false
	defer delete(text, workflow.allocator)
	query, query_ok, query_failure := completion.query_derive(
		string(text),
		u64(logical.point_position.byte_offset),
		pending.trigger,
		pending.trigger_character,
	)
	if !query_ok {
		workflow.latest_completion_failure = query_failure
		return false, false
	}
	request, request_ok := completion_workflow_request_value(
		workflow,
		service,
		status.document_id,
		stats,
		logical,
		language_inspection,
		query,
	)
	if !request_ok do return false, false
	controller_started, start_failure := completion.controller_start(
		&workflow.controller,
		workflow.next_session_id,
		workflow.next_session_generation,
		request,
		workflow.composition,
	)
	if !controller_started {
		workflow.latest_completion_failure = start_failure
		return false, false
	}
	if workflow.next_session_id == completion.Session_ID(max(u64)) ||
	   workflow.next_session_generation == completion.Session_Generation(max(u64)) {
		completion_workflow_end_session(workflow, nil, false)
		return false, false
	}
	workflow.next_session_id += 1
	workflow.next_session_generation += 1
	workflow.target = pending.target
	workflow.dispatch_pending = true
	dispatched: bool
	dispatched, waiting = completion_workflow_dispatch_current(commands)
	if dispatched do workflow.dispatch_pending = false
	return dispatched, waiting
}

@(private)
completion_workflow_dispatch_current :: proc(
	commands: ^Command_Context,
) -> (dispatched: bool, waiting: bool) {
	workflow := commands.completion_workflow
	inspection, inspected, inspect_failure := completion.controller_inspect(&workflow.controller)
	if !inspected {
		workflow.latest_completion_failure = inspect_failure
		return false, false
	}
	service, service_ready, service_waiting := completion_service_context(
		commands.language_service_workflow,
		workflow.target.buffer_id,
	)
	if !service_ready do return false, service_waiting
	if service.owner.handle.id != language_service.Session_ID(inspection.request.scope.server_session_id) ||
	   service.owner.handle.generation != language_service.Session_Generation(
		inspection.request.scope.server_session_generation,
	   ) || service.document.binding.id != language_service.Document_Binding_ID(
		inspection.request.scope.document_binding_id,
	   ) || service.document.binding.generation != language_service.Document_Binding_Generation(
		inspection.request.scope.document_binding_generation,
	   ) || service.descriptor.transmitted_revision != u64(inspection.request.scope.transmitted_revision) {
		return false, service.descriptor.transmitted_revision <
			u64(inspection.request.scope.transmitted_revision)
	}
	if workflow.exchange_live {
		language_service.completion_exchange_close(&workflow.exchange)
		workflow.exchange_live = false
	}
	exchange_ready, exchange_failure := language_service.completion_exchange_init(
		&workflow.exchange,
		service.owner.handle,
		service.document.binding,
		service.capabilities,
		allocator = workflow.allocator,
	)
	if !exchange_ready {
		workflow.latest_service_failure = exchange_failure
		return false, false
	}
	workflow.exchange_live = true
	queued, queue_failure := completion.controller_queue(&workflow.controller)
	if !queued {
		workflow.latest_completion_failure = queue_failure
		return false, false
	}
	_, prepared, prepare_failure := language_service.completion_exchange_prepare(
		&workflow.exchange,
		&service.owner.synchronizer,
		inspection.request,
		language_service_workflow_now_ns(commands.language_service_workflow),
	)
	if !prepared {
		workflow.latest_service_failure = prepare_failure
		return false, false
	}
	sent, send_failure := language_service.completion_exchange_send(
		&workflow.exchange,
		&service.owner.process,
	)
	if !sent {
		workflow.latest_service_failure = send_failure
		return false, false
	}
	confirmed, send_state_failure := completion.controller_send(&workflow.controller)
	if !confirmed {
		workflow.latest_completion_failure = send_state_failure
		return false, false
	}
	return true, false
}

@(private)
completion_workflow_request_value :: proc(
	workflow: ^Completion_Workflow_State,
	service: Completion_Service_Context,
	document_id: document.Document_ID,
	stats: editor.Buffer_Stats,
	logical: editor_view.Snapshot,
	language_inspection: language.Language_Selection_Inspection,
	query: completion.Query_Context,
) -> (completion.Request, bool) {
	provider := workflow.composition.selections[0].selected
	if workflow.next_request_id == 0 || workflow.next_request_generation == 0 ||
	   workflow.next_request_id == completion.Request_ID(max(u64)) ||
	   workflow.next_request_generation == completion.Request_Generation(max(u64)) ||
	   provider.implementation_id == 0 || provider.implementation_generation == 0 ||
	   language_inspection.association.language.id == 0 ||
	   language_inspection.association.language.generation == 0 {
		return {}, false
	}
	request := completion.Request {
		id = workflow.next_request_id,
		generation = workflow.next_request_generation,
		scope = {
			document_id = completion.Document_ID(document_id),
			buffer_id = completion.Buffer_ID(stats.buffer_id),
			document_revision = completion.Document_Revision(stats.revision),
			view_id = completion.View_ID(logical.view_id),
			view_generation = completion.View_Generation(logical.view_generation),
			language_id = completion.Language_ID(language_inspection.association.language.id),
			language_generation = completion.Language_Generation(
				language_inspection.association.language.generation,
			),
			provider_id = completion.Provider_ID(provider.implementation_id),
			provider_generation = completion.Provider_Generation(provider.implementation_generation),
			server_session_id = completion.Server_Session_ID(service.owner.handle.id),
			server_session_generation = completion.Server_Session_Generation(
				service.owner.handle.generation,
			),
			document_binding_id = completion.Document_Binding_ID(service.document.binding.id),
			document_binding_generation = completion.Document_Binding_Generation(
				service.document.binding.generation,
			),
			transmitted_revision = completion.Document_Revision(stats.revision),
		},
		cursor_byte = u64(logical.point_position.byte_offset),
		query_range = query.range,
		query = query.text,
		trigger = query.trigger,
		trigger_character = query.trigger_character,
		provider_capabilities = completion_provider_capabilities(service.capabilities),
		state = .Prepared,
	}
	workflow.next_request_id += 1
	workflow.next_request_generation += 1
	return request, completion.request_is_valid(&request)
}

@(private)
completion_service_context :: proc(
	workflow: ^Language_Service_Workflow_State,
	buffer_id: editor.Buffer_ID,
) -> (Completion_Service_Context, bool, bool) {
	if !language_service_workflow_is_live(workflow) do return {}, false, false
	for &owner in workflow.sessions {
		if !owner.live do continue
		for &document_entry in owner.documents {
			if document_entry.buffer_id != buffer_id do continue
			if owner.phase == .Initializing do return {}, false, true
			if owner.phase != .Active do return {}, false, false
			inspection, inspected := language_service.process_session_inspect(&owner.process)
			descriptor, described, _ := language_service.document_synchronizer_binding(
				&owner.synchronizer,
				document_entry.binding,
			)
			if !inspected || !described do return {}, false, true
			capabilities := language_service.Capability_Values {
				capabilities = inspection.session.capabilities,
				position_encoding = inspection.session.position_encoding,
				synchronization_mode = inspection.session.synchronization_mode,
				completion = owner.capabilities.completion,
			}
			if .Completion not_in capabilities.capabilities || !capabilities.completion.available {
				return {}, false, false
			}
			return {
				owner = &owner,
				document = &document_entry,
				descriptor = descriptor,
				capabilities = capabilities,
			}, true, false
		}
		if owner.phase == .Initializing do return {}, false, true
	}
	return {}, false, false
}

@(private)
completion_provider_capabilities :: proc(
	capabilities: language_service.Capability_Values,
) -> completion.Capabilities {
	if .Completion not_in capabilities.capabilities || !capabilities.completion.available {
		return {}
	}
	result := completion.Capabilities {
		.Explicit, .Identifier, .Incomplete, .Additional_Edits, .Documentation,
	}
	if capabilities.completion.resolve do result += {.Resolve}
	if capabilities.completion.trigger_count > 0 do result += {.Trigger_Character}
	return result
}

@(private)
completion_workflow_receive_message :: proc(
	workflow: ^Completion_Workflow_State,
	owner: ^Language_Service_Workflow_Session,
	message: ^language_service.Message,
) -> (handled: bool, changed: bool) {
	if !completion_workflow_is_live(workflow) || !workflow.exchange_live ||
	   owner == nil || message == nil || message.closed {
		return false, false
	}
	inspection, inspected := language_service.completion_exchange_inspect(&workflow.exchange)
	if !inspected || inspection.session != owner.handle || !message.record.has_id ||
	   message.record.id != inspection.request_id {
		return false, false
	}
	batch_owner, normalized, normalization_failure :=
		language_service.completion_response_normalize(
			&workflow.exchange,
			&owner.synchronizer,
			message,
			workflow.allocator,
		)
	if !normalized {
		workflow.latest_service_failure = normalization_failure
		_, workflow.latest_completion_failure = completion.controller_fail(
			&workflow.controller,
			{operation = .Fail, code = .Provider_Unavailable},
		)
		language_service.completion_exchange_close(&workflow.exchange)
		workflow.exchange_live = false
		return true, true
	}
	defer language_service.completion_batch_owner_close(&batch_owner)
	published, publish_failure := completion.controller_publish(
		&workflow.controller,
		&batch_owner.batch,
	)
	language_service.completion_exchange_close(&workflow.exchange)
	workflow.exchange_live = false
	if !published {
		workflow.latest_completion_failure = publish_failure
		return true, true
	}
	workflow.latest_completion_failure = {}
	workflow.latest_service_failure = {}
	workflow.detail_open = false
	return true, true
}

@(private)
completion_workflow_matches_service :: proc(
	workflow: ^Completion_Workflow_State,
	owner: ^Language_Service_Workflow_Session,
) -> bool {
	if !completion_workflow_is_live(workflow) || owner == nil do return false
	inspection, inspected, _ := completion.controller_inspect(&workflow.controller)
	return inspected && inspection.request.scope.server_session_id ==
		completion.Server_Session_ID(owner.handle.id) &&
		inspection.request.scope.server_session_generation ==
		completion.Server_Session_Generation(owner.handle.generation)
}

@(private)
completion_workflow_after_command :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	route: command.Native_Route,
	result: ^command.Native_Result,
) {
	workflow := commands.completion_workflow
	if !completion_workflow_is_live(workflow) || result == nil {
		return
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return
	inspection, active, _ := completion.controller_inspect(&workflow.controller)
	if active && inspection.state != .Invalid && inspection.state != .Retired &&
	   inspection.state != .Dismissed &&
	   (completion.Buffer_ID(stats.buffer_id) != inspection.request.scope.buffer_id ||
	    workflow.target.view != view || result.completion == .View_Changed) {
		completion_workflow_cancel_current(commands, false)
		return
	}
	if result.completion != .Buffer_Committed do return
	if active && inspection.state != .Invalid && inspection.state != .Retired &&
	   inspection.state != .Dismissed &&
	   completion.Buffer_ID(workflow.target.buffer_id) == inspection.request.scope.buffer_id &&
	   workflow.target.view == view {
		completion_workflow_refine_after_commit(
			commands,
			buffer,
			view_registry,
			view,
			inspection,
		)
		return
	}
	if route != .Insert_Text || !workflow.configuration.enabled {
		return
	}
	trigger := completion.Trigger_Kind.Identifier
	trigger_text: completion.Text
	if service, ready, _ := completion_service_context(
		commands.language_service_workflow,
		stats.buffer_id,
	); ready && len(result.commit.splices) > 0 {
		replacement := result.commit.splices[len(result.commit.splices) - 1].replacement_text
		for index in 0 ..< int(service.capabilities.completion.trigger_count) {
			candidate := service.capabilities.completion.trigger_characters[index]
			value := string(candidate.bytes[:candidate.length])
			if value != "" && len(replacement) >= len(value) &&
			   replacement[len(replacement) - len(value):] == value {
				trigger = .Trigger_Character
				trigger_text, _ = completion.text_copy(value)
				break
			}
		}
	}
	_ = completion_workflow_request(
		workflow,
		commands.current_entry,
		buffer,
		view,
		trigger,
		trigger_text,
		false,
	)
}

@(private)
completion_workflow_refine_after_commit :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	inspection: completion.Session_Inspection,
) {
	workflow := commands.completion_workflow
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	logical, logical_ok, _ := editor_view.snapshot(view_registry, view)
	text, copied := language_service_workflow_copy_buffer(buffer, workflow.allocator)
	if !stats_ok || !logical_ok || !copied {
		completion_workflow_end_session(workflow, nil, false)
		return
	}
	defer delete(text, workflow.allocator)
	query, query_ok, _ := completion.query_derive(
		string(text),
		u64(logical.point_position.byte_offset),
		.Incomplete,
		{},
		inspection.query_range,
	)
	if !query_ok {
		completion_workflow_end_session(workflow, nil, false)
		return
	}
	request := inspection.request
	request.id = workflow.next_request_id
	request.generation = workflow.next_request_generation
	request.scope.document_revision = completion.Document_Revision(stats.revision)
	request.scope.transmitted_revision = completion.Document_Revision(stats.revision)
	request.cursor_byte = u64(logical.point_position.byte_offset)
	request.query_range = query.range
	request.query = query.text
	request.trigger = .Incomplete
	request.trigger_character = {}
	request.state = .Prepared
	workflow.next_request_id += 1
	workflow.next_request_generation += 1
	action, refined, refine_failure := completion.controller_refine(&workflow.controller, request)
	if !refined {
		workflow.latest_completion_failure = refine_failure
		completion_workflow_end_session(workflow, nil, false)
		return
	}
	workflow.detail_open = false
	if action == .Provider_Request {
		service, service_ready, _ := completion_service_context(
			commands.language_service_workflow,
			workflow.target.buffer_id,
		)
		completion_workflow_end_transport(
			workflow,
			service.owner if service_ready else nil,
			service_ready,
		)
		workflow.dispatch_pending = true
	}
}

@(private)
command_context_dispatch_completion_route :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
	view_registry: ^editor_view.Registry,
	view: editor_view.View_Handle,
	route: command.Native_Route,
	transaction_id: edit_transaction.Transaction_ID,
	undo_unit_id: edit_transaction.Undo_Unit_ID,
) -> (Interaction_Result, App_Failure) {
	workflow := commands.completion_workflow
	if !completion_workflow_is_live(workflow) {
		return {}, App_Failure{stage = .Completion}
	}
	#partial switch route {
	case .Complete_At_Point:
		requested := completion_workflow_request(
			workflow,
			commands.current_entry,
			buffer,
			view,
			.Explicit,
			manual = true,
		)
		if !requested {
			command_context_set_diagnostic(commands, "Completion is disabled")
		}
		return Interaction_Result{changed = true}, {}
	case .Completion_Next, .Completion_Previous, .Completion_First, .Completion_Last:
		movement := completion.Selection_Movement.Next
		if route == .Completion_Previous do movement = .Previous
		if route == .Completion_First do movement = .First
		if route == .Completion_Last do movement = .Last
		moved, move_failure := completion.controller_move_selection(&workflow.controller, movement)
		if !moved do workflow.latest_completion_failure = move_failure
		workflow.detail_open = false
		return Interaction_Result{changed = true}, {}
	case .Completion_Accept:
		scope, scoped, scope_failure := completion.controller_acceptance_scope(&workflow.controller)
		if !scoped {
			workflow.latest_completion_failure = scope_failure
			return Interaction_Result{changed = true}, {}
		}
		logical, logical_ok, _ := editor_view.snapshot(view_registry, view)
		if !logical_ok do return {}, App_Failure{stage = .Completion}
		observer_context := Syntax_Commit_Observer_Context {
			workflow = commands.syntax_workflow,
			buffer = buffer,
		}
		_, accepted, acceptance_failure := completion.controller_accept_candidate(
			&workflow.controller,
			scope,
			completion.Acceptance_Target {
				buffer = buffer,
				view_registry = view_registry,
				view = view,
				history_store = commands.history_store,
				transaction_id = transaction_id,
				undo_unit_id = undo_unit_id,
				allocators = {
					persistent = commands.persistent_allocator,
					temporary = commands.temporary_allocator,
				},
				transaction_limits = edit_transaction.DEFAULT_LIMITS,
				commit_observer = syntax_workflow_commit_observer(&observer_context),
				desired_display_column = logical.desired_display_column,
				writable = true,
			},
		)
		if !accepted {
			workflow.latest_completion_failure = acceptance_failure.completion
			command_context_set_diagnostic(commands, "Completion candidate could not be applied")
		} else {
			completion_workflow_end_transport(workflow, nil, false)
			workflow.detail_open = false
		}
		return Interaction_Result{changed = true}, {}
	case .Completion_Cancel:
		completion_workflow_cancel_current(commands, true)
		return Interaction_Result{changed = true}, {}
	case .Completion_Inspect, .Describe_Completion_State:
		completion_workflow_set_inspection_diagnostic(commands)
		return Interaction_Result{changed = true}, {}
	case .Completion_Show_Documentation:
		workflow.detail_open = !workflow.detail_open
		return Interaction_Result{changed = true}, {}
	case:
		return {}, App_Failure{stage = .Completion}
	}
}

@(private)
completion_workflow_set_inspection_diagnostic :: proc(commands: ^Command_Context) {
	workflow := commands.completion_workflow
	inspection, inspected, _ := completion.controller_inspect(&workflow.controller)
	if !inspected {
		command_context_set_diagnostic(commands, "Completion unavailable")
		return
	}
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Completion %v: %d candidate(s), %d visible, selected %d",
		inspection.state,
		inspection.candidate_count,
		inspection.filtered_candidate_count,
		u64(inspection.selected_candidate),
	)
	commands.diagnostic_length = len(message)
}

@(private)
command_context_sync_completion_map :: proc(commands: ^Command_Context) -> App_Failure {
	workflow := commands.completion_workflow
	if !completion_workflow_has_interaction(workflow) do return {}
	definition := workflow.context_map.definition
	if interaction.context_map_handle_is_valid(commands.interaction_workflow.map_handle) {
		if commands.interaction_workflow.map_handle.identity == definition.identity {
			command_context_suspend_modal_pending(commands, false)
			return {}
		}
		command_context_deactivate_context_map(commands, .Invalidated)
	}
	result, activated, activation_failure := interaction.context_map_activate(
		commands.context_maps,
		definition,
		&commands.context_pending,
		&commands.pending,
	)
	if !activated {
		return App_Failure{stage = .Command_Resolution, interaction = activation_failure}
	}
	commands.interaction_workflow.map_handle = result.handle
	command_context_suspend_modal_pending(commands, false)
	return {}
}

@(private)
completion_workflow_deactivate_map :: proc(
	commands: ^Command_Context,
	end: interaction.Context_Map_End,
) {
	if commands == nil ||
	   !interaction.context_map_handle_is_valid(commands.interaction_workflow.map_handle) {
		return
	}
	definition := commands.completion_workflow.context_map.definition
	if commands.interaction_workflow.map_handle.identity != definition.identity do return
	command_context_deactivate_context_map(commands, end)
}

@(private)
completion_workflow_cancel_current :: proc(commands: ^Command_Context, send_cancel: bool) {
	if commands == nil || !completion_workflow_is_live(commands.completion_workflow) do return
	workflow := commands.completion_workflow
	service, service_ready, _ := completion_service_context(
		commands.language_service_workflow,
		workflow.target.buffer_id,
	)
	completion_workflow_end_session(
		workflow,
		service.owner if service_ready else nil,
		send_cancel && service_ready,
	)
	completion_workflow_deactivate_map(commands, .Cancelled)
}

@(private)
completion_workflow_has_interaction :: proc(workflow: ^Completion_Workflow_State) -> bool {
	if !completion_workflow_is_live(workflow) do return false
	inspection, inspected, _ := completion.controller_inspect(&workflow.controller)
	return inspected && (inspection.state == .Ready ||
		(inspection.state == .Requesting && inspection.retained_during_refresh))
}

@(private)
completion_workflow_end_session :: proc(
	workflow: ^Completion_Workflow_State,
	service_owner: ^Language_Service_Workflow_Session,
	send_cancel: bool,
) {
	if !completion_workflow_is_live(workflow) do return
	completion_workflow_end_transport(workflow, service_owner, send_cancel)
	inspection, inspected, _ := completion.controller_inspect(&workflow.controller)
	if inspected && inspection.state != .Invalid && inspection.state != .Retired {
		if inspection.state != .Dismissed do _, _ = completion.controller_cancel(&workflow.controller)
		_, _ = completion.controller_retire(&workflow.controller)
	}
	workflow.pending = {}
	workflow.dispatch_pending = false
	workflow.detail_open = false
}

@(private)
completion_workflow_end_transport :: proc(
	workflow: ^Completion_Workflow_State,
	service_owner: ^Language_Service_Workflow_Session,
	send_cancel: bool,
) {
	if workflow == nil || !workflow.exchange_live do return
	if send_cancel && service_owner != nil {
		_, _ = language_service.completion_exchange_cancel(
			&workflow.exchange,
			&service_owner.process,
		)
	}
	language_service.completion_exchange_close(&workflow.exchange)
	workflow.exchange_live = false
}

@(private)
completion_workflow_is_live :: proc(workflow: ^Completion_Workflow_State) -> bool {
	return workflow != nil && workflow.initialized && !workflow.closed &&
		workflow.registry.state != nil && workflow.controller.state != nil
}
