// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_emulator

@(private)
ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY :: #config(
	ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY,
	"../../.build/terminal-emulator/libodra-terminal-emulator-adapter.a",
)

@(private)
ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY :: #config(
	ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY,
	"../../.build/terminal-vendor/install/lib/libghostty-vt.a",
)

foreign import terminal_emulator_adapter {
	ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY,
	ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY,
	"system:m",
}

@(private, default_calling_convention="c")
foreign terminal_emulator_adapter {
	odra_terminal_emulator_open :: proc(options: ^Options, out_ref: ^Ref) -> Result ---
	odra_terminal_emulator_close :: proc(ref: Ref) -> Result ---
	odra_terminal_emulator_write :: proc(ref: Ref, bytes: ^u8, length: uintptr) -> Result ---
	odra_terminal_emulator_resize :: proc(
		ref: Ref,
		columns, rows: u16,
		cell_width_pixels, cell_height_pixels: u32,
	) -> Result ---
	odra_terminal_emulator_render :: proc(ref: Ref, out_state: ^Render_State) -> Result ---
	odra_terminal_emulator_project :: proc(
		ref: Ref,
		out_projection: ^Projection,
		rows: ^Projected_Row,
		row_capacity: uintptr,
		cells: ^Projected_Cell,
		cell_capacity: uintptr,
	) -> Result ---
	odra_terminal_emulator_scroll_state :: proc(ref: Ref, out_state: ^Scroll_State) -> Result ---
	odra_terminal_emulator_semantic_state :: proc(ref: Ref, out_state: ^Semantic_State) -> Result ---
	odra_terminal_emulator_mouse_state :: proc(ref: Ref, out_state: ^Mouse_State) -> Result ---
	odra_terminal_emulator_hyperlink_at :: proc(
		ref: Ref,
		column: u16,
		row: u32,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_semantic_anchor_open :: proc(ref: Ref, out_anchor: ^Semantic_Anchor) -> Result ---
	odra_terminal_emulator_semantic_anchor_resolve :: proc(
		ref: Ref,
		anchor: Semantic_Anchor,
		out_row: ^u64,
		out_column: ^u16,
	) -> Result ---
	odra_terminal_emulator_semantic_anchor_close :: proc(ref: Ref, anchor: Semantic_Anchor) -> Result ---
	odra_terminal_emulator_scroll :: proc(ref: Ref, behavior: Scroll, value: i64) -> Result ---
	odra_terminal_emulator_compress :: proc(
		ref: Ref,
		out_pending: ^bool,
		out_supported: ^bool,
	) -> Result ---
	odra_terminal_emulator_format_text :: proc(
		ref: Ref,
		request: ^Text_Request,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_format_text_bounded :: proc(
		ref: Ref,
		request: ^Text_Request,
		output: ^u8,
		output_capacity: uintptr,
		out_copied: ^uintptr,
		out_required: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_encode_key :: proc(
		ref: Ref,
		key: Key,
		action: Key_Action,
		modifiers: u32,
		text: ^u8,
		text_length: uintptr,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_encode_focus :: proc(
		ref: Ref,
		event: Focus_Event,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
		out_enabled: ^bool,
	) -> Result ---
	odra_terminal_emulator_encode_paste :: proc(
		ref: Ref,
		text: ^u8,
		text_length: uintptr,
		allow_unsafe: bool,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
		out_bracketed: ^bool,
	) -> Result ---
	odra_terminal_emulator_encode_mouse :: proc(
		ref: Ref,
		action: Mouse_Action,
		button: Mouse_Button,
		modifiers: u32,
		x, y: f32,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_select_all :: proc(
		ref: Ref,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_snapshot :: proc(
		ref: Ref,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_effects :: proc(ref: Ref, out_effects: ^Effects) -> Result ---
	odra_terminal_emulator_title_copy :: proc(
		ref: Ref,
		output: ^u8,
		output_capacity: uintptr,
		out_copied: ^uintptr,
		out_required: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_pwd_copy :: proc(
		ref: Ref,
		output: ^u8,
		output_capacity: uintptr,
		out_copied: ^uintptr,
		out_required: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_writeback_copy :: proc(
		ref: Ref,
		output: ^u8,
		output_capacity: uintptr,
		out_written: ^uintptr,
		out_pending: ^uintptr,
	) -> Result ---
	odra_terminal_emulator_writeback_consume :: proc(ref: Ref, length: uintptr) -> Result ---
	odra_terminal_emulator_image_generation :: proc(ref: Ref, out_generation: ^u64) -> Result ---
	odra_terminal_emulator_project_images :: proc(
		ref: Ref,
		output: ^Image_Placement,
		output_capacity: uintptr,
		out_count: ^uintptr,
		out_generation: ^u64,
		out_decoded_bytes: ^u64,
		out_truncated: ^bool,
	) -> Result ---
	odra_terminal_emulator_feature :: proc(feature: Feature, out_supported: ^bool) -> Result ---
	odra_terminal_emulator_stats :: proc(ref: Ref, out_stats: ^Stats) -> Result ---
}
