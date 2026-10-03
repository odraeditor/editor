// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import "../document"
import "../editor"
import "../editor_session"
import "../interaction"
import "../language"
import "../language_service"
import project_core "../project"
import "../ui"
import "base:runtime"
import json "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

@(private)
Language_Service_Workflow_Phase :: enum u8 {
	None,
	Initializing,
	Active,
	Failed,
}

@(private)
Language_Service_Reconciliation :: enum u8 {
	Unchanged,
	Expandable,
	Replacement_Required,
	Retiring,
	Restricted,
	Unavailable,
	Failed,
	Replacement_Fallback,
}

@(private)
Language_Service_Workflow_Document :: struct {
	entry:          editor_session.Entry_Handle,
	buffer_id:      editor.Buffer_ID,
	document_id:    document.Document_ID,
	binding:        language_service.Document_Binding_Handle,
	canonical_revision: u64,
	saved_revision: u64,
	seen:           bool,
}

@(private)
Language_Service_Workflow_Session :: struct {
	live:                 bool,
	phase:                Language_Service_Workflow_Phase,
	project:              project_core.Project_Handle,
	membership:           project_core.Membership_Handle,
	language:             language.Language_Identity,
	definition:           language_service.Definition_Handle,
	catalog_generation:   language_service.Service_Catalog_Generation,
	root:                 string,
	handle:               language_service.Session_Handle,
	project_access:       editor_session.Project_Registry_Access,
	process:              language_service.Process_Session,
	synchronizer:         language_service.Document_Synchronizer,
	diagnostics:          language_service.Diagnostic_Store,
	capabilities:         language_service.Capability_Values,
	active_features:      language_service.Service_Features,
	selected:             bool,
	fallback:             bool,
	reconciliation:       Language_Service_Reconciliation,
	documents:            [dynamic]Language_Service_Workflow_Document,
	latest_failure:       language_service.Failure_Context,
}

@(private)
Language_Service_Workflow_State :: struct {
	registry:        language_service.Provider_Registry,
	catalog:         language_service.Service_Catalog,
	factory:         language_service.Definition_Handle,
	sessions:        [dynamic]Language_Service_Workflow_Session,
	retired_definitions: [language_service.MAX_SERVICE_CATALOG_DEFINITIONS]language_service.Definition_Handle,
	retired_definition_count: u16,
	next_session_id: language_service.Session_ID,
	clock_start:     time.Tick,
	latest_failure:  language_service.Failure_Context,
	allocator:       runtime.Allocator,
	initialized:     bool,
	closed:          bool,
}

@(private)
Language_Service_Diagnostic_Source :: struct {
	source:    interaction.Diagnostic_Candidate_Source,
	batches:   []language_service.Diagnostic_Batch_Copy,
	documents: []interaction.Diagnostic_Candidate_Document,
	count:     int,
	allocator: runtime.Allocator,
}

@(private)
Language_Service_Visible_Observation :: struct {
	present:               bool,
	language:              language.Language_Identity,
	binding_identity:      u64,
	diagnostic_generation: u64,
	errors:                u32,
	warnings:              u32,
	health:                Language_Service_Workflow_Phase,
}

@(private)
Language_Context_Projection :: struct {
	present:          bool,
	language:         language.Language_Identity,
	owner_generation: u64,
	service_health:   Language_Service_Workflow_Phase,
}

// Language_Service_Workflow_Project_Language_Context resolves presentation-neutral language health.
Language_Service_Workflow_Project_Language_Context :: proc(
	inspection: language.Language_Selection_Inspection,
	inspection_ok: bool,
	service: Language_Service_Visible_Observation,
) -> (projection: Language_Context_Projection) {
	if inspection_ok && inspection.association.language.id != 0 {
		projection.present = true
		projection.language = inspection.association.language
		projection.owner_generation = u64(inspection.selection_generation)
		if projection.owner_generation == 0 {
			projection.owner_generation = u64(projection.language.generation)
		}
	} else if service.present && service.language.id != 0 {
		projection.present = true
		projection.language = service.language
		projection.owner_generation = u64(service.language.generation)
	}
	if projection.present {
		projection.service_health = service.health
	}
	return
}

// Language_Service_Workflow_Init initializes service definitions and runtime ownership.
Language_Service_Workflow_Init :: proc(
	workflow: ^Language_Service_Workflow_State,
	allocator := context.allocator,
) -> (bool, language_service.Failure_Context) {
	if workflow == nil || allocator.procedure == nil {
		return false, language_service.Failure_Context{code = .Invalid_Input}
	}
	workflow^ = {}
	initialized, failure := language_service.provider_registry_init(
		&workflow.registry,
		language_service.Registry_Handle{id = 1, generation = 1},
		language_service.DEFAULT_LIMITS,
		allocator,
	)
	if !initialized do return false, failure
	factory, registered, factory_failure := language_service.provider_registry_register_factory_ols(
		&workflow.registry,
	)
	if !registered {
		language_service.provider_registry_close(&workflow.registry)
		return false, factory_failure
	}
	catalog_initialized, _ := language_service.service_catalog_init(
		&workflow.catalog,
		1,
		language_service.Registry_Handle{id = 1, generation = 1},
		allocator,
	)
	if !catalog_initialized {
		language_service.provider_registry_close(&workflow.registry)
		return false, language_service.Failure_Context{code = .Allocation}
	}
	odin_registration, odin_registered := language.factory_bundle_registration(
		language.FACTORY_ODIN_BUNDLE_IDENTITY,
	)
	if !odin_registered {
		_, _ = language_service.service_catalog_close(&workflow.catalog)
		language_service.provider_registry_close(&workflow.registry)
		return false, language_service.Failure_Context{code = .Invalid_Definition}
	}
	catalog_confirmed, _ := language_service.factory_ols_catalog_confirm(
		&workflow.catalog,
		factory,
		odin_registration.language,
	)
	if !catalog_confirmed {
		_, _ = language_service.service_catalog_close(&workflow.catalog)
		language_service.provider_registry_close(&workflow.registry)
		return false, language_service.Failure_Context{code = .Invalid_Definition}
	}
	sessions, allocation_error := make(
		[dynamic]Language_Service_Workflow_Session,
		0,
		int(language_service.DEFAULT_LIMITS.sessions),
		allocator,
	)
	if allocation_error != nil {
		_, _ = language_service.service_catalog_close(&workflow.catalog)
		language_service.provider_registry_close(&workflow.registry)
		return false, language_service.Failure_Context{code = .Allocation}
	}
	workflow.factory = factory
	workflow.sessions = sessions
	workflow.next_session_id = 1
	workflow.clock_start = time.tick_now()
	workflow.allocator = allocator
	workflow.initialized = true
	return true, {}
}

