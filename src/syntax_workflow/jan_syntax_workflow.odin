// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

import "../editor"
import "../language"
import "../transaction"
import "base:runtime"

@(private)
syntax_workflow_entry_is_jan :: proc(entry: ^Syntax_Analysis_Entry) -> bool {
	return entry != nil &&
		entry.bundle_identity == language.FACTORY_JAN_BUNDLE_IDENTITY
}

/* syntax_workflow_select_jan records an explicit Jan selection for one buffer. */
syntax_workflow_select_jan :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
) -> bool {
	if !Syntax_Workflow_Is_Live(workflow) || buffer == nil do return false
	stats, inspected, _ := editor.buffer_stats(buffer)
	if !inspected do return false
	if syntax_workflow_has_explicit_jan(workflow, stats.buffer_id) do return true
	if workflow.explicit_jan_count >= language.MAX_LIVE_SELECTIONS do return false
	workflow.explicit_jan_buffers[workflow.explicit_jan_count] = stats.buffer_id
	workflow.explicit_jan_count += 1
	return true
}

/* syntax_workflow_clear_explicit_language restores suffix-based selection. */
syntax_workflow_clear_explicit_language :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
) -> bool {
	if !Syntax_Workflow_Is_Live(workflow) || buffer == nil do return false
	stats, inspected, _ := editor.buffer_stats(buffer)
	if !inspected do return false
	for index in 0 ..< int(workflow.explicit_jan_count) {
		if workflow.explicit_jan_buffers[index] != stats.buffer_id do continue
		last := int(workflow.explicit_jan_count) - 1
		workflow.explicit_jan_buffers[index] = workflow.explicit_jan_buffers[last]
		workflow.explicit_jan_buffers[last] = 0
		workflow.explicit_jan_count -= 1
		return true
	}
	return false
}

/* syntax_workflow_set_jan_configuration atomically selects one confirmed policy. */
syntax_workflow_set_jan_configuration :: proc(
	workflow: ^Syntax_Workflow_State,
	configuration: language.Jan_Configuration,
) -> bool {
	if !Syntax_Workflow_Is_Live(workflow) ||
	   !language.jan_configuration_is_valid(configuration) {
		return false
	}
	if configuration.identity == workflow.jan_configuration.identity do return true
	workflow.jan_configuration = configuration
	provider_registry, found := syntax_workflow_provider_registry(
		workflow,
		language.FACTORY_JAN_LANGUAGE_ID,
	)
	if !found do return false
	for &entry in workflow.entries {
		if !entry.live || !syntax_workflow_entry_is_jan(&entry) do continue
		syntax_workflow_entry_reset_owner(workflow, &entry, provider_registry.selection)
	}
	return true
}

@(private)
syntax_workflow_has_explicit_jan :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer_id: editor.Buffer_ID,
) -> bool {
	if workflow == nil || buffer_id == editor.Buffer_ID(0) do return false
	for candidate in workflow.explicit_jan_buffers[:workflow.explicit_jan_count] {
		if candidate == buffer_id do return true
	}
	return false
}

@(private)
syntax_workflow_prune_explicit_languages :: proc(workflow: ^Syntax_Workflow_State) {
	if workflow == nil do return
	index := 0
	for index < int(workflow.explicit_jan_count) {
		_, found := Syntax_Workflow_Find_Buffer(workflow, workflow.explicit_jan_buffers[index])
		if found {
			index += 1
			continue
		}
		last := int(workflow.explicit_jan_count) - 1
		workflow.explicit_jan_buffers[index] = workflow.explicit_jan_buffers[last]
		workflow.explicit_jan_buffers[last] = 0
		workflow.explicit_jan_count -= 1
	}
}

