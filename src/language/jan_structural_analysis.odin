// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"
import "core:time"
import "core:unicode/utf8"

import "../editor"
import "../transaction"

/* TREE_SITTER_JAN_ABI is the generated Jan grammar ABI. */
TREE_SITTER_JAN_ABI :: u32(15)

/* Jan_Structural_Owner retains one Jan parser and concrete tree. */
Jan_Structural_Owner :: struct {
	state:  rawptr,
	closed: bool,
}

/* Jan_Structural_Analysis owns copied pointer-free structural records. */
Jan_Structural_Analysis :: struct {
	state: rawptr,
}

@(private)
Jan_Structural_Owner_State :: struct {
	parser:           rawptr,
	tree:             rawptr,
	memory_owner:     u32,
	parser_generation: Parser_Generation,
	cancel_requested: bool,
	confirmed_scope:  Jan_Analysis_Scope,
	confirmed_usage:  Jan_Resource_Usage,
	confirmed_limits: Jan_Resource_Limits,
	confirmed_root:   Jan_Node_Record,
	confirmed_recovery: Jan_Recovery_Record,
	has_recovery:     bool,
	has_confirmed:    bool,
	latest_failure:   Jan_Failure,
	allocator:        runtime.Allocator,
}

@(private)
Jan_Structural_Analysis_State :: struct {
	scope:      Jan_Analysis_Scope,
	status:     Jan_Analysis_Status,
	nodes:      [dynamic]Jan_Node_Record,
	attributes: [dynamic]Jan_Attribute_Record,
	recoveries: [dynamic]Jan_Recovery_Record,
	indexes:    [dynamic]Jan_Index_Fact,
	usage:      Jan_Resource_Usage,
	allocator:  runtime.Allocator,
}

@(private)
Jan_Structural_Frame :: struct {
	node:             Tree_Sitter_Node,
	parent_id:        Jan_Node_ID,
	structural_depth: u16,
	inline_depth:     u16,
	parent_start:     u32,
	parent_end:       u32,
}

/* jan_structural_owner_init creates one bounded parser for the pinned Jan grammar. */
jan_structural_owner_init :: proc(
	owner: ^Jan_Structural_Owner,
	parser_generation: Parser_Generation,
	allocator := context.allocator,
) -> (ok: bool, failure: Jan_Failure) {
	if owner == nil || parser_generation == Parser_Generation(0) || allocator.procedure == nil {
		return false, jan_structural_failure({}, .Allocation_Failed)
	}
	owner^ = {}
	odra_tree_sitter_memory_install()
	memory_owner := odra_tree_sitter_memory_owner_open()
	if memory_owner == 0 do return false, jan_structural_failure({}, .Limited)
	odra_tree_sitter_memory_owner_begin(memory_owner)
	defer odra_tree_sitter_memory_owner_end()
	language := tree_sitter_factory_language(FACTORY_JAN_BUNDLE_IDENTITY)
	if language == nil || ts_language_abi_version(language) != TREE_SITTER_JAN_ABI {
		_ = odra_tree_sitter_memory_owner_close(memory_owner)
		return false, jan_structural_failure({}, .Provider_Failed)
	}
	state, state_error := new(Jan_Structural_Owner_State, allocator)
	if state_error != nil {
		_ = odra_tree_sitter_memory_owner_close(memory_owner)
		return false, jan_structural_failure({}, .Allocation_Failed)
	}
	state^ = Jan_Structural_Owner_State {
		memory_owner = memory_owner,
		parser_generation = parser_generation,
		allocator = allocator,
	}
	state.parser = ts_parser_new()
	if state.parser == nil || !ts_parser_set_language(state.parser, language) {
		jan_structural_owner_state_release(state)
		return false, jan_structural_failure({}, .Provider_Failed)
	}
	owner.state = state
	return true, {}
}

/* jan_structural_owner_request_cancel rejects the next analysis before parsing. */
jan_structural_owner_request_cancel :: proc(owner: ^Jan_Structural_Owner) -> bool {
	state := jan_structural_owner_state(owner)
	if state == nil do return false
	state.cancel_requested = true
	return true
}

/* jan_structural_owner_clear_cancel admits later structural analysis. */
jan_structural_owner_clear_cancel :: proc(owner: ^Jan_Structural_Owner) -> bool {
	state := jan_structural_owner_state(owner)
	if state == nil do return false
	state.cancel_requested = false
	return true
}

