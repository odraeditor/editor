// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "core:unicode/utf8"

/* context_label_copy creates one pointer-free bounded contextual label. */
context_label_copy :: proc(value: string) -> (label: Context_Label, ok: bool) {
	if len(value) == 0 || len(value) > len(label.bytes) || !utf8.valid_string(value) do return {}, false
	label.length = u32(copy(label.bytes[:], transmute([]u8)value))
	return label, true
}

/* context_label_text borrows validated text from one copied contextual label. */
context_label_text :: proc(label: ^Context_Label) -> string {
	if label == nil || label.length == 0 || label.length > u32(len(label.bytes)) do return ""
	return string(label.bytes[:label.length])
}

/* context_diagnostic_copy creates one pointer-free bounded retained diagnostic. */
context_diagnostic_copy :: proc(value: string) -> (diagnostic: Context_Diagnostic, ok: bool) {
	if len(value) == 0 || len(value) > len(diagnostic.bytes) || !utf8.valid_string(value) do return {}, false
	diagnostic.length = u32(copy(diagnostic.bytes[:], transmute([]u8)value))
	return diagnostic, true
}

/* context_diagnostic_text borrows validated text from one copied diagnostic. */
context_diagnostic_text :: proc(diagnostic: ^Context_Diagnostic) -> string {
	if diagnostic == nil || diagnostic.length == 0 ||
	   diagnostic.length > u32(len(diagnostic.bytes)) {
		return ""
	}
	return string(diagnostic.bytes[:diagnostic.length])
}

/* context_observation_validate admits absent context or one coherent pane-local copied generation. */
context_observation_validate :: proc(
	observation: Context_Observation,
	presentation: Generation,
) -> bool {
	if observation.generation == Generation(0) {
		return !context_observation_has_values(observation)
	}
	if observation.generation != presentation || observation.buffer_identity == 0 ||
	   observation.pane_identity == 0 || observation.pane_generation == 0 {
		return false
	}
	if !document_context_valid(observation.document, observation) ||
	   !alert_context_valid(observation.alert, observation) ||
	   !diagnostic_context_valid(observation.diagnostics, observation) ||
	   !language_context_valid(observation.language, observation) ||
	   !interaction_context_valid(observation.interaction, observation) ||
	   !named_context_valid(observation.project, observation) ||
	   !named_context_valid(observation.workspace, observation) ||
	   !pane_context_valid(observation.pane, observation) {
		return false
	}
	return true
}

@(private)
context_observation_has_values :: proc(observation: Context_Observation) -> bool {
	return observation.buffer_identity != 0 || observation.buffer_revision != 0 ||
	       observation.pane_identity != 0 || observation.pane_generation != 0 ||
	       observation.document.present || observation.alert.present ||
	       observation.diagnostics.present || observation.language.present ||
	       observation.interaction.present ||
	       observation.project.present || observation.workspace.present ||
	       observation.pane.present
}

@(private)
source_stamp_matches :: proc(stamp: Source_Stamp, observation: Context_Observation) -> bool {
	return stamp.presentation == observation.generation &&
	       stamp.buffer_identity == observation.buffer_identity &&
	       stamp.buffer_revision == observation.buffer_revision &&
	       stamp.pane_identity == observation.pane_identity &&
	       stamp.pane_generation == observation.pane_generation &&
	       stamp.owner_identity != 0 && stamp.owner_generation != 0
}

@(private)
bounded_text_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_SEGMENT_TEXT_BYTES && utf8.valid_string(value)
}

@(private)
document_context_valid :: proc(value: Document_Context, observation: Context_Observation) -> bool {
	if !value.present do return value.stamp == Source_Stamp{} && value.encoding == Context_Label{}
	encoding := value.encoding
	return source_stamp_matches(value.stamp, observation) &&
	       bounded_text_valid(context_label_text(&encoding))
}

@(private)
alert_context_valid :: proc(value: Alert_Context, observation: Context_Observation) -> bool {
	if !value.present do return value.stamp == Source_Stamp{} && value.severity == .Invalid && value.diagnostic == Context_Diagnostic{}
	diagnostic := value.diagnostic
	return source_stamp_matches(value.stamp, observation) && value.severity >= .Information &&
	       value.severity <= .Error && bounded_text_valid(context_diagnostic_text(&diagnostic))
}

@(private)
diagnostic_context_valid :: proc(value: Diagnostic_Context, observation: Context_Observation) -> bool {
	if !value.present do return value.stamp == Source_Stamp{} && value.errors == 0 && value.warnings == 0
	return source_stamp_matches(value.stamp, observation) && (value.errors > 0 || value.warnings > 0)
}

@(private)
language_context_valid :: proc(value: Language_Context, observation: Context_Observation) -> bool {
	if !value.present do return value.stamp == Source_Stamp{} && value.name == Context_Label{} &&
		value.service_health == .None && value.operation_health == .None
	name := value.name
	return source_stamp_matches(value.stamp, observation) && bounded_text_valid(context_label_text(&name)) &&
	       value.service_health >= .None && value.service_health <= .Stopped &&
	       value.operation_health >= .None && value.operation_health <= .Failed
}

@(private)
interaction_context_valid :: proc(value: Interaction_Context, observation: Context_Observation) -> bool {
	if !value.present {
		return value.stamp == Source_Stamp{} && value.profile == Context_Label{} &&
		       value.state == Context_Label{} && !value.modal
	}
	profile := value.profile
	state := value.state
	return source_stamp_matches(value.stamp, observation) &&
	       bounded_text_valid(context_label_text(&profile)) &&
	       bounded_text_valid(context_label_text(&state))
}

@(private)
named_context_valid :: proc(value: Named_Context, observation: Context_Observation) -> bool {
	if !value.present do return value.stamp == Source_Stamp{} && value.name == Context_Label{}
	name := value.name
	return source_stamp_matches(value.stamp, observation) && bounded_text_valid(context_label_text(&name))
}

@(private)
pane_context_valid :: proc(value: Pane_Context, observation: Context_Observation) -> bool {
	if !value.present do return value.stamp == Source_Stamp{} && value.policy == .Ordinary
	return source_stamp_matches(value.stamp, observation) && value.policy > .Ordinary && value.policy <= .Read_Only
}