// Language_Service_Workflow_Reconcile aligns service sessions with eligible documents.
Language_Service_Workflow_Reconcile :: proc(
	workflow: ^Language_Service_Workflow_State,
	syntax: ^Syntax_Workflow_State,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	temporary_allocator := context.temp_allocator,
) -> bool {
	if !Language_Service_Workflow_Is_Live(workflow) || session_owner == nil ||
	   temporary_allocator.procedure == nil {
		return false
	}
	changed := false
	active, active_ok, active_failure := editor_session.session_active_project(
		session_owner,
		session_handle,
	)
	if !active_ok {
		_ = active_failure
		return false
	}
	catalog: language_service.Service_Catalog_Inspection
	catalog_ok, _ := language_service.service_catalog_inspect(&workflow.catalog, &catalog)
	if !catalog_ok || !active.active ||
	   catalog.catalog_generation == language_service.Service_Catalog_Generation(0) {
		return language_service_workflow_close_all(workflow) || changed
	}
	for index := len(workflow.sessions) - 1; index >= 0; index -= 1 {
		owner := &workflow.sessions[index]
		if owner.live && owner.project != active.descriptor.handle {
			owner.reconciliation = .Retiring
			language_service_workflow_session_close(workflow, index, false)
			changed = true
		}
	}
	memberships, memberships_ok, memberships_failure := editor_session.session_project_memberships(
		session_owner,
		session_handle,
		active.descriptor.handle,
	)
	if !memberships_ok {
		_ = memberships_failure
		return changed
	}
	defer project_core.descriptor_batch_close(&memberships)
	classified, classified_ok, classified_failure := editor_session.session_classify_project_buffers(
		session_owner,
		session_handle,
		active.descriptor.handle,
		temporary_allocator,
	)
	if !classified_ok {
		_ = classified_failure
		return changed
	}
	defer editor_session.project_buffer_batch_close(&classified)
	for &owner in workflow.sessions {
		if owner.live {
			owner.selected = false
			owner.fallback = false
			owner.reconciliation = .Retiring
			for &binding in owner.documents do binding.seen = false
		}
	}
	for descriptor in classified.descriptors {
		if descriptor.scope != .Project_Owned || descriptor.membership_count == 0 do continue
		access, accessible, _ := editor_session.session_entry_access(session_owner, descriptor.graph.entry)
		if !accessible do continue
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !borrowed || !entry.has_document || entry.document == nil do continue
		language_identity, eligible := language_service_workflow_entry_language_identity(syntax, entry)
		if !eligible do continue
		membership, trusted := language_service_workflow_most_specific_membership(
			descriptor,
			classified.memberships,
			memberships.descriptors,
		)
		if !trusted do continue
		root := language_service_workflow_membership_root(membership, memberships.descriptors)
		if root == "" do continue
		resolution, resolved, _ := language_service.service_catalog_resolve(
			&workflow.catalog,
			{
				language = language_identity,
				project_membership = root,
				resolved_root = root,
				project_trusted = true,
			},
		)
		if !resolved do continue
		definition, definition_ok, definition_failure := language_service.provider_registry_definition(
			&workflow.registry,
			resolution.selected,
		)
		if !definition_ok {
			workflow.latest_failure = definition_failure
			continue
		}
		root_resolution, root_resolved, root_failure := language_service.service_root_resolve(
			{
				membership_root = root,
				document_path = descriptor.normalized_path,
				explicit_root = definition.root,
				root_markers = definition.root_markers,
				limits = definition.definition.limits,
			},
		)
		if !root_resolved {
			workflow.latest_failure = root_failure
			continue
		}
		root = language_service.root_resolution_text(&root_resolution)
		resolution, resolved, _ = language_service.service_catalog_resolve(
			&workflow.catalog,
			{
				language = language_identity,
				project_membership = language_service_workflow_membership_root(
					membership,
					memberships.descriptors,
				),
				resolved_root = root,
				project_trusted = true,
			},
		)
		if !resolved do continue
		language_name := string(language_identity.name.bytes[:language_identity.name.length])
		owner_index, found := language_service_workflow_find_session(
			workflow,
			active.descriptor.handle,
			membership,
			language_identity,
			resolution.selected,
			root,
		)
		if !found {
			owner_index, found = language_service_workflow_session_start(
				workflow,
				session_owner,
				session_handle,
				active.descriptor.handle,
				membership,
				language_identity,
				resolution,
				definition,
				root,
			)
			changed = true
		}
		if !found do continue
		owner := &workflow.sessions[owner_index]
		owner.selected = true
		owner.catalog_generation = catalog.catalog_generation
		if owner.phase != .Active {
			owner.reconciliation = .Failed
			if owner.latest_failure.code == .Executable_Not_Found {
				owner.reconciliation = .Unavailable
			} else if owner.phase == .Initializing {
				owner.reconciliation = .Replacement_Required
			}
			stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
			if stats_ok {
				language_service_workflow_retain_fallback(
					workflow,
					stats.buffer_id,
					owner_index,
				)
			}
			continue
		}
		owner.reconciliation = .Unchanged if len(owner.documents) > 0 else .Expandable
		if language_service_workflow_reconcile_document(
			workflow,
			owner,
			descriptor.graph.entry,
			entry,
			descriptor.normalized_path,
			language_name,
		) {
			changed = true
		}
	}
	for &owner in workflow.sessions {
		if !owner.live || owner.phase != .Active do continue
		for index := len(owner.documents) - 1; index >= 0; index -= 1 {
			binding := &owner.documents[index]
			if binding.seen do continue
			_, _ = language_service.diagnostic_store_invalidate(&owner.diagnostics, binding.binding)
			_, _ = language_service.document_synchronizer_close_document(
				&owner.synchronizer,
				binding.binding,
				binding.canonical_revision,
			)
			ordered_remove(&owner.documents, index)
			changed = true
		}
	}
	for index := len(workflow.sessions) - 1; index >= 0; index -= 1 {
		owner := &workflow.sessions[index]
		if owner.live && !owner.selected && !owner.fallback {
			language_service_workflow_session_close(workflow, index, true)
			changed = true
		}
	}
	language_service_workflow_collect_retired_definitions(workflow)
	return changed
}

