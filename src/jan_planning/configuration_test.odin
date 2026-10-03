// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies configured values are copied and replace factory state atomically. */
@(test)
planning_configuration_copies_generation :: proc(t: ^testing.T) {
	configuration: Configuration
	initialized, failure := planning_configuration_init(&configuration, 1, 1)
	testing.expectf(t, initialized, "planning factory configuration failed with %v", failure.code)
	if !initialized do return
	defer planning_configuration_close(&configuration)
	label := [4]u8{'T', 'a', 's', 'k'}
	states := [2]Workflow_State_Candidate {
		{name = "TODO", presentation = .Todo, log = .State},
		{name = "DONE", finished = true, presentation = .Done, log = .Time},
	}
	workflows := [1]Workflow_Candidate{{identity = "default", states = states[:]}}
	sources := [1]Source_Candidate{{identity = "notes", kind = .Directory, resource = "notes", discovery_depth = 4, document_limit = 128}}
	source_sets := [1]Source_Set_Candidate{{identity = "agenda", sources = sources[:]}}
	captures := [1]Capture_Candidate{{key = 't', label = string(label[:]), entry_kind = .Task, target = "inbox.org::* Inbox", template = "* TODO %?"}}
	agendas := [1]Agenda_Candidate{{key = 'w', label = "Week", query = "task:unfinished", span = .Week, result_limit = 4_096}}
	candidate := Configuration_Candidate {
		generation = 2,
		provider_generation = 2,
		workflows = workflows[:],
		source_sets = source_sets[:],
		captures = captures[:],
		agendas = agendas[:],
	}
	descriptor: Configuration_Descriptor
	published: bool
	descriptor, published, failure = planning_configuration_publish(&configuration, candidate)
	testing.expectf(t, published, "planning configuration failed with %v", failure.code)
	testing.expect_value(t, descriptor.workflow_count, u16(1))
	testing.expect_value(t, descriptor.workflow_states, u16(2))
	testing.expect_value(t, descriptor.source_count, u16(1))
	label[0] = 'M'
	workflow, workflow_ok := planning_configuration_workflow(&configuration, 0)
	state, state_ok := planning_configuration_workflow_state(&configuration, 1)
	source, source_ok := planning_configuration_source(&configuration, 0)
	capture, capture_ok := planning_configuration_capture(&configuration, 0)
	agenda, agenda_ok := planning_configuration_agenda(&configuration, 0)
	testing.expect(t, workflow_ok && state_ok && source_ok && capture_ok && agenda_ok)
	testing.expect_value(t, workflow.identity, "default")
	testing.expect_value(t, state.name, "DONE")
	testing.expect_value(t, source.resource, "notes")
	testing.expect_value(t, capture.label, "Task")
	testing.expect_value(t, agenda.query, "task:unfinished")
}

/* Verifies stale, conflicting, and over-limit candidates retain factory state. */
@(test)
planning_configuration_rejects_atomically :: proc(t: ^testing.T) {
	configuration: Configuration
	initialized, _ := planning_configuration_init(&configuration, 7, 7)
	testing.expect(t, initialized)
	if !initialized do return
	defer planning_configuration_close(&configuration)
	states := [2]Workflow_State_Candidate {
		{name = "TODO", presentation = .Todo, log = .None},
		{name = "DONE", finished = true, presentation = .Done, log = .None},
	}
	workflows := [1]Workflow_Candidate{{identity = "default", states = states[:]}}
	duplicate_captures := [2]Capture_Candidate {
		{key = 't', label = "Task", entry_kind = .Task, target = "inbox", template = "* TODO"},
		{key = 't', label = "Note", entry_kind = .Heading, target = "notes", template = "* Note"},
	}
	candidate := Configuration_Candidate {
		generation = 8,
		provider_generation = 8,
		workflows = workflows[:],
		captures = duplicate_captures[:],
	}
	_, published, failure := planning_configuration_publish(&configuration, candidate)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Conflict)
	confirmed, _ := planning_configuration_inspect(&configuration)
	testing.expect_value(t, confirmed.generation, Configuration_Generation(7))
	too_many: [int(MAX_WORKFLOWS) + 1]Workflow_Candidate
	candidate.workflows = too_many[:]
	candidate.captures = nil
	_, published, failure = planning_configuration_publish(&configuration, candidate)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, Failure_Code.Limited)
}

/* Verifies every configuration allocation can fail without leaking or replacing state. */
@(test)
planning_config_survives_allocation_faults :: proc(t: ^testing.T) {
	for fail_after in 1 ..< 10 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Planning_Test_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		configuration: Configuration
		initialized, _ := planning_configuration_init(
			&configuration,
			1,
			1,
			planning_test_failing_allocator(&failing),
		)
		testing.expect(t, initialized)
		if !initialized {
			mem.tracking_allocator_destroy(&tracking)
			continue
		}
		states := [2]Workflow_State_Candidate {
			{name = "TODO", presentation = .Todo, log = .None},
			{name = "DONE", finished = true, presentation = .Done, log = .None},
		}
		workflows := [1]Workflow_Candidate{{identity = "default", states = states[:]}}
		candidate := Configuration_Candidate{generation = 2, provider_generation = 2, workflows = workflows[:]}
		_, published, failure := planning_configuration_publish(&configuration, candidate)
		if !published do testing.expect_value(t, failure.code, Failure_Code.Allocation_Failed)
		descriptor, _ := planning_configuration_inspect(&configuration)
		if !published do testing.expect_value(t, descriptor.generation, Configuration_Generation(1))
		planning_configuration_close(&configuration)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
}

@(private)
Planning_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
planning_test_failing_allocator :: proc(data: ^Planning_Test_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = planning_test_failing_allocator_proc, data = data}
}

@(private)
planning_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := (^Planning_Test_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, .Out_Of_Memory
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
