// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

import "../document"
import "../display"
import "../editor"
import "../editor_session"
import "../language"
import "../transaction"
import "../ui"
import "base:runtime"
import "core:strings"

/* ODIN_LANGUAGE_ID identifies the built-in Odin language responsibility. */
ODIN_LANGUAGE_ID :: language.Language_ID(1)
/* ODIN_LANGUAGE_GENERATION identifies the factory Odin language contract. */
ODIN_LANGUAGE_GENERATION :: language.Language_Generation(1)
@(private)
Syntax_Analysis_Entry :: struct {
	live:        bool,
	owner_ready: bool,
	bundle_identity: string,
	parser_generation: language.Parser_Generation,
	refresh_attempted: bool,
	entry:       editor_session.Entry_Handle,
	inspection:  language.Language_Selection_Inspection,
	owner:       language.Tree_Sitter_Owner,
	jan_owner:   language.Jan_Structural_Owner,
	jan_analysis: language.Jan_Structural_Analysis,
	jan_analysis_live: bool,
	source:      editor.Buffer_Snapshot,
	syntax:      language.Syntax_Query_Result,
	injections:  Injection_Result,
	pending:     Syntax_Pending_Commit,
}

@(private)
Syntax_Provider_Registry_Entry :: struct {
	live:      bool,
	bundle_identity: string,
	identity:  language.Language_Identity,
	registry:  language.Provider_Registry,
	selection: language.Provider_Selection,
}

@(private)
Syntax_Pending_Commit :: struct {
	live:            bool,
	base_revision:   editor.Revision,
	result_revision: editor.Revision,
	result:          editor.Buffer_Snapshot,
	splices:         []transaction.Normalized_Splice,
	allocator:       runtime.Allocator,
}

@(private)
Syntax_Workflow_State :: struct {
	language_catalog:          language.Language_Catalog,
	provider_registries:       [language.MAX_LANGUAGES]Syntax_Provider_Registry_Entry,
	provider_registry_count:   u16,
	jan_configuration:         language.Jan_Configuration,
	explicit_jan_buffers:      [language.MAX_LIVE_SELECTIONS]editor.Buffer_ID,
	explicit_jan_count:        u16,
	entries:                   [language.MAX_LIVE_SELECTIONS]Syntax_Analysis_Entry,
	live_count:                u16,
	next_selection_generation: language.Selection_Generation,
	next_parser_generation:    language.Parser_Generation,
	next_tree_generation:      language.Tree_Generation,
	next_syntax_generation:    language.Syntax_Snapshot_Generation,
	next_injection_generation: Injection_Generation,
	next_jan_analysis_generation: language.Jan_Analysis_Generation,
	latest_failure:            language.Failure,
	allocator:                 runtime.Allocator,
	initialized:               bool,
	closed:                    bool,
}

// Syntax_Workflow_Init initializes retained language and syntax ownership.
Syntax_Workflow_Init :: proc(
	workflow: ^Syntax_Workflow_State,
	allocator := context.allocator,
) -> (ok: bool, failure: language.Failure) {
	if workflow == nil || allocator.procedure == nil {
		return false, language.Failure{operation = .Initialize, code = .Allocation}
	}
	workflow^ = {}
	workflow.allocator = allocator
	catalog_initialized, catalog_init_failure := language.language_catalog_init(
		&workflow.language_catalog,
		1,
		allocator,
	)
	if !catalog_initialized {
		return false, syntax_workflow_catalog_failure(catalog_init_failure, .Initialize)
	}
	_, catalog_confirmed, catalog_failure := language.factory_bundle_catalog_confirm(
		&workflow.language_catalog,
	)
	if !catalog_confirmed {
		_, _ = language.language_catalog_close(&workflow.language_catalog)
		return false, syntax_workflow_catalog_failure(catalog_failure, .Initialize)
	}
	registrations, registrations_ready := language.factory_syntax_bundle_registrations()
	if !registrations_ready {
		_, _ = language.language_catalog_close(&workflow.language_catalog)
		return false, language.Failure{operation = .Initialize, code = .Invalid_Language}
	}
	for registration, index in registrations {
		added, add_failure := syntax_workflow_provider_registry_add(
			workflow,
			language.Registry_ID(index + 1),
			registration,
		)
		if !added {
			syntax_workflow_provider_registries_close(workflow)
			_, _ = language.language_catalog_close(&workflow.language_catalog)
			return false, add_failure
		}
		if language.jan_configuration_is_valid(registration.jan_configuration) {
			workflow.jan_configuration = registration.jan_configuration
		}
	}
	workflow.next_selection_generation = 1
	workflow.next_parser_generation = 1
	workflow.next_tree_generation = 1
	workflow.next_syntax_generation = 1
	workflow.next_injection_generation = 1
	workflow.next_jan_analysis_generation = 1
	workflow.initialized = true
	return true, {}
}

@(private)
syntax_workflow_provider_registry_add :: proc(
	workflow: ^Syntax_Workflow_State,
	registry_id: language.Registry_ID,
	registration: language.Factory_Bundle_Registration,
) -> (ok: bool, failure: language.Failure) {
	if workflow == nil || registration.language.id == language.Language_ID(0) ||
	   registration.language.generation == language.Language_Generation(0) ||
	   len(registration.bundle_identity) == 0 ||
	   workflow.provider_registry_count >= language.MAX_LANGUAGES {
		return false, language.Failure {
			operation = .Initialize,
			code = .Provider_Limit,
			language_id = registration.language.id,
			limit = language.MAX_LANGUAGES,
			actual = u64(workflow.provider_registry_count) + 1,
		}
	}
	for &candidate in workflow.provider_registries {
		if candidate.live && candidate.identity.id == registration.language.id {
			return false, language.Failure {
				operation = .Initialize,
				code = .Duplicate_Provider,
				language_id = registration.language.id,
			}
		}
	}
	for &candidate in workflow.provider_registries {
		if candidate.live do continue
		initialized, init_failure := language.provider_registry_init(
			&candidate.registry,
			registry_id,
			registration.language,
			registration.provider,
			workflow.allocator,
		)
		if !initialized do return false, init_failure
		selection, selected, selection_failure := language.provider_registry_selection(
			&candidate.registry,
		)
		if !selected {
			_, _ = language.provider_registry_close(&candidate.registry)
			return false, selection_failure
		}
		candidate.live = true
		candidate.bundle_identity = registration.bundle_identity
		candidate.identity = registration.language
		candidate.selection = selection
		workflow.provider_registry_count += 1
		return true, {}
	}
	return false, language.Failure {operation = .Initialize, code = .Provider_Limit}
}

