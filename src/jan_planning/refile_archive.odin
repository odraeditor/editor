// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

import "../editor"
import "../language"
import "../transaction"

/* MAX_ARCHIVE_METADATA_BYTES bounds inspectable archive-origin source data. */
MAX_ARCHIVE_METADATA_BYTES :: 16 * 1_024
/* REFILE_PUBLICATION_SCHEMA_VERSION identifies recoverable publication records. */
REFILE_PUBLICATION_SCHEMA_VERSION :: u16(1)

/* Refile_Mode distinguishes subtree movement from copying. */
Refile_Mode :: enum u8 {
	Invalid,
	Move,
	Copy,
}

/* Refile_Target_Candidate is one copied eligible structural destination. */
Refile_Target_Candidate :: struct {
	resource:           Resource_Identity,
	scope:              Scope,
	target:             Semantic_Target,
	level:              u16,
	project_id:         u64,
	workspace_id:       u64,
	path:               string,
	recent_rank:        u32,
	predicate_admitted: bool,
}

/* Refile_Target_Filter composes optional level, file, context, path, and recent constraints. */
Refile_Target_Filter :: struct {
	minimum_level:    u16,
	maximum_level:    u16,
	resource:         Resource_Identity,
	project_id:       u64,
	workspace_id:     u64,
	path_prefix:      string,
	recent_limit:     u32,
	require_predicate: bool,
}

/* Refile_Request binds one source and destination to exact document generations. */
Refile_Request :: struct {
	operation_id:          Operation_ID,
	mode:                  Refile_Mode,
	source_resource:       Resource_Identity,
	destination_resource:  Resource_Identity,
	source_scope:          Scope,
	destination_scope:     Scope,
	source_target:         Semantic_Target,
	destination_target:    Semantic_Target,
	destination_level:     u16,
	rewrite_generation:    language.Jan_Rewrite_Generation,
}

/* Cross_Document_Refile_Descriptor reports exact copied plan identity and accounting. */
Cross_Document_Refile_Descriptor :: struct {
	operation_id:         Operation_ID,
	mode:                 Refile_Mode,
	source_resource:      Resource_Identity,
	destination_resource: Resource_Identity,
	source_scope:         Scope,
	destination_scope:    Scope,
	payload_fingerprint:  u64,
	payload_bytes:        u64,
	source_mutation:      bool,
	destination_mutation: bool,
}

/* Cross_Document_Refile_Plan owns checked source and destination rewrite plans. */
Cross_Document_Refile_Plan :: struct {
	descriptor:  Cross_Document_Refile_Descriptor,
	source:      language.Jan_Rewrite_Plan,
	destination: language.Jan_Rewrite_Plan,
}

/* Refile_Publication_State identifies every recoverable external-publication boundary. */
Refile_Publication_State :: enum u8 {
	Invalid,
	Prepared,
	Destination_Committed,
	Completed,
	Cancelled,
	Failed,
	Recovery_Required,
	Rolled_Back,
}

/* Refile_Publication_Event is one explicit durable publication observation. */
Refile_Publication_Event :: enum u8 {
	Invalid,
	Cancel,
	Destination_Commit,
	Destination_Fail,
	Source_Commit,
	Source_Fail,
	Rollback_Destination,
}

/* Refile_Publication_Record is the pointer-free recovery authority for one external operation. */
Refile_Publication_Record :: struct {
	schema:                u16,
	operation_id:          Operation_ID,
	mode:                  Refile_Mode,
	source_resource:       Resource_Identity,
	destination_resource:  Resource_Identity,
	source_revision:       editor.Revision,
	destination_revision:  editor.Revision,
	payload_fingerprint:   u64,
	payload_bytes:         u64,
	state:                 Refile_Publication_State,
	destination_committed: bool,
	source_removed:        bool,
}

/* Archive_Origin retains ordinary source facts required to visit or restore a subtree. */
Archive_Origin :: struct {
	resource:       Resource_Identity,
	node_id:        language.Jan_Node_ID,
	parent_node_id: language.Jan_Node_ID,
	source_revision: editor.Revision,
	sibling_index:  u32,
}

/* Archive_Metadata_Text owns bounded inspectable archive-origin syntax. */
Archive_Metadata_Text :: struct {
	bytes:  [MAX_ARCHIVE_METADATA_BYTES]u8,
	length: u16,
}

