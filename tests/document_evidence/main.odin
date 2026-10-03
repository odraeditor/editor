// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/document"
import "../../src/editor"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

main :: proc() {
	sizes := [3]u64{4 * 1024, 4 * 1024 * 1024, document.MAX_FILE_BYTES}
	for size in sizes {
		if !measure_open(size) || !measure_save(size) {
			os.exit(1)
		}
	}
}

measure_open :: proc(size: u64) -> bool {
	directory, directory_error := os.make_directory_temp("", "odra-document-open-evidence-*", context.allocator)
	if directory_error != nil {
		fmt.eprintf("document_open directory_error bytes=%d\n", size)
		return false
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "document.txt"}, context.allocator)
	if path_error != nil {
		fmt.eprintf("document_open path_error bytes=%d\n", size)
		return false
	}
	defer delete(path)
	contents, allocation_error := make([]byte, int(size), context.allocator)
	if allocation_error != nil {
		fmt.eprintf("document_open fixture_allocation_failure bytes=%d\n", size)
		return false
	}
	for index in 0 ..< len(contents) {
		contents[index] = byte('a' + index % 26)
	}
	written := os.write_entire_file(path, contents)
	delete(contents, context.allocator)
	if written != nil {
		fmt.eprintf("document_open fixture_write_failure bytes=%d\n", size)
		return false
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	persistent := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	prepared: document.Prepared_Open
	opened, open_failure := document.open_prepare(
		&prepared,
		document.Open_Request {
			document_id = document.Document_ID(1),
			buffer_id = editor.Buffer_ID(1),
			has_path = true,
			path = path,
			encoding = .UTF8,
		},
		document.Allocator_Set{persistent = persistent, temporary = context.temp_allocator},
	)
	if !opened {
		fmt.eprintf("document_open prepare_failure bytes=%d code=%v\n", size, open_failure.code)
		return false
	}
	view, viewed, view_failure := document.prepared_open_view(&prepared)
	if !viewed {
		document.prepared_open_abort(&prepared)
		fmt.eprintf("document_open inspect_failure bytes=%d code=%v\n", size, view_failure.code)
		return false
	}
	buffer: editor.Buffer
	buffer_ok, buffer_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(1),
		view.contents,
		editor.Allocator_Set{persistent = persistent, temporary = context.temp_allocator},
	)
	if !buffer_ok {
		document.prepared_open_abort(&prepared)
		fmt.eprintf("document_open buffer_failure bytes=%d code=%v\n", size, buffer_failure.code)
		return false
	}
	doc: document.Document
	committed, commit_failure := document.prepared_open_commit(
		&prepared,
		&doc,
		editor.Revision(0),
	)
	if !committed {
		editor.buffer_close(&buffer)
		document.prepared_open_abort(&prepared)
		fmt.eprintf("document_open commit_failure bytes=%d code=%v\n", size, commit_failure.code)
		return false
	}
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	peak := tracking.peak_memory_allocated
	fmt.printf(
		"document_open bytes=%d elapsed_ns=%d peak_bytes=%d\n",
		size,
		elapsed_ns,
		peak,
	)
	document_closed, _ := document.document_close(&doc)
	buffer_closed, _ := editor.buffer_close(&buffer)
	if !document_closed || !buffer_closed || tracking.current_memory_allocated != 0 {
		fmt.eprintf(
			"document_open cleanup_failure bytes=%d tracked=%d\n",
			size,
			tracking.current_memory_allocated,
		)
		return false
	}
	return true
}

