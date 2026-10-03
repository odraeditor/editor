// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package project_search_reference provides an independent bounded Project-search oracle.
package project_search_reference

MAX_ROOTS :: 8
MAX_RESULTS :: 256
MAX_PATH_BYTES :: 128

Source :: struct {
	root:       u8,
	fingerprint: u64,
	path:       [MAX_PATH_BYTES]u8,
	path_bytes: u8,
	text:       string,
}

Result :: struct {
	root:        u8,
	fingerprint: u64,
	start:       u32,
	end:         u32,
	path:        [MAX_PATH_BYTES]u8,
	path_bytes:  u8,
}

Model :: struct {
	project_generation: u64,
	result_generation:  u64,
	results:            [MAX_RESULTS]Result,
	count:              u16,
	complete:           bool,
	continuation:       u16,
}

publish_literal :: proc(model: ^Model, project_generation, expected_generation: u64,
	pattern: string, sources: []Source, limit: u16, cancelled: bool) -> bool {
	if model == nil || project_generation == 0 || expected_generation != model.result_generation ||
	   len(pattern) == 0 || len(sources) > MAX_ROOTS || limit == 0 || limit > MAX_RESULTS || cancelled {
		return false
	}
	next: [MAX_RESULTS]Result
	count: u16
	continuation: u16
	complete := true
	for source, source_index in sources {
		if source.root == 0 || source.fingerprint == 0 || source.path_bytes == 0 do return false
		origin := 0
		for origin + len(pattern) <= len(source.text) {
			index := find(source.text, pattern, origin)
			if index < 0 do break
			if count >= limit {
				complete = false
				continuation = u16(source_index)
				break
			}
			next[count] = {root = source.root, fingerprint = source.fingerprint,
				start = u32(index), end = u32(index + len(pattern)), path = source.path,
				path_bytes = source.path_bytes}
			count += 1
			origin = index + max(len(pattern), 1)
		}
		if !complete do break
	}
	model.project_generation = project_generation
	model.result_generation += 1
	model.results = next
	model.count = count
	model.complete = complete
	model.continuation = continuation
	return true
}

revalidate :: proc(model: ^Model, index: u16, project_generation, fingerprint: u64) -> bool {
	return model != nil && index < model.count && model.project_generation == project_generation &&
	       model.results[index].fingerprint == fingerprint
}

source :: proc(root: u8, fingerprint: u64, path, text: string) -> Source {
	result := Source{root = root, fingerprint = fingerprint, text = text}
	result.path_bytes = u8(copy(result.path[:], path))
	return result
}

find :: proc(text, pattern: string, origin: int) -> int {
	if origin < 0 || len(pattern) == 0 || len(pattern) > len(text) do return -1
	for index in origin ..= len(text) - len(pattern) {
		if text[index:index + len(pattern)] == pattern do return index
	}
	return -1
}
