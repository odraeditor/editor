// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "base:runtime"
import "core:strings"
import "core:text/regex"
import "core:unicode/utf8"

import "../language"

/* MAX_PROPERTY_COMPONENTS bounds one additive property resolution. */
MAX_PROPERTY_COMPONENTS :: 32
/* MAX_TAG_QUERY_TOKENS bounds one Boolean tag expression. */
MAX_TAG_QUERY_TOKENS :: 256
/* MAX_COLUMN_CAPTURE_BYTES bounds one deterministic captured column view. */
MAX_COLUMN_CAPTURE_BYTES :: 4 * 1_024 * 1_024

/* Task_Sequence_Direction selects ordered workflow traversal. */
Task_Sequence_Direction :: enum u8 {
	Invalid,
	Forward,
	Backward,
}

/* Task_Dependency_Policy selects completion prerequisites. */
Task_Dependency_Policy :: struct {
	require_finished_children: bool,
	require_complete_checkboxes: bool,
}

/* Task_Dependency_Status is the copied prerequisite summary for one heading. */
Task_Dependency_Status :: struct {
	unfinished_children:   u32,
	incomplete_checkboxes: u32,
}

/* Task_Transition_Request binds one workflow transition to exact source state. */
Task_Transition_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	target:             Semantic_Target,
	workflow:           string,
	current_state:      string,
	destination_state:  string,
	direction:          Task_Sequence_Direction,
	dependency_policy:  Task_Dependency_Policy,
	dependencies:       Task_Dependency_Status,
	log_record:         string,
	rewrite_generation: language.Jan_Rewrite_Generation,
}

/* Task_Transition describes one admitted workflow edge before source mutation. */
Task_Transition :: struct {
	from:         string,
	to:           string,
	finished:     bool,
	presentation: Presentation_Role,
	log:          Log_Instruction,
}

/* Checkbox_State identifies compatible list checkbox states. */
Checkbox_State :: enum u8 {
	Invalid,
	Unchecked,
	Intermediate,
	Checked,
}

/* Task_Statistics is one derived completion-cookie value. */
Task_Statistics :: struct {
	completed: u32,
	total:     u32,
	percent:   u8,
}

/* Habit_Occurrence is one ordered derived habit outcome. */
Habit_Occurrence :: struct {
	completed: bool,
}

/* Habit_Summary reports derived history without rewriting past occurrences. */
Habit_Summary :: struct {
	completed:     u32,
	missed:        u32,
	current_streak: u32,
}

/* Tag_Origin distinguishes stored, inherited, grouped, and computed membership. */
Tag_Origin :: enum u8 {
	Invalid,
	Local,
	Inherited,
	File,
	Grouped,
	Computed,
}

/* Tag_Candidate is one copied effective-set input with an inspectable owner. */
Tag_Candidate :: struct {
	name:   string,
	origin: Tag_Origin,
	owner:  Semantic_Target,
	active: bool,
}

/* Tag_Group_Kind selects explicit-member or regular-expression expansion. */
Tag_Group_Kind :: enum u8 {
	Invalid,
	Members,
	Regular_Expression,
}

/* Tag_Group is one configured hierarchical or regular-expression group. */
Tag_Group :: struct {
	name:       string,
	kind:       Tag_Group_Kind,
	members:    []string,
	expression: string,
}

/* Tag_Record is one deduplicated effective membership and its origin. */
Tag_Record :: struct {
	name:   string,
	origin: Tag_Origin,
	owner:  Semantic_Target,
}

/* Tag_Query_Kind identifies one postfix Boolean tag-query token. */
Tag_Query_Kind :: enum u8 {
	Invalid,
	Tag,
	And,
	Or,
	Not,
}

/* Tag_Query_Token is one bounded postfix Boolean expression element. */
Tag_Query_Token :: struct {
	kind: Tag_Query_Kind,
	name: string,
}

/* Property_Origin distinguishes editable storage from inherited and derived facts. */
Property_Origin :: enum u8 {
	Invalid,
	Stored,
	Inherited,
	Derived,
}