@(private)
syntax_workflow_provider_registry :: proc(
	workflow: ^Syntax_Workflow_State,
	language_id: language.Language_ID,
) -> (^Syntax_Provider_Registry_Entry, bool) {
	if workflow == nil || language_id == language.Language_ID(0) do return nil, false
	for &candidate in workflow.provider_registries {
		if candidate.live && candidate.identity.id == language_id do return &candidate, true
	}
	return nil, false
}

@(private)
syntax_workflow_provider_registries_close :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (ok: bool, failure: language.Failure) {
	if workflow == nil do return false, language.Failure {operation = .Close, code = .Invalid_Registry}
	for &candidate in workflow.provider_registries {
		if !candidate.live do continue
		closed, close_failure := language.provider_registry_close(&candidate.registry)
		if !closed && failure.code == .None do failure = close_failure
		candidate = {}
	}
	workflow.provider_registry_count = 0
	return failure.code == .None, failure
}

// Syntax_Workflow_Reconcile aligns retained syntax state with one editor session.
Syntax_Workflow_Reconcile :: proc(
	workflow: ^Syntax_Workflow_State,
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
	temporary_allocator := context.temp_allocator,
) -> (ok: bool, failure: editor_session.Failure_Context) {
	if !Syntax_Workflow_Is_Live(workflow) || session == nil || temporary_allocator.procedure == nil {
		return false, editor_session.Failure_Context{code = .Invalid_Session, operation = .Inspect}
	}
	for &provider_registry in workflow.provider_registries {
		if !provider_registry.live do continue
		selection, selected, selection_failure := language.provider_registry_selection(
			&provider_registry.registry,
		)
		if !selected {
			workflow.latest_failure = selection_failure
			continue
		}
		if selection != provider_registry.selection {
			syntax_workflow_replace_selection(workflow, provider_registry.identity.id, selection)
		}
	}

	descriptors, described, descriptor_failure := editor_session.session_descriptors(
		session,
		handle,
		temporary_allocator,
	)
	if !described {
		return false, descriptor_failure
	}
	defer editor_session.descriptor_batch_close(&descriptors)
	seen: [language.MAX_LIVE_SELECTIONS]bool
	for descriptor in descriptors.descriptors {
		access, accessible, access_failure := editor_session.session_entry_access(
			session,
			descriptor.graph.entry,
		)
		if !accessible {
			return false, access_failure
		}
		entry, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
		if !borrowed {
			return false, borrow_failure
		}
		association, eligible, document_id := syntax_workflow_entry_bundle_association(workflow, entry)
		index, found := Syntax_Workflow_Find_Buffer(workflow, descriptor.graph.buffer_id)
		if !eligible {
			if found do syntax_workflow_entry_close(workflow, index)
			continue
		}
		desired_bundle_identity, bundle_found := syntax_workflow_bundle_identity(association)
		if !bundle_found {
			if found do syntax_workflow_entry_close(workflow, index)
			continue
		}
		if !found {
			index, found = syntax_workflow_entry_open(
				workflow,
				descriptor.graph.entry,
				descriptor.graph.buffer_id,
				document_id,
				association,
			)
		} else if workflow.entries[index].inspection.document_id != document_id ||
		          workflow.entries[index].inspection.association.language.id != association.language.id ||
		          workflow.entries[index].bundle_identity != desired_bundle_identity {
			syntax_workflow_entry_close(workflow, index)
			index, found = syntax_workflow_entry_open(
				workflow,
				descriptor.graph.entry,
				descriptor.graph.buffer_id,
				document_id,
				association,
			)
		} else if workflow.entries[index].inspection.association != syntax_workflow_language_association(association) {
			workflow.entries[index].inspection.association = syntax_workflow_language_association(association)
		}
		if found do seen[index] = true
	}
	for index in 0 ..< len(workflow.entries) {
		if workflow.entries[index].live && !seen[index] {
			syntax_workflow_entry_close(workflow, index)
		}
	}
	syntax_workflow_prune_explicit_languages(workflow)
	return true, {}
}

@(private)
Syntax_Commit_Observer_Context :: struct {
	workflow: ^Syntax_Workflow_State,
	buffer:   ^editor.Buffer,
}

// Syntax_Workflow_Commit_Observer returns the transaction observer for syntax updates.
Syntax_Workflow_Commit_Observer :: proc(
	observer_context: ^Syntax_Commit_Observer_Context,
) -> transaction.Commit_Observer {
	if observer_context == nil do return {}
	return transaction.Commit_Observer {
		procedure = syntax_workflow_observe_commit,
		user_data = observer_context,
	}
}

@(private)
syntax_workflow_observe_commit :: proc(
	user_data: rawptr,
	event: transaction.Commit_Event,
) -> bool {
	if user_data == nil do return true
	observer := cast(^Syntax_Commit_Observer_Context)user_data
	workflow := observer.workflow
	if !Syntax_Workflow_Is_Live(workflow) || observer.buffer == nil do return true
	index, found := Syntax_Workflow_Find_Buffer(workflow, event.buffer_id)
	if !found do return true
	entry := &workflow.entries[index]
	if entry.syntax.spans != nil do language.syntax_query_result_close(&entry.syntax)
	if entry.injections.generation != Injection_Generation(0) {
		if len(event.splices) == 0 {
			injection_result_close(&entry.injections)
		} else {
			edit_start := event.splices[0].start
			for splice in event.splices[1:] do edit_start = min(edit_start, splice.start)
			generation, generated := syntax_workflow_take_injection_generation(workflow)
			if generated {
				_, updated := injection_invalidate(
					&entry.injections,
					edit_start,
					event.result_revision,
					generation,
				)
				if !updated do injection_result_close(&entry.injections)
			} else {
				injection_result_close(&entry.injections)
			}
		}
	}
	entry.inspection.syntax_snapshot = {}
	entry.inspection.analysis_status = .Pending
	entry.refresh_attempted = false
	if entry.pending.live {
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_schedule_refresh(entry, event.result_revision)
		return true
	}
	if !entry.owner_ready || !editor.buffer_snapshot_is_live(&entry.source) ||
	   entry.inspection.confirmed_revision != event.base_revision {
		syntax_workflow_schedule_refresh(entry, event.result_revision)
		return true
	}
	opened, _ := editor.buffer_snapshot_open(observer.buffer, &entry.pending.result)
	if !opened {
		syntax_workflow_record_entry_failure(entry, language.Failure {
			operation = .Schedule,
			code = .Unavailable_Base_Snapshot,
			selection_generation = entry.inspection.selection_generation,
			source_revision = event.result_revision,
		})
		return true
	}
	if len(event.splices) == 0 {
		_, _ = editor.buffer_snapshot_close(&entry.pending.result)
		syntax_workflow_schedule_refresh(entry, event.result_revision)
		return true
	}
	splices, copied := syntax_workflow_copy_splices(
		event.splices,
		workflow.allocator,
	)
	if !copied {
		_, _ = editor.buffer_snapshot_close(&entry.pending.result)
		syntax_workflow_record_entry_failure(entry, language.Failure {
			operation = .Schedule,
			code = .Allocation,
			selection_generation = entry.inspection.selection_generation,
			source_revision = event.result_revision,
		})
		return true
	}
	entry.pending.live = true
	entry.pending.base_revision = event.base_revision
	entry.pending.result_revision = event.result_revision
	entry.pending.splices = splices
	entry.pending.allocator = workflow.allocator
	entry.inspection.pending = language.Pending_Work {
		kind = .Incremental,
		selection_generation = entry.inspection.selection_generation,
		source_revision = event.result_revision,
		work_bytes = language.INCREMENTAL_WORK_BYTES,
	}
	return true
}

