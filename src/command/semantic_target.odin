// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../editor"
import editor_view "../view"

/* Semantic_Target_Kind identifies a command-owned editing target. */
Semantic_Target_Kind :: enum u8 {
	Invalid,
	Active_Region,
	Word,
	Line,
	Paragraph,
	Buffer,
	Definition,
	Entry,
	Node,
}

/* Semantic_Target_Source records how a target was established. */
Semantic_Target_Source :: enum u8 {
	Invalid,
	Explicit_Range,
	Active_Selection,
	Inferred,
	Supplied_Context,
}

/* Semantic_Target_Failure_Code classifies bounded target resolution failures. */
Semantic_Target_Failure_Code :: enum u8 {
	None,
	Invalid_Request,
	Unavailable,
	Stale_Context,
	Editor_Failure,
	View_Failure,
	Display_Failure,
}

/* Semantic_Target_Failure preserves the owning subsystem failure. */
Semantic_Target_Failure :: struct {
	code:         Semantic_Target_Failure_Code,
	editor_code:  editor.Failure_Code,
	view_code:    editor_view.Failure_Code,
	display_code: display.Failure_Code,
	expected:     u64,
	actual:       u64,
}

/* Semantic_Target_Candidate carries an analyzer or package-owned semantic range. */
Semantic_Target_Candidate :: struct {
	present:            bool,
	kind:               Semantic_Target_Kind,
	start:              editor.Position,
	end:                editor.Position,
	context_generation: u64,
}

/* Semantic_Target_Context contains the checked owners needed for inference. */
Semantic_Target_Context :: struct {
	buffer:              ^editor.Buffer,
	view_registry:       ^editor_view.Registry,
	view:                editor_view.View_Handle,
	profile:             display.Display_Profile,
	explicit_range:      Native_Explicit_Range,
	supplied:            Semantic_Target_Candidate,
	context_generation:  u64,
}

/* Semantic_Target is one current half-open buffer range. */
Semantic_Target :: struct {
	kind:               Semantic_Target_Kind,
	source:             Semantic_Target_Source,
	start:              editor.Position,
	end:                editor.Position,
	context_generation: u64,
}