/* Property_Candidate is one copied property fact in exact precedence order. */
Property_Candidate :: struct {
	name:     string,
	value:    string,
	origin:   Property_Origin,
	owner:    Semantic_Target,
	additive: bool,
}

/* Property_Resolution preserves value origins and additive composition. */
Property_Resolution :: struct {
	name:               string,
	value:              string,
	origin:             Property_Origin,
	owner:              Semantic_Target,
	components:         [MAX_PROPERTY_COMPONENTS]string,
	component_origins:  [MAX_PROPERTY_COMPONENTS]Property_Origin,
	component_count:    u8,
	configuration_generation: Configuration_Generation,
	editable:           bool,
}

/* Property_Edit_Request binds one stored value edit to its exact owning heading. */
Property_Edit_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	target:             Semantic_Target,
	origin:             Property_Origin,
	current_value:      string,
	replacement_value:  string,
	allowed_values:     []string,
	rewrite_generation: language.Jan_Rewrite_Generation,
}

/* Tag_Edit_Request binds one locally stored tag edit to its exact owner. */
Tag_Edit_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	target:             Semantic_Target,
	origin:             Tag_Origin,
	current_value:      string,
	replacement_value:  string,
	rewrite_generation: language.Jan_Rewrite_Generation,
}

/* Column_Summary selects one deterministic column aggregation. */
Column_Summary :: enum u8 {
	None,
	Count,
}

/* Column_Definition configures one property-backed projected column. */
Column_Definition :: struct {
	property:       string,
	heading:        string,
	width:          u16,
	summary:        Column_Summary,
	format:         string,
	allowed_values: []string,
}

/* Column_Row is one exact heading and its copied property facts. */
Column_Row :: struct {
	target:     Semantic_Target,
	properties: []Property_Candidate,
}

/* Column_Cell is one projected value with its canonical edit owner. */
Column_Cell :: struct {
	row:      u32,
	column:   u16,
	value:    string,
	origin:   Property_Origin,
	owner:    Semantic_Target,
	editable: bool,
}

/* Column_Snapshot owns one deterministic tab-separated captured view. */
Column_Snapshot :: struct {
	state: rawptr,
}

/* Column_Snapshot_Descriptor reports bounded captured-view accounting. */
Column_Snapshot_Descriptor :: struct {
	rows:                  u32,
	columns:               u16,
	bytes:                 u64,
	configuration_generation: Configuration_Generation,
}

@(private)
Column_Snapshot_State :: struct {
	descriptor: Column_Snapshot_Descriptor,
	text:       []u8,
	allocator:  runtime.Allocator,
}

/* task_transition_resolve validates one direct or cyclic workflow transition. */
task_transition_resolve :: proc(
	configuration: ^Configuration,
	request: Task_Transition_Request,
) -> (Task_Transition, bool, Failure) {
	failure := task_metadata_failure(request.operation_id, .Task, .Invalid_Request, .Task)
	if configuration == nil || request.operation_id == Operation_ID(0) ||
	   !scope_is_valid(request.scope) || !semantic_target_is_valid(request.target, request.scope) ||
	   request.target.kind != .Heading || request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   !configuration_text_is_valid(request.workflow, MAX_IDENTITY_BYTES) ||
	   !configuration_text_is_valid(request.current_state, MAX_LABEL_BYTES) {
		return {}, false, failure
	}
	descriptor, inspected := planning_configuration_inspect(configuration)
	if !inspected || descriptor.generation != request.scope.configuration_generation ||
	   descriptor.provider_generation != request.scope.provider_generation {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Stale, .Generation)
	}
	workflow, workflow_ok := task_workflow_find(configuration, request.workflow)
	if !workflow_ok {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Unavailable, .Workflow)
	}
	current_index, current_ok := task_workflow_state_find(configuration, workflow, request.current_state)
	if !current_ok {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Malformed, .Workflow)
	}
	destination_index := -1
	if len(request.destination_state) > 0 {
		destination_index, _ = task_workflow_state_find(configuration, workflow, request.destination_state)
	} else if request.direction != .Invalid {
		count := int(workflow.states.count)
		if request.direction == .Forward {
			destination_index = int(workflow.states.start) + (current_index - int(workflow.states.start) + 1) % count
		} else if request.direction == .Backward {
			destination_index = int(workflow.states.start) + (current_index - int(workflow.states.start) + count - 1) % count
		}
	}
	if destination_index < 0 || destination_index == current_index {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Malformed, .Workflow)
	}
	destination, destination_ok := planning_configuration_workflow_state(configuration, destination_index)
	if !destination_ok {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Malformed, .Workflow)
	}
	if destination.finished {
		blocked := u64(0)
		if request.dependency_policy.require_finished_children do blocked += u64(request.dependencies.unfinished_children)
		if request.dependency_policy.require_complete_checkboxes do blocked += u64(request.dependencies.incomplete_checkboxes)
		if blocked > 0 {
			blocked_failure := task_metadata_failure(request.operation_id, .Task, .Conflict, .Task)
			blocked_failure.actual = blocked
			return {}, false, blocked_failure
		}
	}
	return {
		from = request.current_state,
		to = destination.name,
		finished = destination.finished,
		presentation = destination.presentation,
		log = destination.log,
	}, true, {}
}