// Syntax_Workflow_Maintain advances bounded pending syntax work.
Syntax_Workflow_Maintain :: proc(
	workflow: ^Syntax_Workflow_State,
	session: ^editor_session.Session,
	handle: editor_session.Session_Handle,
) -> (ok: bool, failure: editor_session.Failure_Context) {
	if !Syntax_Workflow_Is_Live(workflow) || session == nil {
		return false, editor_session.Failure_Context{code = .Invalid_Session, operation = .Inspect}
	}
	processed: u16
	for &entry in workflow.entries {
		if processed >= language.MAINTENANCE_ITEMS_PER_STEP do break
		if !entry.live || !entry.owner_ready do continue
		access, accessible, access_failure := editor_session.session_entry_access(session, entry.entry)
		if !accessible do return false, access_failure
		borrow, borrowed, borrow_failure := editor_session.entry_access_borrow(access)
		if !borrowed do return false, borrow_failure
		stats, stats_ok, _ := editor.buffer_stats(borrow.buffer)
		if !stats_ok do continue
		if entry.pending.live {
			syntax_workflow_maintain_incremental(workflow, &entry, stats.revision)
			processed += 1
			continue
		}
		if entry.inspection.pending.kind == .Invalid &&
		   editor.buffer_snapshot_is_live(&entry.source) &&
		   entry.inspection.confirmed_revision == stats.revision {
			continue
		}
		work_kind := language.Work_Kind.Initial
		work_bytes := language.INITIAL_WORK_BYTES
		if editor.buffer_snapshot_is_live(&entry.source) ||
		   entry.inspection.pending.kind == .Refresh ||
		   entry.inspection.confirmed_revision != editor.Revision(0) {
			if entry.refresh_attempted do continue
			work_kind = .Refresh
			work_bytes = language.REFRESH_WORK_BYTES
			entry.refresh_attempted = true
		}
		entry.inspection.pending = language.Pending_Work {
			kind = work_kind,
			selection_generation = entry.inspection.selection_generation,
			source_revision = stats.revision,
			work_bytes = work_bytes,
			refresh_requested = work_kind == .Refresh,
		}
		syntax_workflow_parse_current(
			workflow,
			&entry,
			borrow.buffer,
			work_kind,
			work_bytes,
		)
		processed += 1
	}
	return true, {}
}

@(private)
syntax_workflow_maintain_incremental :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
	current_revision: editor.Revision,
) {
	if workflow == nil || entry == nil || !entry.pending.live do return
	if syntax_workflow_entry_is_jan(entry) {
		syntax_workflow_maintain_jan_incremental(workflow, entry, current_revision)
		return
	}
	if current_revision != entry.pending.result_revision ||
	   entry.inspection.confirmed_revision != entry.pending.base_revision {
		revision := current_revision
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_schedule_refresh(entry, revision)
		return
	}
	tree_generation, generated := syntax_workflow_take_tree_generation(workflow)
	if !generated {
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_record_entry_failure(entry, workflow.latest_failure)
		return
	}
	event := transaction.Commit_Event {
		buffer_id = entry.inspection.buffer_id,
		base_revision = entry.pending.base_revision,
		result_revision = entry.pending.result_revision,
		splices = entry.pending.splices,
	}
	parse, parsed, parse_failure := language.tree_sitter_owner_parse_incremental(
		&entry.owner,
		&entry.source,
		&entry.pending.result,
		event,
		tree_generation,
	)
	if !parsed {
		revision := entry.pending.result_revision
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_record_entry_failure(entry, parse_failure)
		syntax_workflow_schedule_refresh(entry, revision)
		return
	}
	_, _ = editor.buffer_snapshot_close(&entry.source)
	entry.source = entry.pending.result
	entry.pending.result = {}
	syntax_workflow_pending_commit_close(entry)
	entry.inspection.parse_snapshot = parse
	entry.inspection.confirmed_revision = parse.source_revision
	entry.inspection.analysis_status = .Current
	entry.inspection.usage = parse.usage
	entry.inspection.pending = {}
	entry.inspection.latest_failure = {}
	entry.refresh_attempted = false
	syntax_workflow_update_owner_inspection(entry)
	syntax_workflow_refresh_factory_injections(workflow, entry)
}

// Syntax_Workflow_Project_Visible projects current visible syntax spans.
Syntax_Workflow_Project_Visible :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
	display_snapshot: display.Snapshot,
	proposal: ^ui.Proposal,
	text_view: ui.Object_Handle,
	owner_id: ui.Owner_ID,
) {
	if !Syntax_Workflow_Is_Live(workflow) || buffer == nil || proposal == nil do return
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return
	index, found := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
	if !found do return
	entry := &workflow.entries[index]
	if !entry.owner_ready || entry.inspection.selection.state == .Disabled do return
	if entry.inspection.confirmed_revision != stats.revision ||
	   entry.inspection.analysis_status != .Current {
		return
	}
	view, viewed, _ := display.snapshot_view(display_snapshot)
	if !viewed || view.key.buffer_id != stats.buffer_id || view.key.buffer_revision != stats.revision {
		return
	}
	visible_start, visible_end := syntax_workflow_visible_range(view)
	visible_halo := syntax_workflow_visible_halo(buffer, stats, visible_start, visible_end)
	if entry.syntax.spans != nil do language.syntax_query_result_close(&entry.syntax)
	generation, generated := syntax_workflow_take_syntax_generation(workflow)
	if !generated {
		syntax_workflow_record_entry_failure(entry, workflow.latest_failure)
		return
	}
	result: language.Syntax_Query_Result
	queried: bool
	query_failure: language.Failure
	if syntax_workflow_entry_is_jan(entry) {
		result, queried, query_failure = language.jan_structural_analysis_query_spans(
			&entry.jan_analysis,
			visible_start,
			visible_end,
			visible_halo,
			generation,
			workflow.allocator,
		)
	} else {
		result, queried, query_failure = language.tree_sitter_owner_query_spans(
			&entry.owner,
			&entry.source,
			visible_start,
			visible_end,
			visible_halo,
			generation,
			workflow.allocator,
		)
	}
	if !queried {
		syntax_workflow_record_entry_failure(entry, query_failure)
		return
	}
	entry.syntax = result
	entry.inspection.syntax_snapshot = result.snapshot
	entry.inspection.usage = result.snapshot.usage
	entry.inspection.analysis_status = .Current
	entry.inspection.latest_failure = {}
	_, projected, projection_failure := ui.proposal_project_syntax_decorations(
		proposal,
		text_view,
		result.snapshot,
		result.spans[:],
		owner_id,
	)
	if !projected {
		language.syntax_query_result_close(&entry.syntax)
		entry.inspection.syntax_snapshot = {}
		entry.inspection.analysis_status = .Failed
		entry.inspection.latest_failure = language.Failure {
			operation = .Publish_Syntax,
			code = .Invalid_Transaction,
			selection_generation = entry.inspection.selection_generation,
			source_revision = stats.revision,
			limit = projection_failure.limit,
			actual = projection_failure.actual,
		}
	}
}

