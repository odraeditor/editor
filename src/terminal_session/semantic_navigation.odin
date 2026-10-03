// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "../terminal_emulator"

@(private)
Osc_133_Parser :: struct {
	bytes:     [MAX_OSC_133_BYTES]u8,
	length:    u16,
	overflow:  bool,
	last_byte: u8,
}

@(private)
Semantic_Prompt_Owner :: struct {
	sequence: u64,
	anchor:   terminal_emulator.Semantic_Anchor,
}

@(private)
Semantic_State :: struct {
	parser:                  Osc_133_Parser,
	prompts:                 [MAX_SEMANTIC_RECORDS]Semantic_Prompt_Owner,
	prompt_count:            u16,
	results:                 [MAX_SEMANTIC_RECORDS]Command_Result_Record,
	result_count:            u16,
	next_sequence:           u64,
	active_prompt_sequence:  u64,
	active_command_sequence: u64,
	active_output_start:     u64,
}

@(private)
Osc_133_Marker :: struct {
	kind:                u8,
	exit_status:         i32,
	exit_status_present: bool,
}

/* registry_move_prompt resolves one next or previous confirmed retained boundary. */
registry_move_prompt :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	current_sequence: u64,
	movement: Prompt_Movement,
) -> (record: Prompt_Record, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Navigation)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Navigation, .Stale_Reference)
	if movement == .Invalid do return {}, false, failure_record(.Navigation, .Invalid_Argument)
	semantic_reconcile_prompts(session)
	if session.semantic.prompt_count == 0 {
		return {}, false, failure_record(.Navigation, .Navigation_Unavailable)
	}
	index := -1
	if current_sequence == 0 {
		index = 0
		if movement == .Previous do index = int(session.semantic.prompt_count) - 1
	} else {
		current := -1
		for prompt, prompt_index in session.semantic.prompts[:session.semantic.prompt_count] {
			if prompt.sequence == current_sequence do current = prompt_index
		}
		if current < 0 {
			return {}, false, failure_record(.Navigation, .Navigation_Unavailable)
		}
		index = current + 1
		if movement == .Previous do index = current - 1
		if index < 0 || index >= int(session.semantic.prompt_count) {
			return {}, false, failure_record(.Navigation, .Navigation_Unavailable)
		}
	}
	owner := session.semantic.prompts[index]
	row, column, anchor_result := terminal_emulator.semantic_anchor_resolve(
		session.record.emulator, owner.anchor,
	)
	if anchor_result != .OK {
		semantic_remove_prompt(session, index)
		return {}, false, failure_record(.Navigation, .Navigation_Unavailable)
	}
	return Prompt_Record{ref = ref, sequence = owner.sequence, row = row, column = column}, true, {}
}

/* registry_semantic_stats copies bounded semantic-record accounting. */
registry_semantic_stats :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (stats: Semantic_Stats, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return {}, false, registry_access_failure(registry, .Navigation)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return {}, false, failure_record(.Navigation, .Stale_Reference)
	semantic_reconcile_prompts(session)
	semantic_snapshot, result := terminal_emulator.semantic_state(session.record.emulator)
	if result != .OK do return {}, false, emulator_failure(.Navigation, result)
	return Semantic_Stats {
		ref = ref,
		prompt_records = session.semantic.prompt_count,
		result_records = session.semantic.result_count,
		next_sequence = session.semantic.next_sequence,
		alternate_screen = semantic_snapshot.alternate_screen,
	}, true, {}
}

/* registry_copy_command_results copies current records without exposing owned anchors. */
registry_copy_command_results :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	output: []Command_Result_Record,
) -> (copied, required: int, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return 0, 0, false, registry_access_failure(registry, .Navigation)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return 0, 0, false, failure_record(.Navigation, .Stale_Reference)
	semantic_reconcile_prompts(session)
	required = int(session.semantic.result_count)
	copied = copy(output, session.semantic.results[:session.semantic.result_count])
	return copied, required, true, {}
}

@(private)
semantic_write_session :: proc(session: ^Session_State, bytes: []u8) -> terminal_emulator.Result {
	if len(bytes) == 0 do return .OK
	segment_start := 0
	for byte, index in bytes {
		marker, complete := osc_133_parser_push(&session.semantic.parser, byte)
		if !complete do continue
		result := terminal_emulator.write(session.record.emulator, bytes[segment_start:index + 1])
		if result != .OK do return result
		session.record.output_bytes += u64(index + 1 - segment_start)
		semantic_record_marker(session, marker)
		segment_start = index + 1
	}
	if segment_start < len(bytes) {
		result := terminal_emulator.write(session.record.emulator, bytes[segment_start:])
		if result == .OK do session.record.output_bytes += u64(len(bytes) - segment_start)
		return result
	}
	return .OK
}

@(private)
osc_133_parser_push :: proc(parser: ^Osc_133_Parser, byte: u8) -> (Osc_133_Marker, bool) {
	if parser.overflow {
		terminated := byte == 0x07 || byte == 0x9c || (byte == '\\' && parser.last_byte == 0x1b)
		parser.last_byte = byte
		if terminated do parser^ = {}
		return {}, false
	}
	if parser.length == 0 {
		if byte == 0x1b {
			parser.bytes[0] = byte
			parser.length = 1
		}
		return {}, false
	}
	if parser.length == 1 && byte != ']' {
		if byte != 0x1b do parser.length = 0
		return {}, false
	}
	if int(parser.length) < len(parser.bytes) {
		parser.bytes[parser.length] = byte
		parser.length += 1
	} else {
		parser.overflow = true
		parser.last_byte = byte
	}
	terminated := byte == 0x07 || byte == 0x9c ||
		(byte == '\\' && parser.length >= 2 && parser.bytes[parser.length - 2] == 0x1b)
	if !terminated do return {}, false
	marker, recognized := osc_133_parse(parser)
	parser^ = {}
	return marker, recognized
}