/* task_transition_destination_for_key resolves one configured fast-selection key. */
task_transition_destination_for_key :: proc(
	configuration: ^Configuration,
	workflow_identity: string,
	key: rune,
) -> (Workflow_State_Record, bool) {
	if configuration == nil || key == rune(0) do return {}, false
	workflow, found := task_workflow_find(configuration, workflow_identity)
	if !found do return {}, false
	for offset in 0 ..< int(workflow.states.count) {
		state, state_found := planning_configuration_workflow_state(
			configuration,
			int(workflow.states.start) + offset,
		)
		if state_found && state.fast_key == key do return state, true
	}
	return {}, false
}

/* task_transition_plan_prepare creates one checked minimal and undoable source change. */
task_transition_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	configuration: ^Configuration,
	request: Task_Transition_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (Task_Transition, bool, Failure) {
	transition, resolved, failure := task_transition_resolve(configuration, request)
	if !resolved do return {}, false, failure
	if transition.log != .None && len(request.log_record) == 0 {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Confirmation_Required, .Task)
	}
	if plan == nil || analysis == nil || u64(len(source)) != request.scope.source_bytes ||
	   !utf8.valid_string(string(source)) || allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Invalid_Request, .Scope)
	}
	start, end, found := task_heading_state_range(source, request.target, request.current_state)
	if !found {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Stale, .Target)
	}
	if len(request.log_record) > MAX_RESOURCE_BYTES || !utf8.valid_string(request.log_record) {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Malformed, .Task)
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Allocation_Failed, .Task)
	}
	defer strings.builder_destroy(&builder)
	target_start, target_end := int(request.target.range.start), int(request.target.range.end)
	prefix := string(source[target_start:start])
	suffix := string(source[end:target_end])
	if strings.write_string(&builder, prefix) != len(prefix) ||
	   strings.write_string(&builder, transition.to) != len(transition.to) ||
	   strings.write_string(&builder, suffix) != len(suffix) {
		return {}, false, task_metadata_failure(request.operation_id, .Task, .Allocation_Failed, .Task)
	}
	if len(request.log_record) > 0 {
		if target_end > target_start && source[target_end - 1] != '\n' &&
		   strings.write_byte(&builder, '\n') != 1 {
			return {}, false, task_metadata_failure(request.operation_id, .Task, .Allocation_Failed, .Task)
		}
		if strings.write_string(&builder, request.log_record) != len(request.log_record) {
			return {}, false, task_metadata_failure(request.operation_id, .Task, .Allocation_Failed, .Task)
		}
	}
	rewrites := [1]language.Jan_Rewrite_Request{{
		node_id = request.target.node_id,
		range = request.target.range,
		replacement = strings.to_string(builder),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		request.rewrite_generation,
		rewrites[:],
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		allocator,
	)
	if !planned do return {}, false, task_metadata_failure_from_language(request, jan_failure)
	return transition, true, {}
}

