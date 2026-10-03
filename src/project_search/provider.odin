// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_search

import "../document"
import project_core "../project"
import "../search"
import "base:runtime"
import "core:os"
import "core:hash"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

@(private)
Candidate :: struct {
	root_index: u32,
	path:       string,
}

@(private)
Ignore_Rule :: struct {
	root_index:    u32,
	pattern:       string,
	negated:       bool,
	directory_only: bool,
}

@(private)
Native_State :: struct {
	request:              Request,
	provider:             Provider,
	query:                search.Query,
	root_storage:         []Root,
	pattern_storage:      string,
	include_storage:      []string,
	exclude_storage:      []string,
	ignore_rules:         [dynamic]Ignore_Rule,
	candidates:           [dynamic]Candidate,
	matches:              [dynamic]Match,
	walker:               os.Walker,
	walker_active:        bool,
	root_index:           int,
	search_index:         int,
	result_generation:    Result_Generation,
	progress:             Progress,
	usage:                Usage,
	completeness:         Completeness,
	continuation:         Continuation,
	bounded_incomplete:   bool,
	resume_offset:        u64,
	enumeration_complete: bool,
	allocator:            runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
}

/* native_provider_init copies one request and prepares the maintained local provider. */
native_provider_init :: proc(
	provider: ^Native_Provider,
	request: Request,
	allocators: Allocator_Set,
) -> (bool, Failure) {
	if provider == nil || provider.state != nil || !request_is_valid(request) {
		return false, Failure{code = .Invalid_Request, request_id = request.id,
			request_generation = request.generation, project = request.project}
	}
	if allocators.persistent.procedure == nil || allocators.temporary.procedure == nil {
		return false, Failure{code = .Retained_Memory_Limit, request_id = request.id,
			request_generation = request.generation, project = request.project}
	}
	for _, root_index in request.roots {
		root := &request.roots[root_index]
		path := project_core.directory_path_text(&root.path)
		normalized: document.Normalized_Path
		normalized_ok, _ := document.path_normalize(path, &normalized, allocators.temporary)
		if !normalized_ok || document.normalized_path_text(&normalized) != path {
			return false, Failure{code = .Invalid_Root, request_id = request.id,
				request_generation = request.generation, project = request.project,
				membership = root.membership}
		}
	}
	for pattern in request.policy.include_patterns {
		if _, pattern_error := filepath.match(pattern, ""); pattern_error != nil {
			return false, Failure{code = .Invalid_File_Policy, request_id = request.id,
				request_generation = request.generation, project = request.project}
		}
	}
	for pattern in request.policy.exclude_patterns {
		if _, pattern_error := filepath.match(pattern, ""); pattern_error != nil {
			return false, Failure{code = .Invalid_File_Policy, request_id = request.id,
				request_generation = request.generation, project = request.project}
		}
	}
	state, allocation_error := new(Native_State, allocators.persistent)
	if allocation_error != nil {
		return false, Failure{code = .Retained_Memory_Limit, request_id = request.id,
			request_generation = request.generation, project = request.project}
	}
	state.allocator = allocators.persistent
	state.temporary_allocator = allocators.temporary
	state.provider = {id = request.provider, generation = request.provider_generation,
		lifecycle = .Prepared}
	state.result_generation = Result_Generation(request.generation)
	state.completeness = .Incomplete
	state.resume_offset = request.continuation.byte_offset
	copy_ok := native_request_copy(state, request)
	if !copy_ok {
		native_state_release(state)
		return false, Failure{code = .Retained_Memory_Limit, request_id = request.id,
			request_generation = request.generation, project = request.project}
	}
	query_ok, query_failure := search.query_init(&state.query, search.Query_Config{
		id = request.query_id, kind = request.pattern_kind, pattern = request.pattern,
		policy = request.policy.search, limits = request.search_limits,
		allocator = allocators.persistent, temporary_allocator = allocators.temporary,
	})
	if !query_ok {
		failure := native_search_failure(state, query_failure)
		native_state_release(state)
		return false, failure
	}
	state.candidates, allocation_error = make([dynamic]Candidate, 0,
		int(request.limits.files), allocators.persistent)
	if allocation_error != nil {
		failure := native_failure(state, .Retained_Memory_Limit)
		native_state_release(state)
		return false, failure
	}
	state.matches, allocation_error = make([dynamic]Match, 0,
		int(request.limits.matches), allocators.persistent)
	if allocation_error != nil {
		failure := native_failure(state, .Retained_Memory_Limit)
		native_state_release(state)
		return false, failure
	}
	state.ignore_rules, allocation_error = make([dynamic]Ignore_Rule, 0,
		int(request.limits.filter_patterns), allocators.persistent)
	if allocation_error != nil {
		failure := native_failure(state, .Retained_Memory_Limit)
		native_state_release(state)
		return false, failure
	}
	state.usage.retained_bytes = u64(size_of(Native_State)) +
		u64(cap(state.candidates)) * u64(size_of(Candidate)) +
		u64(cap(state.matches)) * u64(size_of(Match)) +
		u64(cap(state.ignore_rules)) * u64(size_of(Ignore_Rule)) +
		u64(len(state.root_storage)) * u64(size_of(Root)) + u64(len(state.pattern_storage)) +
		u64(len(state.include_storage) + len(state.exclude_storage)) * u64(size_of(string))
	for pattern in state.include_storage do state.usage.retained_bytes += u64(len(pattern))
	for pattern in state.exclude_storage do state.usage.retained_bytes += u64(len(pattern))
	if state.usage.retained_bytes > request.limits.retained_bytes {
		failure := native_failure(state, .Retained_Memory_Limit)
		failure.limit = request.limits.retained_bytes
		failure.actual = state.usage.retained_bytes
		native_state_release(state)
		return false, failure
	}
	provider.state = state
	return true, {}
}

