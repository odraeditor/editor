// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

import "../editor"
import "../language"
import "base:runtime"

/* MAX_INJECTION_REGIONS bounds embedded regions in one composition. */
MAX_INJECTION_REGIONS :: 256
/* MAX_INJECTION_DEPTH bounds nested embedded-language ancestry. */
MAX_INJECTION_DEPTH :: 8
/* MAX_INJECTION_CHILD_PROVIDERS bounds distinct embedded language providers. */
MAX_INJECTION_CHILD_PROVIDERS :: 64

/* Injection_Region_ID identifies one candidate within a composition. */
Injection_Region_ID :: distinct u64
/* Injection_Generation identifies one published embedded-region composition. */
Injection_Generation :: distinct u64

/* Injection_Failure_Code identifies an exact composition rejection. */
Injection_Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Duplicate_Identity,
	Invalid_Range,
	Invalid_Parent,
	Cycle,
	Depth_Limit,
	Region_Limit,
	Resource_Limit,
	Cancelled,
	Allocation,
}

/* Injection_Failure reports the candidate and resource bound that failed. */
Injection_Failure :: struct {
	code:   Injection_Failure_Code,
	index:  u16,
	limit:  u64,
	actual: u64,
}

/* Injection_Limits bounds region count, nesting, and analyzed bytes. */
Injection_Limits :: struct {
	regions:    u16,
	depth:      u8,
	span_bytes: u64,
}

/* DEFAULT_INJECTION_LIMITS applies the maintained composition bounds. */
DEFAULT_INJECTION_LIMITS :: Injection_Limits {
	regions = MAX_INJECTION_REGIONS,
	depth = MAX_INJECTION_DEPTH,
	span_bytes = language.MAX_ANALYZED_SOURCE_BYTES,
}

/* Injection_Candidate is copied query output before child-provider resolution. */
Injection_Candidate :: struct {
	identity:        Injection_Region_ID,
	parent_identity: Injection_Region_ID,
	start:           editor.Byte_Offset,
	end:             editor.Byte_Offset,
	language_id:     language.Language_ID,
	priority:        u16,
}

/* Injection_Child_Provider binds an embedded language to one exact selection. */
Injection_Child_Provider :: struct {
	identity:  language.Language_Identity,
	selection: language.Provider_Selection,
}

/* Injection_Compose_Request binds embedded regions to one containing revision. */
Injection_Compose_Request :: struct {
	buffer_id:       editor.Buffer_ID,
	source_revision: editor.Revision,
	source_bytes:    u64,
	containing_language: language.Language_Identity,
	containing_provider: language.Provider_Handle,
	generation:      Injection_Generation,
	candidates:      []Injection_Candidate,
	children:        []Injection_Child_Provider,
	limits:          Injection_Limits,
	cancellation:    language.Syntax_Provider_Cancellation,
}

/* Injection_Region is a pointer-free exact-revision embedded parser identity. */
Injection_Region :: struct {
	identity:        Injection_Region_ID,
	parent_identity: Injection_Region_ID,
	start:           editor.Byte_Offset,
	end:             editor.Byte_Offset,
	depth:           u8,
	priority:        u16,
	language_identity: language.Language_Identity,
	provider:        language.Provider_Handle,
	source_revision: editor.Revision,
	precedence_rank: u16,
}

/* Injection_Result owns one deterministic bounded embedded-region generation. */
Injection_Result :: struct {
	buffer_id:       editor.Buffer_ID,
	source_revision: editor.Revision,
	generation:      Injection_Generation,
	regions:         []Injection_Region,
	skipped_missing_child: u16,
	span_bytes:      u64,
	allocator:       runtime.Allocator,
}

/* Injection_Inspection is a copied bounded embedded-region snapshot. */
Injection_Inspection :: struct {
	buffer_id:       editor.Buffer_ID,
	source_revision: editor.Revision,
	generation:      Injection_Generation,
	regions:         [MAX_INJECTION_REGIONS]Injection_Region,
	region_count:    u16,
	skipped_missing_child: u16,
	span_bytes:      u64,
}

