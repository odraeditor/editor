// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../bridge"
import "../command"
import "../hosting"
import "../interaction"
import "../project"
import "core:fmt"

/* GLOBAL_SELECTION_HISTORY_ID owns durable Project and Workspace opening recency. */
GLOBAL_SELECTION_HISTORY_ID :: "global-selection"

@(private)
command_context_candidate_history_ensure :: proc(
	commands: ^Command_Context,
	command_handle: interaction.Command_Handle,
) -> bool {
	if commands == nil {
		return false
	}
	desired_handle: project.Project_Handle
	desired_id := ""
	active, active_ok, _ := command.project_inspect_active(
		command_context_project_command_context(commands, command_handle),
	)
	if active_ok {
		desired_handle = active.descriptor.handle
		if !active.descriptor.temporary {
			identity := active.descriptor.durable_id
			desired_id = project.project_durable_id_text(&identity)
		}
	}
	if commands.project_workflow.candidate_history.state != nil &&
	   !commands.project_workflow.candidate_history_global &&
	   commands.project_workflow.candidate_history_project == desired_handle {
		return true
	}
	command_context_candidate_history_flush(commands)
	project.candidate_history_close(&commands.project_workflow.candidate_history)
	commands.project_workflow.candidate_history_project = desired_handle
	commands.project_workflow.candidate_history_global = false
	commands.project_workflow.candidate_history_persistence_ready = false
	initialized, init_failure := project.candidate_history_init(
		&commands.project_workflow.candidate_history,
		desired_id,
		commands.persistent_allocator,
	)
	if !initialized {
		command_context_candidate_history_native_diagnostic(commands, "initialization", init_failure)
		commands.project_workflow.candidate_history_project = {}
		return false
	}
	if len(desired_id) == 0 {
		return true
	}
	return command_context_candidate_history_load(commands, desired_id)
}

@(private)
command_context_global_candidate_history_ensure :: proc(commands: ^Command_Context) -> bool {
	if commands == nil {
		return false
	}
	if commands.project_workflow.candidate_history.state != nil &&
	   commands.project_workflow.candidate_history_global {
		return true
	}
	command_context_candidate_history_flush(commands)
	project.candidate_history_close(&commands.project_workflow.candidate_history)
	commands.project_workflow.candidate_history_project = {}
	commands.project_workflow.candidate_history_global = true
	commands.project_workflow.candidate_history_persistence_ready = false
	initialized, init_failure := project.candidate_history_init(
		&commands.project_workflow.candidate_history,
		GLOBAL_SELECTION_HISTORY_ID,
		commands.persistent_allocator,
	)
	if !initialized {
		command_context_candidate_history_native_diagnostic(commands, "initialization", init_failure)
		commands.project_workflow.candidate_history_global = false
		return false
	}
	return command_context_candidate_history_load(commands, GLOBAL_SELECTION_HISTORY_ID)
}

@(private)
command_context_global_candidate_history_rank_source :: proc(
	commands: ^Command_Context,
	definition: ^interaction.Candidate_Source_Definition,
) {
	if commands == nil || definition == nil ||
	   !command_context_global_candidate_history_ensure(commands) {
		return
	}
	for &descriptor in definition.descriptors {
		category, durable := candidate_history_category(descriptor.durable_category)
		if !durable do continue
		sequence, found := project.candidate_history_lookup(
			&commands.project_workflow.candidate_history,
			category,
			descriptor.durable_key,
		)
		if found do descriptor.recency = max(descriptor.recency, sequence)
	}
}

@(private)
command_context_global_candidate_history_record :: proc(
	commands: ^Command_Context,
	category: interaction.Candidate_Durable_Category,
	key: string,
) -> bool {
	if !command_context_global_candidate_history_ensure(commands) {
		return false
	}
	return command_context_candidate_history_record(commands, category, key)
}