@(private)
syntax_workflow_parse_current :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
	buffer: ^editor.Buffer,
	work_kind: language.Work_Kind,
	work_bytes: u64,
) -> bool {
	if workflow == nil || entry == nil || !entry.owner_ready || buffer == nil ||
	   (work_kind != .Initial && work_kind != .Refresh) {
		return false
	}
	if syntax_workflow_entry_is_jan(entry) {
		return syntax_workflow_parse_jan_current(workflow, entry, buffer, work_kind, work_bytes)
	}
	candidate: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &candidate)
	if !opened {
		syntax_workflow_record_entry_failure(entry, language.Failure {
			operation = .Schedule,
			code = .Unavailable_Base_Snapshot,
			selection_generation = entry.inspection.selection_generation,
		})
		return false
	}
	tree_generation, generated := syntax_workflow_take_tree_generation(workflow)
	if !generated {
		_, _ = editor.buffer_snapshot_close(&candidate)
		syntax_workflow_record_entry_failure(entry, workflow.latest_failure)
		return false
	}
	parse, parsed, parse_failure := language.tree_sitter_owner_parse_snapshot(
		&entry.owner,
		&candidate,
		entry.inspection.association.language,
		entry.inspection.selection.active,
		entry.inspection.selection_generation,
		tree_generation,
		work_bytes,
	)
	if !parsed {
		_, _ = editor.buffer_snapshot_close(&candidate)
		syntax_workflow_record_entry_failure(entry, parse_failure)
		if work_kind == .Initial {
			syntax_workflow_schedule_refresh(entry, entry.inspection.pending.source_revision)
		} else {
			entry.inspection.pending = {}
		}
		return false
	}
	if editor.buffer_snapshot_is_live(&entry.source) do _, _ = editor.buffer_snapshot_close(&entry.source)
	entry.source = candidate
	entry.inspection.parse_snapshot = parse
	entry.inspection.confirmed_revision = parse.source_revision
	entry.inspection.analysis_status = .Current
	entry.inspection.usage = parse.usage
	entry.inspection.pending = {}
	entry.inspection.latest_failure = {}
	entry.refresh_attempted = false
	syntax_workflow_update_owner_inspection(entry)
	syntax_workflow_refresh_factory_injections(workflow, entry)
	return true
}

@(private)
syntax_workflow_visible_range :: proc(view: display.Snapshot_View) -> (start, end: u64) {
	if len(view.rows) == 0 do return 0, 0
	start = u64(view.rows[0].source_start)
	end = u64(view.rows[0].source_end)
	for row in view.rows[1:] {
		start = min(start, u64(row.source_start))
		end = max(end, u64(row.source_end))
	}
	return
}

@(private)
syntax_workflow_visible_halo :: proc(
	buffer: ^editor.Buffer,
	stats: editor.Buffer_Stats,
	visible_start, visible_end: u64,
) -> u64 {
	if buffer == nil || visible_start > visible_end || visible_end > stats.text_bytes {
		return 0
	}
	before: u64
	if visible_start > 0 {
		position, positioned, _ := editor.buffer_position(
			buffer,
			editor.Byte_Offset(visible_start - 1),
		)
		if positioned {
			line, resolved, _ := editor.buffer_line_at_position(buffer, position)
			if resolved do before = visible_start - u64(line.start)
		}
	}
	after: u64
	if visible_end < stats.text_bytes {
		position, positioned, _ := editor.buffer_position(
			buffer,
			editor.Byte_Offset(visible_end),
		)
		if positioned {
			line, resolved, _ := editor.buffer_line_at_position(buffer, position)
			if resolved {
				if u64(line.next_start) < stats.text_bytes {
					next_position, next_positioned, _ := editor.buffer_position(buffer, line.next_start)
					if next_positioned {
						next_line, next_resolved, _ := editor.buffer_line_at_position(
							buffer,
							next_position,
						)
						if next_resolved do after = u64(next_line.next_start) - visible_end
					}
				} else {
					after = stats.text_bytes - visible_end
				}
			}
		}
	}
	return min(language.MAX_VISIBLE_HALO_BYTES, max(before, after))
}

@(private)
syntax_workflow_update_owner_inspection :: proc(entry: ^Syntax_Analysis_Entry) {
	if entry == nil || !entry.owner_ready do return
	if syntax_workflow_entry_is_jan(entry) {
		entry.inspection.parser_lifecycle = .Ready
		return
	}
	stats, inspected, _ := language.tree_sitter_owner_stats(&entry.owner)
	if !inspected do return
	entry.inspection.parser_lifecycle = stats.lifecycle
	entry.inspection.pending = stats.pending
}

@(private)
syntax_workflow_record_entry_failure :: proc(
	entry: ^Syntax_Analysis_Entry,
	failure: language.Failure,
) {
	if entry == nil do return
	entry.inspection.analysis_status = .Failed
	entry.inspection.latest_failure = failure
	entry.inspection.syntax_snapshot = {}
}

@(private)
syntax_workflow_schedule_refresh :: proc(
	entry: ^Syntax_Analysis_Entry,
	revision: editor.Revision,
) {
	if entry == nil do return
	entry.inspection.pending = language.Pending_Work {
		kind = .Refresh,
		selection_generation = entry.inspection.selection_generation,
		source_revision = revision,
		work_bytes = language.REFRESH_WORK_BYTES,
		refresh_requested = true,
	}
}