/* task_checkbox_cycle returns the compatible three-state cycle. */
task_checkbox_cycle :: proc(state: Checkbox_State) -> (Checkbox_State, bool) {
	switch state {
	case .Unchecked:     return .Checked, true
	case .Checked:       return .Unchecked, true
	case .Intermediate:  return .Checked, true
	case .Invalid:       return .Invalid, false
	}
	return .Invalid, false
}

/* task_statistics_derive computes one parent cookie from child or checkbox states. */
task_statistics_derive :: proc(states: []Checkbox_State) -> (Task_Statistics, bool) {
	if len(states) > int(MAX_SEMANTIC_TARGETS) do return {}, false
	statistics := Task_Statistics{total = u32(len(states))}
	for state in states {
		if state == .Invalid do return {}, false
		if state == .Checked do statistics.completed += 1
	}
	if statistics.total > 0 do statistics.percent = u8((statistics.completed * 100) / statistics.total)
	return statistics, true
}

/* task_habit_summarize derives completion, misses, and current streak. */
task_habit_summarize :: proc(occurrences: []Habit_Occurrence) -> (Habit_Summary, bool) {
	if len(occurrences) > int(MAX_SEMANTIC_TARGETS) do return {}, false
	summary: Habit_Summary
	for occurrence in occurrences {
		if occurrence.completed do summary.completed += 1
		if !occurrence.completed do summary.missed += 1
	}
	for index := len(occurrences) - 1; index >= 0; index -= 1 {
		if !occurrences[index].completed do break
		summary.current_streak += 1
	}
	return summary, true
}

/* task_priority_normalize accepts alphabetic or numeric source forms. */
task_priority_normalize :: proc(source: string, highest, lowest, default_value: i32) -> (i32, bool) {
	if highest > lowest || default_value < highest || default_value > lowest do return 0, false
	if len(source) == 0 do return default_value, true
	value: i32
	if len(source) == 1 && ((source[0] >= 'A' && source[0] <= 'Z') || (source[0] >= 'a' && source[0] <= 'z')) {
		byte_value := source[0]
		if byte_value >= 'a' do byte_value -= 'a' - 'A'
		value = i32(byte_value - 'A') + 1
	} else {
		for character in source {
			if character < '0' || character > '9' do return 0, false
			value = value * 10 + i32(character - '0')
		}
	}
	return value, value >= highest && value <= lowest
}