/* Internal_Archive_Request binds an archive-tag mutation to one exact subtree. */
Internal_Archive_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	target:             Semantic_Target,
	archived:           bool,
	rewrite_generation: language.Jan_Rewrite_Generation,
}

/* refile_candidates_filter applies all configured candidate constraints without retaining inputs. */
refile_candidates_filter :: proc(
	candidates: []Refile_Target_Candidate,
	filter: Refile_Target_Filter,
	output: []Refile_Target_Candidate,
) -> (count: int, ok: bool, failure: Failure) {
	if len(candidates) > int(MAX_REFILE_CANDIDATES) ||
	   filter.maximum_level > 0 && filter.minimum_level > filter.maximum_level ||
	   len(filter.path_prefix) > MAX_RESOURCE_BYTES || !utf8.valid_string(filter.path_prefix) {
		failure = refile_failure(0, .Limited, .Limit)
		failure.limit = u64(len(output))
		failure.actual = u64(len(candidates))
		return
	}
	for candidate in candidates {
		if !refile_candidate_is_valid(candidate) do return 0, false, refile_failure(0, .Malformed, .Target)
		if filter.minimum_level > 0 && candidate.level < filter.minimum_level do continue
		if filter.maximum_level > 0 && candidate.level > filter.maximum_level do continue
		if resource_identity_is_valid(filter.resource) &&
		   !refile_resource_equal(candidate.resource, filter.resource) {
			continue
		}
		if filter.project_id > 0 && candidate.project_id != filter.project_id do continue
		if filter.workspace_id > 0 && candidate.workspace_id != filter.workspace_id do continue
		if len(filter.path_prefix) > 0 && !strings.has_prefix(candidate.path, filter.path_prefix) do continue
		if filter.recent_limit > 0 &&
		   (candidate.recent_rank == 0 || candidate.recent_rank > filter.recent_limit) {
			continue
		}
		if filter.require_predicate && !candidate.predicate_admitted do continue
		if count >= len(output) {
			failure = refile_failure(0, .Limited, .Limit)
			failure.limit = u64(len(output))
			failure.actual = u64(count + 1)
			return 0, false, failure
		}
		output[count] = candidate
		count += 1
	}
	return count, true, {}
}

/* same_document_refile_plan_prepare creates one atomic checked move or copy plan. */
same_document_refile_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Refile_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	if plan == nil || analysis == nil || !refile_request_is_valid(request) ||
	   request.source_scope != request.destination_scope ||
	   !refile_resource_equal(request.source_resource, request.destination_resource) ||
	   u64(len(source)) != request.source_scope.source_bytes ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return false, refile_failure(request.operation_id, .Invalid_Request, .Refile)
	}
	if refile_ranges_overlap(request.source_target.range, request.destination_target.range) {
		return false, refile_failure(request.operation_id, .Conflict, .Target)
	}
	destination_replacement, built, failure := refile_destination_replacement(
		source,
		request,
		temporary_allocator,
	)
	if !built do return false, failure
	rewrites: [2]language.Jan_Rewrite_Request
	count := 0
	if request.mode == .Move {
		rewrites[count] = {node_id = request.source_target.node_id, range = request.source_target.range}
		count += 1
	}
	rewrites[count] = {
		node_id = request.destination_target.node_id,
		range = request.destination_target.range,
		replacement = destination_replacement,
	}
	count += 1
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		request.rewrite_generation,
		rewrites[:count],
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		allocator,
	)
	if !planned do return false, refile_failure_from_language(request.operation_id, jan_failure)
	return true, {}
}

/* cross_document_refile_plan_prepare checks both revisions before retaining either mutation. */
cross_document_refile_plan_prepare :: proc(
	plan: ^Cross_Document_Refile_Plan,
	source_analysis, destination_analysis: ^language.Jan_Structural_Analysis,
	source, destination: []u8,
	request: Refile_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	return cross_document_refile_plan_prepare_payload(
		plan,
		source_analysis,
		destination_analysis,
		source,
		destination,
		request,
		"",
		allocator,
		temporary_allocator,
	)
}

