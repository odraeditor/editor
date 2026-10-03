// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package interaction owns normalized input and bounded command resolution.
package interaction

/* PROTECTED_RECOVERY_MAP_ID reserves the Odin-owned recovery map identity. */
PROTECTED_RECOVERY_MAP_ID :: Map_ID(0xffff_ffff_ffff_fffe)
/* PROTECTED_RECOVERY_BINDING_COUNT is the accepted initial recovery catalog size. */
PROTECTED_RECOVERY_BINDING_COUNT :: 2

/* Protected_Binding describes one immutable recovery sequence and its policy source. */
Protected_Binding :: struct {
	sequence:     Key_Sequence,
	command_name: string,
	reason:       string,
	provenance:   Definition_Provenance,
}

/* protected_binding_catalog returns the complete accepted factory recovery policy. */
protected_binding_catalog :: proc() -> [PROTECTED_RECOVERY_BINDING_COUNT]Protected_Binding {
	provenance := protected_binding_provenance()
	return {
		{
			sequence = protected_control_sequence('g'),
			command_name = "keyboard-quit",
			reason = "Cancel active interaction or recover from pending input and active selection.",
			provenance = provenance,
		},
		{
			sequence = protected_meta_sequence('x'),
			command_name = "execute-extended-command",
			reason = "Preserve access to registered interactive commands and active bindings.",
			provenance = provenance,
		},
	}
}

@(private)
protected_map_definition :: proc(bindings: []Layered_Binding_Definition) -> Map_Definition {
	return Map_Definition {
		identity = {
			id = PROTECTED_RECOVERY_MAP_ID,
			revision = Map_Revision(1),
		},
		name = "protected-recovery",
		precedence = .Protected_Recovery,
		bindings = bindings,
		unmatched_input_policy = .Fallthrough,
		provenance = protected_binding_provenance(),
	}
}

@(private)
protected_layered_bindings :: proc(
	output: ^[PROTECTED_RECOVERY_BINDING_COUNT]Layered_Binding_Definition,
) {
	assert(output != nil)
	catalog := protected_binding_catalog()
	for entry, index in catalog {
		output[index] = Layered_Binding_Definition {
			sequence = entry.sequence,
			command_name = entry.command_name,
			operation = .Bind,
			provenance = entry.provenance,
			protection_reason = entry.reason,
		}
	}
}

@(private)
protected_binding_provenance :: proc() -> Definition_Provenance {
	return Definition_Provenance {
		provider = "native",
		source = "factory recovery policy",
	}
}

@(private)
protected_control_sequence :: proc(value: rune) -> Key_Sequence {
	return Key_Sequence {
		strokes = {0 = {
			kind = .Unicode_Scalar,
			scalar = value,
			modifiers = {.Control},
		}},
		stroke_count = 1,
	}
}

@(private)
protected_meta_sequence :: proc(value: rune) -> Key_Sequence {
	return Key_Sequence {
		strokes = {0 = {
			kind = .Unicode_Scalar,
			scalar = value,
			modifiers = {.Meta},
		}},
		stroke_count = 1,
	}
}

@(private)
protected_sequence_supported :: proc(
	sequence: Key_Sequence,
	capabilities: Frontend_Key_Capabilities,
) -> bool {
	for index in 0 ..< int(sequence.stroke_count) {
		stroke := sequence.strokes[index]
		if .Control in stroke.modifiers && !capabilities.control_modified_unicode {
			return false
		}
		if .Meta in stroke.modifiers && !capabilities.meta_modified_unicode {
			return false
		}
	}
	return true
}
