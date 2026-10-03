// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* COMPLETION_CONTEXT_BINDING_COUNT is the complete factory completion grammar. */
COMPLETION_CONTEXT_BINDING_COUNT :: 9
/* COMPLETION_CONTEXT_MAP_ID is the stable transient completion map identity. */
COMPLETION_CONTEXT_MAP_ID :: interaction.Map_ID(3_019)
/* COMPLETION_CONTEXT_OWNER_ID identifies the completion interaction lifecycle owner. */
COMPLETION_CONTEXT_OWNER_ID :: interaction.Owner_ID(4_019)

/* Completion_Context_Map owns one complete completion-local binding definition. */
Completion_Context_Map :: struct {
	bindings:   [COMPLETION_CONTEXT_BINDING_COUNT]interaction.Binding_Definition,
	definition: interaction.Context_Map_Definition,
}

/* completion_context_map_init prepares the transient completion grammar in caller-owned storage. */
completion_context_map_init :: proc(value: ^Completion_Context_Map) -> bool {
	if value == nil {
		return false
	}
	value^ = {}
	value.bindings = {
		completion_context_binding(completion_control_key('n'), "completion-next"),
		completion_context_binding(completion_special_key(.Down), "completion-next"),
		completion_context_binding(completion_control_key('p'), "completion-previous"),
		completion_context_binding(completion_special_key(.Up), "completion-previous"),
		completion_context_binding(completion_meta_key('<'), "completion-first"),
		completion_context_binding(completion_meta_key('>'), "completion-last"),
		completion_context_binding(completion_special_key(.Enter), "completion-accept"),
		completion_context_binding(completion_special_key(.Tab), "completion-accept"),
		completion_context_binding(completion_meta_key('?'), "completion-show-documentation"),
	}
	value.definition = {
		identity = {
			id = COMPLETION_CONTEXT_MAP_ID,
			revision = interaction.Map_Revision(1),
		},
		name = "completion-interaction",
		owner_id = COMPLETION_CONTEXT_OWNER_ID,
		precedence = .Transient_Interaction,
		priority = 0,
		bindings = value.bindings[:],
		unmatched_input_policy = .Fallthrough,
	}
	return true
}

@(private)
completion_context_binding :: proc(
	sequence: interaction.Key_Sequence,
	command_name: string,
) -> interaction.Binding_Definition {
	return {
		strokes = sequence.strokes,
		stroke_count = sequence.stroke_count,
		command_name = command_name,
	}
}

@(private)
completion_control_key :: proc(value: rune) -> interaction.Key_Sequence {
	return completion_scalar_key(value, {.Control})
}

@(private)
completion_meta_key :: proc(value: rune) -> interaction.Key_Sequence {
	return completion_scalar_key(value, {.Meta})
}

@(private)
completion_scalar_key :: proc(
	value: rune,
	modifiers: interaction.Modifiers,
) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = {
		kind = .Unicode_Scalar,
		scalar = value,
		modifiers = modifiers,
	}
	return sequence
}

@(private)
completion_special_key :: proc(
	kind: interaction.Logical_Key_Kind,
) -> interaction.Key_Sequence {
	sequence: interaction.Key_Sequence
	sequence.stroke_count = 1
	sequence.strokes[0] = {kind = kind}
	return sequence
}
