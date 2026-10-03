// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../interaction"
import "core:testing"

/* Verifies fixed layouts, exact quotas, and complete copied catalog validation. */
@(test)
keymap_records_are_bounded_and_valid :: proc(t: ^testing.T) {
	testing.expect(t, keymap_record_layout_is_valid())
	text_value := "profileinsert-textdirect-editingfactorysourcesaveprotected recoveryextended-command"
	text := transmute([]byte)text_value
	profiles := [?]Keymap_Profile_Record {{
		profile_id = 1,
		profile_revision = 1,
		state_count = 1,
		initial_state_id = 1,
		map_count = 1,
		name_bytes = 7,
		text_fallback_offset = 7,
		text_fallback_bytes = 11,
	}}
	states := [?]Keymap_State_Record {{
		state_id = 1,
		state_revision = 1,
		admits_text_input = 1,
		admitted_effects = 0x0f,
		name_offset = 18,
		name_bytes = 14,
		provider_offset = 32,
		provider_bytes = 7,
		source_offset = 39,
		source_bytes = 6,
	}}
	maps := [?]Keymap_Map_Record {{
		map_id = 1,
		map_revision = 1,
		precedence = u64(interaction.Precedence_Class.Profile_Base),
		unmatched_input_policy = u64(interaction.Unmatched_Input_Policy.Text_Input),
		binding_count = 1,
		name_offset = 32,
		name_bytes = 7,
		provider_offset = 32,
		provider_bytes = 7,
		source_offset = 39,
		source_bytes = 6,
	}}
	bindings := [?]Keymap_Binding_Record {{
		operation = u64(interaction.Binding_Operation.Bind),
		stroke_count = 1,
		scope = u64(interaction.Binding_Scope.Protected_Recovery),
		command_offset = 45,
		command_bytes = 4,
		protection_reason_offset = 49,
		protection_reason_bytes = 18,
		provider_offset = 32,
		provider_bytes = 7,
		source_offset = 39,
		source_bytes = 6,
	}}
	selectors: [0]Keymap_Selector_Record
	surfaces := [?]Keymap_Surface_Record {{
		surface_id = 1,
		surface_revision = 1,
		name_offset = 67,
		name_bytes = 16,
		provider_offset = 32,
		provider_bytes = 7,
		source_offset = 39,
		source_bytes = 6,
	}}
	remaps: [0]Keymap_Remap_Record
	ordering: [0]Keymap_Ordering_Record
	strokes := [?]Keymap_Stroke_Record {{
		kind = u64(interaction.Logical_Key_Kind.Unicode_Scalar),
		scalar = i64('x'),
	}}
	header := Keymap_Profile_Header_Record {
		schema_version = KEYMAP_PROFILE_SCHEMA_VERSION,
		registry_generation = 1,
		catalog_generation = 1,
		active_profile_id = 1,
		active_state_id = 1,
		profile_count = u64(len(profiles)),
		state_count = u64(len(states)),
		map_count = u64(len(maps)),
		binding_count = u64(len(bindings)),
		selector_count = u64(len(selectors)),
		surface_count = u64(len(surfaces)),
		remap_count = u64(len(remaps)),
		ordering_count = u64(len(ordering)),
		stroke_count = u64(len(strokes)),
		text_bytes = u64(len(text)),
	}
	header.record_bytes, _ = keymap_profile_record_bytes(
		header.profile_count, header.state_count, header.map_count, header.binding_count,
		header.selector_count, header.surface_count, header.remap_count, header.ordering_count,
		header.stroke_count, header.text_bytes,
	)
	failure := keymap_profile_records_validate(
		header, profiles[:], states[:], maps[:], bindings[:], selectors[:], surfaces[:],
		remaps[:], ordering[:], strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.None)
	f4_strokes := strokes
	f4_strokes[0] = {kind = u64(interaction.Logical_Key_Kind.F4)}
	failure = keymap_profile_records_validate(
		header, profiles[:], states[:], maps[:], bindings[:], selectors[:], surfaces[:],
		remaps[:], ordering[:], f4_strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.None)

	bad_version := header
	bad_version.schema_version += 1
	failure = keymap_profile_records_validate(
		bad_version, profiles[:], states[:], maps[:], bindings[:], selectors[:], surfaces[:],
		remaps[:], ordering[:], strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.Unsupported_Schema)

	bad_state := states
	bad_state[0].admits_text_input = 2
	failure = keymap_profile_records_validate(
		header, profiles[:], bad_state[:], maps[:], bindings[:], selectors[:], surfaces[:],
		remaps[:], ordering[:], strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.Invalid_State)

	bad_binding := bindings
	bad_binding[0].scope = u64(interaction.Binding_Scope.Shared_Continuity)
	failure = keymap_profile_records_validate(
		header, profiles[:], states[:], maps[:], bad_binding[:], selectors[:], surfaces[:],
		remaps[:], ordering[:], strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.Invalid_Binding)

	shared_binding := bindings
	shared_binding[0].scope = u64(interaction.Binding_Scope.Shared_Continuity)
	shared_binding[0].selector_count = 1
	shared_binding[0].protection_reason_offset = 0
	shared_binding[0].protection_reason_bytes = 0
	shared_selectors := [?]Keymap_Selector_Record {{profile_id = 1, state_id = 1}}
	shared_header := header
	shared_header.selector_count = 1
	shared_header.record_bytes, _ = keymap_profile_record_bytes(
		shared_header.profile_count, shared_header.state_count, shared_header.map_count,
		shared_header.binding_count, shared_header.selector_count, shared_header.surface_count,
		shared_header.remap_count, shared_header.ordering_count, shared_header.stroke_count,
		shared_header.text_bytes,
	)
	failure = keymap_profile_records_validate(
		shared_header, profiles[:], states[:], maps[:], shared_binding[:], shared_selectors[:],
		surfaces[:], remaps[:], ordering[:], strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.None)
	shared_binding[0].scope = u64(interaction.Binding_Scope.State_Specific)
	failure = keymap_profile_records_validate(
		shared_header, profiles[:], states[:], maps[:], shared_binding[:], shared_selectors[:],
		surfaces[:], remaps[:], ordering[:], strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.None)
	shared_selectors[0].state_id = 99
	failure = keymap_profile_records_validate(
		shared_header, profiles[:], states[:], maps[:], shared_binding[:], shared_selectors[:],
		surfaces[:], remaps[:], ordering[:], strokes[:], text,
	)
	testing.expect_value(t, failure.code, Keymap_Record_Failure_Code.Invalid_Selector)

	_, oversized := keymap_profile_record_bytes(
		MAX_KEYMAP_PROFILE_PROFILES + 1, 1, 1, 0, 0, 1, 0, 0, 0, 0,
	)
	testing.expect_value(t, oversized.code, Keymap_Record_Failure_Code.Profile_Limit)
	_, oversized_copy := keymap_profile_record_bytes(
		MAX_KEYMAP_PROFILE_PROFILES, MAX_KEYMAP_PROFILE_STATES, MAX_KEYMAP_PROFILE_MAPS,
		MAX_KEYMAP_PROFILE_BINDINGS, MAX_KEYMAP_PROFILE_SELECTORS, MAX_KEYMAP_PROFILE_SURFACES,
		MAX_KEYMAP_PROFILE_REMAPS, MAX_KEYMAP_PROFILE_ORDERING, MAX_KEYMAP_PROFILE_STROKES,
		MAX_KEYMAP_PROFILE_TEXT_BYTES,
	)
	testing.expect_value(t, oversized_copy.code, Keymap_Record_Failure_Code.Copy_Limit)
}