// Language_Service_Workflow_Maintain advances bounded service and protocol work.
Language_Service_Workflow_Maintain :: proc(
	workflow: ^Language_Service_Workflow_State,
	completion: Completion_Integration = {},
) -> bool {
	if !Language_Service_Workflow_Is_Live(workflow) do return false
	changed := false
	now_ns := Language_Service_Workflow_Now_Ns(workflow)
	for &owner in workflow.sessions {
		if !owner.live || owner.phase == .Failed do continue
		if owner.phase == .Active {
			language_service_workflow_flush_document_queue(&owner)
		}
		poll, polled := language_service.process_session_poll(&owner.process, now_ns)
		if !polled || poll.health == .Failed {
			if completion.matches_service != nil && completion.end_session != nil &&
			   completion.matches_service(completion.state, &owner) {
				completion.end_session(completion.state, &owner, false)
			}
			if owner.diagnostics.state != nil {
				for binding in owner.documents {
					_, _ = language_service.diagnostic_store_invalidate(
						&owner.diagnostics,
						binding.binding,
					)
				}
			}
			owner.phase = .Failed
			owner.latest_failure = poll.failure
			workflow.latest_failure = poll.failure
			changed = true
			continue
		}
		if !poll.frame_ready do continue
		frame, taken, frame_failure := language_service.process_session_take_frame(&owner.process)
		if !taken {
			owner.latest_failure = frame_failure
			continue
		}
		message, decoded, message_failure := language_service.message_decode(
			frame.body,
			language_service.DEFAULT_LIMITS,
			workflow.allocator,
		)
		language_service.frame_close(&frame)
		if !decoded {
			owner.latest_failure = message_failure
			continue
		}
		if owner.phase == .Initializing && message.record.kind == .Response &&
		   message.record.id.kind == .Integer && message.record.id.integer == 1 {
			if language_service_workflow_confirm_session(workflow, &owner, message.record.capabilities) {
				changed = true
			}
		} else if owner.phase == .Active && .Diagnostics in owner.active_features &&
		          language_service.message_method_is(&message, "textDocument/publishDiagnostics") {
			if language_service_workflow_publish_diagnostics(workflow, &owner, &message) {
				changed = true
			}
		} else if owner.phase == .Active {
			handled := false
			completion_changed := false
			if completion.receive_message != nil {
				handled, completion_changed = completion.receive_message(
					completion.state,
					&owner,
					&message,
				)
			}
			if handled {
				changed = changed || completion_changed
			} else {
				language_service_workflow_handle_unknown(&owner, &message)
			}
		} else {
			language_service_workflow_handle_unknown(&owner, &message)
		}
		language_service.message_close(&message)
	}
	return changed
}

// Language_Service_Workflow_Project_Visible projects diagnostics and copied health.
Language_Service_Workflow_Project_Visible :: proc(
	workflow: ^Language_Service_Workflow_State,
	buffer: ^editor.Buffer,
	proposal: ^ui.Proposal,
	text_view: ui.Object_Handle,
	owner_id: ui.Owner_ID,
) -> (observation: Language_Service_Visible_Observation) {
	if !Language_Service_Workflow_Is_Live(workflow) || buffer == nil || proposal == nil do return
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return
	for &session in workflow.sessions {
		if !session.live do continue
		for binding in session.documents {
			if binding.buffer_id != stats.buffer_id do continue
			observation.present = true
			observation.language = session.language
			observation.health = session.phase
			observation.binding_identity = u64(binding.binding.id)
			observation.diagnostic_generation = u64(binding.binding.generation)
			batch, copied, _ := language_service.diagnostic_store_copy(
				&session.diagnostics,
				binding.binding,
			)
			if !copied do return
			defer language_service.diagnostic_batch_copy_close(&batch)
			if batch.descriptor.canonical_revision != u64(stats.revision) do return
			_, projected, _ := language_service.proposal_project_diagnostics(
				proposal,
				text_view,
				batch.descriptor,
				batch.records,
				owner_id,
			)
			if projected {
				observation.diagnostic_generation = u64(batch.descriptor.generation)
				observation.errors = batch.descriptor.errors
				observation.warnings = batch.descriptor.warnings
			}
			return
		}
	}
	return
}

// Language_Service_Workflow_Diagnostic_Source copies current diagnostic candidates.
Language_Service_Workflow_Diagnostic_Source :: proc(
	workflow: ^Language_Service_Workflow_State,
	source_generation: u64,
	allocator := context.temp_allocator,
) -> (Language_Service_Diagnostic_Source, bool, interaction.Candidate_Failure) {
	if !Language_Service_Workflow_Is_Live(workflow) || source_generation == 0 ||
	   allocator.procedure == nil {
		return {}, false, interaction.Candidate_Failure{code = .Invalid_Source}
	}
	project_handle: project_core.Project_Handle
	document_count := 0
	for session in workflow.sessions {
		if !session.live || session.phase != .Active do continue
		if !project_core.project_handle_is_valid(project_handle) do project_handle = session.project
		if session.project == project_handle do document_count += len(session.documents)
	}
	if !project_core.project_handle_is_valid(project_handle) || document_count == 0 {
		return {}, false, interaction.Candidate_Failure{code = .Invalid_Source}
	}
	result := Language_Service_Diagnostic_Source{allocator = allocator}
	allocation_error: runtime.Allocator_Error
	result.batches, allocation_error = make(
		[]language_service.Diagnostic_Batch_Copy,
		document_count,
		allocator,
	)
	if allocation_error == nil {
		result.documents, allocation_error = make(
			[]interaction.Diagnostic_Candidate_Document,
			document_count,
			allocator,
		)
	}
	if allocation_error != nil {
		Language_Service_Diagnostic_Source_Close(&result)
		return {}, false, interaction.Candidate_Failure{code = .Persistent_Memory_Limit}
	}
	for &session in workflow.sessions {
		if !session.live || session.phase != .Active || session.project != project_handle do continue
		for binding in session.documents {
			batch, copied, _ := language_service.diagnostic_store_copy(
				&session.diagnostics,
				binding.binding,
			)
			if !copied do continue
			uri, uri_ok, _ := language_service.document_synchronizer_uri(
				&session.synchronizer,
				binding.binding,
			)
			if !uri_ok || len(uri) <= len("file://") || uri[:len("file://")] != "file://" {
				language_service.diagnostic_batch_copy_close(&batch)
				continue
			}
			result.batches[result.count] = batch
			result.documents[result.count] = interaction.Diagnostic_Candidate_Document {
				batch = &result.batches[result.count],
				path = uri[len("file://"):],
				buffer_id = u64(binding.buffer_id),
			}
			result.count += 1
		}
	}
	if result.count == 0 {
		Language_Service_Diagnostic_Source_Close(&result)
		return {}, false, interaction.Candidate_Failure{code = .Invalid_Source}
	}
	source, built, failure := interaction.diagnostic_candidate_source_build(
		interaction.Diagnostic_Candidate_Request {
			scope_identity = u64(project_handle.id),
			scope_generation = u64(project_handle.generation),
			source_generation = source_generation,
			documents = result.documents[:result.count],
		},
		allocator,
	)
	if !built {
		Language_Service_Diagnostic_Source_Close(&result)
		return {}, false, failure
	}
	result.source = source
	return result, true, {}
}