/* tag_set_resolve derives a bounded effective set with group expansion and exceptions. */
tag_set_resolve :: proc(
	candidates: []Tag_Candidate,
	groups: []Tag_Group,
	exceptions: []string,
	output: []Tag_Record,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (count: int, ok: bool, failure: Failure) {
	if len(candidates) > int(MAX_SEMANTIC_TARGETS) || len(output) < len(candidates) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil {
		failure = task_metadata_failure(0, .Metadata, .Limited, .Tag)
		failure.limit = u64(len(output))
		failure.actual = u64(len(candidates))
		return
	}
	for candidate in candidates {
		if !candidate.active {
			continue
		}
		if !task_metadata_name_is_valid(candidate.name) || candidate.origin == .Invalid {
			return 0, false, task_metadata_failure(0, .Metadata, .Malformed, .Tag)
		}
		if tag_name_in(candidate.name, exceptions) {
			continue
		}
		count = tag_record_add(output, count, candidate.name, candidate.origin, candidate.owner)
	}
	for group in groups {
		if !task_metadata_name_is_valid(group.name) || group.kind == .Invalid do return 0, false, task_metadata_failure(0, .Metadata, .Malformed, .Tag)
		if !tag_record_has(output[:count], group.name) {
			continue
		}
		if group.kind == .Members {
			for member in group.members {
				if !task_metadata_name_is_valid(member) {
					return 0, false, task_metadata_failure(0, .Metadata, .Malformed, .Tag)
				}
				if tag_name_in(member, exceptions) {
					continue
				}
				if count >= len(output) do return 0, false, task_metadata_failure(0, .Metadata, .Limited, .Tag)
				count = tag_record_add(output, count, member, .Grouped, {})
			}
		} else {
			if len(group.expression) == 0 || len(group.expression) > MAX_QUERY_BYTES ||
			   !utf8.valid_string(group.expression) {
				return 0, false, task_metadata_failure(0, .Metadata, .Malformed, .Tag)
			}
			compiled, compile_error := regex.create(group.expression, {.Unicode}, allocator, temporary_allocator)
			if compile_error != nil do return 0, false, task_metadata_failure(0, .Metadata, .Malformed, .Tag)
			defer regex.destroy_regex(compiled, allocator)
			for candidate in candidates {
				if !candidate.active || tag_name_in(candidate.name, exceptions) {
					continue
				}
				capture, matched := regex.match(compiled, candidate.name, temporary_allocator, temporary_allocator)
				if capture.groups != nil do regex.destroy_capture(capture, temporary_allocator)
				if matched {
					if count >= len(output) do return 0, false, task_metadata_failure(0, .Metadata, .Limited, .Tag)
					count = tag_record_add(output, count, candidate.name, .Grouped, candidate.owner)
				}
			}
		}
	}
	return count, true, {}
}

/* tag_query_matches evaluates one bounded postfix Boolean expression. */
tag_query_matches :: proc(records: []Tag_Record, query: []Tag_Query_Token) -> (bool, bool) {
	if len(query) == 0 || len(query) > MAX_TAG_QUERY_TOKENS do return false, false
	stack: [MAX_TAG_QUERY_TOKENS]bool
	depth := 0
	for token in query {
		switch token.kind {
		case .Tag:
			if !task_metadata_name_is_valid(token.name) || depth >= len(stack) do return false, false
			stack[depth] = tag_record_has(records, token.name)
			depth += 1
		case .Not:
			if depth < 1 do return false, false
			stack[depth - 1] = !stack[depth - 1]
		case .And, .Or:
			if depth < 2 do return false, false
			right, left := stack[depth - 1], stack[depth - 2]
			depth -= 1
			stack[depth - 1] = left && right if token.kind == .And else left || right
		case .Invalid:
			return false, false
		}
	}
	if depth != 1 do return false, false
	return stack[0], true
}

/* property_resolve derives stored, inherited, additive, or derived value provenance. */
property_resolve :: proc(
	name: string,
	candidates: []Property_Candidate,
	generation: Configuration_Generation,
) -> (Property_Resolution, bool, Failure) {
	if !task_metadata_name_is_valid(name) || generation == Configuration_Generation(0) {
		return {}, false, task_metadata_failure(0, .Metadata, .Invalid_Request, .Property)
	}
	resolution := Property_Resolution{name = name, configuration_generation = generation}
	for candidate in candidates {
		if candidate.name != name {
			continue
		}
		if candidate.origin == .Invalid || len(candidate.value) > MAX_RESOURCE_BYTES || !utf8.valid_string(candidate.value) {
			return {}, false, task_metadata_failure(0, .Metadata, .Malformed, .Property)
		}
		if candidate.additive {
			if int(resolution.component_count) >= MAX_PROPERTY_COMPONENTS {
				failure := task_metadata_failure(0, .Metadata, .Limited, .Property)
				failure.limit = MAX_PROPERTY_COMPONENTS
				failure.actual = u64(resolution.component_count) + 1
				return {}, false, failure
			}
			index := int(resolution.component_count)
			resolution.components[index] = candidate.value
			resolution.component_origins[index] = candidate.origin
			resolution.component_count += 1
			continue
		}
		if resolution.origin == .Invalid {
			resolution.value = candidate.value
			resolution.origin = candidate.origin
			resolution.owner = candidate.owner
			resolution.editable = candidate.origin == .Stored
		}
	}
	if resolution.origin == .Invalid && resolution.component_count == 0 do return {}, false, {}
	return resolution, true, {}
}

/* property_edit_plan_prepare creates one checked mutation for a locally stored value. */
property_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Property_Edit_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	if request.origin != .Stored ||
	   (len(request.allowed_values) > 0 && !tag_name_in(request.replacement_value, request.allowed_values)) {
		return false, task_metadata_failure(request.operation_id, .Metadata, .Conflict, .Property)
	}
	return metadata_local_edit_plan_prepare(
		plan,
		analysis,
		source,
		request.operation_id,
		request.scope,
		request.target,
		request.current_value,
		request.replacement_value,
		request.rewrite_generation,
		.Property,
		allocator,
		temporary_allocator,
	)
}