/* jan_structural_owner_publish_initial confirms the first complete Jan generation. */
jan_structural_owner_publish_initial :: proc(
	owner: ^Jan_Structural_Owner,
	source: []u8,
	scope: Jan_Analysis_Scope,
	configuration: Jan_Configuration,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (analysis: Jan_Structural_Analysis, ok: bool, failure: Jan_Failure) {
	state := jan_structural_owner_state(owner)
	if state == nil || state.has_confirmed {
		failure = jan_structural_failure(scope, .Stale)
		failure.operation = .Publish
		jan_structural_owner_reject(state, failure)
		return {}, false, failure
	}
	analysis, ok, failure = jan_structural_owner_analyze_configured(
		owner,
		source,
		scope,
		configuration,
		limits,
		allocator,
	)
	if !ok {
		failure.operation = .Publish
		jan_structural_owner_reject(state, failure)
	}
	return
}

/* jan_structural_owner_refresh atomically replaces one confirmed generation. */
jan_structural_owner_refresh :: proc(
	owner: ^Jan_Structural_Owner,
	source: []u8,
	scope: Jan_Analysis_Scope,
	configuration: Jan_Configuration,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (analysis: Jan_Structural_Analysis, ok: bool, failure: Jan_Failure) {
	state := jan_structural_owner_state(owner)
	if state == nil || !state.has_confirmed ||
	   !jan_structural_refresh_scope_is_valid(state.confirmed_scope, scope) {
		failure = jan_structural_failure(scope, .Stale)
		failure.operation = .Publish
		jan_structural_owner_reject(state, failure)
		return {}, false, failure
	}
	analysis, ok, failure = jan_structural_owner_analyze_configured(
		owner,
		source,
		scope,
		configuration,
		limits,
		allocator,
	)
	if !ok {
		failure.operation = .Publish
		jan_structural_owner_reject(state, failure)
	}
	return
}

/* jan_structural_owner_analyze parses and copies one exact structural generation. */
jan_structural_owner_analyze :: proc(
	owner: ^Jan_Structural_Owner,
	source: []u8,
	scope: Jan_Analysis_Scope,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (analysis: Jan_Structural_Analysis, ok: bool, failure: Jan_Failure) {
	configuration := jan_factory_configuration(scope.configuration.generation)
	return jan_structural_owner_analyze_configured(
		owner,
		source,
		scope,
		configuration,
		limits,
		allocator,
	)
}

/* jan_structural_owner_analyze_configured applies one confirmed syntax generation. */
jan_structural_owner_analyze_configured :: proc(
	owner: ^Jan_Structural_Owner,
	source: []u8,
	scope: Jan_Analysis_Scope,
	configuration: Jan_Configuration,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (analysis: Jan_Structural_Analysis, ok: bool, failure: Jan_Failure) {
	owner_state := jan_structural_owner_state(owner)
	analysis, ok, failure = jan_structural_owner_analyze_configured_core(
		owner,
		source,
		scope,
		configuration,
		nil,
		0,
		limits,
		allocator,
	)
	if !ok do jan_structural_owner_reject(owner_state, failure)
	return
}

/* jan_structural_owner_analyze_incremental applies one exact committed splice batch. */
jan_structural_owner_analyze_incremental :: proc(
	owner: ^Jan_Structural_Owner,
	base_source, result_source: []u8,
	event: transaction.Commit_Event,
	scope: Jan_Analysis_Scope,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (analysis: Jan_Structural_Analysis, ok: bool, failure: Jan_Failure) {
	configuration := jan_factory_configuration(scope.configuration.generation)
	return jan_structural_owner_analyze_incremental_configured(
		owner,
		base_source,
		result_source,
		event,
		scope,
		configuration,
		limits,
		allocator,
	)
}

/* jan_structural_owner_analyze_incremental_configured validates and applies one candidate. */
jan_structural_owner_analyze_incremental_configured :: proc(
	owner: ^Jan_Structural_Owner,
	base_source, result_source: []u8,
	event: transaction.Commit_Event,
	scope: Jan_Analysis_Scope,
	configuration: Jan_Configuration,
	limits := DEFAULT_JAN_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (analysis: Jan_Structural_Analysis, ok: bool, failure: Jan_Failure) {
	owner_state := jan_structural_owner_state(owner)
	if owner_state == nil || !owner_state.has_confirmed || owner_state.tree == nil {
		return {}, false, jan_structural_failure(scope, .Incomplete)
	}
	if !jan_structural_incremental_scope_is_valid(owner_state.confirmed_scope, scope, event) {
		failure = jan_structural_failure(scope, .Stale)
		jan_structural_owner_reject(owner_state, failure)
		return {}, false, failure
	}
	if !jan_resource_limits_are_valid(limits) ||
	   len(event.splices) == 0 || u64(len(event.splices)) > u64(limits.incremental_edits) {
		failure = jan_structural_failure(scope, .Limited)
		failure.limit = u64(limits.incremental_edits)
		failure.actual = u64(len(event.splices))
		jan_structural_owner_reject(owner_state, failure)
		return {}, false, failure
	}
	work_bytes := u64(len(result_source))
	if work_bytes > limits.incremental_step_bytes {
		failure = jan_structural_failure(scope, .Limited)
		failure.limit = limits.incremental_step_bytes
		failure.actual = work_bytes
		jan_structural_owner_reject(owner_state, failure)
		return {}, false, failure
	}
	odra_tree_sitter_memory_owner_begin(owner_state.memory_owner)
	edited_tree := ts_tree_copy(owner_state.tree)
	odra_tree_sitter_memory_owner_end()
	if edited_tree == nil {
		failure = jan_structural_failure(scope, .Allocation_Failed)
		jan_structural_owner_reject(owner_state, failure)
		return {}, false, failure
	}
	defer ts_tree_delete(edited_tree)
	if !jan_structural_apply_normalized_edits(edited_tree, base_source, result_source, event.splices) {
		failure = jan_structural_failure(scope, .Invalid_Rewrite)
		jan_structural_owner_reject(owner_state, failure)
		return {}, false, failure
	}
	analysis, ok, failure = jan_structural_owner_analyze_configured_core(
		owner,
		result_source,
		scope,
		configuration,
		edited_tree,
		u32(len(event.splices)),
		limits,
		allocator,
	)
	if !ok {
		failure.operation = .Publish
		jan_structural_owner_reject(owner_state, failure)
	}
	return
}

@(private)
jan_structural_owner_analyze_configured_core :: proc(
	owner: ^Jan_Structural_Owner,
	source: []u8,
	scope: Jan_Analysis_Scope,
	configuration: Jan_Configuration,
	old_tree: rawptr,
	incremental_edits: u32,
	limits: Jan_Resource_Limits,
	allocator: runtime.Allocator,
) -> (analysis: Jan_Structural_Analysis, ok: bool, failure: Jan_Failure) {
	clock_start := time.tick_now()
	owner_state := jan_structural_owner_state(owner)
	if owner_state == nil || !jan_analysis_scope_is_valid(scope) ||
	   scope.parser_generation != owner_state.parser_generation ||
	   !jan_configuration_is_valid(configuration) ||
	   configuration.identity != scope.configuration ||
	   !jan_resource_limits_are_valid(limits) {
		return {}, false, jan_structural_failure(scope, .Invalid_Configuration)
	}
	if owner_state.cancel_requested {
		failure = jan_structural_failure(scope, .Cancelled)
		jan_structural_owner_reject(owner_state, failure)
		return {}, false, failure
	}
	if !utf8.valid_string(string(source)) {
		return {}, false, jan_structural_failure(scope, .Malformed)
	}
	if u64(len(source)) > limits.source_bytes || u64(len(source)) > u64(max(u32)) {
		failure = jan_structural_failure(scope, .Limited)
		failure.limit = limits.source_bytes
		failure.actual = u64(len(source))
		return {}, false, failure
	}
	step_limit := limits.initial_step_bytes
	if incremental_edits > 0 do step_limit = limits.incremental_step_bytes
	if u64(len(source)) > step_limit {
		failure = jan_structural_failure(scope, .Limited)
		failure.limit = step_limit
		failure.actual = u64(len(source))
		return {}, false, failure
	}
	if allocator.procedure == nil do return {}, false, jan_structural_failure(scope, .Allocation_Failed)

	odra_tree_sitter_memory_owner_begin(owner_state.memory_owner)
	candidate := ts_parser_parse_string(owner_state.parser, old_tree, raw_data(source), u32(len(source)))
	odra_tree_sitter_memory_owner_end()
	if candidate == nil do return {}, false, jan_structural_failure(scope, .Provider_Failed)
	root := ts_tree_root_node(candidate)
	if ts_node_is_null(root) || ts_node_start_byte(root) != 0 ||
	   ts_node_end_byte(root) != u32(len(source)) {
		ts_tree_delete(candidate)
		return {}, false, jan_structural_failure(scope, .Invalid_Range)
	}

	analysis_state, initialized := jan_structural_analysis_state_init(scope, allocator)
	if !initialized {
		ts_tree_delete(candidate)
		return {}, false, jan_structural_failure(scope, .Allocation_Failed)
	}
	stack, stack_error := make([dynamic]Jan_Structural_Frame, 0, 128, allocator)
	if stack_error != nil {
		jan_structural_analysis_state_close(analysis_state)
		ts_tree_delete(candidate)
		return {}, false, jan_structural_failure(scope, .Allocation_Failed)
	}
	defer delete(stack)
	_, append_error := append(&stack, Jan_Structural_Frame {
		node = root,
		parent_start = 0,
		parent_end = u32(len(source)),
	})
	if append_error != nil {
		jan_structural_analysis_state_close(analysis_state)
		ts_tree_delete(candidate)
		return {}, false, jan_structural_failure(scope, .Allocation_Failed)
	}

	for len(stack) > 0 {
		if owner_state.cancel_requested {
			jan_structural_analysis_state_close(analysis_state)
			ts_tree_delete(candidate)
			return {}, false, jan_structural_failure(scope, .Cancelled)
		}
		frame := pop(&stack)
		start := ts_node_start_byte(frame.node)
		end := ts_node_end_byte(frame.node)
		if start < frame.parent_start || end > frame.parent_end || start > end ||
		   !jan_source_offset_is_utf8_boundary(source, start) ||
		   !jan_source_offset_is_utf8_boundary(source, end) {
			jan_structural_analysis_state_close(analysis_state)
			ts_tree_delete(candidate)
			return {}, false, jan_structural_failure(scope, .Invalid_Range)
		}
		kind, label, layer, admitted := jan_structural_node_mapping(frame.node)
		parent_id := frame.parent_id
		child_structural_depth := frame.structural_depth
		child_inline_depth := frame.inline_depth
		if admitted {
			if len(analysis_state.nodes) >= int(limits.nodes) ||
			   frame.structural_depth > limits.structural_depth ||
			   frame.inline_depth > limits.inline_depth {
				jan_structural_analysis_state_close(analysis_state)
				ts_tree_delete(candidate)
				failure = jan_structural_failure(scope, .Limited)
				failure.limit = u64(limits.nodes)
				failure.actual = u64(len(analysis_state.nodes) + 1)
				return {}, false, failure
			}
			node := Jan_Node_Record {
				id = Jan_Node_ID(len(analysis_state.nodes) + 1),
				parent_id = frame.parent_id,
				layer = layer,
				kind = kind,
				structural_depth = frame.structural_depth,
				inline_depth = frame.inline_depth,
				range = {scope = scope, start = editor.Byte_Offset(start), end = editor.Byte_Offset(end)},
			}
			node.kind_text.length = u16(copy(node.kind_text.bytes[:], label))
			if _, node_error := append(&analysis_state.nodes, node); node_error != nil {
				jan_structural_analysis_state_close(analysis_state)
				ts_tree_delete(candidate)
				return {}, false, jan_structural_failure(scope, .Allocation_Failed)
			}
			parent_id = node.id
			if layer == .Structural do child_structural_depth = frame.structural_depth + 1
			if layer == .Inline do child_inline_depth = frame.inline_depth + 1
			analysis_state.usage.structural_depth = max(
				analysis_state.usage.structural_depth,
				frame.structural_depth,
			)
			analysis_state.usage.inline_depth = max(
				analysis_state.usage.inline_depth,
				frame.inline_depth,
			)
			if layer == .Recovery {
				recovery := Jan_Recovery_Record {
					node_id = node.id,
					code = .Malformed,
					range = node.range,
				}
				if _, recovery_error := append(&analysis_state.recoveries, recovery); recovery_error != nil {
					jan_structural_analysis_state_close(analysis_state)
					ts_tree_delete(candidate)
					return {}, false, jan_structural_failure(scope, .Allocation_Failed)
				}
			}
			if jan_structural_node_has_missing_child(frame.node) ||
			   (layer == .Structural &&
			    !jan_structural_node_has_required_close(kind, source, start, end)) {
				recovery := Jan_Recovery_Record {
					node_id = node.id,
					code = .Unterminated,
					range = node.range,
				}
				if _, recovery_error := append(&analysis_state.recoveries, recovery); recovery_error != nil {
					jan_structural_analysis_state_close(analysis_state)
					ts_tree_delete(candidate)
					return {}, false, jan_structural_failure(scope, .Allocation_Failed)
				}
			}
			if !jan_structural_admit_attributes(
				analysis_state,
				node.id,
				kind,
				source,
				start,
				end,
				configuration,
				limits,
			) {
				jan_structural_analysis_state_close(analysis_state)
				ts_tree_delete(candidate)
				return {}, false, jan_structural_failure(scope, .Allocation_Failed)
			}
		}

		child_count := ts_node_named_child_count(frame.node)
		for reverse_index in 0 ..< child_count {
			child_index := child_count - reverse_index - 1
			child := ts_node_named_child(frame.node, child_index)
			if ts_node_is_null(child) do continue
			_, child_error := append(&stack, Jan_Structural_Frame {
				node = child,
				parent_id = parent_id,
				structural_depth = child_structural_depth,
				inline_depth = child_inline_depth,
				parent_start = start,
				parent_end = end,
			})
			if child_error != nil {
				jan_structural_analysis_state_close(analysis_state)
				ts_tree_delete(candidate)
				return {}, false, jan_structural_failure(scope, .Allocation_Failed)
			}
		}
	}

	if !jan_structural_project_heading_forest(analysis_state, source, limits) {
		jan_structural_analysis_state_close(analysis_state)
		ts_tree_delete(candidate)
		return {}, false, jan_structural_failure(scope, .Invalid_Node)
	}
	if !jan_classify_configured_syntax(analysis_state, source, configuration, limits) {
		jan_structural_analysis_state_close(analysis_state)
		ts_tree_delete(candidate)
		return {}, false, jan_structural_failure(scope, .Allocation_Failed)
	}
	index_failure := jan_build_document_indexes(analysis_state, u64(len(source)), limits)
	if index_failure != .None {
		jan_structural_analysis_state_close(analysis_state)
		ts_tree_delete(candidate)
		return {}, false, jan_structural_failure(scope, index_failure)
	}
	analysis_state.status = .Current
	analysis_state.usage.source_bytes = u64(len(source))
	analysis_state.usage.nodes = u32(len(analysis_state.nodes))
	analysis_state.usage.attributes = u64(len(analysis_state.attributes))
	analysis_state.usage.diagnostics = u32(len(analysis_state.recoveries))
	analysis_state.usage.index_facts = u32(len(analysis_state.indexes))
	analysis_state.usage.incremental_edits = incremental_edits
	analysis_state.usage.work_bytes = u64(len(source))
	analysis_state.usage.temporary_bytes = u64(cap(stack)) * u64(size_of(Jan_Structural_Frame))
	analysis_state.usage.elapsed_nanoseconds = u64(max(
		i64(1),
		time.duration_nanoseconds(time.tick_since(clock_start)),
	))
	if analysis_state.usage.elapsed_nanoseconds > limits.candidate_nanoseconds {
		actual := analysis_state.usage.elapsed_nanoseconds
		jan_structural_analysis_state_close(analysis_state)
		ts_tree_delete(candidate)
		failure = jan_structural_failure(scope, .Timeout)
		failure.limit = limits.candidate_nanoseconds
		failure.actual = actual
		return {}, false, failure
	}
	analysis_state.usage.retained_bytes = jan_structural_retained_bytes(analysis_state) +
		odra_tree_sitter_memory_owner_live_bytes(owner_state.memory_owner)
	if analysis_state.usage.retained_bytes > limits.retained_bytes {
		actual := analysis_state.usage.retained_bytes
		jan_structural_analysis_state_close(analysis_state)
		ts_tree_delete(candidate)
		failure = jan_structural_failure(scope, .Limited)
		failure.limit = limits.retained_bytes
		failure.actual = actual
		return {}, false, failure
	}
	if owner_state.tree != nil do ts_tree_delete(owner_state.tree)
	owner_state.tree = candidate
	owner_state.confirmed_scope = scope
	owner_state.confirmed_usage = analysis_state.usage
	owner_state.confirmed_limits = limits
	owner_state.confirmed_root = {}
	if len(analysis_state.nodes) > 0 do owner_state.confirmed_root = analysis_state.nodes[0]
	owner_state.confirmed_recovery = {}
	owner_state.has_recovery = len(analysis_state.recoveries) > 0
	if owner_state.has_recovery do owner_state.confirmed_recovery = analysis_state.recoveries[0]
	owner_state.has_confirmed = true
	owner_state.latest_failure = {}
	return Jan_Structural_Analysis{state = analysis_state}, true, {}
}

/* jan_structural_analysis_nodes returns copied nodes owned by one analysis. */
jan_structural_analysis_nodes :: proc(analysis: ^Jan_Structural_Analysis) -> []Jan_Node_Record {
	state := jan_structural_analysis_state(analysis)
	if state == nil do return nil
	return state.nodes[:]
}

/* jan_structural_analysis_attributes returns copied lexical fields. */
jan_structural_analysis_attributes :: proc(analysis: ^Jan_Structural_Analysis) -> []Jan_Attribute_Record {
	state := jan_structural_analysis_state(analysis)
	if state == nil do return nil
	return state.attributes[:]
}

/* jan_structural_analysis_recoveries returns copied malformed-source records. */
jan_structural_analysis_recoveries :: proc(analysis: ^Jan_Structural_Analysis) -> []Jan_Recovery_Record {
	state := jan_structural_analysis_state(analysis)
	if state == nil do return nil
	return state.recoveries[:]
}

/* jan_structural_analysis_indexes returns revision-bound semantic source facts. */
jan_structural_analysis_indexes :: proc(analysis: ^Jan_Structural_Analysis) -> []Jan_Index_Fact {
	state := jan_structural_analysis_state(analysis)
	if state == nil do return nil
	return state.indexes[:]
}

/* jan_structural_analysis_usage returns bounded retained-resource accounting. */
jan_structural_analysis_usage :: proc(analysis: ^Jan_Structural_Analysis) -> (Jan_Resource_Usage, bool) {
	state := jan_structural_analysis_state(analysis)
	if state == nil do return {}, false
	return state.usage, true
}

/* jan_structural_owner_inspect returns copied last-confirmed state without parsing. */
jan_structural_owner_inspect :: proc(
	owner: ^Jan_Structural_Owner,
	current_scope: Jan_Analysis_Scope,
) -> (inspection: Jan_Inspection, ok: bool, failure: Jan_Failure) {
	state := jan_structural_owner_state(owner)
	if state == nil || !state.has_confirmed {
		failure = jan_structural_failure(current_scope, .Incomplete)
		failure.operation = .Inspect
		return {}, false, failure
	}
	status := Jan_Analysis_Status.Incomplete
	if current_scope == state.confirmed_scope do status = .Current
	inspection = Jan_Inspection {
		scope = state.confirmed_scope,
		status = status,
		node = state.confirmed_root,
		has_node = state.confirmed_root.id != Jan_Node_ID(0),
		recovery = state.confirmed_recovery,
		has_recovery = state.has_recovery,
		usage = state.confirmed_usage,
		limits = state.confirmed_limits,
		latest_failure = state.latest_failure,
	}
	return inspection, true, {}
}

/* jan_structural_analysis_close releases copied records exactly once. */
jan_structural_analysis_close :: proc(analysis: ^Jan_Structural_Analysis) {
	state := jan_structural_analysis_state(analysis)
	if state == nil do return
	jan_structural_analysis_state_close(state)
	analysis^ = {}
}

/* jan_structural_owner_close releases every foreign parser allocation. */
jan_structural_owner_close :: proc(owner: ^Jan_Structural_Owner) -> bool {
	state := jan_structural_owner_state(owner)
	if state == nil do return false
	jan_structural_owner_state_release(state)
	owner^ = Jan_Structural_Owner{closed = true}
	return true
}

@(private)
jan_structural_refresh_scope_is_valid :: proc(
	confirmed, candidate: Jan_Analysis_Scope,
) -> bool {
	return jan_analysis_scope_is_valid(candidate) &&
		candidate.buffer_id == confirmed.buffer_id &&
		candidate.document_id == confirmed.document_id &&
		candidate.has_document == confirmed.has_document &&
		candidate.source_revision >= confirmed.source_revision &&
		candidate.analysis_generation > confirmed.analysis_generation
}

@(private)
jan_structural_incremental_scope_is_valid :: proc(
	confirmed, candidate: Jan_Analysis_Scope,
	event: transaction.Commit_Event,
) -> bool {
	if !jan_analysis_scope_is_valid(candidate) ||
	   event.buffer_id != confirmed.buffer_id ||
	   event.base_revision != confirmed.source_revision ||
	   event.result_revision != candidate.source_revision ||
	   event.result_revision <= event.base_revision ||
	   candidate.buffer_id != confirmed.buffer_id ||
	   candidate.document_id != confirmed.document_id ||
	   candidate.has_document != confirmed.has_document ||
	   candidate.language != confirmed.language ||
	   candidate.provider != confirmed.provider ||
	   candidate.selection_generation != confirmed.selection_generation ||
	   candidate.parser_generation != confirmed.parser_generation ||
	   candidate.grammar_generation != confirmed.grammar_generation ||
	   candidate.configuration != confirmed.configuration ||
	   candidate.baseline != confirmed.baseline ||
	   candidate.analysis_generation <= confirmed.analysis_generation {
		return false
	}
	return true
}

@(private)
jan_structural_owner_reject :: proc(state: ^Jan_Structural_Owner_State, failure: Jan_Failure) {
	if state != nil do state.latest_failure = failure
}

@(private)
jan_structural_apply_normalized_edits :: proc(
	tree: rawptr,
	base_source, result_source: []u8,
	splices: []transaction.Normalized_Splice,
) -> bool {
	if tree == nil || len(splices) == 0 do return false
	base_cursor: u64
	current_byte_cursor: u64
	current_point: Tree_Sitter_Point
	for splice in splices {
		start := u64(splice.start)
		end := u64(splice.end)
		if start < base_cursor || start > end || end > u64(len(base_source)) ||
		   u64(len(splice.removed_text)) != end - start ||
		   string(base_source[int(start):int(end)]) != splice.removed_text {
			return false
		}
		gap_point := jan_structural_point_advance(
			current_point,
			base_source[int(base_cursor):int(start)],
		)
		current_byte_cursor += start - base_cursor
		start_point := gap_point
		old_end_point := jan_structural_point_advance(
			start_point,
			base_source[int(start):int(end)],
		)
		replacement_end := current_byte_cursor + u64(len(splice.replacement_text))
		if replacement_end > u64(len(result_source)) ||
		   string(result_source[int(current_byte_cursor):int(replacement_end)]) != splice.replacement_text ||
		   current_byte_cursor > u64(max(u32)) || replacement_end > u64(max(u32)) {
			return false
		}
		old_end_byte := current_byte_cursor + end - start
		if old_end_byte > u64(max(u32)) do return false
		edit := Tree_Sitter_Input_Edit {
			start_byte = u32(current_byte_cursor),
			old_end_byte = u32(old_end_byte),
			new_end_byte = u32(replacement_end),
			start_point = start_point,
			old_end_point = old_end_point,
			new_end_point = jan_structural_point_advance(
				start_point,
				transmute([]u8)splice.replacement_text,
			),
		}
		ts_tree_edit(tree, &edit)
		base_cursor = end
		current_byte_cursor = replacement_end
		current_point = edit.new_end_point
	}
	return current_byte_cursor + u64(len(base_source)) - base_cursor == u64(len(result_source)) &&
		string(result_source[int(current_byte_cursor):]) == string(base_source[int(base_cursor):])
}

@(private)
jan_structural_point_advance :: proc(point: Tree_Sitter_Point, contents: []u8) -> Tree_Sitter_Point {
	result := point
	for value in contents {
		if value == '\n' {
			result.row += 1
			result.column = 0
		} else {
			result.column += 1
		}
	}
	return result
}

@(private)
jan_structural_owner_state :: proc(owner: ^Jan_Structural_Owner) -> ^Jan_Structural_Owner_State {
	if owner == nil || owner.state == nil || owner.closed do return nil
	return cast(^Jan_Structural_Owner_State)owner.state
}

@(private)
jan_structural_analysis_state :: proc(analysis: ^Jan_Structural_Analysis) -> ^Jan_Structural_Analysis_State {
	if analysis == nil || analysis.state == nil do return nil
	return cast(^Jan_Structural_Analysis_State)analysis.state
}

@(private)
jan_structural_owner_state_release :: proc(state: ^Jan_Structural_Owner_State) {
	if state == nil do return
	odra_tree_sitter_memory_owner_begin(state.memory_owner)
	if state.tree != nil do ts_tree_delete(state.tree)
	if state.parser != nil do ts_parser_delete(state.parser)
	odra_tree_sitter_memory_owner_end()
	closed := odra_tree_sitter_memory_owner_close(state.memory_owner)
	assert(closed, "Jan Tree-sitter allocations remain after owner cleanup")
	allocator := state.allocator
	state^ = {}
	free(state, allocator)
}

@(private)
jan_structural_analysis_state_init :: proc(
	scope: Jan_Analysis_Scope,
	allocator: runtime.Allocator,
) -> (^Jan_Structural_Analysis_State, bool) {
	state, state_error := new(Jan_Structural_Analysis_State, allocator)
	if state_error != nil do return nil, false
	state^ = Jan_Structural_Analysis_State{scope = scope, status = .Pending, allocator = allocator}
	state.nodes, state_error = make([dynamic]Jan_Node_Record, 0, 256, allocator)
	if state_error == nil do state.attributes, state_error = make([dynamic]Jan_Attribute_Record, 0, 128, allocator)
	if state_error == nil do state.recoveries, state_error = make([dynamic]Jan_Recovery_Record, 0, 16, allocator)
	if state_error == nil do state.indexes, state_error = make([dynamic]Jan_Index_Fact, 0, 128, allocator)
	if state_error != nil {
		jan_structural_analysis_state_close(state)
		return nil, false
	}
	return state, true
}

@(private)
jan_structural_analysis_state_close :: proc(state: ^Jan_Structural_Analysis_State) {
	if state == nil do return
	if state.nodes != nil do delete(state.nodes)
	if state.attributes != nil do delete(state.attributes)
	if state.recoveries != nil do delete(state.recoveries)
	if state.indexes != nil do delete(state.indexes)
	allocator := state.allocator
	state^ = {}
	free(state, allocator)
}

@(private)
jan_structural_node_mapping :: proc(
	node: Tree_Sitter_Node,
) -> (kind: Jan_Node_Kind, label: string, layer: Jan_Node_Layer, admitted: bool) {
	if ts_node_is_error(node) || ts_node_is_missing(node) do return .Recovery, "recovery", .Recovery, true
	pointer := ts_node_type(node)
	if pointer == nil do return
	switch string(pointer) {
	case "document": return .Document_Root, "document-root", .Structural, true
	case "zeroth_section": return .Zeroth_Section, "zeroth-section", .Structural, true
	case "heading": return .Heading, "heading", .Structural, true
	case "section": return .Section, "section", .Structural, true
	case "center_block": return .Center_Block, "center-block", .Structural, true
	case "quote_block": return .Quote_Block, "quote-block", .Structural, true
	case "special_block": return .Special_Block, "special-block", .Structural, true
	case "drawer": return .Drawer, "drawer", .Structural, true
	case "property_drawer": return .Property_Drawer, "property-drawer", .Structural, true
	case "dynamic_block": return .Dynamic_Block, "dynamic-block", .Structural, true
	case "footnote_definition": return .Footnote_Definition, "footnote-definition", .Structural, true
	case "inline_task": return .Inline_Task, "inline-task", .Structural, true
	case "list_item": return .List_Item, "list-item", .Structural, true
	case "plain_list": return .Plain_List, "plain-list", .Structural, true
	case "pipe_table": return .Pipe_Table, "pipe-table", .Structural, true
	case "table_provider_form": return .Table_Provider_Form, "table-provider-form", .Structural, true
	case "source_block": return .Source_Block, "source-block", .Structural, true
	case "example_block": return .Example_Block, "example-block", .Structural, true
	case "export_block": return .Export_Block, "export-block", .Structural, true
	case "comment_block": return .Comment_Block, "comment-block", .Structural, true
	case "lesser_block": return .Lesser_Block, "lesser-block", .Structural, true
	case "clock": return .Clock, "clock", .Structural, true
	case "diary_expression": return .Diary_Expression, "diary-expression", .Structural, true
	case "planning_line": return .Planning_Line, "planning-line", .Structural, true
	case "line_comment": return .Line_Comment, "line-comment", .Structural, true
	case "fixed_width_area": return .Fixed_Width_Area, "fixed-width-area", .Structural, true
	case "horizontal_rule": return .Horizontal_Rule, "horizontal-rule", .Structural, true
	case "keyword": return .Keyword, "keyword", .Structural, true
	case "affiliated_keyword": return .Affiliated_Keyword, "affiliated-keyword", .Structural, true
	case "latex_environment": return .Latex_Environment, "latex-environment", .Structural, true
	case "node_property": return .Node_Property, "node-property", .Structural, true
	case "paragraph": return .Paragraph, "paragraph", .Structural, true
	case "table_row": return .Table_Row, "table-row", .Structural, true
	case "table_separator_row": return .Table_Separator_Row, "table-separator-row", .Structural, true
	case "entity": return .Entity, "entity", .Inline, true
	case "special_symbol": return .Special_Symbol, "special-symbol", .Inline, true
	case "latex_fragment": return .Latex_Fragment, "latex-fragment", .Inline, true
	case "export_snippet": return .Export_Snippet, "export-snippet", .Inline, true
	case "named_footnote_reference": return .Named_Footnote_Reference, "named-footnote-reference", .Inline, true
	case "inline_footnote_reference": return .Inline_Footnote_Reference, "inline-footnote-reference", .Inline, true
	case "anonymous_footnote_reference": return .Anonymous_Footnote_Reference, "anonymous-footnote-reference", .Inline, true
	case "citation": return .Citation, "citation", .Inline, true
	case "citation_reference": return .Citation_Reference, "citation-reference", .Inline, true
	case "inline_call": return .Inline_Call, "inline-call", .Inline, true
	case "inline_source": return .Inline_Source, "inline-source", .Inline, true
	case "explicit_line_break": return .Explicit_Line_Break, "explicit-line-break", .Inline, true
	case "plain_link": return .Plain_Link, "plain-link", .Inline, true
	case "angle_link": return .Angle_Link, "angle-link", .Inline, true
	case "regular_link": return .Regular_Link, "regular-link", .Inline, true
	case "macro": return .Macro, "macro", .Inline, true
	case "target": return .Target, "target", .Inline, true
	case "radio_target": return .Radio_Target, "radio-target", .Inline, true
	case "percentage_cookie": return .Percentage_Cookie, "percentage-cookie", .Inline, true
	case "fraction_cookie": return .Fraction_Cookie, "fraction-cookie", .Inline, true
	case "subscript": return .Subscript, "subscript", .Inline, true
	case "superscript": return .Superscript, "superscript", .Inline, true
	case "table_cell": return .Table_Cell, "table-cell", .Inline, true
	case "active_timestamp": return .Active_Timestamp, "active-timestamp", .Inline, true
	case "inactive_timestamp": return .Inactive_Timestamp, "inactive-timestamp", .Inline, true
	case "diary_timestamp": return .Diary_Timestamp, "diary-timestamp", .Inline, true
	case "point_timestamp": return .Point_Timestamp, "point-timestamp", .Inline, true
	case "timestamp_range": return .Timestamp_Range, "timestamp-range", .Inline, true
	case "repeating_timestamp": return .Repeating_Timestamp, "repeating-timestamp", .Inline, true
	case "delayed_timestamp": return .Delayed_Timestamp, "delayed-timestamp", .Inline, true
	case "bold_markup": return .Bold_Markup, "bold-markup", .Inline, true
	case "italic_markup": return .Italic_Markup, "italic-markup", .Inline, true
	case "underline_markup": return .Underline_Markup, "underline-markup", .Inline, true
	case "verbatim_markup": return .Verbatim_Markup, "verbatim-markup", .Inline, true
	case "code_markup": return .Code_Markup, "code-markup", .Inline, true
	case "strike_through_markup": return .Strike_Through_Markup, "strike-through-markup", .Inline, true
	case "plain_text": return .Plain_Text, "plain-text", .Inline, true
	case "blank_line", "line_ending": return .Preserved_Whitespace, "preserved-whitespace", .Preserved, true
	case "recovery": return .Recovery, "recovery", .Recovery, true
	}
	return
}

@(private)
jan_structural_node_has_missing_child :: proc(node: Tree_Sitter_Node) -> bool {
	child_count := ts_node_child_count(node)
	for index in 0 ..< child_count {
		if ts_node_is_missing(ts_node_child(node, index)) do return true
	}
	return false
}

@(private)
jan_structural_node_has_required_close :: proc(
	kind: Jan_Node_Kind,
	source: []u8,
	start, end: u32,
) -> bool {
	needle := ""
	#partial switch kind {
	case .Center_Block: needle = "#+end_center"
	case .Quote_Block: needle = "#+end_quote"
	case .Special_Block: needle = "#+end_"
	case .Drawer, .Property_Drawer: needle = ":end:"
	case .Dynamic_Block: needle = "#+end:"
	case .Table_Provider_Form: needle = "#+end_table"
	case .Source_Block: needle = "#+end_src"
	case .Example_Block: needle = "#+end_example"
	case .Export_Block: needle = "#+end_export"
	case .Comment_Block: needle = "#+end_comment"
	case .Lesser_Block: needle = "#+end_"
	case .Latex_Environment: needle = "\\end{"
	}
	if len(needle) == 0 do return true
	return jan_ascii_contains_folded(source[start:end], needle)
}

@(private)
jan_ascii_contains_folded :: proc(source: []u8, needle: string) -> bool {
	if len(needle) == 0 do return true
	if len(source) < len(needle) do return false
	for start in 0 ..= len(source) - len(needle) {
		matches := true
		for index in 0 ..< len(needle) {
			left := source[start + index]
			right := needle[index]
			if left >= 'A' && left <= 'Z' do left += 'a' - 'A'
			if right >= 'A' && right <= 'Z' do right += 'a' - 'A'
			if left != right {
				matches = false
				break
			}
		}
		if matches do return true
	}
	return false
}

@(private)
jan_structural_admit_attributes :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	kind: Jan_Node_Kind,
	source: []u8,
	start, end: u32,
	configuration: Jan_Configuration,
	limits: Jan_Resource_Limits,
) -> bool {
	line_end := jan_structural_line_end(source, start, end)
	#partial switch kind {
	case .Heading:
		level_end := start
		for level_end < line_end && source[level_end] == '*' do level_end += 1
		if level_end == start do return true
		level_value: [20]u8
		level_length := jan_encode_u32(level_value[:], level_end - start)
		if !jan_structural_append_attribute(state, node_id, .Integer, "level", start, level_end, level_value[:level_length], limits) do return false
		if !jan_structural_append_attribute(state, node_id, .Raw, "marker", start, level_end, source[start:level_end], limits) do return false
		return jan_classify_heading_attributes(state, node_id, source, level_end, line_end, configuration, limits)
	case .Keyword, .Affiliated_Keyword:
		key_start := start
		for key_start < line_end && (source[key_start] == ' ' || source[key_start] == '\t') do key_start += 1
		if key_start + 2 > line_end do return true
		key_start += 2
		key_end := key_start
		for key_end < line_end && source[key_end] != ':' do key_end += 1
		if key_end >= line_end do return true
		if !jan_structural_append_attribute(state, node_id, .Raw, "key", key_start, key_end, source[key_start:key_end], limits) do return false
		value_start := key_end + 1
		for value_start < line_end && (source[value_start] == ' ' || source[value_start] == '\t') do value_start += 1
		if !jan_structural_append_attribute(state, node_id, .Text, "value", value_start, line_end, source[value_start:line_end], limits) do return false
		return jan_classify_keyword_attributes(state, node_id, source, key_start, key_end, configuration, limits)
	case .Node_Property:
		key_start := start
		for key_start < line_end && (source[key_start] == ' ' || source[key_start] == '\t') do key_start += 1
		if key_start >= line_end || source[key_start] != ':' do return true
		key_start += 1
		key_end := key_start
		for key_end < line_end && source[key_end] != ':' do key_end += 1
		if key_end >= line_end do return true
		if !jan_structural_append_attribute(state, node_id, .Raw, "key", key_start, key_end, source[key_start:key_end], limits) do return false
		value_start := key_end + 1
		for value_start < line_end && (source[value_start] == ' ' || source[value_start] == '\t') do value_start += 1
		if !jan_structural_append_attribute(state, node_id, .Text, "value", value_start, line_end, source[value_start:line_end], limits) do return false
		return jan_classify_property_attributes(state, node_id, start, line_end, configuration, limits)
	case .Entity:
		return jan_classify_entity_attributes(state, node_id, source, start, end, configuration, limits)
	case .Plain_Link, .Angle_Link, .Regular_Link:
		return jan_classify_link_attributes(state, node_id, source, start, end, configuration, limits)
	case .Bold_Markup, .Italic_Markup, .Underline_Markup, .Verbatim_Markup,
	     .Code_Markup, .Strike_Through_Markup:
		return jan_classify_markup_attributes(state, node_id, source, start, end, configuration, limits)
	case .Center_Block, .Quote_Block, .Special_Block, .Dynamic_Block, .Table_Provider_Form,
	     .Source_Block, .Example_Block, .Export_Block, .Comment_Block, .Lesser_Block:
		return jan_classify_block_attributes(state, node_id, source, start, end, configuration, limits)
	}
	return true
}

@(private)
jan_structural_append_attribute :: proc(
	state: ^Jan_Structural_Analysis_State,
	node_id: Jan_Node_ID,
	kind: Jan_Attribute_Kind,
	name: string,
	start, end: u32,
	value: []u8,
	limits: Jan_Resource_Limits,
) -> bool {
	if state == nil || node_id == Jan_Node_ID(0) || start > end ||
	   u64(len(value)) > MAX_JAN_ATTRIBUTE_VALUE_BYTES {
		return false
	}
	node_index := int(node_id) - 1
	if node_index < 0 || node_index >= len(state.nodes) ||
	   state.nodes[node_index].attribute_count >= limits.attributes_per_node {
		return false
	}
	attribute := Jan_Attribute_Record {
		node_id = node_id,
		kind = kind,
		range = {scope = state.scope, start = editor.Byte_Offset(start), end = editor.Byte_Offset(end)},
	}
	attribute.name.length = u16(copy(attribute.name.bytes[:], name))
	attribute.value.length = u16(copy(attribute.value.bytes[:], value))
	if _, append_error := append(&state.attributes, attribute); append_error != nil do return false
	state.nodes[node_index].attribute_count += 1
	state.usage.maximum_attributes = max(state.usage.maximum_attributes, state.nodes[node_index].attribute_count)
	return true
}

@(private)
jan_structural_project_heading_forest :: proc(
	state: ^Jan_Structural_Analysis_State,
	source: []u8,
	limits: Jan_Resource_Limits,
) -> bool {
	if state == nil || len(state.nodes) == 0 || state.nodes[0].kind != .Document_Root do return false
	open: [MAX_JAN_STRUCTURAL_DEPTH + 1]Jan_Node_ID
	root_id := state.nodes[0].id
	for index in 0 ..< len(state.nodes) {
		node := &state.nodes[index]
		if node.kind != .Heading do continue
		start := u32(node.range.start)
		level: u32
		for start + level < u32(len(source)) && source[start + level] == '*' do level += 1
		if level == 0 || level > u32(limits.structural_depth) do return false
		for closing in int(level) ..< len(open) {
			if open[closing] != Jan_Node_ID(0) {
				state.nodes[int(open[closing]) - 1].range.end = node.range.start
				open[closing] = 0
			}
		}
		parent_id := root_id
		if level > 1 {
			for ancestor := int(level) - 1; ancestor > 0; ancestor -= 1 {
				if open[ancestor] != Jan_Node_ID(0) {
					parent_id = open[ancestor]
					break
				}
			}
		}
		node.parent_id = parent_id
		node.structural_depth = u16(level)
		state.usage.structural_depth = max(state.usage.structural_depth, u16(level))
		open[level] = node.id
	}
	for level in 1 ..< len(open) {
		if open[level] != Jan_Node_ID(0) {
			state.nodes[int(open[level]) - 1].range.end = editor.Byte_Offset(len(source))
		}
	}
	return true
}

@(private)
jan_structural_line_end :: proc(source: []u8, start, end: u32) -> u32 {
	limit := min(end, u32(len(source)))
	cursor := start
	for cursor < limit && source[cursor] != '\r' && source[cursor] != '\n' do cursor += 1
	return cursor
}

@(private)
jan_source_offset_is_utf8_boundary :: proc(source: []u8, offset: u32) -> bool {
	if offset == 0 || offset == u32(len(source)) do return true
	if offset > u32(len(source)) do return false
	return source[offset] & 0xc0 != 0x80
}

@(private)
jan_encode_u32 :: proc(destination: []u8, value: u32) -> int {
	if len(destination) == 0 do return 0
	if value == 0 {
		destination[0] = '0'
		return 1
	}
	length: int
	remaining := value
	for remaining > 0 && length < len(destination) {
		destination[length] = u8('0' + remaining % 10)
		remaining /= 10
		length += 1
	}
	for index in 0 ..< length / 2 {
		destination[index], destination[length - index - 1] = destination[length - index - 1], destination[index]
	}
	return length
}

@(private)
jan_structural_retained_bytes :: proc(state: ^Jan_Structural_Analysis_State) -> u64 {
	if state == nil do return 0
	return u64(cap(state.nodes)) * u64(size_of(Jan_Node_Record)) +
		u64(cap(state.attributes)) * u64(size_of(Jan_Attribute_Record)) +
		u64(cap(state.recoveries)) * u64(size_of(Jan_Recovery_Record)) +
		u64(cap(state.indexes)) * u64(size_of(Jan_Index_Fact))
}

@(private)
jan_structural_failure :: proc(scope: Jan_Analysis_Scope, code: Jan_Failure_Code) -> Jan_Failure {
	return Jan_Failure{operation = .Analyze, code = code, scope = scope}
}