@(private)
osc_133_parse :: proc(parser: ^Osc_133_Parser) -> (Osc_133_Marker, bool) {
	if parser.overflow || parser.length < 8 do return {}, false
	end := int(parser.length) - 1
	if parser.bytes[end] == '\\' {
		if end == 0 || parser.bytes[end - 1] != 0x1b do return {}, false
		end -= 1
	}
	content := parser.bytes[:end]
	if len(content) < 7 || content[0] != 0x1b || content[1] != ']' ||
	   content[2] != '1' || content[3] != '3' || content[4] != '3' || content[5] != ';' {
		return {}, false
	}
	kind := content[6]
	if kind != 'A' && kind != 'B' && kind != 'C' && kind != 'D' do return {}, false
	if len(content) > 7 && content[7] != ';' do return {}, false
	marker := Osc_133_Marker{kind = kind}
	if kind == 'D' && len(content) > 8 {
		status, parsed := osc_133_exit_status(content[8:])
		if parsed {
			marker.exit_status = status
			marker.exit_status_present = true
		}
	}
	return marker, true
}

@(private)
osc_133_exit_status :: proc(bytes: []u8) -> (i32, bool) {
	if len(bytes) == 0 do return 0, false
	value: i64
	for byte in bytes {
		if byte < '0' || byte > '9' do return 0, false
		value = value * 10 + i64(byte - '0')
		if value > i64(max(i32)) do return 0, false
	}
	return i32(value), true
}

@(private)
semantic_record_marker :: proc(session: ^Session_State, marker: Osc_133_Marker) {
	semantic_snapshot, state_result := terminal_emulator.semantic_state(session.record.emulator)
	if state_result != .OK || semantic_snapshot.alternate_screen do return
	switch marker.kind {
	case 'A':
		semantic_append_prompt(session)
		session.semantic.active_command_sequence = 0
	case 'B':
		// The prompt is complete; input cells now belong to the same prompt record.
	case 'C':
		session.semantic.active_command_sequence = semantic_next_sequence(&session.semantic)
		session.semantic.active_output_start = session.record.output_bytes
	case 'D':
		if session.semantic.active_prompt_sequence == 0 || session.semantic.active_command_sequence == 0 do return
		semantic_append_result(session, marker)
		session.semantic.active_command_sequence = 0
	}
}

@(private)
semantic_append_prompt :: proc(session: ^Session_State) {
	if session.semantic.prompt_count == MAX_SEMANTIC_RECORDS {
		semantic_remove_prompt(session, 0)
	}
	anchor, result := terminal_emulator.semantic_anchor_open(session.record.emulator)
	if result != .OK do return
	sequence := semantic_next_sequence(&session.semantic)
	index := int(session.semantic.prompt_count)
	session.semantic.prompts[index] = {sequence = sequence, anchor = anchor}
	session.semantic.prompt_count += 1
	session.semantic.active_prompt_sequence = sequence
}

@(private)
semantic_append_result :: proc(session: ^Session_State, marker: Osc_133_Marker) {
	if session.semantic.result_count == MAX_SEMANTIC_RECORDS {
		copy(session.semantic.results[:], session.semantic.results[1:])
		session.semantic.result_count -= 1
	}
	index := int(session.semantic.result_count)
	session.semantic.results[index] = Command_Result_Record {
		ref = session.record.ref,
		sequence = session.semantic.active_command_sequence,
		prompt_sequence = session.semantic.active_prompt_sequence,
		output_start_bytes = session.semantic.active_output_start,
		output_end_bytes = session.record.output_bytes,
		exit_status = marker.exit_status,
		exit_status_present = marker.exit_status_present,
	}
	session.semantic.result_count += 1
}

@(private)
semantic_next_sequence :: proc(state: ^Semantic_State) -> u64 {
	state.next_sequence += 1
	if state.next_sequence == 0 do state.next_sequence = 1
	return state.next_sequence
}

@(private)
semantic_reconcile_prompts :: proc(session: ^Session_State) {
	index := 0
	for index < int(session.semantic.prompt_count) {
		owner := session.semantic.prompts[index]
		_, _, result := terminal_emulator.semantic_anchor_resolve(session.record.emulator, owner.anchor)
		if result == .OK {
			index += 1
			continue
		}
		semantic_remove_prompt(session, index)
	}
}

@(private)
semantic_remove_prompt :: proc(session: ^Session_State, index: int) {
	if index < 0 || index >= int(session.semantic.prompt_count) do return
	sequence := session.semantic.prompts[index].sequence
	_ = terminal_emulator.semantic_anchor_close(
		session.record.emulator, session.semantic.prompts[index].anchor,
	)
	copy(session.semantic.prompts[index:], session.semantic.prompts[index + 1:session.semantic.prompt_count])
	session.semantic.prompt_count -= 1
	session.semantic.prompts[session.semantic.prompt_count] = {}
	result_index := 0
	for result_index < int(session.semantic.result_count) {
		if session.semantic.results[result_index].prompt_sequence != sequence {
			result_index += 1
			continue
		}
		copy(
			session.semantic.results[result_index:],
			session.semantic.results[result_index + 1:session.semantic.result_count],
		)
		session.semantic.result_count -= 1
		session.semantic.results[session.semantic.result_count] = {}
	}
	if session.semantic.active_prompt_sequence == sequence {
		session.semantic.active_prompt_sequence = 0
		session.semantic.active_command_sequence = 0
	}
}
