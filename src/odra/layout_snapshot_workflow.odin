// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../document"
import "../editor_session"
import "../layout"
import "base:runtime"
import "core:encoding/base64"
import "core:strings"
import "core:unicode/utf8"

@(private)
PORTABLE_LAYOUT_HEADER :: "ODRA-LAYOUT-1"

@(private)
Portable_Layout_Node :: struct {
	kind:        layout.Node_Kind,
	arrangement: layout.Arrangement,
	target:      string,
	selected:    bool,
	dedication:  layout.Pane_Dedication,
}

@(private)
Portable_Layout_Snapshot :: struct {
	nodes:     [layout.MAX_SNAPSHOT_NODES]Portable_Layout_Node,
	entries:   [layout.MAX_SNAPSHOT_NODES]editor_session.Entry_Handle,
	node_count: int,
	allocator: runtime.Allocator,
}

@(private)
command_context_layout_snapshot_encode :: proc(commands: ^Command_Context) -> (string, bool) {
	if commands == nil || commands.session_owner == nil || !command_context_layout_is_live(commands) {
		return "", false
	}
	handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return "", false
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	if !snapshot_ok || snapshot.node_count == 0 do return "", false
	builder, allocation_error := strings.builder_make(commands.persistent_allocator)
	if allocation_error != nil do return "", false
	defer strings.builder_destroy(&builder)
	if strings.write_string(&builder, PORTABLE_LAYOUT_HEADER) != len(PORTABLE_LAYOUT_HEADER) do return "", false
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Partition {
			line := "\nP\tA" if node.arrangement == .Above_Below else "\nP\tL"
			if strings.write_string(&builder, line) != len(line) do return "", false
			continue
		}
		if node.kind != .Pane || !editor_session.entry_handle_is_valid(node.entry) do return "", false
		access, accessible, _ := editor_session.session_entry_access(commands.session_owner, node.entry)
		if !accessible do return "", false
		entry, borrowed, _ := editor_session.entry_access_borrow(access)
		if !borrowed do return "", false
		status, status_ok, _ := document.document_status(entry.document)
		if !status_ok || !status.has_target do return "", false
		encoded, encode_error := base64.encode(transmute([]u8)status.target_path, base64.ENC_TABLE, commands.persistent_allocator)
		if encode_error != nil do return "", false
		selected := '1' if node.active else '0'
		dedication := '0'
		if node.dedication == .Soft do dedication = '1'
		if node.dedication == .Hard do dedication = '2'
		ok := strings.write_string(&builder, "\nV\t") == 3 &&
		      strings.write_byte(&builder, byte(selected)) == 1 &&
		      strings.write_byte(&builder, '\t') == 1 &&
		      strings.write_byte(&builder, byte(dedication)) == 1 &&
		      strings.write_byte(&builder, '\t') == 1 &&
		      strings.write_string(&builder, encoded) == len(encoded)
		delete(encoded, commands.persistent_allocator)
		if !ok do return "", false
	}
	value, clone_error := strings.clone(strings.to_string(builder), commands.persistent_allocator)
	if clone_error != nil do return "", false
	return value, true
}

@(private)
command_context_layout_snapshot_restore :: proc(commands: ^Command_Context, value: string) -> (restored, complete: bool) {
	if commands == nil || commands.session_owner == nil || !command_context_layout_is_live(commands) do return false, false
	snapshot, decoded := portable_layout_decode(value, commands.persistent_allocator)
	if !decoded do return false, false
	defer portable_layout_snapshot_close(&snapshot)
	selected_entry: editor_session.Entry_Handle
	for index in 0 ..< snapshot.node_count {
		node := &snapshot.nodes[index]
		if node.kind != .Pane do continue
		if !named_location_target_is_available(node.target) do return false, false
		opened, opened_ok, _ := editor_session.session_open_path(
			commands.session_owner,
			editor_session.Open_Path_Request {
				session = commands.session_handle,
				path = node.target,
				encoding = .UTF8,
				configuration = commands.entry_configuration,
			},
		)
		if !opened_ok do return false, false
		snapshot.entries[index] = opened.entry
		if node.selected do selected_entry = opened.entry
	}
	if !editor_session.entry_handle_is_valid(selected_entry) do return false, false
	handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return false, false
	current, current_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	if !current_ok do return false, false
	active, active_ok := command_context_layout_active_node(&current)
	if !active_ok do return false, false
	kept, kept_ok, _ := layout.registry_keep_only(&commands.layout_registry, active.pane)
	if !kept_ok do return false, false
	selected_pane := layout.Pane_ID(0)
	complete = true
	next, applied := portable_layout_restore_node(
		commands, &snapshot, 0, kept.active.pane_id, &selected_pane, &complete,
	)
	if !applied || next != snapshot.node_count || selected_pane == layout.Pane_ID(0) do return false, complete
	selected_handle, selected_ok := portable_layout_current_pane(commands, selected_pane)
	if !selected_ok do return false, complete
	_, focused, _ := layout.registry_focus(&commands.layout_registry, selected_handle)
	if !focused do return false, complete
	_, activated, _ := editor_session.session_activate(commands.session_owner, selected_entry)
	if !activated do return false, complete
	commands.layout_entry = selected_entry
	return true, complete
}

