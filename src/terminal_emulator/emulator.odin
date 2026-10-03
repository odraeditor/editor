// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_emulator

/* open creates one generation-checked foreign terminal owner. */
open :: proc(options := DEFAULT_OPTIONS) -> (ref: Ref, result: Result) {
	owned_options := options
	result = odra_terminal_emulator_open(&owned_options, &ref)
	return
}

/* close releases one live foreign terminal owner exactly once. */
close :: proc(ref: Ref) -> Result {
	return odra_terminal_emulator_close(ref)
}

/* write applies untrusted VT bytes to one live terminal owner. */
write :: proc(ref: Ref, bytes: []u8) -> Result {
	return odra_terminal_emulator_write(ref, raw_data(bytes), uintptr(len(bytes)))
}

/* resize changes terminal cell and pixel geometry. */
resize :: proc(
	ref: Ref,
	columns, rows: u16,
	cell_width_pixels, cell_height_pixels: u32,
) -> Result {
	return odra_terminal_emulator_resize(
		ref, columns, rows, cell_width_pixels, cell_height_pixels)
}

/* render returns a copied render summary without exposing foreign pointers. */
render :: proc(ref: Ref) -> (state: Render_State, result: Result) {
	result = odra_terminal_emulator_render(ref, &state)
	return
}

/* project copies dirty visible rows, cells, colors, cursor, and damage metadata. */
project :: proc(
	ref: Ref,
	rows: []Projected_Row,
	cells: []Projected_Cell,
) -> (projection: Projection, result: Result) {
	result = odra_terminal_emulator_project(
		ref,
		&projection,
		raw_data(rows),
		uintptr(len(rows)),
		raw_data(cells),
		uintptr(len(cells)),
	)
	return
}

/* scroll_state returns copied scrollback, viewport, and compression scheduling state. */
scroll_state :: proc(ref: Ref) -> (state: Scroll_State, result: Result) {
	result = odra_terminal_emulator_scroll_state(ref, &state)
	return
}

/* semantic_state returns copied primary-screen cursor and shell integration state. */
semantic_state :: proc(ref: Ref) -> (state: Semantic_State, result: Result) {
	result = odra_terminal_emulator_semantic_state(ref, &state)
	return
}

/* mouse_state returns copied negotiated child mouse-reporting state. */
mouse_state :: proc(ref: Ref) -> (state: Mouse_State, result: Result) {
	result = odra_terminal_emulator_mouse_state(ref, &state)
	return
}

/* hyperlink_at copies the link target at one viewport cell. */
hyperlink_at :: proc(
	ref: Ref,
	column: u16,
	row: u32,
	output: []u8,
) -> (written: int, result: Result) {
	foreign_written: uintptr
	result = odra_terminal_emulator_hyperlink_at(
		ref, column, row, raw_data(output), uintptr(len(output)), &foreign_written,
	)
	if foreign_written <= uintptr(max(int)) do written = int(foreign_written)
	return
}

/* semantic_anchor_open tracks the current primary-screen cursor across reflow and eviction. */
semantic_anchor_open :: proc(ref: Ref) -> (anchor: Semantic_Anchor, result: Result) {
	result = odra_terminal_emulator_semantic_anchor_open(ref, &anchor)
	return
}

/* semantic_anchor_resolve copies the anchor's current full-screen coordinate. */
semantic_anchor_resolve :: proc(
	ref: Ref,
	anchor: Semantic_Anchor,
) -> (row: u64, column: u16, result: Result) {
	result = odra_terminal_emulator_semantic_anchor_resolve(ref, anchor, &row, &column)
	return
}

/* semantic_anchor_close releases one tracked position exactly once. */
semantic_anchor_close :: proc(ref: Ref, anchor: Semantic_Anchor) -> Result {
	return odra_terminal_emulator_semantic_anchor_close(ref, anchor)
}

