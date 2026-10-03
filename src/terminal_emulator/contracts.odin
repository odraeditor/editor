// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package terminal_emulator owns the private terminal-emulation boundary.
package terminal_emulator

/* WRITEBACK_CAPACITY is the immutable terminal-originated response queue bound. */
WRITEBACK_CAPACITY :: 64 * 1_024
/* CELL_TEXT_BYTES bounds one copied visible grapheme cluster. */
CELL_TEXT_BYTES :: 64
/* SEMANTIC_ANCHOR_CAPACITY bounds tracked semantic positions per terminal. */
SEMANTIC_ANCHOR_CAPACITY :: 128
/* METADATA_BYTES is the immutable copied title and working-context ceiling. */
METADATA_BYTES :: 16 * 1_024
/* UNKNOWN_CAPTURE_BYTES bounds one retained unsupported-sequence diagnostic. */
UNKNOWN_CAPTURE_BYTES :: 4 * 1_024
/* CLIPBOARD_WRITE_BYTES bounds one denied decoded child clipboard transaction. */
CLIPBOARD_WRITE_BYTES :: 64 * 1_024
IMAGE_PLACEMENTS :: 8
IMAGE_ENCODED_BYTES :: 8 * 1_024 * 1_024
IMAGE_DECODED_BYTES :: 16 * 1_024 * 1_024
IMAGE_STORAGE_BYTES :: 32 * 1_024 * 1_024

/* Result is the stable outcome vocabulary for terminal-emulator operations. */
Result :: enum i32 {
	OK = 0,
	Invalid_Argument,
	Unavailable,
	Stale_Handle,
	Allocation_Failed,
	Buffer_Too_Small,
	Unsupported,
	Foreign_Failure,
	Rejected,
}

/* Feature identifies one capability admitted through the private adapter. */
Feature :: enum i32 {
	Invalid = 0,
	Key_Encoding,
	Mouse_Encoding,
	Selection,
	Snapshot,
	Kitty_Graphics,
	Tmux_Control_Mode,
	SIMD,
}

/* Key is the adapter-owned logical key vocabulary. */
Key :: enum i32 {
	Character = 1,
	Enter,
	Arrow_Up,
	Arrow_Down,
	Arrow_Left,
	Arrow_Right,
	Tab,
	Backspace,
	Delete,
	Escape,
	Home,
	End,
	Page_Up,
	Page_Down,
	Space,
}

Key_Action :: enum i32 {
	Press = 0,
	Repeat,
}

Focus_Event :: enum i32 {
	Gained = 0,
	Lost,
}

/* Mouse_Action is the adapter-owned mouse transition vocabulary. */
Mouse_Action :: enum i32 {
	Press = 0,
	Release,
	Motion,
}

/* Mouse_Button is the adapter-owned mouse button vocabulary. */
Mouse_Button :: enum i32 {
	None = -1,
	Left = 0,
	Right,
	Middle,
	Wheel_Up,
	Wheel_Down,
}

Modifier :: enum u32 {
	Shift = 0,
	Control,
	Alt,
	Super,
}

/* Ref identifies one exact generation of a foreign terminal owner. */
Ref :: struct {
	slot:       u32,
	generation: u32,
}

/* Semantic_Anchor identifies one generation-checked tracked terminal position. */
Semantic_Anchor :: struct {
	slot:       u32,
	generation: u32,
}

/* Options defines the initial geometry and an optional fault-injection point. */
Options :: struct {
	columns:                 u16,
	rows:                    u16,
	cell_width_pixels:       u32,
	cell_height_pixels:      u32,
	allocation_fail_after:   u64,
	scrollback_max_bytes:    u64,
	scrollback_max_lines:    u64,
}

Scroll :: enum i32 {
	Top = 0,
	Bottom,
	Delta,
	Row,
}

Text_Scope :: enum i32 {
	Screen = 0,
	Viewport,
	Screen_Range,
	History_Range,
}

Scroll_State :: struct {
	total_rows:           u64,
	scrollback_rows:      u64,
	viewport_offset:      u64,
	viewport_rows:        u64,
	scrollback_max_bytes: u64,
	scrollback_max_lines: u64,
	compression_activity: u64,
	viewport_active:      bool,
}

/* Semantic_State is copied shell-integration state without foreign pointers. */
Semantic_State :: struct {
	cursor_column:  u16,
	cursor_row:     u64,
	alternate_screen: bool,
	cursor_at_prompt: bool,
}

/* Mouse_State is copied negotiated child mouse-reporting state. */
Mouse_State :: struct {
	tracking: bool,
}

Text_Request :: struct {
	scope:        Text_Scope,
	start_column: u16,
	start_row:    u32,
	end_column:   u16,
	end_row:      u32,
	rectangle:    bool,
	unwrap:       bool,
	trim:         bool,
}