/* native_provider_advance performs one bounded traversal or file-search turn. */
native_provider_advance :: proc(
	provider: ^Native_Provider,
	project: project_core.Project_Handle,
	cancellation: ^Cancellation = nil,
) -> (inspection: Inspection, ok: bool, failure: Failure) {
	state := native_state(provider)
	if state == nil {
		return {}, false, Failure{code = .Closed}
	}
	if project != state.request.project {
		return {}, false, native_failure(state, .Stale_Project)
	}
	if state.provider.lifecycle == .Prepared {
		_ = provider_transition(&state.provider, .Prepared, .Running)
	}
	if state.provider.lifecycle != .Running {
		return native_inspection(state), true, {}
	}
	if cancellation_is_requested(cancellation, state.request.generation) {
		native_cancel(state)
		return native_inspection(state), true, {}
	}
	if !state.enumeration_complete {
		enumerated, enumeration_failure := native_enumerate_turn(state, cancellation)
		if enumeration_failure.code != .None {
			native_fail(state)
			return native_inspection(state), false, enumeration_failure
		}
		if !enumerated || state.provider.lifecycle != .Running {
			return native_inspection(state), true, {}
		}
	}
	searched, search_failure := native_search_turn(state, cancellation)
	if search_failure.code != .None {
		native_fail(state)
		return native_inspection(state), false, search_failure
	}
	_ = searched
	return native_inspection(state), true, {}
}

/* native_provider_view borrows the current request and source-backed matches. */
native_provider_view :: proc(provider: ^Native_Provider) -> (Native_View, bool, Failure) {
	state := native_state(provider)
	if state == nil {
		return {}, false, Failure{code = .Closed}
	}
	return Native_View{inspection = native_inspection(state), request = state.request,
		matches = state.matches[:]}, true, {}
}

