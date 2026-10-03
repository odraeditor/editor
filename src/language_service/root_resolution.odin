// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import document "../document"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"

/* Root_Resolution_Request borrows one trusted membership and service root policy. */
Root_Resolution_Request :: struct {
	membership_root: string,
	document_path:   string,
	explicit_root:   string,
	root_markers:    []string,
	limits:          Service_Limits,
}

/* Root_Resolution copies the one canonical root and the matching policy trace. */
Root_Resolution :: struct {
	root:           Service_Root_Text,
	matched_marker: Service_Root_Text,
	explicit:       bool,
}

/* root_resolution_text borrows the complete canonical resolved root. */
root_resolution_text :: proc(resolution: ^Root_Resolution) -> string {
	if resolution == nil || resolution.root.length == 0 do return ""
	return string(resolution.root.bytes[:resolution.root.length])
}

/* root_resolution_marker_text borrows the relative marker that selected the root. */
root_resolution_marker_text :: proc(resolution: ^Root_Resolution) -> string {
	if resolution == nil || resolution.matched_marker.length == 0 do return ""
	return string(resolution.matched_marker.bytes[:resolution.matched_marker.length])
}

/* service_root_resolve selects one canonical contained root without leaving membership. */
service_root_resolve :: proc(
	request: Root_Resolution_Request,
) -> (Root_Resolution, bool, Failure_Context) {
	if !service_limits_valid(request.limits) ||
	   !service_root_markers_valid(request.root_markers, request.limits) {
		return {}, false, Failure_Context{code = .Invalid_Definition, resource = .Root_Bytes}
	}
	membership_storage: document.Normalized_Path
	document_storage: document.Normalized_Path
	membership_ok, _ := document.path_normalize(
		request.membership_root,
		&membership_storage,
		context.temp_allocator,
	)
	document_ok, _ := document.path_normalize(
		request.document_path,
		&document_storage,
		context.temp_allocator,
	)
	membership := document.normalized_path_text(&membership_storage)
	document_path := document.normalized_path_text(&document_storage)
	if !membership_ok || !document_ok || !service_root_contains(membership, document_path) {
		return {}, false, Failure_Context{code = .Outside_Root}
	}
	if request.explicit_root != "" {
		explicit_storage: document.Normalized_Path
		explicit_ok, _ := document.path_normalize(
			request.explicit_root,
			&explicit_storage,
			context.temp_allocator,
		)
		explicit_root := document.normalized_path_text(&explicit_storage)
		if !explicit_ok || !service_root_contains(membership, explicit_root) ||
		   !service_root_contains(explicit_root, document_path) || !os.is_directory(explicit_root) {
			return {}, false, Failure_Context{code = .Outside_Root}
		}
		return Root_Resolution{
			root = service_root_resolution_text_copy(explicit_root),
			explicit = true,
		}, true, {}
	}
	current := filepath.dir(document_path)
	for {
		for marker in request.root_markers {
			candidate, join_error := filepath.join(
				[]string{current, marker},
				context.temp_allocator,
			)
			if join_error != nil do return {}, false, Failure_Context{code = .Allocation}
			info, stat_error := os.stat(candidate, context.temp_allocator)
			delete(candidate, context.temp_allocator)
			if stat_error == nil {
				os.file_info_delete(info, context.temp_allocator)
				return Root_Resolution{
					root = service_root_resolution_text_copy(current),
					matched_marker = service_root_resolution_text_copy(marker),
				}, true, {}
			}
		}
		if current == membership do break
		parent := filepath.dir(current)
		if parent == current || !service_root_contains(membership, parent) do break
		current = parent
	}
	return Root_Resolution{root = service_root_resolution_text_copy(membership)}, true, {}
}

/* service_root_contains applies the shared canonical process and document boundary. */
service_root_contains :: proc(root, candidate: string) -> bool {
	if root == "/" do return strings.has_prefix(candidate, "/")
	return candidate == root ||
		(len(candidate) > len(root) && strings.has_prefix(candidate, root) && candidate[len(root)] == '/')
}

/* service_root_markers_valid admits bounded relative, order-independent markers. */
service_root_markers_valid :: proc(markers: []string, limits: Service_Limits) -> bool {
	if len(markers) > MAX_ROOT_MARKERS do return false
	total_bytes: u64
	for marker, index in markers {
		if len(marker) == 0 || u64(len(marker)) > limits.root_bytes ||
		   !utf8.valid_string(marker) || strings.index_byte(marker, 0) >= 0 ||
		   marker[0] == '/' || marker[0] == '\\' ||
		   (len(marker) > 1 && marker[1] == ':') ||
		   strings.contains_any(marker, "*?[]{}\\") {
			return false
		}
		parts := strings.split(marker, "/", context.temp_allocator)
		parts_valid := true
		for part in parts {
			if len(part) == 0 || part == ".." {
				parts_valid = false
				break
			}
		}
		delete(parts, context.temp_allocator)
		if !parts_valid do return false
		total_bytes += u64(len(marker))
		for prior in 0 ..< index {
			if markers[prior] == marker do return false
		}
	}
	return total_bytes <= limits.root_bytes
}

@(private = "file")
service_root_resolution_text_copy :: proc(value: string) -> Service_Root_Text {
	result: Service_Root_Text
	if len(value) == 0 || len(value) > len(result.bytes) do return result
	result.length = u16(len(value))
	copy(result.bytes[:len(value)], transmute([]u8)value)
	return result
}