/* Syntax_Workflow_Analysis_Inspection copies provider and injection state. */
Syntax_Workflow_Analysis_Inspection :: struct {
	selection:       language.Language_Selection_Inspection,
	provider:        language.Provider_Descriptor,
	provider_found:  bool,
	syntax:          language.Syntax_Snapshot,
	injections:      Injection_Inspection,
}

/* injection_compose resolves children, nesting, resources, and precedence. */
injection_compose :: proc(
	request: Injection_Compose_Request,
	allocator := context.allocator,
) -> (result: Injection_Result, ok: bool, failure: Injection_Failure) {
	if !injection_request_valid(request) || allocator.procedure == nil {
		return {}, false, Injection_Failure {code = .Invalid_Request}
	}
	if injection_cancelled(request.cancellation) {
		return {}, false, Injection_Failure {code = .Cancelled}
	}
	if len(request.candidates) > int(request.limits.regions) {
		return {}, false, Injection_Failure {
			code = .Region_Limit,
			limit = u64(request.limits.regions),
			actual = u64(len(request.candidates)),
		}
	}
	for candidate, index in request.candidates {
		if injection_cancelled(request.cancellation) {
			return {}, false, Injection_Failure {code = .Cancelled, index = u16(index)}
		}
		if candidate.identity == Injection_Region_ID(0) || candidate.start >= candidate.end ||
		   u64(candidate.end) > request.source_bytes || candidate.language_id == language.Language_ID(0) {
			return {}, false, Injection_Failure {code = .Invalid_Range, index = u16(index)}
		}
		for prior in 0 ..< index {
			if request.candidates[prior].identity == candidate.identity {
				return {}, false, Injection_Failure {code = .Duplicate_Identity, index = u16(index)}
			}
		}
	}
	regions, allocation_error := make([]Injection_Region, len(request.candidates), allocator)
	if allocation_error != nil do return {}, false, Injection_Failure {code = .Allocation}
	count := 0
	span_bytes: u64
	for candidate, index in request.candidates {
		if injection_cancelled(request.cancellation) {
			delete(regions, allocator)
			return {}, false, Injection_Failure {code = .Cancelled, index = u16(index)}
		}
		child, child_found := injection_child_provider(request.children, candidate.language_id)
		if !child_found {
			result.skipped_missing_child += 1
			continue
		}
		depth, depth_ok, depth_failure := injection_candidate_depth(request.candidates, index, request.limits.depth)
		if !depth_ok {
			delete(regions, allocator)
			return {}, false, depth_failure
		}
		span := u64(candidate.end) - u64(candidate.start)
		if span > request.limits.span_bytes - min(span_bytes, request.limits.span_bytes) {
			delete(regions, allocator)
			return {}, false, Injection_Failure {
				code = .Resource_Limit,
				index = u16(index),
				limit = request.limits.span_bytes,
				actual = span_bytes + span,
			}
		}
		span_bytes += span
		regions[count] = Injection_Region {
			identity = candidate.identity,
			parent_identity = candidate.parent_identity,
			start = candidate.start,
			end = candidate.end,
			depth = depth,
			priority = candidate.priority,
			language_identity = child.identity,
			provider = child.selection.active,
			source_revision = request.source_revision,
		}
		count += 1
	}
	regions = regions[:count]
	injection_regions_sort(regions)
	for &region, index in regions do region.precedence_rank = u16(index + 1)
	result.buffer_id = request.buffer_id
	result.source_revision = request.source_revision
	result.generation = request.generation
	result.regions = regions
	result.span_bytes = span_bytes
	result.allocator = allocator
	return result, true, {}
}