/* scroll changes the visible viewport without exposing terminal pointers. */
scroll :: proc(ref: Ref, behavior: Scroll, value: i64 = 0) -> Result {
	return odra_terminal_emulator_scroll(ref, behavior, value)
}

/* compress performs one incremental scrollback compression step. */
compress :: proc(ref: Ref) -> (pending, supported: bool, result: Result) {
	result = odra_terminal_emulator_compress(ref, &pending, &supported)
	return
}

/* format_text copies or sizes one plain-text screen, viewport, or absolute range. */
format_text :: proc(
	ref: Ref,
	request: Text_Request,
	output: []u8,
) -> (written: int, result: Result) {
	foreign_written: uintptr
	owned_request := request
	result = odra_terminal_emulator_format_text(
		ref,
		&owned_request,
		raw_data(output),
		uintptr(len(output)),
		&foreign_written,
	)
	if foreign_written <= uintptr(max(int)) do written = int(foreign_written)
	return
}

/* format_text_bounded copies a prefix and reports the complete required size. */
format_text_bounded :: proc(
	ref: Ref,
	request: Text_Request,
	output: []u8,
) -> (copied, required: int, result: Result) {
	foreign_copied, foreign_required: uintptr
	owned_request := request
	result = odra_terminal_emulator_format_text_bounded(
		ref,
		&owned_request,
		raw_data(output),
		uintptr(len(output)),
		&foreign_copied,
		&foreign_required,
	)
	if foreign_copied <= uintptr(max(int)) do copied = int(foreign_copied)
	if foreign_required <= uintptr(max(int)) do required = int(foreign_required)
	return
}

/* encode_key translates one logical key into terminal input bytes. */
encode_key :: proc(
	ref: Ref,
	key: Key,
	action: Key_Action,
	modifiers: bit_set[Modifier; u32],
	text: []u8,
	output: []u8,
) -> (written: int, result: Result) {
	foreign_written: uintptr
	result = odra_terminal_emulator_encode_key(
		ref,
		key,
		action,
		transmute(u32)modifiers,
		raw_data(text),
		uintptr(len(text)),
		raw_data(output),
		uintptr(len(output)),
		&foreign_written,
	)
	if foreign_written <= uintptr(max(int)) {
		written = int(foreign_written)
	}
	return
}

/* encode_paste validates and frames mutable text for the terminal's current mode. */
encode_paste :: proc(
	ref: Ref,
	text: []u8,
	allow_unsafe: bool,
	output: []u8,
) -> (written: int, bracketed: bool, result: Result) {
	foreign_written: uintptr
	result = odra_terminal_emulator_encode_paste(
		ref,
		raw_data(text),
		uintptr(len(text)),
		allow_unsafe,
		raw_data(output),
		uintptr(len(output)),
		&foreign_written,
		&bracketed,
	)
	if foreign_written <= uintptr(max(int)) do written = int(foreign_written)
	return
}

/* encode_focus emits a report only when the child enabled focus reporting. */
encode_focus :: proc(
	ref: Ref,
	event: Focus_Event,
	output: []u8,
) -> (written: int, enabled: bool, result: Result) {
	foreign_written: uintptr
	result = odra_terminal_emulator_encode_focus(
		ref,
		event,
		raw_data(output),
		uintptr(len(output)),
		&foreign_written,
		&enabled,
	)
	if foreign_written <= uintptr(max(int)) do written = int(foreign_written)
	return
}

/* encode_mouse translates one logical mouse event into terminal input bytes. */
encode_mouse :: proc(
	ref: Ref,
	action: Mouse_Action,
	button: Mouse_Button,
	modifiers: bit_set[Modifier; u32],
	x, y: f32,
	output: []u8,
) -> (written: int, result: Result) {
	foreign_written: uintptr
	result = odra_terminal_emulator_encode_mouse(
		ref,
		action,
		button,
		transmute(u32)modifiers,
		x,
		y,
		raw_data(output),
		uintptr(len(output)),
		&foreign_written,
	)
	if foreign_written <= uintptr(max(int)) {
		written = int(foreign_written)
	}
	return
}

