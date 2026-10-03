// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../language"

/* syntax_style_role maps one stable language role into the shared UI vocabulary. */
syntax_style_role :: proc(role: language.Syntax_Role) -> (Style_Role, bool) {
	switch role {
	case .Attribute:          return .Syntax_Attribute, true
	case .Boolean:            return .Syntax_Boolean, true
	case .Comment:            return .Syntax_Comment, true
	case .Constant:           return .Syntax_Constant, true
	case .Constructor:        return .Syntax_Constructor, true
	case .Function:           return .Syntax_Function, true
	case .Function_Builtin:   return .Syntax_Function_Builtin, true
	case .Keyword:            return .Syntax_Keyword, true
	case .Label:              return .Syntax_Label, true
	case .Number:             return .Syntax_Number, true
	case .Operator:           return .Syntax_Operator, true
	case .Punctuation:        return .Syntax_Punctuation, true
	case .String:             return .Syntax_String, true
	case .Type:               return .Syntax_Type, true
	case .Variable:           return .Syntax_Variable, true
	case .Variable_Parameter: return .Syntax_Variable_Parameter, true
	case .Invalid:            return .Invalid, false
	}
	return .Invalid, false
}

/* proposal_project_syntax_decorations copies one complete exact-revision span set. */
proposal_project_syntax_decorations :: proc(
	proposal: ^Proposal,
	text_view_handle: Object_Handle,
	snapshot: language.Syntax_Snapshot,
	spans: []language.Syntax_Span,
	owner_id: Owner_ID,
) -> (count: u32, ok: bool, failure: Failure) {
	state := proposal_state(proposal)
	view, view_ok := resolve_view(state, text_view_handle)
	if state == nil || owner_id == Owner_ID(0) || !view_ok || view.kind != .Text_View ||
	   !view.text.present || !syntax_snapshot_matches_view(snapshot, spans, view.text) {
		return 0, false, generation_failure(state, .Prepare, .Invalid_Decoration)
	}
	if len(spans) > len(state.decorations) - state.decoration_count {
		failure = generation_failure(state, .Prepare, .Decoration_Limit)
		failure.limit = u64(len(state.decorations))
		failure.actual = u64(state.decoration_count + len(spans))
		return 0, false, failure
	}
	if u64(len(spans)) > u64(max(u64)) - u64(state.next_object_id) {
		return 0, false, generation_failure(state, .Prepare, .Generation_Limit)
	}
	previous_end: u64
	for span, index in spans {
		role, mapped := syntax_style_role(span.role)
		if !mapped || !resolve_style_role(state, role) ||
		   !language.syntax_span_is_valid(span, view.text.source_text_bytes) ||
		   span.provider != snapshot.provider || span.source_revision != snapshot.source_revision ||
		   index > 0 && u64(span.start) < previous_end {
			return 0, false, generation_failure(state, .Prepare, .Invalid_Decoration)
		}
		previous_end = u64(span.end)
	}

	start_count := state.decoration_count
	start_bytes := state.accounting.decoration_bytes
	start_object_id := state.next_object_id
	for span in spans {
		role, _ := syntax_style_role(span.role)
		_, added, add_failure := proposal_add_decoration(
			proposal,
			Decoration_Descriptor {
				owner_id = owner_id,
				kind = .Text_Range,
				projection = view.projection,
				source_revision = u64(span.source_revision),
				start = u64(span.start),
				end = u64(span.end),
				style_role = role,
				precedence = span.precedence,
			},
		)
		if !added {
			for index in start_count ..< state.decoration_count do state.decorations[index] = {}
			state.decoration_count = start_count
			state.accounting.decoration_bytes = start_bytes
			state.next_object_id = start_object_id
			return 0, false, add_failure
		}
	}
	return u32(len(spans)), true, {}
}

@(private)
syntax_snapshot_matches_view :: proc(
	snapshot: language.Syntax_Snapshot,
	spans: []language.Syntax_Span,
	view: Text_View_State,
) -> bool {
	return snapshot.generation != language.Syntax_Snapshot_Generation(0) &&
		snapshot.buffer_id != 0 && u64(snapshot.buffer_id) == view.buffer_id &&
		u64(snapshot.source_revision) == view.revision &&
		snapshot.language.id != 0 && snapshot.language.generation != 0 &&
		snapshot.provider.registry_id != 0 &&
		snapshot.provider.language_id == snapshot.language.id &&
		snapshot.provider.provider_id != 0 && snapshot.provider.provider_generation != 0 &&
		snapshot.selection_generation != 0 && snapshot.parser_generation != 0 &&
		snapshot.query_generation != 0 &&
		u64(snapshot.span_count) == u64(len(spans)) &&
		u64(snapshot.usage.spans) == u64(len(spans)) &&
		snapshot.usage.retained_span_bytes == u64(len(spans)) * u64(size_of(language.Syntax_Span))
}
