// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../editor"
import "../hosting"
import "../interaction"
import "core:hash"
import "core:strconv"
import "core:strings"

/* LANGUAGE_KEYMAP_PROJECTION_BYTES bounds one copied language keymap. */
LANGUAGE_KEYMAP_PROJECTION_BYTES :: 64 * 1024

@(private)
Language_Keymap_Workflow_State :: struct {
	map_handle:          interaction.Context_Map_Handle,
	language_id:         u64,
	language_generation: u64,
	registry_generation: interaction.Registry_Generation,
	profile:             interaction.Profile_Identity,
	state:               interaction.Interaction_State_Identity,
	resolved:            bool,
}

@(private)
language_keymap_profile_state_name :: proc(
	profile: interaction.Profile_Identity,
	state: interaction.Interaction_State_Definition,
	commands: ^Command_Context,
) -> (string, bool) {
	if commands == nil || commands.profile_activation == nil do return "", false
	catalog, active := interaction.profile_activation_catalog(commands.profile_activation)
	if !active do return "", false
	for definition in catalog.profiles {
		if definition.identity != profile do continue
		if definition.name == "direct" do return "direct", true
		switch state.name {
		case "Normal":           return "normal", true
		case "Insert":           return "insert", true
		case "Visual Character": return "visual-character", true
		case "Visual Line":      return "visual-line", true
		case "Replace":          return "replace", true
		case "Visual Block":     return "visual-block", true
		}
		return "", false
	}
	return "", false
}

@(private)
language_keymap_hash_identity :: proc(value: string, salt: u64) -> u64 {
	result := hash.fnv64a(transmute([]byte)value) ~ salt
	return max(result, 1)
}

@(private)
language_keymap_parse_stroke :: proc(value: string) -> (interaction.Key_Stroke, bool) {
	fields := strings.split(value, ",", context.temp_allocator)
	defer delete(fields, context.temp_allocator)
	if len(fields) != 3 do return {}, false
	kind, kind_ok := strconv.parse_u64_of_base(fields[0], 10)
	scalar, scalar_ok := strconv.parse_i64_of_base(fields[1], 10)
	modifiers, modifiers_ok := strconv.parse_u64_of_base(fields[2], 10)
	if !kind_ok || !scalar_ok || !modifiers_ok ||
	   kind == 0 || kind > u64(interaction.Logical_Key_Kind.F4) ||
	   scalar < 0 || scalar > i64(max(rune)) || modifiers > u64(max(u8)) {
		return {}, false
	}
	return interaction.Key_Stroke {
		kind = interaction.Logical_Key_Kind(kind),
		scalar = rune(scalar),
		modifiers = transmute(interaction.Modifiers)u8(modifiers),
	}, true
}

@(private)
language_keymap_parse_binding :: proc(
	line: string,
) -> (interaction.Binding_Definition, bool) {
	separator := strings.index_byte(line, '\t')
	if separator <= 0 || separator >= len(line) - 1 do return {}, false
	sequence_text := line[:separator]
	command_name := line[separator + 1:]
	if len(command_name) == 0 || len(command_name) > interaction.MAX_COMMAND_NAME_BYTES {
		return {}, false
	}
	stroke_fields := strings.split(sequence_text, ";", context.temp_allocator)
	defer delete(stroke_fields, context.temp_allocator)
	if len(stroke_fields) == 0 || len(stroke_fields) > interaction.MAX_SEQUENCE_STROKES {
		return {}, false
	}
	binding: interaction.Binding_Definition
	binding.command_name = command_name
	binding.stroke_count = u8(len(stroke_fields))
	for stroke_text, index in stroke_fields {
		stroke, parsed := language_keymap_parse_stroke(stroke_text)
		if !parsed do return {}, false
		binding.strokes[index] = stroke
	}
	return binding, true
}

@(private)
language_keymap_parse_projection :: proc(
	projection: string,
	bindings: []interaction.Binding_Definition,
) -> (identity: string, priority: i32, binding_count: int, ok: bool) {
	lines := strings.split_lines(projection, context.temp_allocator)
	defer delete(lines, context.temp_allocator)
	if len(lines) == 0 do return "", 0, 0, false
	header := strings.split(lines[0], "\t", context.temp_allocator)
	defer delete(header, context.temp_allocator)
	if len(header) != 5 || header[0] != "odra-language-keymap" || header[1] != "1" ||
	   len(header[2]) == 0 || len(header[2]) > interaction.MAX_IDENTITY_BYTES {
		return "", 0, 0, false
	}
	priority_value, priority_ok := strconv.parse_i64_of_base(header[3], 10)
	count, count_ok := strconv.parse_u64_of_base(header[4], 10)
	if !priority_ok || priority_value < i64(min(i32)) || priority_value > i64(max(i32)) ||
	   !count_ok || count == 0 || count > u64(len(bindings)) ||
	   len(lines) != int(count) + 1 {
		return "", 0, 0, false
	}
	for line, index in lines[1:] {
		binding, parsed := language_keymap_parse_binding(line)
		if !parsed do return "", 0, 0, false
		bindings[index] = binding
	}
	return header[2], i32(priority_value), int(count), true
}