/* select_all copies all selectable terminal text into caller storage. */
select_all :: proc(ref: Ref, output: []u8) -> (written: int, result: Result) {
	foreign_written: uintptr
	result = odra_terminal_emulator_select_all(
		ref, raw_data(output), uintptr(len(output)), &foreign_written)
	if foreign_written <= uintptr(max(int)) {
		written = int(foreign_written)
	}
	return
}

/* snapshot copies a restorable terminal snapshot into caller storage. */
snapshot :: proc(ref: Ref, output: []u8) -> (written: int, result: Result) {
	foreign_written: uintptr
	result = odra_terminal_emulator_snapshot(
		ref, raw_data(output), uintptr(len(output)), &foreign_written)
	if foreign_written <= uintptr(max(int)) {
		written = int(foreign_written)
	}
	return
}

/* effects returns copied effect accounting for one live terminal owner. */
effects :: proc(ref: Ref) -> (value: Effects, result: Result) {
	result = odra_terminal_emulator_effects(ref, &value)
	return
}

/* title_copy copies bounded non-executable terminal title metadata. */
title_copy :: proc(ref: Ref, output: []u8) -> (copy: Metadata_Copy, result: Result) {
	copied, required: uintptr
	result = odra_terminal_emulator_title_copy(
		ref, raw_data(output), uintptr(len(output)), &copied, &required,
	)
	copy.copied_bytes = u64(copied)
	copy.required_bytes = u64(required)
	copy.truncated = copied < required
	return
}

/* pwd_copy copies bounded untrusted working-context metadata. */
pwd_copy :: proc(ref: Ref, output: []u8) -> (copy: Metadata_Copy, result: Result) {
	copied, required: uintptr
	result = odra_terminal_emulator_pwd_copy(
		ref, raw_data(output), uintptr(len(output)), &copied, &required,
	)
	copy.copied_bytes = u64(copied)
	copy.required_bytes = u64(required)
	copy.truncated = copied < required
	return
}

/* writeback_copy copies queued terminal responses without consuming them. */
writeback_copy :: proc(
	ref: Ref,
	output: []u8,
) -> (written, pending: int, result: Result) {
	foreign_written, foreign_pending: uintptr
	result = odra_terminal_emulator_writeback_copy(
		ref,
		raw_data(output),
		uintptr(len(output)),
		&foreign_written,
		&foreign_pending,
	)
	if foreign_written <= uintptr(max(int)) do written = int(foreign_written)
	if foreign_pending <= uintptr(max(int)) do pending = int(foreign_pending)
	return
}

/* writeback_consume releases bytes copied and accepted by the process queue. */
writeback_consume :: proc(ref: Ref, length: int) -> Result {
	if length < 0 do return .Invalid_Argument
	return odra_terminal_emulator_writeback_consume(ref, uintptr(length))
}

/* image_generation returns the terminal image-storage revision. */
image_generation :: proc(ref: Ref) -> (generation: u64, result: Result) {
	result = odra_terminal_emulator_image_generation(ref, &generation)
	return
}

/* project_images copies bounded visible Kitty image placement metadata. */
project_images :: proc(
	ref: Ref,
	output: []Image_Placement,
) -> (projection: Image_Projection, result: Result) {
	count: uintptr
	result = odra_terminal_emulator_project_images(
		ref,
		raw_data(output),
		uintptr(len(output)),
		&count,
		&projection.generation,
		&projection.decoded_bytes,
		&projection.truncated,
	)
	projection.count = u64(count)
	return
}

/* supports reports one adapter-owned capability without exposing vendor enums. */
supports :: proc(feature: Feature) -> (supported: bool, result: Result) {
	result = odra_terminal_emulator_feature(feature, &supported)
	return
}

/* stats returns copied lifecycle and foreign-allocation accounting. */
stats :: proc(ref: Ref) -> (value: Stats, result: Result) {
	result = odra_terminal_emulator_stats(ref, &value)
	return
}