/* Syntax_Workflow_Compose_Injections owns one exact-revision region generation. */
Syntax_Workflow_Compose_Injections :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer_id: editor.Buffer_ID,
	candidates: []Injection_Candidate,
	limits := DEFAULT_INJECTION_LIMITS,
) -> (ok: bool, failure: Injection_Failure) {
	if !Syntax_Workflow_Is_Live(workflow) || buffer_id == editor.Buffer_ID(0) {
		return false, Injection_Failure {code = .Invalid_Request}
	}
	index, found := Syntax_Workflow_Find_Buffer(workflow, buffer_id)
	if !found do return false, Injection_Failure {code = .Invalid_Request}
	entry := &workflow.entries[index]
	if !entry.owner_ready || entry.inspection.analysis_status != .Current {
		return false, Injection_Failure {code = .Invalid_Request}
	}
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&entry.source)
	if !stats_ok || stats.buffer_id != buffer_id ||
	   stats.revision != entry.inspection.confirmed_revision {
		return false, Injection_Failure {code = .Invalid_Request}
	}
	children: [MAX_INJECTION_CHILD_PROVIDERS]Injection_Child_Provider
	child_count := 0
	for candidate in candidates {
		known := false
		for child in children[:child_count] {
			if child.identity.id == candidate.language_id {
				known = true
				break
			}
		}
		if known do continue
		registry, registry_found := syntax_workflow_provider_registry(workflow, candidate.language_id)
		if !registry_found || registry.selection.state == .Disabled do continue
		if child_count >= MAX_INJECTION_CHILD_PROVIDERS {
			return false, Injection_Failure {
				code = .Region_Limit,
				limit = MAX_INJECTION_CHILD_PROVIDERS,
				actual = u64(child_count) + 1,
			}
		}
		children[child_count] = {
			identity = registry.identity,
			selection = registry.selection,
		}
		child_count += 1
	}
	generation, generated := syntax_workflow_take_injection_generation(workflow)
	if !generated {
		return false, Injection_Failure {code = .Resource_Limit}
	}
	result, composed, compose_failure := injection_compose(
		Injection_Compose_Request {
			buffer_id = buffer_id,
			source_revision = stats.revision,
			source_bytes = stats.text_bytes,
			containing_language = entry.inspection.association.language,
			containing_provider = entry.inspection.selection.active,
			generation = generation,
			candidates = candidates,
			children = children[:child_count],
			limits = limits,
		},
		workflow.allocator,
	)
	if !composed do return false, compose_failure
	if entry.injections.generation != Injection_Generation(0) do injection_result_close(&entry.injections)
	entry.injections = result
	return true, {}
}

/* Syntax_Workflow_Inspect_Analysis returns no borrowed or foreign values. */
Syntax_Workflow_Inspect_Analysis :: proc(
	workflow: ^Syntax_Workflow_State,
	buffer: ^editor.Buffer,
) -> (inspection: Syntax_Workflow_Analysis_Inspection, ok: bool) {
	selection, provider, provider_found, inspected := Syntax_Workflow_Inspect_Buffer(workflow, buffer)
	if !inspected do return {}, false
	inspection.selection = selection
	inspection.provider = provider
	inspection.provider_found = provider_found
	index, found := Syntax_Workflow_Find_Buffer(workflow, selection.buffer_id)
	if !found do return inspection, true
	entry := &workflow.entries[index]
	inspection.syntax = entry.inspection.syntax_snapshot
	inspection.injections = {
		buffer_id = entry.injections.buffer_id,
		source_revision = entry.injections.source_revision,
		generation = entry.injections.generation,
		region_count = u16(len(entry.injections.regions)),
		skipped_missing_child = entry.injections.skipped_missing_child,
		span_bytes = entry.injections.span_bytes,
	}
	copy(
		inspection.injections.regions[:inspection.injections.region_count],
		entry.injections.regions,
	)
	return inspection, true
}

/* injection_invalidate preserves only regions provably before one edit. */
injection_invalidate :: proc(
	result: ^Injection_Result,
	edit_start: editor.Byte_Offset,
	new_revision: editor.Revision,
	new_generation: Injection_Generation,
) -> (invalidated: u16, ok: bool) {
	if result == nil || result.regions == nil || new_revision == editor.Revision(0) ||
	   new_generation == Injection_Generation(0) || new_generation <= result.generation {
		return 0, false
	}
	write := 0
	span_bytes: u64
	for region in result.regions {
		if region.end > edit_start {
			invalidated += 1
			continue
		}
		result.regions[write] = region
		result.regions[write].source_revision = new_revision
		span_bytes += u64(region.end) - u64(region.start)
		write += 1
	}
	result.regions = result.regions[:write]
	result.source_revision = new_revision
	result.generation = new_generation
	result.span_bytes = span_bytes
	return invalidated, true
}