// Language_Service_Diagnostic_Source_Close releases one copied diagnostic source.
Language_Service_Diagnostic_Source_Close :: proc(
	source: ^Language_Service_Diagnostic_Source,
) {
	if source == nil do return
	if source.source.allocator.procedure != nil {
		interaction.diagnostic_candidate_source_close(&source.source)
	}
	for index in 0 ..< source.count {
		language_service.diagnostic_batch_copy_close(&source.batches[index])
	}
	if source.documents != nil do delete(source.documents, source.allocator)
	if source.batches != nil do delete(source.batches, source.allocator)
	source^ = {}
}

// Language_Service_Workflow_Resolve_Diagnostic_Action validates one diagnostic navigation action.
Language_Service_Workflow_Resolve_Diagnostic_Action :: proc(
	workflow: ^Language_Service_Workflow_State,
	action: interaction.Candidate_Action,
) -> (editor_session.Entry_Handle, u64, bool) {
	if !Language_Service_Workflow_Is_Live(workflow) || action.kind != .Navigate_Diagnostic {
		return {}, 0, false
	}
	for &session in workflow.sessions {
		if !session.live || session.phase != .Active do continue
		for binding in session.documents {
			if u64(binding.buffer_id) != action.primary || binding.canonical_revision != action.secondary {
				continue
			}
			batch, copied, _ := language_service.diagnostic_store_copy(
				&session.diagnostics,
				binding.binding,
			)
			if !copied do return {}, 0, false
			matched := false
			start := u64(0)
			for record in batch.records {
				location := interaction.Diagnostic_Candidate_Location {
					binding = record.binding,
					diagnostic_generation = record.generation,
					diagnostic_id = record.id,
					canonical_revision = record.canonical_revision,
					buffer_id = u64(binding.buffer_id),
					start = record.range.start,
					end = record.range.end,
				}
				if interaction.diagnostic_candidate_action_matches(
					action,
					location,
					action.owner_generation,
				) {
					matched = true
					start = record.range.start
					break
				}
			}
			language_service.diagnostic_batch_copy_close(&batch)
			if matched do return binding.entry, start, true
		}
	}
	return {}, 0, false
}

// Language_Service_Workflow_Session_For_Buffer resolves the owning live service session.
Language_Service_Workflow_Session_For_Buffer :: proc(
	workflow: ^Language_Service_Workflow_State,
	buffer_id: editor.Buffer_ID,
) -> (int, bool) {
	if !Language_Service_Workflow_Is_Live(workflow) do return 0, false
	fallback := -1
	selected := -1
	bound := -1
	for &session, index in workflow.sessions {
		if !session.live do continue
		if fallback == -1 do fallback = index
		if session.selected do selected = index
		for binding in session.documents {
			if binding.buffer_id == buffer_id do bound = index
		}
	}
	if selected >= 0 do return selected, true
	if bound >= 0 do return bound, true
	return fallback, fallback >= 0
}

// Language_Service_Workflow_Restart explicitly replaces one failed service process.
Language_Service_Workflow_Restart :: proc(
	workflow: ^Language_Service_Workflow_State,
	buffer_id: editor.Buffer_ID,
) -> (bool, language_service.Failure_Context) {
	index, found := Language_Service_Workflow_Session_For_Buffer(workflow, buffer_id)
	if !found {
		return false, language_service.Failure_Context{code = .Invalid_Session}
	}
	owner := &workflow.sessions[index]
	if owner.phase != .Failed || owner.process.state == nil {
		failure := owner.latest_failure
		if failure.code == .None {
			failure = language_service.Failure_Context{code = .Invalid_Session, session = owner.handle}
		}
		return false, failure
	}
	registry, borrowed, _ := editor_session.project_registry_access_borrow(owner.project_access)
	if !borrowed {
		return false, language_service.Failure_Context{code = .Project_Scope, session = owner.handle}
	}
	memberships, listed, _ := project_core.registry_membership_descriptors(registry, owner.project)
	if !listed {
		return false, language_service.Failure_Context{code = .Project_Scope, session = owner.handle}
	}
	defer project_core.descriptor_batch_close(&memberships)
	membership_current := false
	for &descriptor in memberships.descriptors {
		if descriptor.handle == owner.membership {
			membership_current = project_core.trust_allows_behavior(descriptor.trust, .Language_Service) &&
				language_service.service_root_contains(
					project_core.directory_path_text(&descriptor.path),
					owner.root,
				)
			break
		}
	}
	definition, definition_ok, definition_failure := language_service.provider_registry_definition(
		&workflow.registry,
		owner.definition,
	)
	if !membership_current || !definition_ok {
		if definition_failure.code == .None {
			definition_failure = language_service.Failure_Context{code = .Project_Scope, session = owner.handle}
		}
		return false, definition_failure
	}
	restarted, restart_failure := language_service.process_session_restart(
		&owner.process,
		Language_Service_Workflow_Now_Ns(workflow),
	)
	if !restarted {
		owner.latest_failure = restart_failure
		workflow.latest_failure = restart_failure
		return false, restart_failure
	}
	if owner.diagnostics.state != nil do language_service.diagnostic_store_close(&owner.diagnostics)
	if owner.synchronizer.state != nil do language_service.document_synchronizer_close(&owner.synchronizer)
	clear(&owner.documents)
	owner.capabilities = {}
	inspection, inspected := language_service.process_session_inspect(&owner.process)
	if inspected do owner.handle = inspection.session.handle
	owner.phase = .Initializing
	initialize, built := language_service_workflow_initialize_body(owner.root, definition)
	if !built {
		failure := language_service.Failure_Context{code = .Allocation, session = owner.handle}
		owner.latest_failure = failure
		workflow.latest_failure = failure
		return false, failure
	}
	queued, queue_failure := language_service.process_session_send_frame(
		&owner.process,
		transmute([]u8)initialize,
	)
	if !queued {
		owner.latest_failure = queue_failure
		workflow.latest_failure = queue_failure
		return false, queue_failure
	}
	owner.latest_failure = {}
	workflow.latest_failure = {}
	return true, {}
}

