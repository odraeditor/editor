// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "core:sys/posix"
import "base:runtime"
import "../display"
import "../interaction"
import "../ui"
import editor_view "../view"

/* MAX_OUTPUT_BYTES bounds one encoded terminal write request. */
MAX_OUTPUT_BYTES :: u32(2 * 1024 * 1024)
/* MAX_RECOVERY_MESSAGE_BYTES bounds one physical global recovery diagnostic. */
MAX_RECOVERY_MESSAGE_BYTES :: u32(512)

/* Geometry is the checked physical terminal size used as projection input. */
Geometry :: struct {
	width_cells: u32,
	height_rows: u32,
}

/* Failure_Code classifies expected terminal lifecycle and I/O failures. */
Failure_Code :: enum u16 {
	None,
	Unsupported_Platform,
	Invalid_Session,
	Already_Acquired,
	Not_A_Terminal,
	Acquisition_Failed,
	Raw_Mode_Failed,
	Signal_Failed,
	Geometry_Failed,
	Invalid_Geometry,
	Output_Limit,
	Write_Failed,
	Flush_Failed,
	Read_Failed,
	Interrupted,
	Restoration_Failed,
	Invalid_Renderer,
	Incompatible_Snapshot,
	Renderer_Memory_Limit,
	Render_Output_Limit,
	Invalid_UI_Presentation,
	Recovery_Message_Limit,
}

/* Failure_Context reports the failed terminal operation without hiding OS status. */
Failure_Context :: struct {
	code:       Failure_Code,
	os_errno:   i32,
	limit:      u64,
	actual:     u64,
	bytes_done: u64,
	display_failure: display.Failure_Context,
}

/* Text_Surface_Projection binds one logical text surface to its display snapshot. */
Text_Surface_Projection :: struct {
	surface:  ui.Object_Handle,
	snapshot: display.Snapshot,
	logical:  editor_view.Snapshot,
}

/* UI_Presentation borrows one complete UI snapshot and every text projection. */
UI_Presentation :: struct {
	root:          ^ui.Snapshot,
	text_surfaces: []Text_Surface_Projection,
}

/* Read_Result distinguishes one byte, bounded idle step, resize interruption, and failure. */
Read_Result :: enum u8 {
	Byte,
	Idle,
	Resize,
	Failure,
}

/* MAX_INPUT_SEQUENCE_BYTES bounds one terminal escape, pointer, or UTF-8 sequence. */
MAX_INPUT_SEQUENCE_BYTES :: u8(32)

/* Pointer_Context binds decoded physical input to one observed UI geometry. */
Pointer_Context :: struct {
	frontend:            interaction.Pointer_Frontend_ID,
	source:              interaction.Pointer_Source_ID,
	root_generation:     interaction.Pointer_Root_Generation,
	geometry_generation: interaction.Pointer_Geometry_Generation,
	capabilities:        interaction.Pointer_Capabilities,
}

/* Decode_Status distinguishes complete events from bounded non-events and failures. */
Decode_Status :: enum u8 {
	Event,
	Pending,
	Incomplete,
	Malformed,
	Oversized,
	Unknown,
	Unsupported,
}

/*
Decode_Output reports one normalized input and the physical sequence size consumed.
Text borrows decoder storage and expires at the next decoder operation.
*/
Decode_Output :: struct {
	status:         Decode_Status,
	input:          interaction.Input,
	sequence_bytes: u8,
}

/* Decoder retains at most one bounded incomplete physical input sequence. */
Decoder :: struct {
	bytes:            [MAX_INPUT_SEQUENCE_BYTES]u8,
	count:            u8,
	expected:         u8,
	state:            Decoder_State,
	pointer_sequence: interaction.Pointer_Sequence,
}

@(private)
Decoder_State :: enum u8 {
	Ground,
	Escape,
	CSI,
	SS3,
	UTF8,
}

/* Session is a non-copyable owner consumed exactly once by session_restore. */
Session :: struct {
	input_fd:              posix.FD,
	output_fd:             posix.FD,
	saved_attributes:      posix.termios,
	saved_resize_action:   posix.sigaction_t,
	geometry:              Geometry,
	resize_generation:     u32,
	pointer_geometry_generation: interaction.Pointer_Geometry_Generation,
	acquired:              bool,
	raw_mode:              bool,
	signal_owned:          bool,
	pointer_reporting:     bool,
	restored:              bool,
}

/* session_is_live reports whether the session still owns acquired terminal state. */
session_is_live :: proc(session: ^Session) -> bool {
	return session != nil && session.acquired && !session.restored
}

/* Renderer owns one bounded physical terminal target. */
Renderer :: struct {
	state:  rawptr,
	closed: bool,
}

/* Icon_Profile selects portable or icon-font terminal glyph catalogs. */
Icon_Profile :: enum u8 {
	Invalid,
	Portable,
	Nerd_Font,
}

/* Renderer_Config fixes geometry, display policy, output bounds, and ownership. */
Renderer_Config :: struct {
	constraints:      display.Viewport_Constraints,
	profile:          display.Display_Profile,
	color:            ui.Renderer_Color_Capability,
	icons:            Icon_Profile,
	max_output_bytes: u32,
	allocator:        runtime.Allocator,
}