@(private)
cross_document_refile_plan_prepare_payload :: proc(
	plan: ^Cross_Document_Refile_Plan,
	source_analysis, destination_analysis: ^language.Jan_Structural_Analysis,
	source, destination: []u8,
	request: Refile_Request,
	payload_override: string,
	allocator: runtime.Allocator,
	temporary_allocator: runtime.Allocator,
) -> (bool, Failure) {
	if plan == nil || source_analysis == nil || destination_analysis == nil ||
	   plan.source.state != nil || plan.destination.state != nil ||
	   !refile_request_is_valid(request) || request.source_scope == request.destination_scope ||
	   refile_resource_equal(request.source_resource, request.destination_resource) ||
	   u64(len(source)) != request.source_scope.source_bytes ||
	   u64(len(destination)) != request.destination_scope.source_bytes ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return false, refile_failure(request.operation_id, .Invalid_Request, .Refile)
	}
	payload, payload_ok, failure := refile_payload(
		source,
		request,
		temporary_allocator,
		payload_override,
	)
	if !payload_ok do return false, failure
	destination_replacement, replacement_ok, append_failure := refile_append_payload(
		destination,
		request.destination_target,
		payload,
		temporary_allocator,
	)
	if !replacement_ok do return false, append_failure
	if request.mode == .Move {
		source_rewrite := [1]language.Jan_Rewrite_Request{{
			node_id = request.source_target.node_id,
			range = request.source_target.range,
		}}
		planned, jan_failure := language.jan_rewrite_plan_prepare(
			&plan.source,
			source_analysis,
			source,
			request.rewrite_generation,
			source_rewrite[:],
			language.DEFAULT_JAN_RESOURCE_LIMITS,
			allocator,
		)
		if !planned do return false, refile_failure_from_language(request.operation_id, jan_failure)
	}
	destination_rewrite := [1]language.Jan_Rewrite_Request{{
		node_id = request.destination_target.node_id,
		range = request.destination_target.range,
		replacement = destination_replacement,
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		&plan.destination,
		destination_analysis,
		destination,
		request.rewrite_generation,
		destination_rewrite[:],
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		allocator,
	)
	if !planned {
		language.jan_rewrite_plan_close(&plan.source)
		return false, refile_failure_from_language(request.operation_id, jan_failure)
	}
	plan.descriptor = {
		operation_id = request.operation_id,
		mode = request.mode,
		source_resource = request.source_resource,
		destination_resource = request.destination_resource,
		source_scope = request.source_scope,
		destination_scope = request.destination_scope,
		payload_fingerprint = refile_payload_fingerprint(payload),
		payload_bytes = u64(len(payload)),
		source_mutation = request.mode == .Move,
		destination_mutation = true,
	}
	return true, {}
}

/* cross_document_refile_admit locks both open buffers and validates their exact revisions. */
cross_document_refile_admit :: proc(
	plan: ^Cross_Document_Refile_Plan,
	source_buffer, destination_buffer: ^editor.Buffer,
	root: ^transaction.Multibuffer_Transaction,
	transaction_id: transaction.Transaction_ID,
	undo_unit_id: transaction.Undo_Unit_ID,
	allocators: transaction.Allocator_Set,
	limits := transaction.DEFAULT_LIMITS,
) -> (bool, Failure) {
	if plan == nil || source_buffer == nil || destination_buffer == nil || root == nil ||
	   plan.descriptor.operation_id == Operation_ID(0) {
		return false, refile_failure(0, .Invalid_Request, .Refile)
	}
	buffers := [2]^editor.Buffer{source_buffer, destination_buffer}
	started, transaction_failure := transaction.multibuffer_begin(
		root,
		transaction_id,
		undo_unit_id,
		buffers[:],
		{kind = .Language_Tool, descriptor = "jan"},
		"jan-refile",
		allocators,
		limits,
	)
	if !started do return false, refile_failure_from_transaction(plan.descriptor.operation_id, transaction_failure)
	destination_batch := language.jan_rewrite_plan_transaction_batch(&plan.destination)
	applied: bool
	applied, transaction_failure = transaction.multibuffer_apply_batch(
		root,
		plan.descriptor.destination_scope.analysis.buffer_id,
		destination_batch,
	)
	if !applied do return false, refile_failure_from_transaction(plan.descriptor.operation_id, transaction_failure)
	if plan.descriptor.source_mutation {
		source_batch := language.jan_rewrite_plan_transaction_batch(&plan.source)
		applied, transaction_failure = transaction.multibuffer_apply_batch(
			root,
			plan.descriptor.source_scope.analysis.buffer_id,
			source_batch,
		)
		if !applied do return false, refile_failure_from_transaction(plan.descriptor.operation_id, transaction_failure)
	}
	validated: bool
	validated, transaction_failure = transaction.multibuffer_validate(root)
	if !validated do return false, refile_failure_from_transaction(plan.descriptor.operation_id, transaction_failure)
	return true, {}
}