@(private)
syntax_workflow_parse_jan_current :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
	buffer: ^editor.Buffer,
	work_kind: language.Work_Kind,
	work_bytes: u64,
) -> bool {
	candidate: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(buffer, &candidate)
	if !opened {
		syntax_workflow_record_entry_failure(entry, language.Failure {
			operation = .Schedule,
			code = .Unavailable_Base_Snapshot,
			language_id = entry.inspection.association.language.id,
			selection_generation = entry.inspection.selection_generation,
		})
		return false
	}
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&candidate)
	if !stats_ok {
		_, _ = editor.buffer_snapshot_close(&candidate)
		return false
	}
	source, copied := syntax_workflow_copy_snapshot(&candidate, workflow.allocator)
	if !copied {
		_, _ = editor.buffer_snapshot_close(&candidate)
		syntax_workflow_record_entry_failure(entry, language.Failure {
			operation = .Schedule,
			code = .Allocation,
			language_id = entry.inspection.association.language.id,
			selection_generation = entry.inspection.selection_generation,
			source_revision = stats.revision,
		})
		return false
	}
	defer delete(source, workflow.allocator)
	analysis_generation, generated := syntax_workflow_take_jan_analysis_generation(workflow)
	if !generated {
		_, _ = editor.buffer_snapshot_close(&candidate)
		syntax_workflow_record_entry_failure(entry, workflow.latest_failure)
		return false
	}
	scope := syntax_workflow_jan_scope(workflow, entry, stats.revision, analysis_generation)
	analysis: language.Jan_Structural_Analysis
	analyzed: bool
	jan_failure: language.Jan_Failure
	if entry.jan_analysis_live {
		analysis, analyzed, jan_failure = language.jan_structural_owner_refresh(
			&entry.jan_owner,
			source,
			scope,
			workflow.jan_configuration,
			language.DEFAULT_JAN_RESOURCE_LIMITS,
			workflow.allocator,
		)
	} else {
		analysis, analyzed, jan_failure = language.jan_structural_owner_publish_initial(
			&entry.jan_owner,
			source,
			scope,
			workflow.jan_configuration,
			language.DEFAULT_JAN_RESOURCE_LIMITS,
			workflow.allocator,
		)
	}
	if !analyzed {
		_, _ = editor.buffer_snapshot_close(&candidate)
		syntax_workflow_record_entry_failure(entry, syntax_workflow_jan_failure(entry, jan_failure))
		if work_kind == .Initial {
			syntax_workflow_schedule_refresh(entry, stats.revision)
		} else {
			entry.inspection.pending = {}
		}
		return false
	}
	if entry.jan_analysis_live do language.jan_structural_analysis_close(&entry.jan_analysis)
	if editor.buffer_snapshot_is_live(&entry.source) do _, _ = editor.buffer_snapshot_close(&entry.source)
	entry.jan_analysis = analysis
	entry.jan_analysis_live = true
	entry.source = candidate
	syntax_workflow_publish_jan_analysis(workflow, entry, scope, work_bytes)
	return true
}

@(private)
syntax_workflow_maintain_jan_incremental :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
	current_revision: editor.Revision,
) {
	if current_revision != entry.pending.result_revision ||
	   entry.inspection.confirmed_revision != entry.pending.base_revision ||
	   !entry.jan_analysis_live {
		revision := current_revision
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_schedule_refresh(entry, revision)
		return
	}
	base_source, base_copied := syntax_workflow_copy_snapshot(&entry.source, workflow.allocator)
	result_source, result_copied := syntax_workflow_copy_snapshot(&entry.pending.result, workflow.allocator)
	if !base_copied || !result_copied {
		if base_source != nil do delete(base_source, workflow.allocator)
		if result_source != nil do delete(result_source, workflow.allocator)
		revision := entry.pending.result_revision
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_record_entry_failure(entry, language.Failure {
			operation = .Schedule,
			code = .Allocation,
			language_id = entry.inspection.association.language.id,
			selection_generation = entry.inspection.selection_generation,
			source_revision = revision,
		})
		return
	}
	defer delete(base_source, workflow.allocator)
	defer delete(result_source, workflow.allocator)
	analysis_generation, generated := syntax_workflow_take_jan_analysis_generation(workflow)
	if !generated {
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_record_entry_failure(entry, workflow.latest_failure)
		return
	}
	scope := syntax_workflow_jan_scope(workflow, entry, entry.pending.result_revision, analysis_generation)
	event := transaction.Commit_Event {
		buffer_id = entry.inspection.buffer_id,
		base_revision = entry.pending.base_revision,
		result_revision = entry.pending.result_revision,
		splices = entry.pending.splices,
	}
	analysis, analyzed, jan_failure := language.jan_structural_owner_analyze_incremental_configured(
		&entry.jan_owner,
		base_source,
		result_source,
		event,
		scope,
		workflow.jan_configuration,
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		workflow.allocator,
	)
	if !analyzed {
		revision := entry.pending.result_revision
		syntax_workflow_pending_commit_close(entry)
		syntax_workflow_record_entry_failure(entry, syntax_workflow_jan_failure(entry, jan_failure))
		syntax_workflow_schedule_refresh(entry, revision)
		return
	}
	language.jan_structural_analysis_close(&entry.jan_analysis)
	_, _ = editor.buffer_snapshot_close(&entry.source)
	entry.jan_analysis = analysis
	entry.source = entry.pending.result
	entry.pending.result = {}
	syntax_workflow_pending_commit_close(entry)
	syntax_workflow_publish_jan_analysis(
		workflow,
		entry,
		scope,
		language.INCREMENTAL_WORK_BYTES,
	)
}