/* tag_local_edit_plan_prepare creates one checked mutation for locally stored membership. */
tag_local_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Tag_Edit_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	if request.origin != .Local {
		return false, task_metadata_failure(request.operation_id, .Metadata, .Conflict, .Tag)
	}
	return metadata_local_edit_plan_prepare(
		plan,
		analysis,
		source,
		request.operation_id,
		request.scope,
		request.target,
		request.current_value,
		request.replacement_value,
		request.rewrite_generation,
		.Tag,
		allocator,
		temporary_allocator,
	)
}

/* column_view_project creates property-backed cells with canonical edit owners. */
column_view_project :: proc(
	definitions: []Column_Definition,
	rows: []Column_Row,
	generation: Configuration_Generation,
	output: []Column_Cell,
) -> (count: int, ok: bool, failure: Failure) {
	required := len(definitions) * len(rows)
	if len(definitions) == 0 || generation == Configuration_Generation(0) || required > len(output) ||
	   required > int(MAX_SEMANTIC_TARGETS) {
		failure = task_metadata_failure(0, .Metadata, .Limited, .Column)
		failure.limit = u64(len(output))
		failure.actual = u64(required)
		return
	}
	for row, row_index in rows {
		for definition, column_index in definitions {
			if !task_metadata_name_is_valid(definition.property) || definition.width == 0 {
				return 0, false, task_metadata_failure(0, .Metadata, .Malformed, .Column)
			}
			resolution, found, property_failure := property_resolve(definition.property, row.properties, generation)
			if property_failure.code != .None do return 0, false, property_failure
			cell := Column_Cell{row = u32(row_index), column = u16(column_index), owner = row.target}
			if found {
				cell.value = resolution.value
				cell.origin = resolution.origin
				cell.owner = resolution.owner
				cell.editable = resolution.editable
			}
			output[count] = cell
			count += 1
		}
	}
	return count, true, {}
}