/* injection_result_close releases one owned embedded-region generation. */
injection_result_close :: proc(result: ^Injection_Result) {
	if result == nil do return
	if result.regions != nil do delete(result.regions, result.allocator)
	result^ = {}
}

@(private)
injection_cancelled :: proc(cancellation: language.Syntax_Provider_Cancellation) -> bool {
	return cancellation.check != nil && cancellation.check(cancellation.user_data)
}

@(private)
injection_request_valid :: proc(request: Injection_Compose_Request) -> bool {
	return request.buffer_id != editor.Buffer_ID(0) &&
		request.generation != Injection_Generation(0) &&
		request.containing_language.id != language.Language_ID(0) &&
		request.containing_provider.provider_id != language.Provider_ID(0) &&
		request.limits.regions > 0 && request.limits.regions <= MAX_INJECTION_REGIONS &&
		request.limits.depth > 0 && request.limits.depth <= MAX_INJECTION_DEPTH &&
		request.limits.span_bytes > 0 && request.limits.span_bytes <= language.MAX_ANALYZED_SOURCE_BYTES &&
		len(request.children) <= MAX_INJECTION_CHILD_PROVIDERS
}

@(private)
injection_child_provider :: proc(
	children: []Injection_Child_Provider,
	language_id: language.Language_ID,
) -> (Injection_Child_Provider, bool) {
	for child in children {
		if child.identity.id == language_id && child.selection.language.id == language_id &&
		   child.selection.state != .Disabled && child.selection.active.provider_id != language.Provider_ID(0) {
			return child, true
		}
	}
	return {}, false
}

@(private)
injection_candidate_depth :: proc(
	candidates: []Injection_Candidate,
	index: int,
	depth_limit: u8,
) -> (depth: u8, ok: bool, failure: Injection_Failure) {
	current := index
	seen: [MAX_INJECTION_DEPTH + 1]Injection_Region_ID
	for {
		parent := candidates[current].parent_identity
		if parent == Injection_Region_ID(0) do return depth, true, {}
		if depth >= depth_limit {
			return 0, false, Injection_Failure {code = .Depth_Limit, index = u16(index), limit = u64(depth_limit), actual = u64(depth) + 1}
		}
		for identity in seen[:depth + 1] {
			if identity != Injection_Region_ID(0) && identity == parent {
				return 0, false, Injection_Failure {code = .Cycle, index = u16(index)}
			}
		}
		seen[depth] = candidates[current].identity
		parent_index := -1
		for candidate, candidate_index in candidates {
			if candidate.identity == parent {
				parent_index = candidate_index
				break
			}
		}
		if parent_index < 0 || candidates[parent_index].start > candidates[current].start ||
		   candidates[parent_index].end < candidates[current].end {
			return 0, false, Injection_Failure {code = .Invalid_Parent, index = u16(index)}
		}
		depth += 1
		current = parent_index
	}
}

@(private)
injection_regions_sort :: proc(regions: []Injection_Region) {
	for index in 1 ..< len(regions) {
		candidate := regions[index]
		position := index
		for position > 0 && injection_region_precedes(candidate, regions[position - 1]) {
			regions[position] = regions[position - 1]
			position -= 1
		}
		regions[position] = candidate
	}
}

@(private)
injection_region_precedes :: proc(left, right: Injection_Region) -> bool {
	if left.priority != right.priority do return left.priority > right.priority
	left_span := u64(left.end) - u64(left.start)
	right_span := u64(right.end) - u64(right.start)
	if left_span != right_span do return left_span < right_span
	if left.start != right.start do return left.start < right.start
	return left.provider.provider_id < right.provider.provider_id
}