@(private)
syntax_workflow_publish_jan_analysis :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
	scope: language.Jan_Analysis_Scope,
	work_bytes: u64,
) {
	usage, usage_ok := language.jan_structural_analysis_usage(&entry.jan_analysis)
	entry.inspection.parse_snapshot = {
		buffer_id = scope.buffer_id,
		source_revision = scope.source_revision,
		language = scope.language,
		provider = scope.provider,
		selection_generation = scope.selection_generation,
		parser_generation = scope.parser_generation,
		tree_generation = language.Tree_Generation(scope.analysis_generation),
		query_generation = 1,
		status = .Current,
	}
	if usage_ok {
		entry.inspection.usage = {
			retained_source_bytes = usage.source_bytes,
			retained_tree_bytes = usage.retained_bytes,
			temporary_bytes = usage.temporary_bytes,
			captures = usage.nodes,
			work_bytes = usage.work_bytes,
		}
		entry.inspection.parse_snapshot.usage = entry.inspection.usage
	}
	entry.inspection.confirmed_revision = scope.source_revision
	entry.inspection.analysis_status = .Current
	entry.inspection.pending = {}
	entry.inspection.latest_failure = {}
	entry.inspection.parser_lifecycle = .Ready
	entry.refresh_attempted = false
	_ = workflow
	_ = work_bytes
}

@(private)
syntax_workflow_jan_scope :: proc(
	workflow: ^Syntax_Workflow_State,
	entry: ^Syntax_Analysis_Entry,
	revision: editor.Revision,
	analysis_generation: language.Jan_Analysis_Generation,
) -> language.Jan_Analysis_Scope {
	return {
		buffer_id = entry.inspection.buffer_id,
		document_id = entry.inspection.document_id,
		has_document = entry.inspection.has_document,
		source_revision = revision,
		language = entry.inspection.association.language,
		provider = entry.inspection.selection.active,
		selection_generation = entry.inspection.selection_generation,
		parser_generation = entry.parser_generation,
		grammar_generation = 1,
		configuration = workflow.jan_configuration.identity,
		baseline = language.jan_factory_baseline(),
		analysis_generation = analysis_generation,
	}
}

@(private)
syntax_workflow_copy_snapshot :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	allocator: runtime.Allocator,
) -> (source: []u8, ok: bool) {
	stats, inspected, _ := editor.buffer_snapshot_stats(snapshot)
	if !inspected || stats.text_bytes > u64(max(int)) || allocator.procedure == nil do return nil, false
	allocation_error: runtime.Allocator_Error
	source, allocation_error = make([]u8, int(stats.text_bytes), allocator)
	if allocation_error != nil do return nil, false
	copied, read_ok, _ := editor.buffer_snapshot_read(snapshot, 0, source)
	if !read_ok || copied != stats.text_bytes {
		delete(source, allocator)
		return nil, false
	}
	return source, true
}

@(private)
syntax_workflow_take_jan_analysis_generation :: proc(
	workflow: ^Syntax_Workflow_State,
) -> (generation: language.Jan_Analysis_Generation, ok: bool) {
	if !Syntax_Workflow_Is_Live(workflow) ||
	   workflow.next_jan_analysis_generation == language.Jan_Analysis_Generation(max(u64)) {
		if workflow != nil {
			workflow.latest_failure = language.Failure{operation = .Schedule, code = .Generation_Limit}
		}
		return 0, false
	}
	generation = workflow.next_jan_analysis_generation
	workflow.next_jan_analysis_generation += 1
	return generation, true
}

@(private)
syntax_workflow_jan_failure :: proc(
	entry: ^Syntax_Analysis_Entry,
	failure: language.Jan_Failure,
) -> language.Failure {
	code := language.Failure_Code.Invalid_Provider
	switch failure.code {
	case .None:
		code = .None
	case .Cancelled:
		code = .Cancelled
	case .Timeout:
		code = .Timeout
	case .Stale:
		code = .Stale_Selection
	case .Malformed, .Invalid_Range, .Invalid_Node, .Invalid_Index, .Invalid_Rewrite:
		code = .Syntax_Error_Region
	case .Limited:
		code = .Work_Limit
	case .Allocation_Failed:
		code = .Allocation
	case .Provider_Failed:
		code = .Parser_Initialization
	case .Unsupported, .Incomplete, .Invalid_Baseline, .Invalid_Configuration:
		code = .Invalid_Provider
	}
	return {
		operation = .Schedule,
		code = code,
		language_id = entry.inspection.association.language.id,
		provider = entry.inspection.selection.active,
		selection_generation = entry.inspection.selection_generation,
		source_revision = failure.scope.source_revision,
		limit = failure.limit,
		actual = failure.actual,
		diagnostic = failure.diagnostic,
	}
}