/* column_snapshot_capture copies one deterministic tab-separated view. */
column_snapshot_capture :: proc(
	snapshot: ^Column_Snapshot,
	definitions: []Column_Definition,
	rows: []Column_Row,
	generation: Configuration_Generation,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (Column_Snapshot_Descriptor, bool, Failure) {
	if snapshot == nil || snapshot.state != nil || allocator.procedure == nil || temporary_allocator.procedure == nil {
		return {}, false, task_metadata_failure(0, .Metadata, .Invalid_Request, .Column)
	}
	required := len(definitions) * len(rows)
	cells, cells_error := make([]Column_Cell, required, temporary_allocator)
	if cells_error != nil do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
	defer delete(cells, temporary_allocator)
	_, projected, failure := column_view_project(definitions, rows, generation, cells)
	if !projected do return {}, false, failure
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
	defer strings.builder_destroy(&builder)
	for definition, index in definitions {
		if index > 0 && strings.write_byte(&builder, '\t') != 1 do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
		heading := definition.heading
		if len(heading) == 0 do heading = definition.property
		if strings.write_string(&builder, heading) != len(heading) do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
	}
	if strings.write_byte(&builder, '\n') != 1 do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
	for row_index in 0 ..< len(rows) {
		for column_index in 0 ..< len(definitions) {
			if column_index > 0 && strings.write_byte(&builder, '\t') != 1 do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
			value := cells[row_index * len(definitions) + column_index].value
			if strings.write_string(&builder, value) != len(value) do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
		}
		if strings.write_byte(&builder, '\n') != 1 do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
	}
	text := strings.to_string(builder)
	if len(text) > MAX_COLUMN_CAPTURE_BYTES {
		limited := task_metadata_failure(0, .Metadata, .Limited, .Column)
		limited.limit = MAX_COLUMN_CAPTURE_BYTES
		limited.actual = u64(len(text))
		return {}, false, limited
	}
	state, state_error := new(Column_Snapshot_State, allocator)
	if state_error != nil do return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
	state^ = Column_Snapshot_State{allocator = allocator}
	state.text, state_error = make([]u8, len(text), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false, task_metadata_failure(0, .Metadata, .Allocation_Failed, .Column)
	}
	copy(state.text, text)
	state.descriptor = {rows = u32(len(rows)), columns = u16(len(definitions)), bytes = u64(len(text)), configuration_generation = generation}
	snapshot.state = state
	return state.descriptor, true, {}
}

/* column_snapshot_text borrows captured text until close. */
column_snapshot_text :: proc(snapshot: ^Column_Snapshot) -> (string, bool) {
	state := column_snapshot_state(snapshot)
	if state == nil do return "", false
	return string(state.text), true
}

/* column_snapshot_close releases one captured column view. */
column_snapshot_close :: proc(snapshot: ^Column_Snapshot) {
	state := column_snapshot_state(snapshot)
	if state == nil do return
	allocator := state.allocator
	if state.text != nil do delete(state.text, allocator)
	state^ = {}
	free(state, allocator)
	snapshot.state = nil
}

@(private)
metadata_local_edit_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	operation_id: Operation_ID,
	scope: Scope,
	target: Semantic_Target,
	current_value, replacement_value: string,
	generation: language.Jan_Rewrite_Generation,
	field: Failure_Field,
	allocator, temporary_allocator: runtime.Allocator,
) -> (bool, Failure) {
	if plan == nil || analysis == nil || operation_id == Operation_ID(0) ||
	   !scope_is_valid(scope) || !semantic_target_is_valid(target, scope) ||
	   u64(len(source)) != scope.source_bytes || generation == language.Jan_Rewrite_Generation(0) ||
	   len(current_value) == 0 || len(current_value) > MAX_RESOURCE_BYTES ||
	   len(replacement_value) > MAX_RESOURCE_BYTES || !utf8.valid_string(current_value) ||
	   !utf8.valid_string(replacement_value) || allocator.procedure == nil ||
	   temporary_allocator.procedure == nil {
		return false, task_metadata_failure(operation_id, .Metadata, .Invalid_Request, field)
	}
	target_start, target_end := int(target.range.start), int(target.range.end)
	match_start, matches := -1, 0
	for cursor := target_start; cursor + len(current_value) <= target_end; cursor += 1 {
		if string(source[cursor:cursor + len(current_value)]) == current_value {
			match_start = cursor
			matches += 1
		}
	}
	if matches != 1 {
		failure := task_metadata_failure(operation_id, .Metadata, .Conflict, field)
		failure.actual = u64(matches)
		return false, failure
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil do return false, task_metadata_failure(operation_id, .Metadata, .Allocation_Failed, field)
	defer strings.builder_destroy(&builder)
	prefix := string(source[target_start:match_start])
	suffix := string(source[match_start + len(current_value):target_end])
	if strings.write_string(&builder, prefix) != len(prefix) ||
	   strings.write_string(&builder, replacement_value) != len(replacement_value) ||
	   strings.write_string(&builder, suffix) != len(suffix) {
		return false, task_metadata_failure(operation_id, .Metadata, .Allocation_Failed, field)
	}
	rewrites := [1]language.Jan_Rewrite_Request{{
		node_id = target.node_id,
		range = target.range,
		replacement = strings.to_string(builder),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		generation,
		rewrites[:],
		language.DEFAULT_JAN_RESOURCE_LIMITS,
		allocator,
	)
	if !planned {
		failure := task_metadata_failure(operation_id, .Metadata, .Invalid_Target, field)
		#partial switch jan_failure.code {
		case .Stale:             failure.code = .Stale
		case .Malformed:         failure.code = .Malformed
		case .Limited:           failure.code = .Limited
		case .Allocation_Failed: failure.code = .Allocation_Failed
		}
		failure.limit = jan_failure.limit
		failure.actual = jan_failure.actual
		return false, failure
	}
	return true, {}
}

@(private)
task_workflow_find :: proc(configuration: ^Configuration, identity: string) -> (Workflow_Record, bool) {
	descriptor, ok := planning_configuration_inspect(configuration)
	if !ok do return {}, false
	for index in 0 ..< int(descriptor.workflow_count) {
		workflow, found := planning_configuration_workflow(configuration, index)
		if found && workflow.identity == identity do return workflow, true
	}
	return {}, false
}

@(private)
task_workflow_state_find :: proc(configuration: ^Configuration, workflow: Workflow_Record, name: string) -> (int, bool) {
	for offset in 0 ..< int(workflow.states.count) {
		index := int(workflow.states.start) + offset
		state, found := planning_configuration_workflow_state(configuration, index)
		if found && state.name == name do return index, true
	}
	return -1, false
}

@(private)
task_heading_state_range :: proc(source: []u8, target: Semantic_Target, state: string) -> (int, int, bool) {
	start, limit := int(target.range.start), int(target.range.end)
	if start < 0 || limit > len(source) || start >= limit do return 0, 0, false
	cursor := start
	for cursor < limit && source[cursor] == '*' do cursor += 1
	if cursor == start || cursor >= limit || (source[cursor] != ' ' && source[cursor] != '\t') do return 0, 0, false
	for cursor < limit && (source[cursor] == ' ' || source[cursor] == '\t') do cursor += 1
	end := cursor
	for end < limit && source[end] != ' ' && source[end] != '\t' && source[end] != '\r' && source[end] != '\n' do end += 1
	if string(source[cursor:end]) != state do return 0, 0, false
	return cursor, end, true
}

@(private)
tag_record_add :: proc(output: []Tag_Record, count: int, name: string, origin: Tag_Origin, owner: Semantic_Target) -> int {
	if !task_metadata_name_is_valid(name) || tag_record_has(output[:count], name) do return count
	if count >= len(output) do return count
	output[count] = {name = name, origin = origin, owner = owner}
	return count + 1
}

@(private)
tag_record_has :: proc(records: []Tag_Record, name: string) -> bool {
	for record in records do if record.name == name do return true
	return false
}

@(private)
tag_name_in :: proc(name: string, names: []string) -> bool {
	for candidate in names do if candidate == name do return true
	return false
}

@(private)
task_metadata_name_is_valid :: proc(name: string) -> bool {
	return len(name) > 0 && len(name) <= MAX_LABEL_BYTES && utf8.valid_string(name)
}

@(private)
column_snapshot_state :: proc(snapshot: ^Column_Snapshot) -> ^Column_Snapshot_State {
	if snapshot == nil || snapshot.state == nil do return nil
	return cast(^Column_Snapshot_State)snapshot.state
}

@(private)
task_metadata_failure :: proc(operation_id: Operation_ID, kind: Operation_Kind, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = kind, code = code, field = field}
}

@(private)
task_metadata_failure_from_language :: proc(request: Task_Transition_Request, source: language.Jan_Failure) -> Failure {
	code := Failure_Code.Invalid_Request
	#partial switch source.code {
	case .Stale:             code = .Stale
	case .Malformed:         code = .Malformed
	case .Limited:           code = .Limited
	case .Cancelled:         code = .Cancelled
	case .Allocation_Failed: code = .Allocation_Failed
	case .Incomplete:        code = .Unavailable
	}
	return {
		operation_id = request.operation_id,
		kind = .Task,
		code = code,
		field = .Target,
		limit = source.limit,
		actual = source.actual,
	}
}