@(private)
syntax_workflow_copy_splices :: proc(
	source: []transaction.Normalized_Splice,
	allocator: runtime.Allocator,
) -> (result: []transaction.Normalized_Splice, ok: bool) {
	if len(source) == 0 || u64(len(source)) > transaction.MAX_SPLICES ||
	   allocator.procedure == nil {
		return nil, false
	}
	text_bytes: u64
	for splice in source {
		addition := u64(len(splice.replacement_text)) + u64(len(splice.removed_text))
		if addition > language.MAX_TEMPORARY_BYTES - min(text_bytes, language.MAX_TEMPORARY_BYTES) {
			return nil, false
		}
		text_bytes += addition
	}
	allocation_error: runtime.Allocator_Error
	result, allocation_error = make([]transaction.Normalized_Splice, len(source), allocator)
	if allocation_error != nil do return nil, false
	for splice, index in source {
		replacement, replacement_error := strings.clone(splice.replacement_text, allocator)
		if replacement_error != nil {
			syntax_workflow_delete_splices(result[:index], allocator)
			delete(result, allocator)
			return nil, false
		}
		removed, removed_error := strings.clone(splice.removed_text, allocator)
		if removed_error != nil {
			if len(replacement) > 0 do delete(replacement, allocator)
			syntax_workflow_delete_splices(result[:index], allocator)
			delete(result, allocator)
			return nil, false
		}
		result[index] = splice
		result[index].replacement_text = replacement
		result[index].removed_text = removed
	}
	return result, true
}

@(private)
syntax_workflow_delete_splices :: proc(
	splices: []transaction.Normalized_Splice,
	allocator: runtime.Allocator,
) {
	for splice in splices {
		if len(splice.replacement_text) > 0 do delete(splice.replacement_text, allocator)
		if len(splice.removed_text) > 0 do delete(splice.removed_text, allocator)
	}
}

@(private)
syntax_workflow_pending_commit_close :: proc(entry: ^Syntax_Analysis_Entry) {
	if entry == nil do return
	if editor.buffer_snapshot_is_live(&entry.pending.result) {
		_, _ = editor.buffer_snapshot_close(&entry.pending.result)
	}
	if entry.pending.splices != nil {
		syntax_workflow_delete_splices(entry.pending.splices, entry.pending.allocator)
		delete(entry.pending.splices, entry.pending.allocator)
	}
	entry.pending = {}
}

// Syntax_Workflow_Close releases all retained syntax workflow state.
Syntax_Workflow_Close :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (ok: bool, failure: language.Failure) {
	if !Syntax_Workflow_Is_Live(workflow) {
		return false, language.Failure{operation = .Close, code = .Invalid_Registry}
	}
	for index in 0 ..< len(workflow.entries) {
		if workflow.entries[index].live do syntax_workflow_entry_close(workflow, index)
	}
	registries_closed, registry_failure := syntax_workflow_provider_registries_close(workflow)
	if !registries_closed do return false, registry_failure
	catalog_closed, catalog_failure := language.language_catalog_close(&workflow.language_catalog)
	if !catalog_closed do return false, syntax_workflow_catalog_failure(catalog_failure, .Close)
	workflow.initialized = false
	workflow.closed = true
	return true, {}
}

// Syntax_Workflow_Find_Buffer resolves a live syntax entry by buffer identity.
Syntax_Workflow_Find_Buffer :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer_id: editor.Buffer_ID,
) -> (index: int, found: bool) {
	if workflow == nil || buffer_id == editor.Buffer_ID(0) do return 0, false
	for &entry, candidate_index in workflow.entries {
		if entry.live && entry.inspection.buffer_id == buffer_id do return candidate_index, true
	}
	return 0, false
}

// Syntax_Workflow_Inspect_Buffer copies the current selection and provider view.
Syntax_Workflow_Inspect_Buffer :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
) -> (
	inspection: language.Language_Selection_Inspection,
	provider: language.Provider_Descriptor,
	provider_found: bool,
	ok: bool,
) {
	if !Syntax_Workflow_Is_Live(workflow) || buffer == nil do return {}, {}, false, false
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok do return {}, {}, false, false
	index, found := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
	if found {
		inspection = workflow.entries[index].inspection
	} else {
		inspection = language.Language_Selection_Inspection {
			buffer_id = stats.buffer_id,
			confirmed_revision = stats.revision,
			analysis_status = .Plain_Text,
		}
	}
	provider_handle := inspection.selection.active
	if provider_handle.provider_id == language.Provider_ID(0) {
		provider_handle = inspection.selection.factory
	}
	provider_registry, registry_found := syntax_workflow_provider_registry(
		workflow,
		inspection.association.language.id,
	)
	if !registry_found do return inspection, {}, false, true
	provider, provider_found, _ = language.provider_registry_provider(
		&provider_registry.registry,
		provider_handle,
	)
	return inspection, provider, provider_found, true
}