/* Render_State is a copied, frontend-independent render summary. */
Render_State :: struct {
	columns:        u16,
	rows:           u16,
	cursor_column:  u16,
	cursor_row:     u16,
	cursor_visible: bool,
}

/* Effects is copied accounting for terminal-originated synchronous effects. */
Effects :: struct {
	bell_count:                    u64,
	writeback_count:               u64,
	writeback_bytes:               u64,
	writeback_pending_bytes:       u64,
	writeback_dropped_bytes:       u64,
	title_change_count:            u64,
	pwd_change_count:              u64,
	clipboard_read_denied_count:   u64,
	clipboard_write_denied_count:  u64,
	notification_denied_count:     u64,
	notification_bytes:            u64,
	progress_count:                u64,
	progress_state:                u64,
	progress_percent:              i64,
	unknown_sequence_count:        u64,
	unknown_sequence_bytes:        u64,
	unknown_truncated_count:       u64,
}

/* Image_Placement is copied bounded Kitty graphics metadata without foreign pointers. */
Image_Placement :: struct {
	image_id:        u32,
	placement_id:    u32,
	generation:      u64,
	decoded_bytes:   u64,
	image_width:     u32,
	image_height:    u32,
	format:          i32,
	viewport_column: i32,
	viewport_row:    i32,
	grid_columns:    u32,
	grid_rows:       u32,
	pixel_width:     u32,
	pixel_height:    u32,
	z:               i32,
	visible:         bool,
	pending:         bool,
	rejected:        bool,
}

/* Image_Projection reports one bounded placement snapshot. */
Image_Projection :: struct {
	generation:    u64,
	count:         u64,
	decoded_bytes: u64,
	truncated:     bool,
}

/* Metadata_Copy reports one bounded copied terminal metadata value. */
Metadata_Copy :: struct {
	copied_bytes:   u64,
	required_bytes: u64,
	truncated:      bool,
}

Damage :: enum i32 {
	Clean = 0,
	Partial,
	Full,
}

Cursor_Style :: enum i32 {
	Bar = 0,
	Block,
	Underline,
	Hollow_Block,
}

Cell_Width :: enum i32 {
	Narrow = 0,
	Wide,
	Spacer_Tail,
	Spacer_Head,
}

Semantic_Content :: enum i32 {
	Output = 0,
	Input,
	Prompt,
}

Style_Color_Kind :: enum i32 {
	None = 0,
	Palette,
	RGB,
}

Color :: struct {
	r, g, b: u8,
}

Style_Color :: struct {
	kind:    Style_Color_Kind,
	palette: u8,
	rgb:     Color,
}

Cell_Style :: struct {
	foreground:      Style_Color,
	background:      Style_Color,
	underline_color: Style_Color,
	bold:             bool,
	italic:           bool,
	faint:            bool,
	blink:            bool,
	inverse:          bool,
	invisible:        bool,
	strikethrough:    bool,
	overline:         bool,
	underline:        i32,
}

Projected_Cell :: struct {
	column:           u16,
	row:              u16,
	text:             [CELL_TEXT_BYTES]u8,
	text_length:      u16,
	width:            Cell_Width,
	semantic_content: Semantic_Content,
	has_text:         bool,
	selected:         bool,
	protected_cell:   bool,
	hyperlink:        bool,
	text_clipped:     bool,
	style:            Cell_Style,
}

Projected_Row :: struct {
	row:               u16,
	dirty:             bool,
	wrapped:           bool,
	wrap_continuation: bool,
}

Projection :: struct {
	damage:                Damage,
	columns:               u16,
	rows:                  u16,
	damaged_rows:          u16,
	first_damaged_row:     u16,
	last_damaged_row:      u16,
	damaged_cells:         u64,
	clipped_cells:         u64,
	clipped_text_bytes:    u64,
	cursor_column:         u16,
	cursor_row:            u16,
	cursor_style:          Cursor_Style,
	cursor_in_viewport:    bool,
	cursor_visible:        bool,
	cursor_blinking:       bool,
	cursor_password_input: bool,
	cursor_wide_tail:      bool,
	background:            Color,
	foreground:            Color,
	cursor:                Color,
	cursor_color_set:      bool,
	palette:               [256]Color,
}

/* Stats is copied lifecycle and foreign-allocation accounting. */
Stats :: struct {
	generation:          u32,
	live:                bool,
	allocation_attempts: u64,
	allocations:         u64,
	frees:               u64,
	live_bytes:          u64,
	peak_bytes:          u64,
}

DEFAULT_OPTIONS :: Options {
	columns = 80,
	rows = 24,
	cell_width_pixels = 8,
	cell_height_pixels = 16,
	scrollback_max_bytes = 32 * 1_024 * 1_024,
	scrollback_max_lines = 100_000,
}