@(private)
command_context_candidate_history_load :: proc(
	commands: ^Command_Context,
	project_id: string,
) -> bool {
	output, allocation_error := make(
		[]u8,
		hosting.MAX_CANDIDATE_HISTORY_BYTES,
		commands.temporary_allocator,
	)
	if allocation_error != nil {
		command_context_set_diagnostic(commands, "Candidate history load failed: temporary memory limit; empty ordering active")
		return false
	}
	defer delete(output, commands.temporary_allocator)
	output_length, loaded, load_failure := hosting.runtime_candidate_usage_load(
		commands.racket_runtime,
		commands.candidate_history_state_root,
		project_id,
		output,
	)
	if !loaded || output_length < bridge.CANDIDATE_HISTORY_LOAD_HEADER_BYTES {
		command_context_candidate_history_host_diagnostic(commands, "load", load_failure)
		return false
	}
	bytes := output[:int(output_length)]
	if candidate_history_word(bytes, 0) != bridge.CANDIDATE_HISTORY_SCHEMA_VERSION {
		command_context_set_diagnostic(commands, "Candidate history load failed: unsupported copied schema; empty ordering active")
		return false
	}
	observation := bridge.Candidate_History_Observation(candidate_history_word(bytes, 8))
	generation := candidate_history_word(bytes, 16)
	next_sequence := candidate_history_word(bytes, 24)
	entry_count := candidate_history_word(bytes, 32)
	key_bytes := candidate_history_word(bytes, 40)
	diagnostic_offset := candidate_history_word(bytes, 48)
	diagnostic_bytes := candidate_history_word(bytes, 56)
	expected_bytes, width_ok := bridge.candidate_history_load_record_bytes(
		entry_count,
		key_bytes,
		diagnostic_bytes,
	)
	if !width_ok || expected_bytes != output_length || diagnostic_offset != key_bytes {
		command_context_set_diagnostic(commands, "Candidate history load failed: invalid copied record width; empty ordering active")
		return false
	}
	if observation == .Absent {
		if generation != 0 || next_sequence != 1 || entry_count != 0 || key_bytes != 0 {
			return false
		}
		cleared, _ := project.candidate_history_clear_loaded(
			&commands.project_workflow.candidate_history,
		)
		commands.project_workflow.candidate_history_persistence_ready = cleared
		return cleared
	}
	entry_start := int(bridge.CANDIDATE_HISTORY_LOAD_HEADER_BYTES)
	key_start := entry_start + int(entry_count * bridge.CANDIDATE_HISTORY_ENTRY_RECORD_BYTES)
	diagnostic_start := key_start + int(diagnostic_offset)
	diagnostic_end := diagnostic_start + int(diagnostic_bytes)
	if observation == .Rejected || observation == .Unavailable {
		if generation != 0 || next_sequence != 1 || entry_count != 0 || key_bytes != 0 ||
		   diagnostic_bytes == 0 || diagnostic_end > len(bytes) {
			command_context_set_diagnostic(commands, "Candidate history load failed: invalid rejection record; empty ordering active")
			return false
		}
		cleared, clear_failure := project.candidate_history_clear_loaded(
			&commands.project_workflow.candidate_history,
		)
		if !cleared {
			command_context_candidate_history_native_diagnostic(commands, "fallback", clear_failure)
			return false
		}
		commands.project_workflow.candidate_history_persistence_ready = false
		state := "rejected"
		if observation == .Unavailable {
			state = "unavailable"
		}
		message := fmt.bprintf(
			commands.diagnostic[:],
			"Candidate history %s: %s; empty ordering active",
			state,
			string(bytes[diagnostic_start:diagnostic_end]),
		)
		commands.diagnostic_length = len(message)
		return true
	}
	if observation != .Confirmed || generation == 0 || next_sequence == 0 ||
	   diagnostic_bytes != 0 {
		command_context_set_diagnostic(commands, "Candidate history load failed: invalid observation; empty ordering active")
		return false
	}
	definitions, definitions_error := make(
		[]project.Candidate_History_Entry_Definition,
		int(entry_count),
		commands.temporary_allocator,
	)
	if definitions_error != nil {
		command_context_set_diagnostic(commands, "Candidate history load failed: temporary memory limit; empty ordering active")
		return false
	}
	defer delete(definitions, commands.temporary_allocator)
	for &definition, index in definitions {
		offset := entry_start + index * int(bridge.CANDIDATE_HISTORY_ENTRY_RECORD_BYTES)
		category := project.Candidate_History_Category(candidate_history_word(bytes, offset))
		key_offset := candidate_history_word(bytes, offset + 8)
		key_length := candidate_history_word(bytes, offset + 16)
		sequence := candidate_history_word(bytes, offset + 24)
		if key_offset > key_bytes || key_length > key_bytes - key_offset {
			command_context_set_diagnostic(commands, "Candidate history load failed: invalid key range; empty ordering active")
			return false
		}
		definition.category = category
		definition.key = string(bytes[
			key_start + int(key_offset):key_start + int(key_offset + key_length)
		])
		definition.sequence = sequence
	}
	replaced, replace_failure := project.candidate_history_replace(
		&commands.project_workflow.candidate_history,
		project_id,
		generation,
		next_sequence,
		definitions,
	)
	commands.project_workflow.candidate_history_persistence_ready = replaced
	if !replaced {
		command_context_candidate_history_native_diagnostic(commands, "admission", replace_failure)
	}
	return replaced
}