@(private)
portable_layout_restore_node :: proc(
	commands: ^Command_Context,
	snapshot: ^Portable_Layout_Snapshot,
	index: int,
	pane_id: layout.Pane_ID,
	selected_pane: ^layout.Pane_ID,
	complete: ^bool,
) -> (next: int, ok: bool) {
	if index < 0 || index >= snapshot.node_count do return index, false
	node := snapshot.nodes[index]
	if node.kind == .Pane {
		pane, pane_ok := portable_layout_current_pane(commands, pane_id)
		if !pane_ok do return index, false
		dedication, cleared, _ := layout.registry_pane_dedication_set(&commands.layout_registry, pane, .None)
		if !cleared do return index, false
		replaced, replaced_ok, _ := layout.registry_replace_pane_buffer(
			&commands.layout_registry, dedication.pane, commands.session_owner, snapshot.entries[index],
		)
		if !replaced_ok do return index, false
		_, dedicated, _ := layout.registry_pane_dedication_set(
			&commands.layout_registry, replaced.pane, node.dedication,
		)
		if !dedicated do return index, false
		if node.selected do selected_pane^ = pane_id
		return index + 1, true
	}
	pane, pane_ok := portable_layout_current_pane(commands, pane_id)
	if !pane_ok do return index, false
	_, focused, _ := layout.registry_focus(&commands.layout_registry, pane)
	if !focused do return index, false
	current, current_ok := portable_layout_current_pane(commands, pane_id)
	if !current_ok do return index, false
	split: layout.Split_Result
	split_ok: bool
	if node.arrangement == .Above_Below {
		split, split_ok, _ = layout.registry_split_below(&commands.layout_registry, current)
	} else {
		split, split_ok, _ = layout.registry_split_right(&commands.layout_registry, current)
	}
	if !split_ok {
		complete^ = false
		selected_index, selected_found := portable_layout_subtree_selected(snapshot, index)
		fallback_index := selected_index if selected_found else index + 1
		_, fallback_ok := portable_layout_restore_node(
			commands, snapshot, fallback_index, pane_id, selected_pane, complete,
		)
		if !fallback_ok do return index, false
		after, valid := portable_layout_subtree_end(snapshot, index, 0)
		return after, valid
	}
	after_first, first_ok := portable_layout_restore_node(
		commands, snapshot, index + 1, split.original.pane_id, selected_pane, complete,
	)
	if !first_ok do return index, false
	after_second, second_ok := portable_layout_restore_node(
		commands, snapshot, after_first, split.created.pane_id, selected_pane, complete,
	)
	return after_second, second_ok
}

@(private)
portable_layout_current_pane :: proc(commands: ^Command_Context, pane_id: layout.Pane_ID) -> (layout.Pane_Handle, bool) {
	handle, handle_ok, _ := layout.registry_handle(&commands.layout_registry)
	if !handle_ok do return {}, false
	snapshot, snapshot_ok, _ := layout.registry_snapshot(&commands.layout_registry, handle)
	if !snapshot_ok do return {}, false
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.pane.pane_id == pane_id do return node.pane, true
	}
	return {}, false
}