@(private)
command_context_deactivate_language_keymap :: proc(commands: ^Command_Context) -> App_Failure {
	state := &commands.language_keymap_workflow
	if interaction.context_map_handle_is_valid(state.map_handle) &&
	   interaction.context_map_handle_is_active(commands.context_maps, state.map_handle) {
		_, ended, failure := interaction.context_map_end(
			commands.context_maps,
			state.map_handle,
			.Invalidated,
			&commands.context_pending,
			&commands.pending,
		)
		if !ended || failure.code != .None {
			return App_Failure{stage = .Command_Resolution, interaction = failure}
		}
	}
	state^ = {}
	return {}
}

@(private)
command_context_sync_language_keymap :: proc(
	commands: ^Command_Context,
	buffer: ^editor.Buffer,
) -> App_Failure {
	if commands == nil || commands.context_maps == nil || commands.racket_runtime == nil ||
	   commands.syntax_workflow == nil || commands.profile_activation == nil {
		return {}
	}
	inspection, _, _, inspected := syntax_workflow_inspect_buffer(commands.syntax_workflow, buffer)
	profile, active_state, selected := interaction.profile_activation_selection(
		commands.profile_activation,
	)
	state_name, state_named := language_keymap_profile_state_name(
		profile,
		active_state,
		commands,
	)
	language_name := string(
		inspection.association.language.name.bytes[:inspection.association.language.name.length],
	)
	if !inspected || !selected || !state_named || inspection.association.language.id == 0 ||
	   inspection.association.language.generation == 0 || len(language_name) == 0 {
		return command_context_deactivate_language_keymap(commands)
	}
	workflow := &commands.language_keymap_workflow
	if workflow.language_id == u64(inspection.association.language.id) &&
	   workflow.language_generation == u64(inspection.association.language.generation) &&
	   workflow.registry_generation == commands.registry_generation &&
	   workflow.profile == profile && workflow.state == active_state.identity && workflow.resolved &&
	   (!interaction.context_map_handle_is_valid(workflow.map_handle) ||
	    interaction.context_map_handle_is_active(commands.context_maps, workflow.map_handle)) {
		return {}
	}
	projection, allocation_error := make(
		[]byte,
		LANGUAGE_KEYMAP_PROJECTION_BYTES,
		commands.temporary_allocator,
	)
	if allocation_error != nil do return App_Failure{stage = .Command_Resolution}
	defer delete(projection, commands.temporary_allocator)
	written, invoked, _ := hosting.runtime_provider_invoke(
		commands.racket_runtime,
		"language.keymap-projection",
		u64(commands.registry_generation),
		0,
		language_name,
		transmute([]byte)state_name,
		projection,
	)
	if !invoked {
		return command_context_deactivate_language_keymap(commands)
	}
	if written == 0 {
		deactivation_failure := command_context_deactivate_language_keymap(commands)
		if deactivation_failure.stage != .None do return deactivation_failure
		workflow.language_id = u64(inspection.association.language.id)
		workflow.language_generation = u64(inspection.association.language.generation)
		workflow.registry_generation = commands.registry_generation
		workflow.profile = profile
		workflow.state = active_state.identity
		workflow.resolved = true
		return {}
	}
	bindings: [interaction.MAX_CONTEXT_BINDINGS]interaction.Binding_Definition
	identity, priority, binding_count, parsed := language_keymap_parse_projection(
		string(projection[:written]),
		bindings[:],
	)
	if !parsed do return App_Failure{stage = .Command_Resolution}
	deactivation_failure := command_context_deactivate_language_keymap(commands)
	if deactivation_failure.stage != .None do return deactivation_failure
	map_id := interaction.Map_ID(language_keymap_hash_identity(identity, 0x4c4b_4d41_5000_0000))
	owner_id := interaction.Owner_ID(language_keymap_hash_identity(identity, 0x4c4b_4f57_4e00_0000))
	result, activated, _ := interaction.context_map_activate(
		commands.context_maps,
		interaction.Context_Map_Definition {
			identity = {id = map_id, revision = 1},
			name = identity,
			owner_id = owner_id,
			precedence = .Language_Context,
			priority = priority,
			bindings = bindings[:binding_count],
			unmatched_input_policy = .Fallthrough,
		},
		&commands.context_pending,
		&commands.pending,
	)
	if !activated {
		workflow.language_id = u64(inspection.association.language.id)
		workflow.language_generation = u64(inspection.association.language.generation)
		workflow.registry_generation = commands.registry_generation
		workflow.profile = profile
		workflow.state = active_state.identity
		workflow.resolved = true
		return {}
	}
	workflow^ = {
		map_handle = result.handle,
		language_id = u64(inspection.association.language.id),
		language_generation = u64(inspection.association.language.generation),
		registry_generation = commands.registry_generation,
		profile = profile,
		state = active_state.identity,
		resolved = true,
	}
	return {}
}