@(private)
command_context_candidate_history_rank_source :: proc(
	commands: ^Command_Context,
	definition: ^interaction.Candidate_Source_Definition,
	command_handle: interaction.Command_Handle,
) {
	if commands == nil || definition == nil {
		return
	}
	_ = command_context_candidate_history_ensure(commands, command_handle)
	if commands.project_workflow.candidate_history.state == nil {
		return
	}
	for &descriptor in definition.descriptors {
		category, durable := candidate_history_category(descriptor.durable_category)
		if !durable {
			continue
		}
		sequence, found := project.candidate_history_lookup(
			&commands.project_workflow.candidate_history,
			category,
			descriptor.durable_key,
		)
		if found {
			descriptor.recency = max(descriptor.recency, sequence)
		}
	}
}

@(private)
command_context_candidate_history_record :: proc(
	commands: ^Command_Context,
	category: interaction.Candidate_Durable_Category,
	key: string,
) -> bool {
	if commands == nil || commands.project_workflow.candidate_history.state == nil {
		return false
	}
	project_category, durable := candidate_history_category(category)
	if !durable {
		return true
	}
	_, recorded, record_failure := project.candidate_history_record_success(
		&commands.project_workflow.candidate_history,
		project_category,
		key,
	)
	if recorded && project.candidate_history_flush_due(
		&commands.project_workflow.candidate_history,
	) {
		command_context_candidate_history_flush(commands)
	}
	if !recorded {
		command_context_candidate_history_native_diagnostic(commands, "recording", record_failure)
	}
	return recorded
}

@(private)
command_context_candidate_history_flush :: proc(commands: ^Command_Context) -> bool {
	if commands == nil || !commands.project_workflow.candidate_history_persistence_ready ||
	   commands.project_workflow.candidate_history.state == nil {
		return false
	}
	for {
		batch, copied, snapshot_failure := project.candidate_history_snapshot(
			&commands.project_workflow.candidate_history,
			commands.temporary_allocator,
		)
		if !copied {
			command_context_candidate_history_native_diagnostic(commands, "snapshot", snapshot_failure)
			return false
		}
		if batch.dirty_generation == 0 {
			project.candidate_history_batch_close(&batch)
			return true
		}
		published := command_context_candidate_history_publish(commands, &batch)
		project.candidate_history_batch_close(&batch)
		if published {
			return true
		}
		retry, retry_failure := project.candidate_history_note_flush_failure(
			&commands.project_workflow.candidate_history,
		)
		if !retry {
			command_context_candidate_history_native_diagnostic(commands, "publication retry", retry_failure)
			return false
		}
	}
}