@(private)
portable_layout_decode :: proc(value: string, allocator: runtime.Allocator) -> (snapshot: Portable_Layout_Snapshot, ok: bool) {
	if allocator.procedure == nil do return {}, false
	snapshot.allocator = allocator
	offset := 0
	header, header_ok := portable_layout_next_line(value, &offset)
	if !header_ok || header != PORTABLE_LAYOUT_HEADER do return {}, false
	for offset <= len(value) {
		line, line_ok := portable_layout_next_line(value, &offset)
		if !line_ok || len(line) == 0 || snapshot.node_count >= layout.MAX_SNAPSHOT_NODES {
			portable_layout_snapshot_close(&snapshot)
			return {}, false
		}
		node := &snapshot.nodes[snapshot.node_count]
		if line == "P\tA" {
			node.kind = .Partition
			node.arrangement = .Above_Below
		} else if line == "P\tL" {
			node.kind = .Partition
			node.arrangement = .Left_Right
		} else if len(line) >= 7 && line[0] == 'V' && line[1] == '\t' &&
		          (line[2] == '0' || line[2] == '1') && line[3] == '\t' &&
		          (line[4] >= '0' && line[4] <= '2') && line[5] == '\t' {
			decoded, decode_error := base64.decode(line[6:], base64.DEC_TABLE, nil, allocator)
			if decode_error != nil || len(decoded) == 0 || !utf8.valid_string(string(decoded)) {
				if decoded != nil do delete(decoded, allocator)
				portable_layout_snapshot_close(&snapshot)
				return {}, false
			}
			node.kind = .Pane
			node.target = string(decoded)
			node.selected = line[2] == '1'
			node.dedication = layout.Pane_Dedication(int(line[4] - '0') + int(layout.Pane_Dedication.None))
		} else {
			portable_layout_snapshot_close(&snapshot)
			return {}, false
		}
		snapshot.node_count += 1
		if offset == len(value) do break
	}
	if snapshot.node_count == 0 {
		portable_layout_snapshot_close(&snapshot)
		return {}, false
	}
	end, topology_ok := portable_layout_subtree_end(&snapshot, 0, 0)
	selected_count := 0
	for index in 0 ..< snapshot.node_count {
		if snapshot.nodes[index].selected do selected_count += 1
	}
	if !topology_ok || end != snapshot.node_count || selected_count != 1 {
		portable_layout_snapshot_close(&snapshot)
		return {}, false
	}
	return snapshot, true
}

@(private)
portable_layout_next_line :: proc(value: string, offset: ^int) -> (string, bool) {
	if offset == nil || offset^ < 0 || offset^ > len(value) do return "", false
	start := offset^
	end := start
	for end < len(value) && value[end] != '\n' do end += 1
	offset^ = end + 1 if end < len(value) else end
	return value[start:end], true
}

@(private)
portable_layout_subtree_end :: proc(snapshot: ^Portable_Layout_Snapshot, index, depth: int) -> (int, bool) {
	if snapshot == nil || index < 0 || index >= snapshot.node_count || depth > layout.MAX_PARTITION_DEPTH {
		return index, false
	}
	if snapshot.nodes[index].kind == .Pane do return index + 1, true
	if snapshot.nodes[index].kind != .Partition do return index, false
	after_first, first_ok := portable_layout_subtree_end(snapshot, index + 1, depth + 1)
	if !first_ok do return index, false
	return portable_layout_subtree_end(snapshot, after_first, depth + 1)
}

@(private)
portable_layout_subtree_selected :: proc(snapshot: ^Portable_Layout_Snapshot, index: int) -> (int, bool) {
	end, valid := portable_layout_subtree_end(snapshot, index, 0)
	if !valid do return 0, false
	for candidate in index ..< end {
		if snapshot.nodes[candidate].kind == .Pane && snapshot.nodes[candidate].selected {
			return candidate, true
		}
	}
	return 0, false
}

@(private)
portable_layout_snapshot_close :: proc(snapshot: ^Portable_Layout_Snapshot) {
	if snapshot == nil do return
	for index in 0 ..< snapshot.node_count {
		if len(snapshot.nodes[index].target) > 0 do delete(snapshot.nodes[index].target, snapshot.allocator)
	}
	snapshot^ = {}
}