// Language_Service_Workflow_Close releases sessions, registries, catalogs, and definitions.
Language_Service_Workflow_Close :: proc(workflow: ^Language_Service_Workflow_State) -> bool {
	if !Language_Service_Workflow_Is_Live(workflow) do return false
	language_service_workflow_close_all(workflow, true)
	delete(workflow.sessions)
	_, _ = language_service.service_catalog_close(&workflow.catalog)
	language_service.provider_registry_close(&workflow.registry)
	workflow.initialized = false
	workflow.closed = true
	return true
}

@(private)
language_service_workflow_session_start :: proc(
	workflow: ^Language_Service_Workflow_State,
	session_owner: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	project_handle: project_core.Project_Handle,
	membership: project_core.Membership_Handle,
	language_identity: language.Language_Identity,
	selection: language_service.Service_Resolution_Trace,
	definition: language_service.Definition_View,
	root: string,
) -> (int, bool) {
	if len(workflow.sessions) >= cap(workflow.sessions) || workflow.next_session_id == 0 do return 0, false
	if root == "" do return 0, false
	access, accessible, access_failure := editor_session.session_project_registry_access(
		session_owner,
		session_handle,
		project_handle,
	)
	if !accessible {
		workflow.latest_failure = language_service.Failure_Context{code = .Project_Scope}
		_ = access_failure
		return 0, false
	}
	owned_root, root_error := strings.clone(root, workflow.allocator)
	if root_error != nil {
		workflow.latest_failure = language_service.Failure_Context{code = .Allocation}
		return 0, false
	}
	owner := Language_Service_Workflow_Session {
		live = true,
		phase = .Failed,
		reconciliation = .Replacement_Required,
		project = project_handle,
		membership = membership,
		language = language_identity,
		definition = selection.selected,
		catalog_generation = selection.catalog_generation,
		root = owned_root,
		project_access = access,
	}
	owner.handle = language_service.Session_Handle {
		provider = definition.provider.handle,
		id = workflow.next_session_id,
		generation = 1,
	}
	workflow.next_session_id += 1
	owner.documents, _ = make(
		[dynamic]Language_Service_Workflow_Document,
		0,
		int(definition.definition.limits.documents_per_session),
		workflow.allocator,
	)
	if owner.documents == nil {
		owner.latest_failure = language_service.Failure_Context{code = .Allocation}
		_, _ = append(&workflow.sessions, owner)
		return len(workflow.sessions) - 1, true
	}
	path := os.get_env("PATH", context.temp_allocator)
	executable, discovered, discovery_failure := language_service.provider_registry_revalidate_executable(
		&workflow.registry,
		selection.selected,
		language_service.Executable_Discovery {
			package_artifact = definition.package_artifact,
			distributed_artifact = definition.distributed_artifact,
			search_path = path,
		},
	)
	if !discovered || executable.availability == .Unavailable {
		owner.reconciliation = .Unavailable
		owner.latest_failure = discovery_failure
		workflow.latest_failure = discovery_failure
		_, _ = append(&workflow.sessions, owner)
		return len(workflow.sessions) - 1, true
	}
	command_storage: [int(language_service.DEFAULT_LIMITS.arguments) + 1]string
	command_storage[0] = executable.path
	copy(command_storage[1:], definition.arguments)
	command := command_storage[:1 + len(definition.arguments)]
	process, started, start_failure := language_service.process_session_start(
		language_service.Process_Start_Request {
			handle = owner.handle,
			command = command,
			environment = definition.environment,
			working_directory = root,
			limits = definition.definition.limits,
			deadlines = definition.definition.deadlines,
			restart = definition.definition.restart,
		},
		Language_Service_Workflow_Now_Ns(workflow),
		workflow.allocator,
	)
	if !started {
		owner.reconciliation = .Failed
		owner.latest_failure = start_failure
		workflow.latest_failure = start_failure
		_, _ = append(&workflow.sessions, owner)
		return len(workflow.sessions) - 1, true
	}
	owner.process = process
	initialize, built := language_service_workflow_initialize_body(root, definition)
	if !built {
		owner.latest_failure = language_service.Failure_Context{code = .Allocation}
		language_service.process_session_close(&owner.process)
		_, _ = append(&workflow.sessions, owner)
		return len(workflow.sessions) - 1, true
	}
	queued, queue_failure := language_service.process_session_send_frame(
		&owner.process,
		transmute([]u8)initialize,
	)
	if !queued {
		owner.latest_failure = queue_failure
		language_service.process_session_close(&owner.process)
		_, _ = append(&workflow.sessions, owner)
		return len(workflow.sessions) - 1, true
	}
	owner.phase = .Initializing
	_, append_error := append(&workflow.sessions, owner)
	if append_error != nil {
		language_service.process_session_close(&owner.process)
		delete(owner.documents)
		delete(owner.root, workflow.allocator)
		return 0, false
	}
	return len(workflow.sessions) - 1, true
}