// Syntax_Workflow_Structural_Context borrows an exact-revision structural context.
Syntax_Workflow_Structural_Context :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
) -> (
	owner: ^language.Tree_Sitter_Owner,
	source: ^editor.Buffer_Snapshot,
	scope: language.Structural_Scope,
	ok: bool,
	failure: language.Failure,
) {
	if !Syntax_Workflow_Is_Live(workflow) || buffer == nil {
		return nil, nil, {}, false, language.Failure {
			operation = .Query_Structure,
			code = .Structural_Capability_Unavailable,
		}
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok {
		return nil, nil, {}, false, language.Failure {
			operation = .Query_Structure,
			code = .Unavailable_Base_Snapshot,
		}
	}
	index, found := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
	if !found {
		return nil, nil, {}, false, language.Failure {
			operation = .Query_Structure,
			code = .Structural_Capability_Unavailable,
			source_revision = stats.revision,
		}
	}
	entry := &workflow.entries[index]
	if syntax_workflow_entry_is_jan(entry) || !entry.owner_ready || entry.inspection.analysis_status != .Current {
		failure = entry.inspection.latest_failure
		if failure.code == .None {
			failure = language.Failure {
				operation = .Query_Structure,
				code = .Structural_Capability_Unavailable,
				language_id = entry.inspection.association.language.id,
				provider = entry.inspection.selection.active,
				selection_generation = entry.inspection.selection_generation,
				source_revision = stats.revision,
			}
		}
		return nil, nil, {}, false, failure
	}
	if !editor.buffer_snapshot_is_live(&entry.source) ||
	   entry.inspection.confirmed_revision != stats.revision {
		return nil, nil, {}, false, language.Failure {
			operation = .Query_Structure,
			code = .Unavailable_Base_Snapshot,
			language_id = entry.inspection.association.language.id,
			provider = entry.inspection.selection.active,
			selection_generation = entry.inspection.selection_generation,
			source_revision = stats.revision,
		}
	}
	parse := entry.inspection.parse_snapshot
	scope = language.Structural_Scope {
		buffer_id = parse.buffer_id,
		source_revision = parse.source_revision,
		language = parse.language,
		provider = parse.provider,
		selection_generation = parse.selection_generation,
		parser_generation = parse.parser_generation,
		tree_generation = parse.tree_generation,
	}
	if !language.structural_scope_is_valid(scope) || scope.buffer_id != stats.buffer_id ||
	   scope.source_revision != stats.revision {
		return nil, nil, {}, false, language.Failure {
			operation = .Query_Structure,
			code = .Stale_Selection,
			language_id = parse.language.id,
			provider = parse.provider,
			selection_generation = parse.selection_generation,
			source_revision = stats.revision,
		}
	}
	return &entry.owner, &entry.source, scope, true, {}
}

// Syntax_Workflow_Symbol_At_Point resolves one symbol at a canonical byte offset.
Syntax_Workflow_Symbol_At_Point :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
	document_id: document.Document_ID,
	has_document: bool,
	point: editor.Byte_Offset,
) -> (symbol: language.Generic_Symbol, ok: bool, failure: language.Failure) {
	if buffer == nil {
		return {}, false, language.Failure {
			operation = .Query_Symbols,
			code = .Symbol_Capability_Unavailable,
		}
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok {
		return {}, false, language.Failure {
			operation = .Query_Symbols,
			code = .Unavailable_Base_Snapshot,
		}
	}
	index, found := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
	if found {
		entry := &workflow.entries[index]
		if !syntax_workflow_entry_is_jan(entry) && entry.owner_ready && entry.inspection.analysis_status == .Current &&
		   editor.buffer_snapshot_is_live(&entry.source) &&
		   entry.inspection.confirmed_revision == stats.revision {
			parse := entry.inspection.parse_snapshot
			scope := language.Symbol_Query_Scope {
				kind = .Active_Buffer,
				buffer_id = parse.buffer_id,
				document_id = document_id,
				has_document = has_document,
				source_revision = parse.source_revision,
				language = parse.language,
				provider = parse.provider,
				selection_generation = parse.selection_generation,
				request_generation = language.Symbol_Request_Generation(1),
			}
			resolved, provider_ok, provider_failure := language.tree_sitter_owner_symbol_at_point(
				&entry.owner,
				&entry.source,
				scope,
				point,
			)
			if provider_ok do return resolved, true, {}
			failure = provider_failure
		}
	}

	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened {
		return {}, false, language.Failure {
			operation = .Query_Symbols,
			code = .Unavailable_Base_Snapshot,
			source_revision = stats.revision,
		}
	}
	defer editor.buffer_snapshot_close(&snapshot)
	return language.generic_symbol_at_point(&snapshot, document_id, has_document, point)
}

// Syntax_Workflow_Symbol_Index copies one exact-revision symbol index.
Syntax_Workflow_Symbol_Index :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
	document_id: document.Document_ID,
	has_document: bool,
	request_generation: language.Symbol_Request_Generation,
	result_generation: language.Symbol_Result_Generation,
	allocator := context.allocator,
) -> (index: language.Symbol_Index, ok: bool, failure: language.Failure) {
	if buffer == nil {
		return {}, false, language.Failure {
			operation = .Query_Symbols,
			code = .Symbol_Capability_Unavailable,
		}
	}
	stats, stats_ok, _ := editor.buffer_stats(buffer)
	if !stats_ok {
		return {}, false, language.Failure {
			operation = .Query_Symbols,
			code = .Unavailable_Base_Snapshot,
		}
	}
	entry_index, found := Syntax_Workflow_Find_Buffer(workflow, stats.buffer_id)
	if found {
		entry := &workflow.entries[entry_index]
		if !syntax_workflow_entry_is_jan(entry) && entry.owner_ready && entry.inspection.analysis_status == .Current &&
		   editor.buffer_snapshot_is_live(&entry.source) &&
		   entry.inspection.confirmed_revision == stats.revision {
			parse := entry.inspection.parse_snapshot
			scope := language.Symbol_Query_Scope {
				kind = .Active_Buffer,
				buffer_id = parse.buffer_id,
				document_id = document_id,
				has_document = has_document,
				source_revision = parse.source_revision,
				language = parse.language,
				provider = parse.provider,
				selection_generation = parse.selection_generation,
				request_generation = request_generation,
			}
			provider_index, provider_ok, provider_failure := language.tree_sitter_owner_symbol_index(
				&entry.owner,
				&entry.source,
				scope,
				result_generation,
				language.DEFAULT_SYMBOL_LIMITS,
				allocator,
			)
			if provider_ok do return provider_index, true, {}
			if provider_failure.code != .Symbol_Capability_Unavailable &&
			   provider_failure.code != .Stale_Selection {
				return {}, false, provider_failure
			}
		}
	}
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &snapshot)
	if !opened {
		return {}, false, language.Failure {
			operation = .Query_Symbols,
			code = .Unavailable_Base_Snapshot,
			source_revision = stats.revision,
		}
	}
	defer editor.buffer_snapshot_close(&snapshot)
	return language.generic_symbol_index(
		&snapshot,
		document_id,
		has_document,
		request_generation,
		result_generation,
		language.DEFAULT_SYMBOL_LIMITS,
		allocator,
	)
}

@(private)
syntax_workflow_entry_open :: proc(
	workflow: ^Syntax_Workflow_State,
	entry_handle: editor_session.Entry_Handle,
	buffer_id: editor.Buffer_ID,
	document_id: document.Document_ID,
	association: language.Language_Catalog_Association,
) -> (index: int, ok: bool) {
	if !Syntax_Workflow_Is_Live(workflow) || buffer_id == editor.Buffer_ID(0) ||
	   document_id == document.Document_ID(0) ||
	   association.language.id == language.Language_ID(0) ||
	   association.language.generation == language.Language_Generation(0) ||
	   workflow.live_count >= language.MAX_LIVE_SELECTIONS {
		workflow.latest_failure = language.Failure {
			operation = .Select,
			code = .Snapshot_Limit,
			language_id = association.language.id,
			limit = language.MAX_LIVE_SELECTIONS,
			actual = u64(workflow.live_count) + 1,
		}
		return 0, false
	}
	for &candidate, candidate_index in workflow.entries {
		if candidate.live do continue
		provider_registry, registry_found := syntax_workflow_provider_registry(
			workflow,
			association.language.id,
		)
		if !registry_found {
			workflow.latest_failure = language.Failure {
				operation = .Select,
				code = .Invalid_Provider,
				language_id = association.language.id,
			}
			return 0, false
		}
		selection_generation, generated := syntax_workflow_take_selection_generation(workflow)
		if !generated do return 0, false
		bundle_identity, bundle_found := syntax_workflow_bundle_identity(association)
		if !bundle_found do return 0, false
		candidate = Syntax_Analysis_Entry {
			live = true,
			bundle_identity = bundle_identity,
			entry = entry_handle,
			inspection = {
				buffer_id = buffer_id,
				document_id = document_id,
				has_document = true,
				association = syntax_workflow_language_association(association),
				selection = provider_registry.selection,
				selection_generation = selection_generation,
				analysis_status = .Plain_Text,
			},
		}
		workflow.live_count += 1
		if candidate.inspection.selection.state == .Disabled {
			return candidate_index, true
		}
		syntax_workflow_entry_initialize_owner(workflow, &candidate)
		return candidate_index, true
	}
	return 0, false
}

