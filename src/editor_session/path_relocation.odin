// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package editor_session

import "../document"
import "base:runtime"
import "core:strings"

@(private)
Path_Relocation_Entry :: struct {
	slot_index: int,
	label:      string,
	path:       string,
	document:   document.Prepared_Relocation,
}

/* session_document_paths_under counts associated documents at or below one normalized path. */
session_document_paths_under :: proc(
	session: ^Session,
	handle: Session_Handle,
	path: string,
	directory: bool,
) -> (u32, bool, Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Inspect)
	if resolved_failure.code != .None do return 0, false, resolved_failure
	normalized: document.Normalized_Path
	if normalized_ok, normalized_failure := document.path_normalize(
		path, &normalized, data.temporary_allocator,
	); !normalized_ok {
		failure := session_failure(data, .Inspect, .Invalid_Path)
		failure.document_failure = normalized_failure
		return 0, false, failure
	}
	target := document.normalized_path_text(&normalized)
	count: u32
	for &slot in data.slots {
		if slot.live && slot.owner != nil && slot.owner.document_live &&
		   path_relocation_matches(slot.owner.normalized_path, target, directory) {
			count += 1
		}
	}
	return count, true, {}
}

/* session_relocate_document_paths atomically updates associated paths after a checked move. */
session_relocate_document_paths :: proc(
	session: ^Session,
	handle: Session_Handle,
	request: Path_Relocation_Request,
) -> (Path_Relocation_Result, bool, Failure_Context) {
	data, resolved_failure := resolve_session(session, handle, .Relocate_Paths)
	if resolved_failure.code != .None do return {}, false, resolved_failure
	from: document.Normalized_Path
	to: document.Normalized_Path
	from_ok, from_failure := document.path_normalize(request.from, &from, data.temporary_allocator)
	to_ok, to_failure := document.path_normalize(request.to, &to, data.temporary_allocator)
	if !from_ok || !to_ok {
		failure := session_failure(data, .Relocate_Paths, .Invalid_Path)
		failure.document_failure = from_failure if !from_ok else to_failure
		return {}, false, failure
	}
	from_path := document.normalized_path_text(&from)
	to_path := document.normalized_path_text(&to)
	if from_path == to_path do return {}, false, session_failure(data, .Relocate_Paths, .Invalid_Path)
	entries, allocation_error := make(
		[]Path_Relocation_Entry, int(data.usage.live_documents), data.temporary_allocator,
	)
	if allocation_error != nil {
		return {}, false, session_failure(data, .Relocate_Paths, .Temporary_Memory_Limit)
	}
	defer delete(entries, data.temporary_allocator)
	count := 0
	projected_labels := data.usage.retained_label_bytes
	for &slot, slot_index in data.slots {
		if !slot.live || slot.owner == nil || !slot.owner.document_live do continue
		old_path := slot.owner.normalized_path
		if !path_relocation_matches(old_path, from_path, request.directory) do continue
		suffix := old_path[len(from_path):]
		if len(to_path) + len(suffix) > int(document.MAX_PATH_BYTES) {
			path_relocation_abort(entries[:count], data.allocator)
			return {}, false, session_failure(data, .Relocate_Paths, .Invalid_Path)
		}
		storage: [int(document.MAX_PATH_BYTES)]u8
		length := copy(storage[:], transmute([]u8)to_path)
		length += copy(storage[length:], transmute([]u8)suffix)
		new_path := string(storage[:length])
		if encoded := data.path_index[new_path]; encoded != 0 && encoded != slot_index + 1 {
			path_relocation_abort(entries[:count], data.allocator)
			return {}, false, session_failure(data, .Relocate_Paths, .Path_Collision)
		}
		old_bytes := slot.owner.reservation.label_bytes
		new_bytes := u64(len(new_path) * 2)
		projected_labels = projected_labels - old_bytes + new_bytes
		if projected_labels > data.policy.retained_label_bytes {
			path_relocation_abort(entries[:count], data.allocator)
			return {}, false, session_failure(data, .Relocate_Paths, .Retained_Label_Limit)
		}
		label, label_error := strings.clone(new_path, data.allocator)
		if label_error != nil {
			path_relocation_abort(entries[:count], data.allocator)
			return {}, false, session_failure(data, .Relocate_Paths, .Persistent_Memory_Limit)
		}
		path, path_error := strings.clone(new_path, data.allocator)
		if path_error != nil {
			delete(label, data.allocator)
			path_relocation_abort(entries[:count], data.allocator)
			return {}, false, session_failure(data, .Relocate_Paths, .Persistent_Memory_Limit)
		}
		prepared: document.Prepared_Relocation
		prepared_ok, prepare_failure := document.document_relocation_prepare(
			&slot.owner.document, old_path, new_path, &prepared,
			{persistent = data.allocator, temporary = data.temporary_allocator},
		)
		if !prepared_ok {
			delete(path, data.allocator)
			delete(label, data.allocator)
			path_relocation_abort(entries[:count], data.allocator)
			failure := session_failure(data, .Relocate_Paths, .Document_Failure)
			failure.document_failure = prepare_failure
			return {}, false, failure
		}
		entries[count] = {
			slot_index = slot_index,
			label = label,
			path = path,
			document = prepared,
		}
		count += 1
	}
	for &entry in entries[:count] {
		slot := &data.slots[entry.slot_index]
		owner := slot.owner
		old_label_bytes := owner.reservation.label_bytes
		new_label_bytes := u64(len(entry.path) * 2)
		delete_key(&data.label_index, string(owner.selection_label))
		delete_key(&data.path_index, string(owner.normalized_path))
		published, publish_failure := document.prepared_relocation_publish(&entry.document)
		assert(published && publish_failure.code == .None)
		delete(owner.selection_label, data.allocator)
		delete(owner.normalized_path, data.allocator)
		owner.selection_label = entry.label
		owner.normalized_path = entry.path
		entry.label = ""
		entry.path = ""
		data.label_index[string(owner.selection_label)] = entry.slot_index + 1
		data.path_index[string(owner.normalized_path)] = entry.slot_index + 1
		data.usage.registry_bytes = data.usage.registry_bytes - old_label_bytes + new_label_bytes
		owner.reservation.registry_bytes = owner.reservation.registry_bytes - old_label_bytes + new_label_bytes
		owner.reservation.label_bytes = new_label_bytes
	}
	data.usage.retained_label_bytes = projected_labels
	assert(session_validate(data))
	return Path_Relocation_Result{relocated = u32(count)}, true, {}
}

@(private)
path_relocation_matches :: proc(path, from: string, directory: bool) -> bool {
	if path == from do return true
	return directory && len(path) > len(from) && strings.has_prefix(path, from) &&
		path[len(from)] == '/'
}

@(private)
path_relocation_abort :: proc(entries: []Path_Relocation_Entry, allocator: runtime.Allocator) {
	for &entry in entries {
		if entry.document.state != nil do _, _ = document.prepared_relocation_abort(&entry.document)
		if len(entry.path) > 0 do delete(entry.path, allocator)
		if len(entry.label) > 0 do delete(entry.label, allocator)
	}
}
