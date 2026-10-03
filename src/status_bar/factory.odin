// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "core:fmt"
import "core:path/filepath"
import "core:unicode/utf8"

/* BUFFER_STATE_SEGMENT_ID identifies the factory buffer safety marker. */
BUFFER_STATE_SEGMENT_ID :: Segment_ID(1)
/* BUFFER_IDENTITY_SEGMENT_ID identifies the factory user-facing buffer label. */
BUFFER_IDENTITY_SEGMENT_ID :: Segment_ID(2)
/* POSITION_SEGMENT_ID identifies the factory pane-local position summary. */
POSITION_SEGMENT_ID :: Segment_ID(3)
/* ALERT_SEGMENT_ID identifies one retained exceptional pane-local condition. */
ALERT_SEGMENT_ID :: Segment_ID(4)
/* ENCODING_SEGMENT_ID identifies canonical document encoding and line endings. */
ENCODING_SEGMENT_ID :: Segment_ID(5)
/* PANE_STATE_SEGMENT_ID identifies exceptional pane-local policy. */
PANE_STATE_SEGMENT_ID :: Segment_ID(6)
/* WORKSPACE_SEGMENT_ID identifies the active Workspace context. */
WORKSPACE_SEGMENT_ID :: Segment_ID(7)
/* PROJECT_SEGMENT_ID identifies the active Project context. */
PROJECT_SEGMENT_ID :: Segment_ID(8)
/* EDITING_CONTEXT_SEGMENT_ID identifies language, service, and diagnostic context. */
EDITING_CONTEXT_SEGMENT_ID :: Segment_ID(9)
/* BUFFER_SIZE_SEGMENT_ID identifies the factory buffer byte count. */
BUFFER_SIZE_SEGMENT_ID :: Segment_ID(10)
/* BUFFER_CONTEXT_SEGMENT_ID identifies bounded project-relative file context. */
BUFFER_CONTEXT_SEGMENT_ID :: Segment_ID(11)
/* PROGRESS_SEGMENT_ID identifies the pane-local viewport progress label. */
PROGRESS_SEGMENT_ID :: Segment_ID(12)