/* native_provider_revalidate confirms one match still refers to the same source version. */
native_provider_revalidate :: proc(
	provider: ^Native_Provider,
	match_id: u64,
) -> (Match, bool, Failure) {
	state := native_state(provider)
	if state == nil {
		return {}, false, Failure{code = .Closed}
	}
	for match in state.matches {
		if match.id != match_id do continue
		fingerprint, fingerprint_ok := native_fingerprint(match.path, state.temporary_allocator)
		if !fingerprint_ok || fingerprint != match.fingerprint {
			return {}, false, Failure{code = .Stale_Fingerprint, request_id = state.request.id,
				request_generation = state.request.generation, project = state.request.project,
				file = match.file}
		}
		return match, true, {}
	}
	return {}, false, native_failure(state, .Stale_Generation)
}

/* native_provider_close releases all provider state and invalidates borrowed views. */
native_provider_close :: proc(provider: ^Native_Provider) -> (bool, Failure) {
	state := native_state(provider)
	if state == nil {
		return false, Failure{code = .Closed}
	}
	if state.walker_active {
		os.walker_destroy(&state.walker)
		state.walker_active = false
	}
	state.provider.lifecycle = .Closed
	native_state_release(state)
	provider.state = nil
	return true, {}
}

@(private)
native_enumerate_turn :: proc(state: ^Native_State, cancellation: ^Cancellation) -> (bool, Failure) {
	processed: u32
	for processed < state.request.limits.entries_per_turn {
		if cancellation_is_requested(cancellation, state.request.generation) {
			native_cancel(state)
			return false, {}
		}
		if !state.walker_active {
			if state.root_index >= len(state.request.roots) {
				native_finish_enumeration(state)
				state.progress.roots_completed = u32(len(state.request.roots))
				return true, {}
			}
			root_path := project_core.directory_path_text(&state.request.roots[state.root_index].path)
			if !os.is_directory(root_path) {
				return false, Failure{code = .Invalid_Root, request_id = state.request.id,
					request_generation = state.request.generation, project = state.request.project,
					membership = state.request.roots[state.root_index].membership}
			}
			if state.request.policy.ignored == .Respect {
				if !native_ignore_rules_load(state, u32(state.root_index), root_path) {
					return false, native_failure(state, .Retained_Memory_Limit)
				}
			}
			os.walker_init(&state.walker, root_path)
			state.walker_active = true
		}
		info, walked := os.walker_walk(&state.walker)
		if _, walk_error := os.walker_error(&state.walker); walk_error != nil {
			return false, native_failure(state, .Filesystem)
		}
		if !walked {
			os.walker_destroy(&state.walker)
			state.walker = {}
			state.walker_active = false
			state.root_index += 1
			state.progress.roots_completed = u32(state.root_index)
			continue
		}
		if state.progress.entries_examined >= state.request.limits.examined_entries {
			state.completeness = .Incomplete
			state.bounded_incomplete = true
			state.continuation = {present = true, root_index = u32(state.root_index),
				file_index = u64(len(state.candidates))}
			native_finish_enumeration(state)
			return true, {}
		}
		state.progress.entries_examined += 1
		processed += 1
		root_path := project_core.directory_path_text(&state.request.roots[state.root_index].path)
		relative := native_relative_path(root_path, info.fullpath)
		hidden := len(info.name) > 0 && info.name[0] == '.'
		ignored := native_path_is_ignored(state, u32(state.root_index), relative,
			info.name, info.type == .Directory)
		if info.type == .Directory {
			if state.request.policy.hidden == .Exclude && hidden || ignored {
				os.walker_skip_dir(&state.walker)
			}
			continue
		}
		if info.type != .Regular || state.request.policy.hidden == .Exclude && hidden || ignored ||
		   !native_path_selected(state.request.policy, relative, info.name) {
			continue
		}
		if native_candidate_find(state.candidates[:], info.fullpath) >= 0 {
			continue
		}
		if len(state.candidates) >= int(state.request.limits.files) {
			state.completeness = .Incomplete
			state.bounded_incomplete = true
			state.continuation = {present = true, root_index = u32(state.root_index),
				file_index = u64(len(state.candidates))}
			native_finish_enumeration(state)
			return true, {}
		}
		projected_retained := state.usage.retained_bytes + u64(len(info.fullpath))
		if projected_retained > state.request.limits.retained_bytes {
			failure := native_failure(state, .Retained_Memory_Limit)
			failure.limit = state.request.limits.retained_bytes
			failure.actual = projected_retained
			return false, failure
		}
		path, allocation_error := strings.clone(info.fullpath, state.allocator)
		if allocation_error != nil {
			return false, native_failure(state, .Retained_Memory_Limit)
		}
		if _, append_error := append(&state.candidates, Candidate{
			root_index = u32(state.root_index), path = path,
		}); append_error != nil {
			delete(path, state.allocator)
			return false, native_failure(state, .Retained_Memory_Limit)
		}
		state.usage.files = u32(len(state.candidates))
		state.usage.retained_bytes += u64(len(path))
	}
	return false, {}
}