@(private)
syntax_workflow_bundle_identity :: proc(
	association: language.Language_Catalog_Association,
) -> (string, bool) {
	selector_value := association.selector
	selector := string(selector_value.bytes[:selector_value.length])
	return language.factory_syntax_identity_for_selector(association.language.id, selector)
}

@(private)
syntax_workflow_refresh_factory_injections :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
) {
	if workflow == nil || entry == nil || !entry.live || !entry.owner_ready ||
	   entry.bundle_identity != language.FACTORY_HTML_BUNDLE_IDENTITY {
		return
	}
	inspection, queried, _ := language.tree_sitter_owner_query_factory_injections(
		&entry.owner,
		&entry.source,
	)
	if !queried {
		if entry.injections.generation != Injection_Generation(0) do injection_result_close(&entry.injections)
		return
	}
	candidates: [language.MAX_FACTORY_INJECTION_CAPTURES]Injection_Candidate
	for capture, index in inspection.captures[:inspection.count] {
		candidates[index] = {
			identity = Injection_Region_ID(index + 1),
			start = capture.start,
			end = capture.end,
			language_id = capture.language_id,
			priority = capture.priority,
		}
	}
	_, _ = Syntax_Workflow_Compose_Injections(
		workflow,
		entry.inspection.buffer_id,
		candidates[:inspection.count],
	)
}

@(private)
syntax_workflow_entry_initialize_owner :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
) {
	if workflow == nil || entry == nil || !entry.live ||
	   entry.inspection.selection.active.provider_id == 0 {
		return
	}
	parser_generation, generated := syntax_workflow_take_parser_generation(workflow)
	if !generated {
		entry.inspection.analysis_status = .Failed
		entry.inspection.latest_failure = workflow.latest_failure
		return
	}
	entry.parser_generation = parser_generation
	if syntax_workflow_entry_is_jan(entry) {
		initialized, jan_failure := language.jan_structural_owner_init(
			&entry.jan_owner,
			parser_generation,
			workflow.allocator,
		)
		if !initialized {
			failure := syntax_workflow_jan_failure(entry, jan_failure)
			entry.inspection.analysis_status = .Failed
			entry.inspection.latest_failure = failure
			workflow.latest_failure = failure
			return
		}
	} else {
		initialized, init_failure := language.tree_sitter_owner_init_factory(
			&entry.owner,
			entry.bundle_identity,
			parser_generation,
			workflow.allocator,
		)
		if !initialized {
			entry.inspection.analysis_status = .Failed
			entry.inspection.latest_failure = init_failure
			workflow.latest_failure = init_failure
			return
		}
		compiled, query_failure := language.tree_sitter_owner_compile_factory_query(
			&entry.owner,
			entry.bundle_identity,
			language.Query_Generation(1),
		)
		if !compiled {
			_, _ = language.tree_sitter_owner_close(&entry.owner)
			entry.inspection.analysis_status = .Failed
			entry.inspection.latest_failure = query_failure
			workflow.latest_failure = query_failure
			return
		}
	}
	entry.owner_ready = true
	entry.inspection.parser_lifecycle = .Ready
	entry.inspection.analysis_status = .Pending
	entry.inspection.pending = language.Pending_Work {
		kind = .Initial,
		selection_generation = entry.inspection.selection_generation,
		work_bytes = language.INITIAL_WORK_BYTES,
	}
}

@(private)
syntax_workflow_replace_selection :: proc(
	workflow: ^Syntax_Workflow_State,
	language_id: language.Language_ID,
	selection: language.Provider_Selection,
) {
	provider_registry, found := syntax_workflow_provider_registry(workflow, language_id)
	if !found do return
	provider_registry.selection = selection
	for &entry in workflow.entries {
		if !entry.live do continue
		if entry.inspection.association.language.id == language_id {
			syntax_workflow_entry_reset_owner(workflow, &entry, selection)
			continue
		}
		refresh_injections := false
		for region in entry.injections.regions {
			if region.language_identity.id == language_id {
				refresh_injections = true
				break
			}
		}
		if refresh_injections do syntax_workflow_refresh_factory_injections(workflow, &entry)
	}
}

@(private)
syntax_workflow_entry_reset_owner :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
	selection: language.Provider_Selection,
) {
	if entry == nil do return
	if entry.pending.live do syntax_workflow_pending_commit_close(entry)
	if entry.syntax.spans != nil do language.syntax_query_result_close(&entry.syntax)
	if entry.injections.generation != Injection_Generation(0) do injection_result_close(&entry.injections)
	if editor.buffer_snapshot_is_live(&entry.source) do _, _ = editor.buffer_snapshot_close(&entry.source)
	if entry.jan_analysis_live {
		language.jan_structural_analysis_close(&entry.jan_analysis)
		entry.jan_analysis_live = false
	}
	if entry.owner_ready && syntax_workflow_entry_is_jan(entry) {
		if !language.jan_structural_owner_close(&entry.jan_owner) {
			workflow.latest_failure = language.Failure {
				operation = .Close,
				code = .Invalid_Provider,
				language_id = entry.inspection.association.language.id,
			}
		}
	} else if entry.owner_ready {
		_, close_failure := language.tree_sitter_owner_close(&entry.owner)
		if close_failure.code != .None do workflow.latest_failure = close_failure
	}
	entry.owner = {}
	entry.jan_owner = {}
	entry.owner_ready = false
	entry.parser_generation = 0
	entry.inspection.selection = selection
	entry.inspection.parse_snapshot = {}
	entry.inspection.syntax_snapshot = {}
	entry.inspection.usage = {}
	entry.inspection.pending = {}
	entry.inspection.confirmed_revision = 0
	entry.inspection.parser_lifecycle = .Uninitialized
	entry.inspection.analysis_status = .Plain_Text
	generation, generated := syntax_workflow_take_selection_generation(workflow)
	if generated do entry.inspection.selection_generation = generation
	if selection.state != .Disabled do syntax_workflow_entry_initialize_owner(workflow, entry)
}