@(private)
language_service_workflow_confirm_session :: proc(
	workflow: ^Language_Service_Workflow_State,
	owner: ^Language_Service_Workflow_Session,
	capabilities: language_service.Capability_Values,
) -> bool {
	registry, borrowed, _ := editor_session.project_registry_access_borrow(owner.project_access)
	definition, definition_ok, definition_failure := language_service.provider_registry_definition(
		&workflow.registry,
		owner.definition,
	)
	if !borrowed || !definition_ok {
		owner.phase = .Failed
		owner.latest_failure = definition_failure
		return false
	}
	profile, profile_ok := language_service.effective_service_profile(definition, capabilities)
	if !profile_ok {
		owner.phase = .Failed
		owner.latest_failure = {code = .Invalid_Definition, definition = owner.definition}
		return false
	}
	effective_capabilities := language_service.Capability_Values{
		capabilities = profile.active_capabilities,
		position_encoding = profile.position_encoding,
		synchronization_mode = profile.synchronization_mode,
		completion = profile.completion,
	}
	confirmed, confirm_failure := language_service.process_session_confirm_initialized(
		&owner.process,
		effective_capabilities,
	)
	if !confirmed {
		owner.phase = .Failed
		owner.latest_failure = confirm_failure
		return false
	}
	synchronizer_ready, synchronizer_failure := language_service.document_synchronizer_init(
		&owner.synchronizer,
		registry,
		language_service.Synchronizer_Request {
			session = owner.handle,
			project = owner.project,
			membership = owner.membership,
			root_policy = definition.root_policy,
			resolved_root = owner.root,
			languages = definition.languages,
			capabilities = profile.active_capabilities,
			position_encoding = profile.position_encoding,
			synchronization_mode = profile.synchronization_mode,
			limits = definition.definition.limits,
		},
		workflow.allocator,
	)
	if !synchronizer_ready {
		owner.phase = .Failed
		owner.latest_failure = synchronizer_failure
		return false
	}
	diagnostics_ready, diagnostics_failure := language_service.diagnostic_store_init(
		&owner.diagnostics,
		owner.handle,
		definition.definition.limits,
		workflow.allocator,
	)
	if !diagnostics_ready {
		language_service.document_synchronizer_close(&owner.synchronizer)
		owner.phase = .Failed
		owner.latest_failure = diagnostics_failure
		return false
	}
	initialized := transmute([]u8)(string(`{"jsonrpc":"2.0","method":"initialized","params":{}}`))
	initialized_queued, initialized_failure := language_service.process_session_send_frame(
		&owner.process,
		initialized,
	)
	settings, settings_built := language_service.service_configuration_notification(
		profile.client_settings,
		context.temp_allocator,
	)
	settings_queued := false
	settings_failure := language_service.Failure_Context{code = .Allocation}
	if settings_built {
		settings_queued, settings_failure = language_service.process_session_send_frame(
			&owner.process,
			transmute([]u8)settings,
		)
	}
	if !initialized_queued || !settings_built || !settings_queued {
		language_service.diagnostic_store_close(&owner.diagnostics)
		language_service.document_synchronizer_close(&owner.synchronizer)
		language_service.process_session_close(&owner.process)
		owner.phase = .Failed
		owner.latest_failure = initialized_failure if !initialized_queued else settings_failure
		return false
	}
	owner.phase = .Active
	owner.capabilities = effective_capabilities
	owner.active_features = profile.active_features
	owner.latest_failure = {}
	return true
}

@(private)
language_service_workflow_reconcile_document :: proc(
	workflow: ^Language_Service_Workflow_State,
	owner: ^Language_Service_Workflow_Session,
	entry_handle: editor_session.Entry_Handle,
	entry: editor_session.Entry_Borrow,
	path: string,
	language_name: string,
) -> bool {
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	status, status_ok, _ := document.document_status(entry.document)
	if !stats_ok || !status_ok do return false
	for &binding in owner.documents {
		if binding.buffer_id != stats.buffer_id do continue
		binding.seen = true
		changed := false
		if binding.canonical_revision != u64(stats.revision) {
			text, copied := Language_Service_Workflow_Copy_Buffer(entry.buffer, workflow.allocator)
			if !copied do return false
			defer delete(text, workflow.allocator)
			old_text, old_ok, _ := language_service.document_synchronizer_text(
				&owner.synchronizer,
				binding.binding,
			)
			_, _ = language_service.diagnostic_store_invalidate(&owner.diagnostics, binding.binding)
			if old_ok && binding.canonical_revision + 1 == u64(stats.revision) {
				updated, _ := language_service.document_synchronizer_change(
					&owner.synchronizer,
					language_service.Document_Change_Request {
						binding = binding.binding,
						base_revision = binding.canonical_revision,
						target_revision = u64(stats.revision),
						start = 0,
						end = u64(len(old_text)),
					replacement = string(text),
					target_text = string(text),
					},
				)
				if updated {
					binding.canonical_revision = u64(stats.revision)
					changed = true
				}
			}
			if !changed {
				_, _ = language_service.document_synchronizer_close_document(
					&owner.synchronizer,
					binding.binding,
					binding.canonical_revision,
				)
				uri := fmt.aprintf("file://%s", path, allocator = context.temp_allocator)
				replacement, opened, _ := language_service.document_synchronizer_open(
					&owner.synchronizer,
					language_service.Document_Open_Request {
						document_identity = u64(status.document_id),
						buffer_identity = u64(stats.buffer_id),
						canonical_revision = u64(stats.revision),
						path = path,
						uri = uri,
						language = language_name,
						text = string(text),
					},
				)
				if opened {
					binding.binding = replacement
					binding.canonical_revision = u64(stats.revision)
					changed = true
				}
			}
		}
		if status.has_saved_revision && u64(status.saved_revision) == binding.canonical_revision &&
		   binding.saved_revision != binding.canonical_revision {
			if saved, _ := language_service.document_synchronizer_save(
				&owner.synchronizer,
				binding.binding,
				binding.canonical_revision,
			); saved {
				binding.saved_revision = binding.canonical_revision
				changed = true
			}
		}
		return changed
	}
	text, copied := Language_Service_Workflow_Copy_Buffer(entry.buffer, workflow.allocator)
	if !copied do return false
	defer delete(text, workflow.allocator)
	uri := fmt.aprintf("file://%s", path, allocator = context.temp_allocator)
	binding, opened, open_failure := language_service.document_synchronizer_open(
		&owner.synchronizer,
		language_service.Document_Open_Request {
			document_identity = u64(status.document_id),
			buffer_identity = u64(stats.buffer_id),
			canonical_revision = u64(stats.revision),
			path = path,
			uri = uri,
			language = language_name,
			text = string(text),
		},
	)
	if !opened {
		owner.latest_failure = open_failure
		return false
	}
	saved_revision := u64(0)
	if status.has_saved_revision do saved_revision = u64(status.saved_revision)
	_, append_error := append(&owner.documents, Language_Service_Workflow_Document {
		entry = entry_handle,
		buffer_id = stats.buffer_id,
		document_id = status.document_id,
		binding = binding,
		canonical_revision = u64(stats.revision),
		saved_revision = saved_revision,
		seen = true,
	})
	return append_error == nil
}

@(private)
language_service_workflow_flush_document_queue :: proc(owner: ^Language_Service_Workflow_Session) {
	view, queued := language_service.document_synchronizer_peek(&owner.synchronizer)
	if !queued do return
	sent, failure := language_service.process_session_send_frame(&owner.process, view.body)
	if sent {
		language_service.document_synchronizer_ack(&owner.synchronizer, view.record.generation)
	} else {
		owner.latest_failure = failure
	}
}