/* compose_factory creates the required core Status Bar from copied buffer facts. */
compose_factory :: proc(request: Factory_Request) -> (View, bool, Failure_Context) {
	policy := request.policy
	if !policy.configured do policy = DEFAULT_FACTORY_POLICY
	if request.generation == Generation(0) || request.buffer.generation != request.generation ||
	   !factory_policy_is_valid(policy) ||
	   !context_observation_validate(request.contextual, request.generation) ||
	   request.contextual.generation != Generation(0) &&
	   (request.buffer.identity != request.contextual.buffer_identity ||
	    request.buffer.revision != request.contextual.buffer_revision) ||
	   len(request.buffer.label) == 0 || !utf8.valid_string(request.buffer.label) ||
	   len(request.buffer.context_label) > MAX_SEGMENT_TEXT_BYTES ||
	   !utf8.valid_string(request.buffer.context_label) ||
	   request.buffer.line == 0 || request.buffer.line_count == 0 ||
	   request.buffer.line > request.buffer.line_count || request.buffer.column == 0 ||
	   request.buffer.point_offset > request.buffer.text_bytes {
		return {}, false, Failure_Context{operation = .Factory, code = .Invalid_Request}
	}

	buffer_state := ""
	if request.buffer.writable && request.buffer.modified do buffer_state = "**"
	if !request.buffer.writable && !request.buffer.modified do buffer_state = "%%"
	if !request.buffer.writable && request.buffer.modified do buffer_state = "%*"

	percentage: u64
	if request.buffer.text_bytes > 0 {
		percentage = u64(min(u128(100), u128(request.buffer.point_offset) * 100 / u128(request.buffer.text_bytes)))
	}
	position_label_storage: [32]u8
	position_label := fmt.bprintf(position_label_storage[:], "%d%%", percentage)
	if request.buffer.point_offset == 0 {
		position_label = "Top"
	} else if request.buffer.text_bytes > 0 &&
	          request.buffer.point_offset == request.buffer.text_bytes {
		position_label = "Bot"
	}
	position_storage: [128]u8
	position_full := ""
	position_compact_storage: [32]u8
	position_compact := fmt.bprintf(
		position_compact_storage[:],
		"%d:%d",
		request.buffer.line,
		request.buffer.column,
	)
	switch policy.position {
	case .Line_Column_Percentage:
		position_full = position_compact
	case .Line_Column:
		position_full = position_compact
	case .Byte_Offset:
		position_full = fmt.bprintf(position_storage[:], "B:%d", request.buffer.point_offset)
		position_compact = position_full
	case .Invalid:
		unreachable()
	}
	if len(request.programmable) > MAX_PROGRAMMABLE_SEGMENTS {
		return {}, false, Failure_Context {
			operation = .Factory,
			code = .Segment_Limit,
			limit = MAX_PROGRAMMABLE_SEGMENTS,
			actual = u64(len(request.programmable)),
		}
	}
	segments: [MAX_SEGMENTS]Segment_Definition
	segment_count := 0
	alert_diagnostic := request.contextual.alert.diagnostic
	document_encoding := request.contextual.document.encoding
	workspace_label := request.contextual.workspace.name
	project_label := request.contextual.project.name
	language_label := request.contextual.language.name
	interaction_state_label := request.contextual.interaction.state
	if request.contextual.alert.present {
		marker := "i"
		if request.contextual.alert.severity == .Warning do marker = "!"
		if request.contextual.alert.severity == .Error do marker = "!!"
		segments[segment_count] = Segment_Definition {
			id = ALERT_SEGMENT_ID,
			kind = .Alert,
			group = .Left,
			priority = 252,
			full_text = marker,
			compact_text = "!",
			required = true,
			style_role = .Alert,
			inspection_text = context_diagnostic_text(&alert_diagnostic),
			primary_command = request.actions.alert,
		}
		segment_count += 1
	}
	show_optional := policy.compact != .Essential_Only
	if len(buffer_state) > 0 {
		segments[segment_count] = Segment_Definition {
			id = BUFFER_STATE_SEGMENT_ID,
			kind = .Buffer_State,
			group = .Left,
			priority = 255,
			full_text = buffer_state,
			required = true,
			style_role = .Safety,
		}
		segment_count += 1
	}
	buffer_size_storage: [32]u8
	buffer_size := fmt.bprintf(buffer_size_storage[:], "%d", request.buffer.text_bytes)
	if show_optional {
		segments[segment_count] = Segment_Definition {
			id = BUFFER_SIZE_SEGMENT_ID,
			kind = .Buffer_State,
			group = .Left,
			priority = 70,
			full_text = buffer_size,
			compact_text = buffer_size,
			omittable = true,
			style_role = .Ordinary,
		}
		segment_count += 1
	}
	pane_label := ""
	pane_compact := ""
	if request.contextual.pane.present {
		switch request.contextual.pane.policy {
		case .Soft_Dedicated:
			pane_label, pane_compact = "Soft", "S"
		case .Hard_Dedicated:
			pane_label, pane_compact = "Hard", "H"
		case .Read_Only:
			pane_label, pane_compact = "View RO", "RO"
		case .Ordinary:
		}
	}
	if show_optional && .Pane_State in policy.visible && len(pane_label) > 0 {
		segments[segment_count] = Segment_Definition {
			id = PANE_STATE_SEGMENT_ID,
			kind = .Pane_State,
			group = .Left,
			priority = 30,
			full_text = pane_label,
			compact_text = pane_compact,
			omittable = true,
			style_role = .Context,
		}
		segment_count += 1
	}
	buffer_context_storage: [MAX_SEGMENT_TEXT_BYTES]u8
	if show_optional && len(request.buffer.context_label) > 0 {
		buffer_context := fmt.bprintf(
			buffer_context_storage[:],
			"%s/",
			request.buffer.context_label,
		)
		segments[segment_count] = Segment_Definition {
			id = BUFFER_CONTEXT_SEGMENT_ID,
			kind = .Buffer_Identity,
			group = .Left,
			priority = 90,
			full_text = buffer_context,
			compact_text = filepath.base(request.buffer.context_label),
			omittable = true,
			truncatable = true,
			style_role = .Context,
			inspection_text = request.buffer.context_label,
		}
		segment_count += 1
	}
	segments[segment_count] = Segment_Definition {
		id = BUFFER_IDENTITY_SEGMENT_ID,
		kind = .Buffer_Identity,
		group = .Left,
		priority = 254,
		full_text = request.buffer.label,
		required = true,
		truncatable = true,
		style_role = .Buffer_Identity,
		inspection_text = request.buffer.label,
		primary_command = request.actions.buffer_identity,
	}
	segment_count += 1
	segments[segment_count] = Segment_Definition {
		id = POSITION_SEGMENT_ID,
		kind = .Position,
		group = .Left,
		priority = 253,
		full_text = position_full,
		compact_text = position_compact,
		required = true,
		style_role = .Position,
	}
	segment_count += 1
	if show_optional && policy.position == .Line_Column_Percentage {
		segments[segment_count] = Segment_Definition {
			id = PROGRESS_SEGMENT_ID,
			kind = .Position,
			group = .Left,
			priority = 75,
			full_text = position_label,
			compact_text = position_label,
			omittable = true,
			style_role = .Position,
		}
		segment_count += 1
	}
	workspace_storage: [MAX_SEGMENT_TEXT_BYTES]u8
	if show_optional && .Workspace in policy.visible && request.contextual.workspace.present {
		workspace_name := context_label_text(&workspace_label)
		workspace_text := fmt.bprintf(workspace_storage[:], "W:%s", workspace_name)
		segments[segment_count] = Segment_Definition {
			id = WORKSPACE_SEGMENT_ID,
			kind = .Workspace,
			group = .Right,
			priority = 40,
			full_text = workspace_text,
			compact_text = "W",
			omittable = true,
			style_role = .Workspace,
			inspection_text = workspace_name,
			primary_command = request.actions.workspace,
		}
		segment_count += 1
	}
	project_storage: [MAX_SEGMENT_TEXT_BYTES]u8
	if show_optional && .Project in policy.visible && request.contextual.project.present {
		project_name := context_label_text(&project_label)
		project_text := fmt.bprintf(project_storage[:], "P:%s", project_name)
		segments[segment_count] = Segment_Definition {
			id = PROJECT_SEGMENT_ID,
			kind = .Project,
			group = .Right,
			priority = 50,
			full_text = project_text,
			compact_text = "P",
			omittable = true,
			style_role = .Project,
			inspection_text = project_name,
			primary_command = request.actions.project,
			secondary_command = request.actions.project_inspection,
		}
		segment_count += 1
	}
	if show_optional && .Encoding in policy.visible && request.contextual.document.present {
		segments[segment_count] = Segment_Definition {
			id = ENCODING_SEGMENT_ID,
			kind = .Encoding,
			group = .Right,
			priority = 20,
			full_text = context_label_text(&document_encoding),
			compact_text = "U8",
			omittable = true,
			style_role = .Context,
		}
		segment_count += 1
	}
	editing_storage: [MAX_SEGMENT_TEXT_BYTES]u8
	editing_text := ""
	editing_compact := ""
	modal_active := request.contextual.interaction.present && request.contextual.interaction.modal
	if modal_active ||
	   (.Editing_Context in policy.visible && show_optional &&
	    (request.contextual.language.present || request.contextual.diagnostics.present)) {
		modal_state := ""
		modal_compact := ""
		if modal_active {
			modal_state = context_label_text(&interaction_state_label)
			modal_compact = "N"
			if modal_state == "Normal" {
				modal_state = "NORMAL"
			} else if modal_state == "Insert" {
				modal_state = "INSERT"
				modal_compact = "I"
			} else if modal_state == "Replace" {
				modal_state = "REPLACE"
				modal_compact = "R"
			} else if modal_state == "Visual Character" {
				modal_state = "VISUAL"
				modal_compact = "V"
			} else if modal_state == "Visual Line" {
				modal_state = "VISUAL LINE"
				modal_compact = "V"
			} else if modal_state == "Visual Block" {
				modal_state = "VISUAL BLOCK"
				modal_compact = "V"
			}
		}
		language_name := ""
		if request.contextual.language.present do language_name = context_label_text(&language_label)
		health := ""
		operation_health := ""
		if request.contextual.language.present {
			switch request.contextual.language.service_health {
			case .Initializing: health = " LS:init"
			case .Active:       health = " LS"
			case .Failed:       health = " LS:failed"
			case .Stopped:      health = " LS:stopped"
			case .None:
			}
			switch request.contextual.language.operation_health {
			case .Busy:   operation_health = " L:busy"
			case .Failed: operation_health = " L:failed"
			case .None:
			}
		}
		diagnostics_storage: [64]u8
		diagnostics := ""
		if request.contextual.diagnostics.present {
			diagnostics = fmt.bprintf(
				diagnostics_storage[:],
				" %dE %dW",
				request.contextual.diagnostics.errors,
				request.contextual.diagnostics.warnings,
			)
		}
		separator := ""
		if len(modal_state) > 0 && (len(language_name) > 0 || len(health) > 0 ||
		   len(operation_health) > 0 || len(diagnostics) > 0) {
			separator = " "
		}
		editing_text = fmt.bprintf(
			editing_storage[:],
			"%s%s%s%s%s%s",
			modal_state,
			separator,
			language_name,
			health,
			operation_health,
			diagnostics,
		)
		editing_compact = modal_compact
		if !modal_active && len(language_name) > 0 {
			editing_compact = fmt.bprintf(editing_storage[len(editing_text):], "%s", language_name)
		}
		segments[segment_count] = Segment_Definition {
			id = EDITING_CONTEXT_SEGMENT_ID,
			kind = .Editing_Context,
			group = .Right,
			priority = 60,
			full_text = editing_text,
			compact_text = editing_compact,
			required = modal_active,
			omittable = !modal_active,
			style_role = .Editing_Context,
			primary_command = request.actions.editing_context,
			secondary_command = request.actions.editing_context_secondary,
		}
		segment_count += 1
	}
	if policy.compact == .Prefer_Compact {
		for &segment in segments[:segment_count] {
			if segment.omittable && len(segment.compact_text) > 0 {
				segment.full_text = segment.compact_text
			}
		}
	}
	for programmable in request.programmable {
		segments[segment_count] = programmable
		segment_count += 1
	}
	if segment_count > int(request.limits.segments) {
		return {}, false, Failure_Context {
			operation = .Factory,
			code = .Segment_Limit,
			limit = u64(request.limits.segments),
			actual = u64(segment_count),
		}
	}
	view, ok, failure := compose(Composition_Request {
		generation = request.generation,
		width_cells = request.width_cells,
		segments = segments[:segment_count],
		profile = request.profile,
		allocator = request.allocator,
		limits = request.limits,
	})
	if !ok {
		failure.operation = .Factory
		return {}, false, failure
	}
	return view, true, {}
}