/* cross_document_refile_plan_close releases both checked mutation plans. */
cross_document_refile_plan_close :: proc(plan: ^Cross_Document_Refile_Plan) {
	if plan == nil do return
	language.jan_rewrite_plan_close(&plan.source)
	language.jan_rewrite_plan_close(&plan.destination)
	plan^ = {}
}

/* refile_publication_prepare creates the durable recovery authority before external effects. */
refile_publication_prepare :: proc(descriptor: Cross_Document_Refile_Descriptor) -> (Refile_Publication_Record, bool) {
	if descriptor.operation_id == Operation_ID(0) || descriptor.mode == .Invalid ||
	   !resource_identity_is_valid(descriptor.source_resource) ||
	   !resource_identity_is_valid(descriptor.destination_resource) ||
	   descriptor.payload_fingerprint == 0 || descriptor.payload_bytes == 0 {
		return {}, false
	}
	return {
		schema = REFILE_PUBLICATION_SCHEMA_VERSION,
		operation_id = descriptor.operation_id,
		mode = descriptor.mode,
		source_resource = descriptor.source_resource,
		destination_resource = descriptor.destination_resource,
		source_revision = descriptor.source_scope.analysis.source_revision,
		destination_revision = descriptor.destination_scope.analysis.source_revision,
		payload_fingerprint = descriptor.payload_fingerprint,
		payload_bytes = descriptor.payload_bytes,
		state = .Prepared,
	}, true
}

/* refile_publication_advance records exact committed state without inferring recovery. */
refile_publication_advance :: proc(
	record: Refile_Publication_Record,
	event: Refile_Publication_Event,
) -> (Refile_Publication_Record, bool, Failure) {
	if !refile_publication_record_is_valid(record) || event == .Invalid {
		return record, false, refile_failure(record.operation_id, .Malformed, .Resource)
	}
	next := record
	switch record.state {
	case .Prepared:
		#partial switch event {
		case .Cancel:
			next.state = .Cancelled
		case .Destination_Fail:
			next.state = .Failed
		case .Destination_Commit:
			next.destination_committed = true
			if record.mode == .Copy do next.state = .Completed
			if record.mode == .Move do next.state = .Destination_Committed
		case:
			return record, false, refile_failure(record.operation_id, .Conflict, .Resource)
		}
	case .Destination_Committed:
		#partial switch event {
		case .Source_Commit:
			next.source_removed = true
			next.state = .Completed
		case .Source_Fail, .Cancel:
			next.state = .Recovery_Required
		case:
			return record, false, refile_failure(record.operation_id, .Conflict, .Resource)
		}
	case .Recovery_Required:
		#partial switch event {
		case .Source_Commit:
			next.source_removed = true
			next.state = .Completed
		case .Rollback_Destination:
			next.destination_committed = false
			next.state = .Rolled_Back
		case:
			return record, false, refile_failure(record.operation_id, .Conflict, .Resource)
		}
	case .Completed, .Cancelled, .Failed, .Rolled_Back, .Invalid:
		return record, false, refile_failure(record.operation_id, .Conflict, .Resource)
	}
	failure: Failure
	if next.state == .Recovery_Required {
		failure = refile_failure(record.operation_id, .Recovery_Required, .Resource)
		failure.committed = 1
	}
	return next, true, failure
}

/* archive_origin_metadata_format emits ordinary property-drawer source data. */
archive_origin_metadata_format :: proc(origin: Archive_Origin) -> (Archive_Metadata_Text, bool) {
	if !archive_origin_is_valid(origin) do return {}, false
	result: Archive_Metadata_Text
	resource := origin.resource
	key := resource_identity_text(&resource)
	text := fmt.bprintf(
		result.bytes[:],
		":PROPERTIES:\n:JAN_ARCHIVE_SOURCE_PROVIDER: %d\n:JAN_ARCHIVE_SOURCE: %s\n:JAN_ARCHIVE_NODE: %d\n:JAN_ARCHIVE_PARENT: %d\n:JAN_ARCHIVE_REVISION: %d\n:JAN_ARCHIVE_POSITION: %d\n:END:\n",
		origin.resource.provider,
		key,
		origin.node_id,
		origin.parent_node_id,
		origin.source_revision,
		origin.sibling_index,
	)
	if len(text) == 0 || len(text) >= len(result.bytes) do return {}, false
	result.length = u16(len(text))
	return result, true
}