@(private)
language_service_workflow_publish_diagnostics :: proc(
	workflow: ^Language_Service_Workflow_State,
	owner: ^Language_Service_Workflow_Session,
	message: ^language_service.Message,
) -> bool {
	uri, uri_ok := language_service.diagnostic_message_uri(
		message,
		language_service.DEFAULT_LIMITS.uri_bytes,
		workflow.allocator,
	)
	if !uri_ok do return false
	defer delete(uri, workflow.allocator)
	for binding in owner.documents {
		known_uri, known, _ := language_service.document_synchronizer_uri(
			&owner.synchronizer,
			binding.binding,
		)
		if !known || known_uri != uri do continue
		_, published, failure := language_service.diagnostic_store_publish_message(
			&owner.diagnostics,
			&owner.synchronizer,
			binding.binding,
			binding.canonical_revision,
			message,
		)
		if !published do owner.latest_failure = failure
		return published
	}
	return false
}

@(private)
language_service_workflow_handle_unknown :: proc(
	owner: ^Language_Service_Workflow_Session,
	message: ^language_service.Message,
) {
	action := language_service.unknown_method_action(message.record)
	if action != .Reply_Method_Not_Found do return
	if message.record.id.kind == .Integer {
		body := fmt.aprintf(
			`{{"jsonrpc":"2.0","id":%d,"error":{{"code":-32601,"message":"Method not found"}}}}`,
			message.record.id.integer,
			allocator = context.temp_allocator,
		)
		_, owner.latest_failure = language_service.process_session_send_frame(
			&owner.process,
			transmute([]u8)body,
		)
	}
}

@(private)
language_service_workflow_entry_language_identity :: proc(
	syntax: ^Syntax_Workflow_State,
	entry: editor_session.Entry_Borrow,
) -> (language.Language_Identity, bool) {
	association, associated, _ := syntax_workflow_entry_language_association(syntax, entry)
	if !associated || association.language.name.length == 0 do return {}, false
	return association.language, true
}

@(private)
language_service_workflow_entry_language :: proc(
	syntax: ^Syntax_Workflow_State,
	entry: editor_session.Entry_Borrow,
	admitted: []string,
) -> (language.Language_Name, bool) {
	association, associated, _ := syntax_workflow_entry_language_association(syntax, entry)
	if !associated || association.language.name.length == 0 do return {}, false
	name := string(association.language.name.bytes[:association.language.name.length])
	for candidate in admitted {
		if candidate == name do return association.language.name, true
	}
	return {}, false
}

@(private)
language_service_workflow_membership_root :: proc(
	membership: project_core.Membership_Handle,
	memberships: []project_core.Membership_Descriptor,
) -> string {
	for &descriptor in memberships {
		if descriptor.handle == membership {
			return project_core.directory_path_text(&descriptor.path)
		}
	}
	return ""
}

@(private)
language_service_workflow_most_specific_membership :: proc(
	descriptor: editor_session.Project_Buffer_Descriptor,
	classified: []project_core.Membership_Handle,
	memberships: []project_core.Membership_Descriptor,
) -> (project_core.Membership_Handle, bool) {
	best: project_core.Membership_Descriptor
	best_bytes := -1
	start := int(descriptor.membership_offset)
	end := start + int(descriptor.membership_count)
	if start < 0 || end > len(classified) do return {}, false
	for handle in classified[start:end] {
		for candidate in memberships {
			if candidate.handle != handle do continue
			path := candidate.path
			path_bytes := len(project_core.directory_path_text(&path))
			if path_bytes > best_bytes {
				best = candidate
				best_bytes = path_bytes
			}
		}
	}
	return best.handle,
		project_core.membership_handle_is_valid(best.handle) &&
		project_core.trust_allows_behavior(best.trust, .Language_Service)
}

@(private)
language_service_workflow_find_session :: proc(
	workflow: ^Language_Service_Workflow_State,
	project_handle: project_core.Project_Handle,
	membership: project_core.Membership_Handle,
	language_identity: language.Language_Identity,
	definition: language_service.Definition_Handle,
	root: string,
) -> (int, bool) {
	for &owner, index in workflow.sessions {
		if owner.live && owner.project == project_handle && owner.membership == membership &&
		   language_service_workflow_same_language(owner.language, language_identity) &&
		   owner.definition == definition &&
		   owner.root == root {
			owner.language = language_identity
			return index, true
		}
	}
	return 0, false
}

@(private)
language_service_workflow_same_language :: proc(
	left, right: language.Language_Identity,
) -> bool {
	left_copy := left
	right_copy := right
	return left_copy.id == right_copy.id && left_copy.name.length == right_copy.name.length &&
		string(left_copy.name.bytes[:left_copy.name.length]) ==
		string(right_copy.name.bytes[:right_copy.name.length])
}

@(private)
language_service_workflow_collect_retired_definitions :: proc(
	workflow: ^Language_Service_Workflow_State,
) {
	if !Language_Service_Workflow_Is_Live(workflow) do return
	catalog: language_service.Service_Catalog_Inspection
	catalog_ok, _ := language_service.service_catalog_inspect(&workflow.catalog, &catalog)
	if !catalog_ok do return
	for index := int(workflow.retired_definition_count) - 1; index >= 0; index -= 1 {
		handle := workflow.retired_definitions[index]
		retained := false
		for &definition in catalog.definitions[:catalog.definition_count] {
			if definition.definition == handle {
				retained = true
				break
			}
		}
		if !retained {
			for &owner in workflow.sessions {
				if owner.live && owner.definition == handle {
					retained = true
					break
				}
			}
		}
		if retained do continue
		registry, registry_ok := language_service.provider_registry_inspect(&workflow.registry)
		if registry_ok && registry.active == handle {
			restored, _ := language_service.provider_registry_restore_factory(&workflow.registry)
			if !restored do continue
		}
		discarded, _ := language_service.provider_registry_discard_definition(
			&workflow.registry,
			handle,
		)
		if !discarded do continue
		workflow.retired_definition_count -= 1
		workflow.retired_definitions[index] =
			workflow.retired_definitions[workflow.retired_definition_count]
		workflow.retired_definitions[workflow.retired_definition_count] = {}
	}
}

@(private)
language_service_workflow_retain_fallback :: proc(
	workflow: ^Language_Service_Workflow_State,
	buffer_id: editor.Buffer_ID,
	excluded_index: int,
) -> bool {
	if workflow == nil do return false
	for &owner, owner_index in workflow.sessions {
		if owner_index == excluded_index || !owner.live || owner.phase != .Active do continue
		for &binding in owner.documents {
			if binding.buffer_id != buffer_id do continue
			binding.seen = true
			owner.fallback = true
			owner.reconciliation = .Replacement_Fallback
			return true
		}
	}
	return false
}