measure_save :: proc(size: u64) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	persistent := mem.tracking_allocator(&tracking)
	directory, directory_error := os.make_directory_temp("", "odra-document-evidence-*", context.allocator)
	if directory_error != nil {
		fmt.eprintf("document_evidence directory_error bytes=%d\n", size)
		return false
	}
	defer {
		os.remove_all(directory)
		delete(directory)
	}
	path, path_error := os.join_path({directory, "document.txt"}, context.allocator)
	if path_error != nil {
		fmt.eprintf("document_evidence path_error bytes=%d\n", size)
		return false
	}
	defer delete(path)

	prepared_open: document.Prepared_Open
	opened, open_failure := document.open_prepare(
		&prepared_open,
		document.Open_Request {
			document_id = document.Document_ID(1),
			buffer_id = editor.Buffer_ID(1),
			has_path = true,
			path = path,
			encoding = .UTF8,
		},
		document.Allocator_Set{persistent = persistent, temporary = context.temp_allocator},
	)
	if !opened {
		fmt.eprintf("document_evidence open_failure bytes=%d code=%v\n", size, open_failure.code)
		return false
	}

	contents, allocation_error := make([]byte, int(size), persistent)
	if allocation_error != nil {
		document.prepared_open_abort(&prepared_open)
		fmt.eprintf("document_evidence source_allocation_failure bytes=%d\n", size)
		return false
	}
	for index in 0 ..< len(contents) {
		contents[index] = byte('a' + index % 26)
	}
	buffer: editor.Buffer
	buffer_ok, buffer_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(1),
		string(contents),
		editor.Allocator_Set{persistent = persistent, temporary = context.temp_allocator},
	)
	delete(contents, persistent)
	if !buffer_ok {
		document.prepared_open_abort(&prepared_open)
		fmt.eprintf("document_evidence buffer_failure bytes=%d code=%v\n", size, buffer_failure.code)
		return false
	}
	doc: document.Document
	committed, commit_failure := document.prepared_open_commit(
		&prepared_open,
		&doc,
		editor.Revision(0),
	)
	if !committed {
		_, _ = editor.buffer_close(&buffer)
		document.prepared_open_abort(&prepared_open)
		fmt.eprintf("document_evidence commit_failure bytes=%d code=%v\n", size, commit_failure.code)
		return false
	}

	setup_peak := tracking.peak_memory_allocated
	baseline := tracking.current_memory_allocated
	tracking.peak_memory_allocated = baseline
	started := time.tick_now()
	prepared_save: document.Prepared_Save
	prepared, prepare_failure := document.save_prepare(&doc, &buffer, &prepared_save)
	if !prepared {
		document.document_close(&doc)
		editor.buffer_close(&buffer)
		fmt.eprintf("document_evidence prepare_failure bytes=%d code=%v\n", size, prepare_failure.code)
		return false
	}
	result, saved, save_failure := document.prepared_save_publish(&prepared_save)
	elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
	if !saved {
		document.document_close(&doc)
		editor.buffer_close(&buffer)
		fmt.eprintf(
			"document_evidence save_failure bytes=%d code=%v publication=%v\n",
			size,
			save_failure.code,
			result.publication,
		)
		return false
	}
	file_info, stat_error := os.stat(path, context.temp_allocator)
	if stat_error != nil || u64(file_info.size) != size {
		document.document_close(&doc)
		editor.buffer_close(&buffer)
		fmt.eprintf("document_evidence size_mismatch expected=%d\n", size)
		return false
	}
	save_peak := tracking.peak_memory_allocated
	fmt.printf(
		"document_save bytes=%d elapsed_ns=%d baseline_bytes=%d save_peak_bytes=%d save_peak_extra_bytes=%d setup_peak_bytes=%d publication=%v\n",
		size,
		elapsed_ns,
		baseline,
		save_peak,
		save_peak - baseline,
		setup_peak,
		result.publication,
	)
	document_closed, _ := document.document_close(&doc)
	buffer_closed, _ := editor.buffer_close(&buffer)
	if !document_closed || !buffer_closed || tracking.current_memory_allocated != 0 {
		fmt.eprintf(
			"document_evidence cleanup_failure bytes=%d tracked=%d\n",
			size,
			tracking.current_memory_allocated,
		)
		return false
	}
	return true
}