/* archive_metadata_text borrows one bounded formatted metadata record. */
archive_metadata_text :: proc(metadata: ^Archive_Metadata_Text) -> string {
	if metadata == nil || metadata.length == 0 || int(metadata.length) > len(metadata.bytes) do return ""
	return string(metadata.bytes[:metadata.length])
}

/* external_archive_plan_prepare moves one subtree with inspectable origin metadata. */
external_archive_plan_prepare :: proc(
	plan: ^Cross_Document_Refile_Plan,
	source_analysis, destination_analysis: ^language.Jan_Structural_Analysis,
	source, destination: []u8,
	request: Refile_Request,
	origin: Archive_Origin,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	if request.mode != .Move || !archive_origin_is_valid(origin) ||
	   origin.node_id != request.source_target.node_id ||
	   !refile_resource_equal(origin.resource, request.source_resource) {
		return false, refile_failure(request.operation_id, .Invalid_Request, .Archive)
	}
	payload, payload_ok, payload_failure := archive_payload_add_metadata(
		source,
		request.source_target,
		origin,
		temporary_allocator,
	)
	if !payload_ok do return false, refile_failure(request.operation_id, payload_failure, .Archive)
	return cross_document_refile_plan_prepare_payload(
		plan,
		source_analysis,
		destination_analysis,
		source,
		destination,
		request,
		payload,
		allocator,
		temporary_allocator,
	)
}

/* external_archive_restore_plan_prepare removes exact origin metadata while moving content back. */
external_archive_restore_plan_prepare :: proc(
	plan: ^Cross_Document_Refile_Plan,
	archive_analysis, destination_analysis: ^language.Jan_Structural_Analysis,
	archive_source, destination: []u8,
	request: Refile_Request,
	origin: Archive_Origin,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	if request.mode != .Move || !archive_origin_is_valid(origin) ||
	   !refile_resource_equal(origin.resource, request.destination_resource) {
		return false, refile_failure(request.operation_id, .Invalid_Request, .Archive)
	}
	payload, payload_ok, payload_failure := archive_payload_remove_metadata(
		archive_source,
		request.source_target,
		origin,
		temporary_allocator,
	)
	if !payload_ok do return false, refile_failure(request.operation_id, payload_failure, .Archive)
	return cross_document_refile_plan_prepare_payload(
		plan,
		archive_analysis,
		destination_analysis,
		archive_source,
		destination,
		request,
		payload,
		allocator,
		temporary_allocator,
	)
}

/* archive_origin_resource returns the exact provider-owned resource to visit. */
archive_origin_resource :: proc(origin: Archive_Origin) -> (Resource_Identity, bool) {
	if !archive_origin_is_valid(origin) do return {}, false
	return origin.resource, true
}

/* internal_archive_plan_prepare adds or removes the compatible ARCHIVE tag atomically. */
internal_archive_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Internal_Archive_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	if plan == nil || analysis == nil || request.operation_id == Operation_ID(0) ||
	   !scope_is_valid(request.scope) || !semantic_target_is_valid(request.target, request.scope) ||
	   request.target.kind != .Heading || u64(len(source)) != request.scope.source_bytes ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		return false, refile_failure(request.operation_id, .Invalid_Request, .Archive)
	}
	start, end := int(request.target.range.start), int(request.target.range.end)
	replacement, changed, ok, rewrite_failure := internal_archive_rewrite(
		string(source[start:end]),
		request.archived,
		temporary_allocator,
	)
	if !ok do return false, refile_failure(request.operation_id, rewrite_failure, .Archive)
	if !changed do return false, refile_failure(request.operation_id, .Conflict, .Archive)
	rewrites := [1]language.Jan_Rewrite_Request{{
		node_id = request.target.node_id,
		range = request.target.range,
		replacement = replacement,
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		request.rewrite_generation,
		rewrites[:],
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		allocator,
	)
	if !planned do return false, refile_failure_from_language(request.operation_id, jan_failure)
	return true, {}
}

/* archive_content_visible applies explicit archived-content inclusion policy. */
archive_content_visible :: proc(archived, include_archived: bool) -> bool {
	return !archived || include_archived
}