// Language_Service_Workflow_Copy_Buffer copies canonical buffer bytes for protocol publication.
Language_Service_Workflow_Copy_Buffer :: proc(
	buffer: ^editor.Buffer,
	allocator: runtime.Allocator,
) -> ([]u8, bool) {
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened do return nil, false
	defer editor.buffer_snapshot_close(&snapshot)
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	if !stats_ok || stats.text_bytes > language_service.DEFAULT_LIMITS.synchronization_bytes {
		return nil, false
	}
	text, allocation_error := make([]u8, int(stats.text_bytes), allocator)
	if allocation_error != nil do return nil, false
	copied, read_ok, _ := editor.buffer_snapshot_read(&snapshot, 0, text)
	if !read_ok || copied != stats.text_bytes {
		delete(text, allocator)
		return nil, false
	}
	return text, true
}

@(private)
language_service_workflow_initialize_body :: proc(
	root: string,
	definition: language_service.Definition_View,
) -> (string, bool) {
	root_uri := fmt.aprintf("file://%s", root, allocator = context.temp_allocator)
	encoded_uri, marshal_error := json.marshal(root_uri, {}, context.temp_allocator)
	if marshal_error != nil do return "", false
	encoded_root, root_marshal_error := json.marshal(root, {}, context.temp_allocator)
	if root_marshal_error != nil do return "", false
	options := definition.initialization_options
	if options == "" do options = `{}`
	body := fmt.aprintf(
		`{{"jsonrpc":"2.0","id":1,"method":"initialize","params":{{"processId":null,"clientInfo":{{"name":"Odra"}},"rootPath":%s,"rootUri":%s,"capabilities":{{"general":{{"positionEncodings":["utf-8","utf-16"]}},"textDocument":{{"synchronization":{{"dynamicRegistration":false,"didSave":true}},"publishDiagnostics":{{"relatedInformation":true,"versionSupport":true}}}}}},"initializationOptions":%s,"workspaceFolders":[{{"uri":%s,"name":"Project"}}]}}}}`,
		string(encoded_root),
		string(encoded_uri),
		options,
		string(encoded_uri),
		allocator = context.temp_allocator,
	)
	return body, body != ""
}

@(private)
language_service_workflow_session_close :: proc(
	workflow: ^Language_Service_Workflow_State,
	index: int,
	graceful: bool,
) {
	if workflow == nil || index < 0 || index >= len(workflow.sessions) do return
	owner := &workflow.sessions[index]
	if !owner.live do return
	if graceful && owner.phase == .Active && owner.process.state != nil {
		language_service_workflow_session_shutdown(workflow, owner)
	}
	if owner.diagnostics.state != nil do language_service.diagnostic_store_close(&owner.diagnostics)
	if owner.synchronizer.state != nil do language_service.document_synchronizer_close(&owner.synchronizer)
	if owner.process.state != nil do language_service.process_session_close(&owner.process)
	if owner.documents != nil do delete(owner.documents)
	if len(owner.root) > 0 do delete(owner.root, workflow.allocator)
	ordered_remove(&workflow.sessions, index)
}

@(private)
language_service_workflow_close_all :: proc(
	workflow: ^Language_Service_Workflow_State,
	graceful := false,
) -> bool {
	if workflow == nil do return false
	changed := len(workflow.sessions) > 0
	for len(workflow.sessions) > 0 {
		language_service_workflow_session_close(workflow, len(workflow.sessions) - 1, graceful)
	}
	return changed
}

@(private)
language_service_workflow_session_shutdown :: proc(
	workflow: ^Language_Service_Workflow_State,
	owner: ^Language_Service_Workflow_Session,
) {
	for &binding in owner.documents {
		_, _ = language_service.diagnostic_store_invalidate(&owner.diagnostics, binding.binding)
		_, _ = language_service.document_synchronizer_close_document(
			&owner.synchronizer,
			binding.binding,
			binding.canonical_revision,
		)
	}
	for {
		view, queued := language_service.document_synchronizer_peek(&owner.synchronizer)
		if !queued do break
		sent, _ := language_service.process_session_send_frame(&owner.process, view.body)
		if !sent do break
		language_service.document_synchronizer_ack(&owner.synchronizer, view.record.generation)
	}
	now_ns := Language_Service_Workflow_Now_Ns(workflow)
	shutting_down, _ := language_service.process_session_begin_shutdown(&owner.process, now_ns)
	if shutting_down {
		shutdown := transmute([]u8)(string(`{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}`))
		_, _ = language_service.process_session_send_frame(&owner.process, shutdown)
		response_seen := false
		for _ in 0 ..< 3_000 {
			poll, polled := language_service.process_session_poll(
				&owner.process,
				Language_Service_Workflow_Now_Ns(workflow),
			)
			if !polled || poll.health == .Stopped || poll.health == .Failed do break
			if poll.frame_ready {
				frame, taken, _ := language_service.process_session_take_frame(&owner.process)
				if taken {
					message, decoded, _ := language_service.message_decode(frame.body)
					language_service.frame_close(&frame)
					if decoded {
						response_seen = message.record.kind == .Response &&
							message.record.id.kind == .Integer && message.record.id.integer == 2
						language_service.message_close(&message)
					}
				}
			}
			if response_seen {
				exit := transmute([]u8)(string(`{"jsonrpc":"2.0","method":"exit","params":null}`))
				_, _ = language_service.process_session_send_frame(&owner.process, exit)
				response_seen = false
			}
			time.sleep(time.Millisecond)
		}
	}
	inspection, inspected := language_service.process_session_inspect(&owner.process)
	if inspected && inspection.session.health != .Stopped && inspection.process.state != .Reaped {
		_, _ = language_service.process_session_force_terminate(
			&owner.process,
			Language_Service_Workflow_Now_Ns(workflow),
		)
		for _ in 0 ..< 1_000 {
			poll, polled := language_service.process_session_poll(
				&owner.process,
				Language_Service_Workflow_Now_Ns(workflow),
			)
			if !polled || poll.health == .Stopped do break
			time.sleep(time.Millisecond)
		}
	}
}

// Language_Service_Workflow_Now_Ns returns the injected or monotonic workflow clock.
Language_Service_Workflow_Now_Ns :: proc(workflow: ^Language_Service_Workflow_State) -> i64 {
	return max(i64(1), time.duration_nanoseconds(time.tick_since(workflow.clock_start)))
}

// Language_Service_Workflow_Is_Live reports whether service workflow state may be used.
Language_Service_Workflow_Is_Live :: proc(workflow: ^Language_Service_Workflow_State) -> bool {
	return workflow != nil && workflow.initialized && !workflow.closed &&
		workflow.registry.state != nil && workflow.catalog.state != nil
}