@(private)
native_search_turn :: proc(state: ^Native_State, cancellation: ^Cancellation) -> (bool, Failure) {
	files_this_turn: u32
	bytes_this_turn: u64
	for state.search_index < len(state.candidates) && files_this_turn < state.request.limits.files_per_turn {
		if cancellation_is_requested(cancellation, state.request.generation) {
			native_cancel(state)
			return false, {}
		}
		candidate := &state.candidates[state.search_index]
		info, stat_error := os.stat(candidate.path, state.temporary_allocator)
		if stat_error != nil {
			return false, native_failure(state, .Filesystem)
		}
		fingerprint := native_fingerprint_from_info(info)
		os.file_info_delete(info, state.temporary_allocator)
		if !source_fingerprint_is_valid(fingerprint) {
			return false, native_failure(state, .Filesystem)
		}
		if fingerprint.size > state.request.limits.file_bytes {
			state.completeness = .Incomplete
			state.bounded_incomplete = true
			state.continuation = {present = true, file_index = u64(state.search_index)}
			state.search_index += 1
			continue
		}
		if state.progress.bytes_read + fingerprint.size > state.request.limits.total_read_bytes {
			state.completeness = .Incomplete
			state.bounded_incomplete = true
			state.continuation = {present = true, file_index = u64(state.search_index)}
			native_complete(state)
			return true, {}
		}
		if files_this_turn > 0 && bytes_this_turn + fingerprint.size > state.request.limits.read_bytes_per_turn {
			break
		}
		bytes, read_error := os.read_entire_file_from_path(candidate.path, state.temporary_allocator)
		if read_error != nil {
			return false, native_failure(state, .Filesystem)
		}
		if u64(len(bytes)) > state.request.limits.file_bytes {
			delete(bytes, state.temporary_allocator)
			return false, native_failure(state, .File_Byte_Limit)
		}
		state.progress.files_examined += 1
		state.progress.bytes_read += u64(len(bytes))
		state.usage.read_bytes += u64(len(bytes))
		files_this_turn += 1
		bytes_this_turn += u64(len(bytes))
		binary := native_source_is_binary(bytes)
		if binary && state.request.policy.binary == .Exclude {
			delete(bytes, state.temporary_allocator)
			state.search_index += 1
			continue
		}
		if !utf8.valid_string(string(bytes)) {
			delete(bytes, state.temporary_allocator)
			if state.request.policy.binary == .Exclude {
				state.search_index += 1
				continue
			}
			return false, native_failure(state, .Malformed_UTF8)
		}
		origin := state.resume_offset if state.search_index == int(state.request.continuation.file_index) else 0
		searched, failure := native_search_file(state, candidate, fingerprint,
			string(bytes), origin, cancellation)
		state.resume_offset = 0
		delete(bytes, state.temporary_allocator)
		if failure.code != .None {
			return false, failure
		}
		if !searched || state.provider.lifecycle != .Running {
			return false, {}
		}
		state.progress.files_searched += 1
		state.search_index += 1
	}
	if state.search_index >= len(state.candidates) {
		native_complete(state)
		return true, {}
	}
	return false, {}
}