@(private)
archive_payload_add_metadata :: proc(
	source: []u8,
	target: Semantic_Target,
	origin: Archive_Origin,
	allocator: runtime.Allocator,
) -> (string, bool, Failure_Code) {
	if target.range.end > editor.Byte_Offset(len(source)) || allocator.procedure == nil {
		return "", false, .Invalid_Request
	}
	metadata, metadata_ok := archive_origin_metadata_format(origin)
	if !metadata_ok do return "", false, .Malformed
	metadata_text := archive_metadata_text(&metadata)
	start, end := int(target.range.start), int(target.range.end)
	subtree := string(source[start:end])
	line_end := strings.index_byte(subtree, '\n')
	if line_end < 0 do line_end = len(subtree)
	builder, builder_error := strings.builder_make(allocator)
	if builder_error != nil do return "", false, .Allocation_Failed
	defer strings.builder_destroy(&builder)
	if strings.write_string(&builder, subtree[:line_end]) != line_end do return "", false, .Allocation_Failed
	if strings.write_byte(&builder, '\n') != 1 do return "", false, .Allocation_Failed
	if strings.write_string(&builder, metadata_text) != len(metadata_text) do return "", false, .Allocation_Failed
	if line_end < len(subtree) &&
	   strings.write_string(&builder, subtree[line_end + 1:]) != len(subtree) - line_end - 1 {
		return "", false, .Allocation_Failed
	}
	return strings.to_string(builder), true, .None
}

@(private)
archive_payload_remove_metadata :: proc(
	source: []u8,
	target: Semantic_Target,
	origin: Archive_Origin,
	allocator: runtime.Allocator,
) -> (string, bool, Failure_Code) {
	if target.range.end > editor.Byte_Offset(len(source)) || allocator.procedure == nil {
		return "", false, .Invalid_Request
	}
	metadata, metadata_ok := archive_origin_metadata_format(origin)
	if !metadata_ok do return "", false, .Malformed
	metadata_text := archive_metadata_text(&metadata)
	start, end := int(target.range.start), int(target.range.end)
	subtree := string(source[start:end])
	line_end := strings.index_byte(subtree, '\n')
	if line_end < 0 do return "", false, .Malformed
	metadata_start := line_end + 1
	if metadata_start + len(metadata_text) > len(subtree) ||
	   subtree[metadata_start:metadata_start + len(metadata_text)] != metadata_text {
		return "", false, .Stale
	}
	builder, builder_error := strings.builder_make(allocator)
	if builder_error != nil do return "", false, .Allocation_Failed
	defer strings.builder_destroy(&builder)
	if strings.write_string(&builder, subtree[:metadata_start]) != metadata_start {
		return "", false, .Allocation_Failed
	}
	remainder := subtree[metadata_start + len(metadata_text):]
	if strings.write_string(&builder, remainder) != len(remainder) do return "", false, .Allocation_Failed
	return strings.to_string(builder), true, .None
}

@(private)
refile_candidate_is_valid :: proc(candidate: Refile_Target_Candidate) -> bool {
	return resource_identity_is_valid(candidate.resource) && scope_is_valid(candidate.scope) &&
	       semantic_target_is_valid(candidate.target, candidate.scope) &&
	       candidate.target.kind == .Heading && candidate.level > 0 &&
	       len(candidate.path) > 0 && len(candidate.path) <= MAX_RESOURCE_BYTES &&
	       utf8.valid_string(candidate.path)
}

@(private)
refile_request_is_valid :: proc(request: Refile_Request) -> bool {
	return request.operation_id != Operation_ID(0) && request.mode != .Invalid &&
	       resource_identity_is_valid(request.source_resource) &&
	       resource_identity_is_valid(request.destination_resource) &&
	       scope_is_valid(request.source_scope) && scope_is_valid(request.destination_scope) &&
	       semantic_target_is_valid(request.source_target, request.source_scope) &&
	       semantic_target_is_valid(request.destination_target, request.destination_scope) &&
	       request.source_target.kind == .Heading && request.destination_target.kind == .Heading &&
	       request.destination_level > 0 &&
	       request.rewrite_generation != language.Jan_Rewrite_Generation(0)
}

@(private)
refile_payload :: proc(
	source: []u8,
	request: Refile_Request,
	allocator: runtime.Allocator,
	payload_override: string = "",
) -> (string, bool, Failure) {
	if request.source_target.range.end > editor.Byte_Offset(len(source)) {
		return "", false, refile_failure(request.operation_id, .Stale, .Target)
	}
	if len(payload_override) > int(MAX_COPIED_TEXT_BYTES) || !utf8.valid_string(payload_override) {
		return "", false, refile_failure(request.operation_id, .Malformed, .Refile)
	}
	payload := payload_override
	if len(payload) == 0 {
		start, end := int(request.source_target.range.start), int(request.source_target.range.end)
		payload = string(source[start:end])
	}
	releveled, ok, relevel_failure := refile_subtree_relevel(
		payload,
		request.destination_level + 1,
		allocator,
	)
	if !ok do return "", false, refile_failure(request.operation_id, relevel_failure, .Refile)
	return releveled, true, {}
}