@(private)
syntax_workflow_entry_close :: proc(workflow: ^Syntax_Workflow_State, index: int) {
	if workflow == nil || index < 0 || index >= len(workflow.entries) do return
	entry := &workflow.entries[index]
	if !entry.live do return
	if entry.pending.live do syntax_workflow_pending_commit_close(entry)
	if entry.syntax.spans != nil do language.syntax_query_result_close(&entry.syntax)
	if entry.injections.generation != Injection_Generation(0) do injection_result_close(&entry.injections)
	if editor.buffer_snapshot_is_live(&entry.source) do _, _ = editor.buffer_snapshot_close(&entry.source)
	if entry.jan_analysis_live do language.jan_structural_analysis_close(&entry.jan_analysis)
	if entry.owner_ready && syntax_workflow_entry_is_jan(entry) {
		if !language.jan_structural_owner_close(&entry.jan_owner) {
			workflow.latest_failure = language.Failure {
				operation = .Close,
				code = .Invalid_Provider,
				language_id = entry.inspection.association.language.id,
			}
		}
	} else if entry.owner_ready {
		_, close_failure := language.tree_sitter_owner_close(&entry.owner)
		if close_failure.code != .None do workflow.latest_failure = close_failure
	}
	entry^ = {}
	assert(workflow.live_count > 0)
	workflow.live_count -= 1
}

@(private)
syntax_workflow_entry_bundle_association :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: editor_session.Entry_Borrow,
) -> (
	association: language.Language_Catalog_Association,
	eligible: bool,
	document_id: document.Document_ID,
) {
	resolved, associated, resolved_document_id := Syntax_Workflow_Entry_Language_Association(
		workflow,
		entry,
	)
	if !associated do return {}, false, resolved_document_id
	association = resolved
	_, eligible = syntax_workflow_provider_registry(workflow, association.language.id)
	return association, eligible, resolved_document_id
}

@(private)
syntax_workflow_language_association :: proc(
	association: language.Language_Catalog_Association,
) -> language.Language_Association {
	return {
		language = association.language,
		source = association.kind == .Explicit ? .Native_Request : .Factory_Filename_Suffix,
		value = association.selector,
	}
}

// Syntax_Workflow_Entry_Language_Association resolves catalog data for one entry.
Syntax_Workflow_Entry_Language_Association :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: editor_session.Entry_Borrow,
) -> (
	association: language.Language_Catalog_Association,
	ok: bool,
	document_id: document.Document_ID,
) {
	if workflow == nil || !entry.has_document || entry.document == nil do return {}, false, 0
	status, status_ok, _ := document.document_status(entry.document)
	if !status_ok || !status.has_target do return {}, false, status.document_id
	explicit := ""
	stats, stats_ok, _ := editor.buffer_stats(entry.buffer)
	if stats_ok && syntax_workflow_has_explicit_jan(workflow, stats.buffer_id) do explicit = "jan"
	association, ok, _ = language.language_catalog_resolve(
		&workflow.language_catalog,
		status.target_path,
		explicit,
	)
	return association, ok, status.document_id
}

@(private)
syntax_factory_language :: proc() -> language.Language_Identity {
	registration, _ := language.factory_bundle_registration(language.FACTORY_ODIN_BUNDLE_IDENTITY)
	return registration.language
}

@(private)
syntax_factory_association :: proc() -> language.Language_Association {
	association: language.Language_Association
	association.language = syntax_factory_language()
	association.source = .Factory_Filename_Suffix
	association.value.length = u16(copy(association.value.bytes[:], ".odin"))
	return association
}

@(private)
syntax_factory_provider_definition :: proc() -> language.Provider_Definition {
	registration, _ := language.factory_bundle_registration(language.FACTORY_ODIN_BUNDLE_IDENTITY)
	return registration.provider
}

@(private)
syntax_workflow_take_selection_generation :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (language.Selection_Generation, bool) {
	if workflow.next_selection_generation == 0 {
		workflow.latest_failure = language.Failure{operation = .Select, code = .Generation_Limit}
		return 0, false
	}
	result := workflow.next_selection_generation
	workflow.next_selection_generation += 1
	return result, true
}

@(private)
syntax_workflow_take_parser_generation :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (language.Parser_Generation, bool) {
	if workflow.next_parser_generation == 0 {
		workflow.latest_failure = language.Failure{operation = .Initialize, code = .Generation_Limit}
		return 0, false
	}
	result := workflow.next_parser_generation
	workflow.next_parser_generation += 1
	return result, true
}

@(private)
syntax_workflow_take_tree_generation :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (language.Tree_Generation, bool) {
	if workflow.next_tree_generation == 0 {
		workflow.latest_failure = language.Failure{operation = .Schedule, code = .Generation_Limit}
		return 0, false
	}
	result := workflow.next_tree_generation
	workflow.next_tree_generation += 1
	return result, true
}

@(private)
syntax_workflow_take_syntax_generation :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (language.Syntax_Snapshot_Generation, bool) {
	if workflow.next_syntax_generation == 0 {
		workflow.latest_failure = language.Failure{operation = .Publish_Syntax, code = .Generation_Limit}
		return 0, false
	}
	result := workflow.next_syntax_generation
	workflow.next_syntax_generation += 1
	return result, true
}

@(private)
syntax_workflow_take_injection_generation :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (Injection_Generation, bool) {
	if workflow.next_injection_generation == 0 {
		workflow.latest_failure = language.Failure{operation = .Publish_Syntax, code = .Generation_Limit}
		return 0, false
	}
	result := workflow.next_injection_generation
	workflow.next_injection_generation += 1
	return result, true
}

// Syntax_Workflow_Is_Live reports whether the workflow may be used.
Syntax_Workflow_Is_Live :: proc(workflow: ^Syntax_Workflow_State) -> bool {
	return workflow != nil && workflow.initialized && !workflow.closed &&
		workflow.language_catalog.state != nil && workflow.provider_registry_count > 0
}

@(private)
syntax_workflow_catalog_failure :: proc(
	failure: language.Language_Catalog_Failure,
	operation: language.Operation,
) -> language.Failure {
	code := language.Failure_Code.Invalid_Association
	if failure.code == .Allocation do code = .Allocation
	if failure.code == .Generation_Limit || failure.code == .Stale_Generation do code = .Generation_Limit
	return language.Failure {
		operation = operation,
		code = code,
		limit = failure.limit,
		actual = failure.actual,
	}
}