@(private)
native_search_file :: proc(
	state: ^Native_State,
	candidate: ^Candidate,
	fingerprint: Source_Fingerprint,
	source: string,
	initial_origin: u64,
	cancellation: ^Cancellation,
) -> (bool, Failure) {
	origin := initial_origin
	if origin > u64(len(source)) do return false, native_failure(state, .Stale_Generation)
	for origin < u64(len(source)) {
		if cancellation_is_requested(cancellation, state.request.generation) {
			native_cancel(state)
			return false, {}
		}
		remaining := int(state.request.limits.matches) - len(state.matches)
		if remaining <= 0 {
			state.completeness = .Incomplete
			state.bounded_incomplete = true
			state.continuation = {present = true, file_index = u64(state.search_index), byte_offset = origin}
			native_complete(state)
			return false, {}
		}
		turn_capacity := min(remaining, int(state.request.search_limits.retained_occurrences))
		spans, allocation_error := make([]search.Source_Match, turn_capacity, state.temporary_allocator)
		if allocation_error != nil {
			return false, native_failure(state, .Temporary_Memory_Limit)
		}
		turn, turn_ok, search_failure := search.source_search_turn(
			&state.query, source, origin, spans, state.temporary_allocator,
		)
		if !turn_ok {
			delete(spans, state.temporary_allocator)
			return false, native_search_failure(state, search_failure)
		}
		state.progress.cancellation_checks += turn.cancellation_checks
		state.usage.work_items += turn.logical_bytes
		for span in spans[:int(turn.matches)] {
			match, match_ok := native_match_build(state, candidate, fingerprint, source, span)
			if !match_ok {
				delete(spans, state.temporary_allocator)
				return false, native_failure(state, .Retained_Memory_Limit)
			}
			if _, append_error := append(&state.matches, match); append_error != nil {
				delete(match.preview, state.allocator)
				delete(spans, state.temporary_allocator)
				return false, native_failure(state, .Retained_Memory_Limit)
			}
			state.progress.matches += 1
			state.usage.matches += 1
			state.usage.retained_bytes += u64(len(match.preview))
		}
		delete(spans, state.temporary_allocator)
		if turn.complete {
			return true, {}
		}
		if turn.next_offset <= origin {
			return false, native_failure(state, .Arithmetic_Overflow)
		}
		origin = turn.next_offset
	}
	return true, {}
}

@(private)
native_match_build :: proc(
	state: ^Native_State,
	candidate: ^Candidate,
	fingerprint: Source_Fingerprint,
	source: string,
	span: search.Source_Match,
) -> (Match, bool) {
	line, column := native_line_column(source, span.start)
	preview_start, preview_end := native_preview_bounds(source, span.start, span.end)
	projected_retained := state.usage.retained_bytes + preview_end - preview_start
	if projected_retained > state.request.limits.retained_bytes do return {}, false
	preview, allocation_error := strings.clone(source[int(preview_start):int(preview_end)], state.allocator)
	if allocation_error != nil {
		return {}, false
	}
	return Match{id = native_match_id(state, candidate.path, span.start, span.end),
		file = File_ID(max(hash.fnv64a(transmute([]byte)candidate.path), 1)),
		root = state.request.roots[candidate.root_index].membership, path = candidate.path,
		fingerprint = fingerprint, start = span.start, end = span.end,
		line = line, column = column, preview = preview,
		preview_match_start = u32(span.start - preview_start),
		preview_match_end = u32(span.end - preview_start)}, true
}

@(private)
native_match_id :: proc(state: ^Native_State, path: string, start, end: u64) -> u64 {
	result := hash.fnv64a(transmute([]byte)path)
	result = (result ~ start) * 1_099_511_628_211
	result = (result ~ end) * 1_099_511_628_211
	if result == 0 do result = 1
	for {
		duplicate := false
		for match in state.matches do if match.id == result {
			duplicate = true
			break
		}
		if !duplicate do return result
		result += 1
		if result == 0 do result = 1
	}
}