@(private)
refile_destination_replacement :: proc(
	source: []u8,
	request: Refile_Request,
	allocator: runtime.Allocator,
) -> (string, bool, Failure) {
	payload, ok, failure := refile_payload(source, request, allocator)
	if !ok do return "", false, failure
	return refile_append_payload(source, request.destination_target, payload, allocator)
}

@(private)
refile_append_payload :: proc(
	source: []u8,
	target: Semantic_Target,
	payload: string,
	allocator: runtime.Allocator,
) -> (string, bool, Failure) {
	if target.range.end > editor.Byte_Offset(len(source)) || len(payload) == 0 {
		return "", false, refile_failure(0, .Stale, .Target)
	}
	start, end := int(target.range.start), int(target.range.end)
	current := string(source[start:end])
	builder, builder_error := strings.builder_make(allocator)
	if builder_error != nil do return "", false, refile_failure(0, .Allocation_Failed, .Refile)
	defer strings.builder_destroy(&builder)
	if strings.write_string(&builder, current) != len(current) do return "", false, refile_failure(0, .Allocation_Failed, .Refile)
	if len(current) > 0 && current[len(current) - 1] != '\n' && strings.write_byte(&builder, '\n') != 1 {
		return "", false, refile_failure(0, .Allocation_Failed, .Refile)
	}
	if strings.write_string(&builder, payload) != len(payload) do return "", false, refile_failure(0, .Allocation_Failed, .Refile)
	if payload[len(payload) - 1] != '\n' && strings.write_byte(&builder, '\n') != 1 {
		return "", false, refile_failure(0, .Allocation_Failed, .Refile)
	}
	return strings.to_string(builder), true, {}
}

@(private)
refile_subtree_relevel :: proc(
	source: string,
	destination_level: u16,
	allocator: runtime.Allocator,
) -> (string, bool, Failure_Code) {
	if len(source) == 0 || destination_level == 0 || allocator.procedure == nil {
		return "", false, .Invalid_Request
	}
	first_level := refile_heading_level(source)
	if first_level == 0 do return "", false, .Malformed
	delta := int(destination_level) - int(first_level)
	builder, builder_error := strings.builder_make(allocator)
	if builder_error != nil do return "", false, .Allocation_Failed
	defer strings.builder_destroy(&builder)
	line_start := 0
	for line_start < len(source) {
		line_end := line_start
		for line_end < len(source) && source[line_end] != '\n' do line_end += 1
		line := source[line_start:line_end]
		level := refile_heading_level(line)
		if level > 0 {
			new_level := level + delta
			if new_level <= 0 || new_level > 255 do return "", false, .Malformed
			for _ in 0 ..< new_level do if strings.write_byte(&builder, '*') != 1 do return "", false, .Allocation_Failed
			if strings.write_string(&builder, line[level:]) != len(line) - level do return "", false, .Allocation_Failed
		} else if strings.write_string(&builder, line) != len(line) {
			return "", false, .Allocation_Failed
		}
		if line_end < len(source) && strings.write_byte(&builder, '\n') != 1 do return "", false, .Allocation_Failed
		line_start = line_end + 1
	}
	return strings.to_string(builder), true, .None
}

@(private)
refile_heading_level :: proc(text: string) -> int {
	level := 0
	for level < len(text) && text[level] == '*' do level += 1
	if level == 0 || level >= len(text) || text[level] != ' ' do return 0
	return level
}