@(private)
command_context_candidate_history_publish :: proc(
	commands: ^Command_Context,
	batch: ^project.Candidate_History_Batch,
) -> bool {
	key_bytes: u64
	for entry in batch.entries {
		key_bytes += u64(len(entry.key))
	}
	request_bytes, width_ok := bridge.candidate_history_publish_record_bytes(
		u64(len(batch.entries)),
		key_bytes,
	)
	if !width_ok {
		command_context_set_diagnostic(commands, "Candidate history publication failed: copied request exceeds limit")
		return false
	}
	request, request_error := make(
		[]u8,
		int(request_bytes),
		commands.temporary_allocator,
	)
	if request_error != nil {
		command_context_set_diagnostic(commands, "Candidate history publication failed: temporary memory limit")
		return false
	}
	defer delete(request, commands.temporary_allocator)
	candidate_history_put(request, 0, bridge.CANDIDATE_HISTORY_SCHEMA_VERSION)
	candidate_history_put(request, 8, batch.generation + 1)
	candidate_history_put(request, 16, batch.next_sequence)
	candidate_history_put(request, 24, u64(len(batch.entries)))
	candidate_history_put(request, 32, key_bytes)
	candidate_history_put(request, 40, batch.generation)
	entry_start := int(bridge.CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES)
	key_start := entry_start + len(batch.entries) * int(bridge.CANDIDATE_HISTORY_ENTRY_RECORD_BYTES)
	key_offset := 0
	for entry, index in batch.entries {
		offset := entry_start + index * int(bridge.CANDIDATE_HISTORY_ENTRY_RECORD_BYTES)
		candidate_history_put(request, offset, u64(entry.category))
		candidate_history_put(request, offset + 8, u64(key_offset))
		candidate_history_put(request, offset + 16, u64(len(entry.key)))
		candidate_history_put(request, offset + 24, entry.sequence)
		copy(request[key_start + key_offset:], transmute([]u8)entry.key)
		key_offset += len(entry.key)
	}
	output: [bridge.CANDIDATE_HISTORY_PUBLICATION_BYTES]u8
	output_length, published, publish_failure := hosting.runtime_candidate_usage_publish(
		commands.racket_runtime,
		commands.candidate_history_state_root,
		batch.project_id,
		request,
		output[:],
	)
	if !published {
		command_context_candidate_history_host_diagnostic(commands, "publication", publish_failure)
		return false
	}
	if output_length != bridge.CANDIDATE_HISTORY_PUBLICATION_BYTES ||
	   candidate_history_word(output[:], 0) != bridge.CANDIDATE_HISTORY_SCHEMA_VERSION {
		command_context_set_diagnostic(commands, "Candidate history publication failed: invalid copied result")
		return false
	}
	publication := bridge.Candidate_History_Publication(candidate_history_word(output[:], 8))
	if publication < .Published_Durable || publication > .Published_Durability_Uncertain {
		command_context_set_diagnostic(commands, "Candidate history publication failed: invalid durability result")
		return false
	}
	published_generation := candidate_history_word(output[:], 16)
	marked, mark_failure := project.candidate_history_mark_published(
		&commands.project_workflow.candidate_history,
		batch.dirty_generation,
		published_generation,
	)
	if !marked {
		command_context_candidate_history_native_diagnostic(commands, "publication confirmation", mark_failure)
	}
	return marked
}

@(private)
command_context_candidate_history_native_diagnostic :: proc(
	commands: ^Command_Context,
	operation: string,
	failure: project.Candidate_History_Failure,
) {
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Candidate history %s failed: %v (expected %d, limit %d, actual %d); navigation remains available",
		operation,
		failure.code,
		failure.expected,
		failure.limit,
		failure.actual,
	)
	commands.diagnostic_length = len(message)
}

@(private)
command_context_candidate_history_host_diagnostic :: proc(
	commands: ^Command_Context,
	operation: string,
	failure: hosting.Failure_Context,
) {
	message := fmt.bprintf(
		commands.diagnostic[:],
		"Candidate history %s failed: %v: %s; navigation remains available",
		operation,
		failure.code,
		failure.diagnostic,
	)
	commands.diagnostic_length = len(message)
}

@(private)
candidate_history_category :: proc(
	category: interaction.Candidate_Durable_Category,
) -> (project.Candidate_History_Category, bool) {
	switch category {
	case .Command:
		return .Command, true
	case .Document:
		return .Document, true
	case .Project_File:
		return .Project_File, true
	case .Project:
		return .Project, true
	case .Workspace:
		return .Workspace, true
	case .None, .Package_Catalog:
		return .Invalid, false
	}
	return .Invalid, false
}

@(private)
candidate_history_word :: proc(bytes: []u8, offset: int) -> u64 {
	assert(offset >= 0 && offset + 8 <= len(bytes))
	value: u64
	for index in 0 ..< 8 {
		value |= u64(bytes[offset + index]) << u64(index * 8)
	}
	return value
}

@(private)
candidate_history_put :: proc(bytes: []u8, offset: int, value: u64) {
	assert(offset >= 0 && offset + 8 <= len(bytes))
	for index in 0 ..< 8 {
		bytes[offset + index] = u8(value >> u64(index * 8))
	}
}