@(private)
native_request_copy :: proc(state: ^Native_State, request: Request) -> bool {
	allocation_error: runtime.Allocator_Error
	state.root_storage, allocation_error = make([]Root, len(request.roots), state.allocator)
	if allocation_error != nil do return false
	copy(state.root_storage, request.roots)
	state.pattern_storage, allocation_error = strings.clone(request.pattern, state.allocator)
	if allocation_error != nil do return false
	state.include_storage, allocation_error = make([]string, len(request.policy.include_patterns), state.allocator)
	if allocation_error != nil do return false
	state.exclude_storage, allocation_error = make([]string, len(request.policy.exclude_patterns), state.allocator)
	if allocation_error != nil do return false
	for pattern, index in request.policy.include_patterns {
		state.include_storage[index], allocation_error = strings.clone(pattern, state.allocator)
		if allocation_error != nil do return false
	}
	for pattern, index in request.policy.exclude_patterns {
		state.exclude_storage[index], allocation_error = strings.clone(pattern, state.allocator)
		if allocation_error != nil do return false
	}
	state.request = request
	state.request.roots = state.root_storage
	state.request.pattern = state.pattern_storage
	state.request.policy.include_patterns = state.include_storage
	state.request.policy.exclude_patterns = state.exclude_storage
	return true
}

@(private)
native_ignore_rules_load :: proc(state: ^Native_State, root_index: u32, root: string) -> bool {
	names := [?]string{".ignore", ".gitignore"}
	for name in names {
		path := filepath.join([]string{root, name}, state.temporary_allocator) or_continue
		info, stat_error := os.stat(path, state.temporary_allocator)
		if stat_error != nil {
			delete(path, state.temporary_allocator)
			continue
		}
		size := info.size
		os.file_info_delete(info, state.temporary_allocator)
		if size < 0 || u64(size) > state.request.limits.filter_pattern_bytes *
		   u64(state.request.limits.filter_patterns) {
			delete(path, state.temporary_allocator)
			continue
		}
		contents, read_error := os.read_entire_file_from_path(path, state.temporary_allocator)
		delete(path, state.temporary_allocator)
		if read_error != nil {
			continue
		}
		lines := strings.split_lines(string(contents), state.temporary_allocator)
		for line in lines {
			trimmed := strings.trim_space(line)
			if len(trimmed) == 0 || trimmed[0] == '#' {
				continue
			}
			if len(state.ignore_rules) >= int(state.request.limits.filter_patterns) ||
			   u64(len(trimmed)) > state.request.limits.filter_pattern_bytes {
				delete(lines, state.temporary_allocator)
				delete(contents, state.temporary_allocator)
				return false
			}
			negated := trimmed[0] == '!'
			if negated do trimmed = trimmed[1:]
			for len(trimmed) > 0 && trimmed[0] == '/' do trimmed = trimmed[1:]
			directory_only := len(trimmed) > 0 && trimmed[len(trimmed) - 1] == '/'
			if directory_only do trimmed = trimmed[:len(trimmed) - 1]
			if len(trimmed) == 0 do continue
			owned, allocation_error := strings.clone(trimmed, state.allocator)
			if state.usage.retained_bytes + u64(len(trimmed)) > state.request.limits.retained_bytes {
				delete(lines, state.temporary_allocator)
				delete(contents, state.temporary_allocator)
				return false
			}
			if allocation_error != nil {
				delete(lines, state.temporary_allocator)
				delete(contents, state.temporary_allocator)
				return false
			}
			_, append_error := append(&state.ignore_rules, Ignore_Rule{root_index = root_index,
				pattern = owned, negated = negated, directory_only = directory_only})
			if append_error != nil {
				delete(owned, state.allocator)
				delete(lines, state.temporary_allocator)
				delete(contents, state.temporary_allocator)
				return false
			}
			state.usage.retained_bytes += u64(len(owned))
		}
		delete(lines, state.temporary_allocator)
		delete(contents, state.temporary_allocator)
	}
	return true
}