@(private)
internal_archive_rewrite :: proc(
	source: string,
	archived: bool,
	allocator: runtime.Allocator,
) -> (string, bool, bool, Failure_Code) {
	line_end := strings.index_byte(source, '\n')
	if line_end < 0 do line_end = len(source)
	heading := source[:line_end]
	if refile_heading_level(heading) == 0 do return "", false, false, .Malformed
	tag := ":ARCHIVE:"
	position := strings.index(heading, tag)
	if archived && position >= 0 || !archived && position < 0 do return source, false, true, .None
	builder, builder_error := strings.builder_make(allocator)
	if builder_error != nil do return "", false, false, .Allocation_Failed
	defer strings.builder_destroy(&builder)
	if archived {
		last_space := strings.last_index_byte(heading, ' ')
		has_tag_block := last_space >= 0 && last_space + 2 < len(heading) &&
		                 heading[last_space + 1] == ':' && heading[len(heading) - 1] == ':'
		if has_tag_block {
			if strings.write_string(&builder, heading) != len(heading) ||
			   strings.write_string(&builder, "ARCHIVE:") != len("ARCHIVE:") {
				return "", false, false, .Allocation_Failed
			}
		} else if strings.write_string(&builder, heading) != len(heading) ||
		          strings.write_string(&builder, " :ARCHIVE:") != len(" :ARCHIVE:") {
			return "", false, false, .Allocation_Failed
		}
	} else {
		standalone := position > 0 && heading[position - 1] == ' ' && position + len(tag) == len(heading)
		prefix_end := position + 1
		if standalone do prefix_end = position - 1
		suffix_start := position + len(tag)
		if strings.write_string(&builder, heading[:prefix_end]) != prefix_end ||
		   strings.write_string(&builder, heading[suffix_start:]) != len(heading) - suffix_start {
			return "", false, false, .Allocation_Failed
		}
	}
	if strings.write_string(&builder, source[line_end:]) != len(source) - line_end {
		return "", false, false, .Allocation_Failed
	}
	return strings.to_string(builder), true, true, .None
}

@(private)
archive_origin_is_valid :: proc(origin: Archive_Origin) -> bool {
	resource := origin.resource
	key := resource_identity_text(&resource)
	return resource_identity_is_valid(origin.resource) && origin.node_id != language.Jan_Node_ID(0) &&
	       !strings.contains_any(key, "\r\n")
}

@(private)
refile_publication_record_is_valid :: proc(record: Refile_Publication_Record) -> bool {
	return record.schema == REFILE_PUBLICATION_SCHEMA_VERSION &&
	       record.operation_id != Operation_ID(0) && record.mode != .Invalid &&
	       resource_identity_is_valid(record.source_resource) &&
	       resource_identity_is_valid(record.destination_resource) &&
	       record.payload_fingerprint != 0 && record.payload_bytes > 0 &&
	       record.state != .Invalid &&
	       (!record.source_removed || record.destination_committed)
}

@(private)
refile_resource_equal :: proc(left, right: Resource_Identity) -> bool {
	left_copy, right_copy := left, right
	return left.provider == right.provider &&
	       resource_identity_text(&left_copy) == resource_identity_text(&right_copy)
}

@(private)
refile_ranges_overlap :: proc(left, right: language.Jan_Source_Range) -> bool {
	return left.scope == right.scope && left.start < right.end && right.start < left.end
}

@(private)
refile_payload_fingerprint :: proc(payload: string) -> u64 {
	fingerprint := u64(14_695_981_039_346_656_037)
	for value in transmute([]u8)payload {
		fingerprint ~= u64(value)
		fingerprint *= 1_099_511_628_211
	}
	if fingerprint == 0 do fingerprint = 1
	return fingerprint
}

@(private)
refile_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Refile_Archive, code = code, field = field}
}

@(private)
refile_failure_from_language :: proc(operation_id: Operation_ID, failure: language.Jan_Failure) -> Failure {
	result := refile_failure(operation_id, .Invalid_Target, .Refile)
	#partial switch failure.code {
	case .Stale:             result.code = .Stale
	case .Malformed:         result.code = .Malformed
	case .Limited:           result.code = .Limited
	case .Allocation_Failed: result.code = .Allocation_Failed
	case .Cancelled:         result.code = .Cancelled
	}
	result.limit = failure.limit
	result.actual = failure.actual
	return result
}

@(private)
refile_failure_from_transaction :: proc(operation_id: Operation_ID, failure: transaction.Failure_Context) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch failure.code {
	case .Stale_Revision, .Mismatched_Revision: code = .Stale
	case .Cancelled:                           code = .Cancelled
	case .Text_Limit, .Splice_Limit, .Work_Limit,
	     .Metadata_Memory_Limit, .Temporary_Memory_Limit,
	     .Persistent_Memory_Limit:              code = .Limited
	}
	return {
		operation_id = operation_id,
		kind = .Refile_Archive,
		code = code,
		field = .Resource,
		limit = failure.limit,
		actual = failure.actual,
	}
}