/* semantic_target_resolve resolves an explicit, selected, inferred, or supplied target. */
semantic_target_resolve :: proc(
	target_context: Semantic_Target_Context,
	kind: Semantic_Target_Kind,
) -> (target: Semantic_Target, ok: bool, failure: Semantic_Target_Failure) {
	if target_context.buffer == nil || kind == .Invalid {
		return {}, false, {code = .Invalid_Request}
	}
	stats, stats_ok, stats_failure := editor.buffer_stats(target_context.buffer)
	if !stats_ok {
		return {}, false, {code = .Editor_Failure, editor_code = stats_failure.code}
	}
	if target_context.explicit_range.present {
		start, end, valid := semantic_target_checked_range(
			stats,
			target_context.explicit_range.start,
			target_context.explicit_range.end,
		)
		if !valid do return {}, false, {code = .Stale_Context}
		return {
			kind = kind,
			source = .Explicit_Range,
			start = start,
			end = end,
			context_generation = target_context.context_generation,
		}, true, {}
	}
	if semantic_target_requires_supplied_context(kind) {
		candidate := target_context.supplied
		if !candidate.present || candidate.kind != kind {
			return {}, false, {code = .Unavailable}
		}
		if candidate.context_generation != target_context.context_generation {
			return {}, false, {
				code = .Stale_Context,
				expected = target_context.context_generation,
				actual = candidate.context_generation,
			}
		}
		start, end, valid := semantic_target_checked_range(stats, candidate.start, candidate.end)
		if !valid do return {}, false, {code = .Stale_Context}
		return {
			kind = kind,
			source = .Supplied_Context,
			start = start,
			end = end,
			context_generation = candidate.context_generation,
		}, true, {}
	}
	if kind == .Buffer {
		start, start_ok, start_failure := editor.buffer_position(target_context.buffer, 0)
		if !start_ok {
			return {}, false, {code = .Editor_Failure, editor_code = start_failure.code}
		}
		end, end_ok, end_failure := editor.buffer_position(
			target_context.buffer,
			editor.Byte_Offset(stats.text_bytes),
		)
		if !end_ok {
			return {}, false, {code = .Editor_Failure, editor_code = end_failure.code}
		}
		return semantic_target_inferred(kind, start, end, target_context.context_generation), true, {}
	}
	selection, selection_ok, selection_failure := editor.buffer_selection_snapshot(target_context.buffer)
	if !selection_ok {
		return {}, false, {code = .Editor_Failure, editor_code = selection_failure.code}
	}
	if kind == .Active_Region {
		if !selection.region_active || !selection.mark.present {
			return {}, false, {code = .Unavailable}
		}
		start, end := semantic_target_order(selection.point_position, selection.mark.position)
		return {
			kind = kind,
			source = .Active_Selection,
			start = start,
			end = end,
			context_generation = selection.generation,
		}, true, {}
	}
	if target_context.view_registry == nil {
		return {}, false, {code = .Invalid_Request}
	}
	logical, logical_ok, logical_failure := editor_view.snapshot(
		target_context.view_registry,
		target_context.view,
	)
	if !logical_ok {
		return {}, false, {code = .View_Failure, view_code = logical_failure.code}
	}
	switch kind {
	case .Word:
		range, found, range_ok, range_failure := display.word_selection_range(
			target_context.buffer,
			logical,
			target_context.profile,
		)
		if !range_ok {
			return {}, false, {code = .Display_Failure, display_code = range_failure.code}
		}
		if !found do return {}, false, {code = .Unavailable}
		return semantic_target_inferred(kind, range.start, range.end, selection.generation), true, {}
	case .Line:
		line, line_ok, line_failure := editor.buffer_line_at_position(
			target_context.buffer,
			logical.point_position,
		)
		if !line_ok {
			return {}, false, {code = .Editor_Failure, editor_code = line_failure.code}
		}
		start, start_ok, start_failure := editor.buffer_position(target_context.buffer, line.start)
		if !start_ok {
			return {}, false, {code = .Editor_Failure, editor_code = start_failure.code}
		}
		end, end_ok, end_failure := editor.buffer_position(target_context.buffer, line.next_start)
		if !end_ok {
			return {}, false, {code = .Editor_Failure, editor_code = end_failure.code}
		}
		return semantic_target_inferred(kind, start, end, selection.generation), true, {}
	case .Paragraph:
		range, range_ok, range_failure := display.paragraph_selection_range(target_context.buffer, logical)
		if !range_ok {
			return {}, false, {code = .Display_Failure, display_code = range_failure.code}
		}
		return semantic_target_inferred(kind, range.start, range.end, selection.generation), true, {}
	case .Invalid, .Active_Region, .Buffer, .Definition, .Entry, .Node:
		return {}, false, {code = .Invalid_Request}
	}
	unreachable()
}

@(private)
semantic_target_requires_supplied_context :: proc(kind: Semantic_Target_Kind) -> bool {
	return kind == .Definition || kind == .Entry || kind == .Node
}

@(private)
semantic_target_checked_range :: proc(
	stats: editor.Buffer_Stats,
	start, end: editor.Position,
) -> (editor.Position, editor.Position, bool) {
	if start.buffer_id != stats.buffer_id || end.buffer_id != stats.buffer_id ||
	   start.revision != stats.revision || end.revision != stats.revision ||
	   u64(start.byte_offset) > stats.text_bytes || u64(end.byte_offset) > stats.text_bytes {
		return {}, {}, false
	}
	ordered_start, ordered_end := semantic_target_order(start, end)
	return ordered_start, ordered_end, true
}

@(private)
semantic_target_order :: proc(
	left, right: editor.Position,
) -> (editor.Position, editor.Position) {
	if left.byte_offset <= right.byte_offset do return left, right
	return right, left
}

@(private)
semantic_target_inferred :: proc(
	kind: Semantic_Target_Kind,
	start, end: editor.Position,
	context_generation: u64,
) -> Semantic_Target {
	return {
		kind = kind,
		source = .Inferred,
		start = start,
		end = end,
		context_generation = context_generation,
	}
}