@(private)
native_path_is_ignored :: proc(state: ^Native_State, root_index: u32,
	relative, name: string, directory: bool) -> bool {
	if state.request.policy.ignored == .Include_Ignored do return false
	ignored := false
	for rule in state.ignore_rules {
		if rule.root_index != root_index || rule.directory_only && !directory do continue
		matched := native_pattern_matches(rule.pattern, relative, name)
		if matched do ignored = !rule.negated
	}
	return ignored
}

@(private)
native_path_selected :: proc(policy: Policy, relative, name: string) -> bool {
	included := len(policy.include_patterns) == 0
	for pattern in policy.include_patterns do if native_pattern_matches(pattern, relative, name) {
		included = true
		break
	}
	if !included do return false
	for pattern in policy.exclude_patterns do if native_pattern_matches(pattern, relative, name) do return false
	return true
}

@(private)
native_pattern_matches :: proc(pattern, relative, name: string) -> bool {
	target := relative if strings.contains(pattern, "/") else name
	matched, match_error := filepath.match(pattern, target)
	return match_error == nil && matched
}

@(private)
native_relative_path :: proc(root, path: string) -> string {
	if path == root do return ""
	if strings.has_prefix(path, root) && len(path) > len(root) && path[len(root)] == '/' {
		return path[len(root) + 1:]
	}
	return path
}

@(private)
native_source_is_binary :: proc(bytes: []byte) -> bool {
	for value in bytes[:min(len(bytes), 8 * int(KIBIBYTE))] do if value == 0 do return true
	return false
}

@(private)
native_fingerprint :: proc(path: string, allocator: runtime.Allocator) -> (Source_Fingerprint, bool) {
	info, stat_error := os.stat(path, allocator)
	if stat_error != nil do return {}, false
	defer os.file_info_delete(info, allocator)
	return native_fingerprint_from_info(info), true
}

@(private)
native_fingerprint_from_info :: proc(info: os.File_Info) -> Source_Fingerprint {
	nanoseconds := time.time_to_unix_nano(info.modification_time)
	seconds := nanoseconds / i64(time.Second)
	remainder := nanoseconds % i64(time.Second)
	if remainder < 0 {
		seconds -= 1
		remainder += i64(time.Second)
	}
	return {present = info.type == .Regular && info.size >= 0, inode = u64(info.inode),
		size = u64(max(info.size, 0)), modified_seconds = seconds,
		modified_nanoseconds = i32(remainder)}
}

@(private)
native_line_column :: proc(source: string, offset: u64) -> (line, column: u64) {
	line = 1
	column = 1
	bytes := transmute([]byte)source
	cursor := 0
	for cursor < int(offset) {
		value, width := utf8.decode_rune(bytes[cursor:])
		if width <= 0 do break
		if value == '\n' {
			line += 1
			column = 1
		} else {
			column += 1
		}
		cursor += width
	}
	return
}

@(private)
native_preview_bounds :: proc(source: string, start, end: u64) -> (u64, u64) {
	bytes := transmute([]byte)source
	left := int(start)
	for left > 0 && bytes[left - 1] != '\n' do left -= 1
	right := int(end)
	for right < len(bytes) && bytes[right] != '\n' do right += 1
	if right - left > 512 do right = min(right, left + 512)
	if u64(right) < end {
		left = int(start)
		right = min(len(bytes), left + 512)
	}
	for right > left && right < len(bytes) && bytes[right] & 0xc0 == 0x80 do right -= 1
	return u64(left), u64(right)
}

@(private)
native_finish_enumeration :: proc(state: ^Native_State) {
	if state.walker_active {
		os.walker_destroy(&state.walker)
		state.walker = {}
		state.walker_active = false
	}
	slice.sort_by(state.candidates[:], native_candidate_less)
	state.enumeration_complete = true
	if state.request.continuation.present {
		state.search_index = min(int(state.request.continuation.file_index), len(state.candidates))
	}
}

@(private)
native_complete :: proc(state: ^Native_State) {
	if !state.bounded_incomplete {
		state.completeness = .Complete
		state.continuation = {}
	}
	_ = provider_transition(&state.provider, .Running, .Complete)
}

@(private)
native_cancel :: proc(state: ^Native_State) {
	if state.walker_active {
		os.walker_destroy(&state.walker)
		state.walker = {}
		state.walker_active = false
	}
	state.completeness = .Incomplete
	state.continuation = {present = true, root_index = u32(state.root_index),
		file_index = u64(state.search_index)}
	_ = provider_transition(&state.provider, .Running, .Cancelled)
}

@(private)
native_fail :: proc(state: ^Native_State) {
	_ = provider_transition(&state.provider, .Running, .Failed)
}

@(private)
native_inspection :: proc(state: ^Native_State) -> Inspection {
	return {request_id = state.request.id, request_generation = state.request.generation,
		provider = state.provider.id, provider_generation = state.provider.generation,
		project = state.request.project, result_generation = state.result_generation,
		lifecycle = state.provider.lifecycle, completeness = state.completeness,
		progress = state.progress, continuation = state.continuation, usage = state.usage}
}

@(private)
native_failure :: proc(state: ^Native_State, code: Failure_Code) -> Failure {
	if state == nil do return Failure{code = code}
	return {code = code, request_id = state.request.id,
		request_generation = state.request.generation, project = state.request.project}
}

@(private)
native_search_failure :: proc(state: ^Native_State, failure: search.Failure) -> Failure {
	code := Failure_Code.Invalid_Pattern
	#partial switch failure.code {
	case .Malformed_UTF8: code = .Malformed_UTF8
	case .Invalid_Pattern_Kind, .Empty_Pattern, .Pattern_Limit: code = .Invalid_Pattern
	case .Invalid_Case_Mode, .Invalid_Boundary_Mode, .Invalid_Whitespace_Mode: code = .Invalid_Search_Policy
	case .Invalid_Limits: code = .Invalid_Limits
	case .Regex_Parser_Error, .Regex_Compiler_Error: code = .Invalid_Expression
	case .Match_Span_Limit: code = .Match_Limit
	case .Persistent_Memory_Limit: code = .Retained_Memory_Limit
	case .Temporary_Memory_Limit: code = .Temporary_Memory_Limit
	case .Arithmetic_Overflow: code = .Arithmetic_Overflow
	}
	result := native_failure(state, code)
	result.limit = failure.limit
	result.actual = failure.actual
	return result
}

@(private)
native_candidate_find :: proc(candidates: []Candidate, path: string) -> int {
	for candidate, index in candidates do if candidate.path == path do return index
	return -1
}

@(private)
native_candidate_less :: proc(left, right: Candidate) -> bool {
	if left.path == right.path do return left.root_index < right.root_index
	return left.path < right.path
}

@(private)
native_state :: proc(provider: ^Native_Provider) -> ^Native_State {
	if provider == nil || provider.state == nil do return nil
	return (^Native_State)(provider.state)
}

@(private)
native_state_release :: proc(state: ^Native_State) {
	if state == nil do return
	if state.walker_active do os.walker_destroy(&state.walker)
	for match in state.matches do delete(match.preview, state.allocator)
	for candidate in state.candidates do delete(candidate.path, state.allocator)
	for rule in state.ignore_rules do delete(rule.pattern, state.allocator)
	delete(state.matches)
	delete(state.candidates)
	delete(state.ignore_rules)
	for pattern in state.include_storage do delete(pattern, state.allocator)
	for pattern in state.exclude_storage do delete(pattern, state.allocator)
	delete(state.include_storage, state.allocator)
	delete(state.exclude_storage, state.allocator)
	delete(state.pattern_storage, state.allocator)
	delete(state.root_storage, state.allocator)
	if state.query.state != nil do search.query_close(&state.query)
	allocator := state.allocator
	free(state, allocator)
}
