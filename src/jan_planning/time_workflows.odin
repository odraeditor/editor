// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_planning

import "core:strings"
import "core:unicode/utf8"

import "../language"

/* MAX_RECURRENCE_STEPS bounds one catch-up calculation. */
MAX_RECURRENCE_STEPS :: 4_096
/* MAX_TIME_SOURCE_REPLACEMENTS bounds one logical time mutation. */
MAX_TIME_SOURCE_REPLACEMENTS :: 64
/* MAX_TIMESTAMP_TEXT_BYTES bounds one canonical compatible timestamp. */
MAX_TIMESTAMP_TEXT_BYTES :: 256

/* Civil_Date is one proleptic Gregorian calendar date. */
Civil_Date :: struct {
	year:  i32,
	month: u8,
	day:   u8,
}

/* Civil_Time is one local wall-clock value without a zone. */
Civil_Time :: struct {
	hour:       u8,
	minute:     u8,
	second:     u8,
	nanosecond: u32,
}

/* Local_Date_Time is one civil value awaiting or retaining zone interpretation. */
Local_Date_Time :: struct {
	date: Civil_Date,
	time: Civil_Time,
}

/* Time_Zone_Owner identifies fixed zone-precedence levels. */
Time_Zone_Owner :: enum u8 {
	Invalid,
	Invocation,
	Document,
	Project,
	Workspace,
	User,
	System,
}

/* Time_Zone_Candidate is one copied zone-precedence input. */
Time_Zone_Candidate :: struct {
	owner:  Time_Zone_Owner,
	value:  string,
	active: bool,
}

/* Time_Zone_Resolution reports one captured interpretation zone. */
Time_Zone_Resolution :: struct {
	owner: Time_Zone_Owner,
	value: Time_Zone_Text,
}

/* Local_Time_Classification distinguishes valid, nonexistent, and ambiguous time. */
Local_Time_Classification :: enum u8 {
	Invalid,
	Valid,
	Gap,
	Fold,
}

/* Fold_Policy selects one side of an ambiguous local time. */
Fold_Policy :: enum u8 {
	Invalid,
	Earlier,
	Later,
}

/* Local_Time_Resolution_Input is one zone-provider result without effect authority. */
Local_Time_Resolution_Input :: struct {
	local:          Local_Date_Time,
	zone:           Time_Zone_Resolution,
	classification: Local_Time_Classification,
	earlier:        Absolute_Instant,
	later:          Absolute_Instant,
}

/* Local_Time_Resolution records one explicit zone interpretation. */
Local_Time_Resolution :: struct {
	local:   Local_Date_Time,
	zone:    Time_Zone_Resolution,
	instant: Absolute_Instant,
	fold:    Fold_Policy,
}

/* Calendar_Unit identifies compatible recurrence units. */
Calendar_Unit :: enum u8 {
	Invalid,
	Day,
	Week,
	Month,
	Year,
}

/* Calendar_Interval is one positive bounded recurrence or warning interval. */
Calendar_Interval :: struct {
	amount: u32,
	unit:   Calendar_Unit,
}

/* Recurrence_Kind distinguishes compatible +, ++, and .+ behavior. */
Recurrence_Kind :: enum u8 {
	Invalid,
	Stored_Base,
	Catch_Up,
	Completion_Base,
}

/* Invalid_Date_Policy makes month and year overflow explicit. */
Invalid_Date_Policy :: enum u8 {
	Invalid,
	Reject,
	Clamp,
}

/* Recurrence is one compatible timestamp repeater. */
Recurrence :: struct {
	kind:     Recurrence_Kind,
	interval: Calendar_Interval,
}

/* Timestamp_Spec is one canonical source timestamp description. */
Timestamp_Spec :: struct {
	local:       Local_Date_Time,
	active:      bool,
	has_time:    bool,
	recurrence:  Recurrence,
	warning:     Calendar_Interval,
}

/* Timestamp_Text owns one bounded canonical source representation. */
Timestamp_Text :: struct {
	bytes:  [MAX_TIMESTAMP_TEXT_BYTES]u8,
	length: u16,
}

/* Timestamp_Range is one optional compatible source timestamp range. */
Timestamp_Range :: struct {
	start: Timestamp_Spec,
	end:   Timestamp_Spec,
}

/* Timestamp_Range_Text owns one bounded canonical compatible range. */
Timestamp_Range_Text :: struct {
	bytes:  [2 * MAX_TIMESTAMP_TEXT_BYTES + 2]u8,
	length: u16,
}

/* Planning_Fact_Kind identifies heading time facts. */
Planning_Fact_Kind :: enum u8 {
	Invalid,
	Scheduled,
	Deadline,
	Closed,
	Clock,
	Timer,
}

/* Time_Source_Replacement is one exact old value and its canonical replacement. */
Time_Source_Replacement :: struct {
	current:     string,
	replacement: string,
}

/* Time_Source_Edit_Request binds related time changes to one exact heading owner. */
Time_Source_Edit_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	target:             Semantic_Target,
	replacements:       []Time_Source_Replacement,
	rewrite_generation: language.Jan_Rewrite_Generation,
}

/* Repeating_Timestamp_Candidate is one eligible source timestamp to advance. */
Repeating_Timestamp_Candidate :: struct {
	current: string,
	spec:    Timestamp_Spec,
}

/* Repeating_Task_Transition_Request binds task completion and every repeater. */
Repeating_Task_Transition_Request :: struct {
	task:       Task_Transition_Request,
	timestamps: []Repeating_Timestamp_Candidate,
	completed:  Local_Date_Time,
	now:        Local_Date_Time,
	policy:     Invalid_Date_Policy,
	locale:     string,
}

/* time_zone_resolve applies invocation-to-system precedence independent of input order. */
time_zone_resolve :: proc(candidates: []Time_Zone_Candidate) -> (Time_Zone_Resolution, bool, Failure) {
	for owner_value := int(Time_Zone_Owner.Invocation); owner_value <= int(Time_Zone_Owner.System); owner_value += 1 {
		owner := Time_Zone_Owner(owner_value)
		for candidate in candidates {
			if !candidate.active || candidate.owner != owner do continue
			zone, copied := active_clock_time_zone_copy(candidate.value)
			if !copied do return {}, false, planning_failure(.Time, .Malformed, .Time)
			return {owner = owner, value = zone}, true, {}
		}
	}
	return {}, false, planning_failure(.Time, .Unavailable, .Time)
}

/* local_time_resolve rejects gaps and requires an explicit fold policy. */
local_time_resolve :: proc(
	input: Local_Time_Resolution_Input,
	policy: Fold_Policy,
) -> (Local_Time_Resolution, bool, Failure) {
	if !local_date_time_is_valid(input.local) || input.zone.owner == .Invalid ||
	   !active_clock_time_zone_is_valid(input.zone.value) {
		return {}, false, planning_failure(.Time, .Malformed, .Time)
	}
	instant: Absolute_Instant
	fold := Fold_Policy.Invalid
	switch input.classification {
	case .Valid:
		instant = input.earlier
	case .Gap:
		return {}, false, planning_failure(.Time, .Conflict, .Time)
	case .Fold:
		if policy == .Earlier {
			instant, fold = input.earlier, .Earlier
		} else if policy == .Later {
			instant, fold = input.later, .Later
		} else {
			return {}, false, planning_failure(.Time, .Confirmation_Required, .Time)
		}
	case .Invalid:
		return {}, false, planning_failure(.Time, .Malformed, .Time)
	}
	if !absolute_instant_is_valid(instant) do return {}, false, planning_failure(.Time, .Malformed, .Time)
	return {local = input.local, zone = input.zone, instant = instant, fold = fold}, true, {}
}

/* timestamp_text_format emits locale-independent compatible Jan/Org syntax. */
timestamp_text_format :: proc(spec: Timestamp_Spec, locale: string) -> (Timestamp_Text, bool) {
	if !timestamp_spec_is_valid(spec) || len(locale) == 0 || len(locale) > MAX_IDENTITY_BYTES ||
	   !utf8.valid_string(locale) {
		return {}, false
	}
	result: Timestamp_Text
	opening, closing := byte('['), byte(']')
	if spec.active do opening, closing = '<', '>'
	day_names := [7]string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
	weekday := civil_date_weekday(spec.local.date)
	cursor := 0
	written := time_buffer_write_byte(result.bytes[:], &cursor, opening) &&
	           time_buffer_write_u64(result.bytes[:], &cursor, u64(spec.local.date.year), 4) &&
	           time_buffer_write_byte(result.bytes[:], &cursor, '-') &&
	           time_buffer_write_u64(result.bytes[:], &cursor, u64(spec.local.date.month), 2) &&
	           time_buffer_write_byte(result.bytes[:], &cursor, '-') &&
	           time_buffer_write_u64(result.bytes[:], &cursor, u64(spec.local.date.day), 2) &&
	           time_buffer_write_byte(result.bytes[:], &cursor, ' ') &&
	           time_buffer_write_string(result.bytes[:], &cursor, day_names[weekday])
	if !written do return {}, false
	if spec.has_time {
		written = time_buffer_write_byte(result.bytes[:], &cursor, ' ') &&
		          time_buffer_write_u64(result.bytes[:], &cursor, u64(spec.local.time.hour), 2) &&
		          time_buffer_write_byte(result.bytes[:], &cursor, ':') &&
		          time_buffer_write_u64(result.bytes[:], &cursor, u64(spec.local.time.minute), 2)
		if !written do return {}, false
	}
	if spec.recurrence.kind != .Invalid {
		marker := "+"
		if spec.recurrence.kind == .Catch_Up do marker = "++"
		if spec.recurrence.kind == .Completion_Base do marker = ".+"
		interval_text := time_interval_text(result.bytes[cursor:], marker, spec.recurrence.interval)
		if len(interval_text) == 0 do return {}, false
		cursor += len(interval_text)
	}
	if spec.warning.unit != .Invalid {
		interval_text := time_interval_text(result.bytes[cursor:], "-", spec.warning)
		if len(interval_text) == 0 do return {}, false
		cursor += len(interval_text)
	}
	if cursor >= len(result.bytes) do return {}, false
	result.bytes[cursor] = closing
	result.length = u16(cursor + 1)
	return result, true
}

/* timestamp_text returns the copied canonical representation. */
timestamp_text :: proc(value: ^Timestamp_Text) -> string {
	if value == nil || value.length == 0 || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:value.length])
}

/* timestamp_range_text_format emits one canonical compatible timestamp range. */
timestamp_range_text_format :: proc(value: Timestamp_Range, locale: string) -> (Timestamp_Range_Text, bool) {
	start, start_ok := timestamp_text_format(value.start, locale)
	end, end_ok := timestamp_text_format(value.end, locale)
	if !start_ok || !end_ok || value.start.active != value.end.active ||
	   local_date_time_compare(value.start.local, value.end.local) > 0 {
		return {}, false
	}
	result: Timestamp_Range_Text
	cursor := 0
	if !time_buffer_write_string(result.bytes[:], &cursor, timestamp_text(&start)) ||
	   !time_buffer_write_string(result.bytes[:], &cursor, "--") ||
	   !time_buffer_write_string(result.bytes[:], &cursor, timestamp_text(&end)) {
		return {}, false
	}
	result.length = u16(cursor)
	return result, true
}

/* timestamp_range_text returns one copied canonical range representation. */
timestamp_range_text :: proc(value: ^Timestamp_Range_Text) -> string {
	if value == nil || value.length == 0 || int(value.length) > len(value.bytes) do return ""
	return string(value.bytes[:value.length])
}

/* civil_date_shift_days applies one bounded relative calendar offset. */
civil_date_shift_days :: proc(value: Civil_Date, offset: i32) -> (Civil_Date, bool) {
	if !civil_date_is_valid(value) || offset < -100_000 || offset > 100_000 do return {}, false
	result := value
	if offset == 0 do return result, true
	if offset >= 0 {
		shifted, ok := local_date_time_add(
			{date = value},
			{amount = u32(offset), unit = .Day},
			.Clamp,
		)
		if !ok do return {}, false
		return shifted.date, true
	}
	for _ in 0 ..< int(-offset) {
		if result.day > 1 {
			result.day -= 1
			continue
		}
		if result.month > 1 {
			result.month -= 1
		} else {
			if result.year <= 1 do return {}, false
			result.year -= 1
			result.month = 12
		}
		result.day = u8(civil_days_in_month(result.year, result.month))
	}
	return result, true
}

/* recurrence_advance applies compatible +, ++, and .+ calendar arithmetic. */
recurrence_advance :: proc(
	stored, completed, now: Local_Date_Time,
	recurrence: Recurrence,
	policy: Invalid_Date_Policy,
) -> (Local_Date_Time, u32, bool, Failure) {
	if !local_date_time_is_valid(stored) || !local_date_time_is_valid(completed) ||
	   !local_date_time_is_valid(now) || !recurrence_is_valid(recurrence) || policy == .Invalid {
		return {}, 0, false, planning_failure(.Time, .Malformed, .Time)
	}
	base := stored
	if recurrence.kind == .Completion_Base do base = completed
	result, advanced := local_date_time_add(base, recurrence.interval, policy)
	if !advanced do return {}, 0, false, planning_failure(.Time, .Conflict, .Time)
	steps := u32(1)
	if recurrence.kind == .Catch_Up {
		for local_date_time_compare(result, now) <= 0 {
			if steps >= MAX_RECURRENCE_STEPS {
				failure := planning_failure(.Time, .Limited, .Time)
				failure.limit = MAX_RECURRENCE_STEPS
				failure.actual = u64(steps) + 1
				return {}, steps, false, failure
			}
			result, advanced = local_date_time_add(result, recurrence.interval, policy)
			if !advanced do return {}, steps, false, planning_failure(.Time, .Conflict, .Time)
			steps += 1
		}
	}
	return result, steps, true, {}
}

/* repeating_task_transition_plan_prepare advances task state and repeaters atomically. */
repeating_task_transition_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	configuration: ^Configuration,
	request: Repeating_Task_Transition_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (Task_Transition, u32, bool, Failure) {
	if len(request.timestamps) == 0 || len(request.timestamps) > MAX_TIME_SOURCE_REPLACEMENTS - 2 {
		failure := time_workflow_failure(request.task.operation_id, .Limited)
		failure.limit = MAX_TIME_SOURCE_REPLACEMENTS - 2
		failure.actual = u64(len(request.timestamps))
		return {}, 0, false, failure
	}
	transition, resolved, failure := task_transition_resolve(configuration, request.task)
	if !resolved do return {}, 0, false, failure
	if !transition.finished {
		return {}, 0, false, time_workflow_failure(request.task.operation_id, .Conflict)
	}
	replacements: [MAX_TIME_SOURCE_REPLACEMENTS]Time_Source_Replacement
	texts: [MAX_TIME_SOURCE_REPLACEMENTS]Timestamp_Text
	count := 1
	replacements[0] = {current = request.task.current_state, replacement = transition.to}
	for candidate, index in request.timestamps {
		if candidate.spec.recurrence.kind == .Invalid || len(candidate.current) == 0 {
			return {}, 0, false, time_workflow_failure(request.task.operation_id, .Malformed)
		}
		next, _, advanced, recurrence_failure := recurrence_advance(
			candidate.spec.local,
			request.completed,
			request.now,
			candidate.spec.recurrence,
			request.policy,
		)
		if !advanced do return {}, 0, false, recurrence_failure
		next_spec := candidate.spec
		next_spec.local = next
		formatted, formatted_ok := timestamp_text_format(next_spec, request.locale)
		if !formatted_ok do return {}, 0, false, time_workflow_failure(request.task.operation_id, .Malformed)
		texts[index] = formatted
		replacements[count] = {current = candidate.current, replacement = timestamp_text(&texts[index])}
		count += 1
	}
	if len(request.task.log_record) > 0 {
		replacements[count] = {replacement = request.task.log_record}
		count += 1
	}
	planned, plan_failure := time_source_plan_prepare(
		plan,
		analysis,
		source,
		{
			operation_id = request.task.operation_id,
			scope = request.task.scope,
			target = request.task.target,
			replacements = replacements[:count],
			rewrite_generation = request.task.rewrite_generation,
		},
		allocator,
		temporary_allocator,
	)
	if !planned do return {}, 0, false, plan_failure
	return transition, u32(len(request.timestamps)), true, {}
}

/* time_source_plan_prepare creates one atomic rewrite for related heading time facts. */
time_source_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	request: Time_Source_Edit_Request,
	allocator := context.allocator,
	temporary_allocator := context.temp_allocator,
) -> (bool, Failure) {
	if plan == nil || analysis == nil || request.operation_id == Operation_ID(0) ||
	   !scope_is_valid(request.scope) || !semantic_target_is_valid(request.target, request.scope) ||
	   request.target.kind != .Heading || u64(len(source)) != request.scope.source_bytes ||
	   len(request.replacements) == 0 || len(request.replacements) > MAX_TIME_SOURCE_REPLACEMENTS ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   allocator.procedure == nil || temporary_allocator.procedure == nil ||
	   !utf8.valid_string(string(source)) {
		return false, time_workflow_failure(request.operation_id, .Invalid_Request)
	}
	Match :: struct {start, end: int, replacement: string}
	matches: [MAX_TIME_SOURCE_REPLACEMENTS]Match
	target_start, target_end := int(request.target.range.start), int(request.target.range.end)
	insertion_used := false
	for replacement, replacement_index in request.replacements {
		if len(replacement.current) > MAX_TIMESTAMP_TEXT_BYTES || len(replacement.replacement) > MAX_RESOURCE_BYTES ||
		   !utf8.valid_string(replacement.current) || !utf8.valid_string(replacement.replacement) {
			return false, time_workflow_failure(request.operation_id, .Malformed)
		}
		if len(replacement.current) == 0 {
			if insertion_used do return false, time_workflow_failure(request.operation_id, .Conflict)
			insertion_used = true
			position := target_start
			for position < target_end && source[position] != '\r' && source[position] != '\n' do position += 1
			if position < target_end && source[position] == '\r' do position += 1
			if position < target_end && source[position] == '\n' do position += 1
			matches[replacement_index] = {start = position, end = position, replacement = replacement.replacement}
			continue
		}
		match_start, occurrences := -1, 0
		for cursor := target_start; cursor + len(replacement.current) <= target_end; cursor += 1 {
			if string(source[cursor:cursor + len(replacement.current)]) == replacement.current {
				match_start, occurrences = cursor, occurrences + 1
			}
		}
		if occurrences != 1 {
			failure := time_workflow_failure(request.operation_id, .Stale)
			failure.actual = u64(occurrences)
			return false, failure
		}
		matches[replacement_index] = {
			start = match_start,
			end = match_start + len(replacement.current),
			replacement = replacement.replacement,
		}
	}
	selected := matches[:len(request.replacements)]
	for left in 0 ..< len(selected) {
		for right in left + 1 ..< len(selected) {
			if selected[right].start < selected[left].start do selected[left], selected[right] = selected[right], selected[left]
		}
	}
	for index in 1 ..< len(selected) {
		if selected[index].start < selected[index - 1].end ||
		   selected[index].start == selected[index - 1].start {
			return false, time_workflow_failure(request.operation_id, .Conflict)
		}
	}
	builder, builder_error := strings.builder_make(temporary_allocator)
	if builder_error != nil do return false, time_workflow_failure(request.operation_id, .Allocation_Failed)
	defer strings.builder_destroy(&builder)
	cursor := target_start
	for match in selected {
		prefix := string(source[cursor:match.start])
		if strings.write_string(&builder, prefix) != len(prefix) ||
		   strings.write_string(&builder, match.replacement) != len(match.replacement) {
			return false, time_workflow_failure(request.operation_id, .Allocation_Failed)
		}
		cursor = match.end
	}
	suffix := string(source[cursor:target_end])
	if strings.write_string(&builder, suffix) != len(suffix) {
		return false, time_workflow_failure(request.operation_id, .Allocation_Failed)
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
	if !planned {
		failure := time_workflow_failure(request.operation_id, .Invalid_Target)
		#partial switch jan_failure.code {
		case .Stale:             failure.code = .Stale
		case .Malformed:         failure.code = .Malformed
		case .Limited:           failure.code = .Limited
		case .Allocation_Failed: failure.code = .Allocation_Failed
		case .Cancelled:         failure.code = .Cancelled
		}
		failure.limit, failure.actual = jan_failure.limit, jan_failure.actual
		return false, failure
	}
	return true, {}
}

/* civil_date_is_valid checks one Gregorian date. */
civil_date_is_valid :: proc(value: Civil_Date) -> bool {
	if value.year < 1 || value.year > 9_999 || value.month < 1 || value.month > 12 do return false
	return value.day >= 1 && int(value.day) <= civil_days_in_month(value.year, value.month)
}

/* local_date_time_is_valid checks civil date and wall-clock bounds. */
local_date_time_is_valid :: proc(value: Local_Date_Time) -> bool {
	return civil_date_is_valid(value.date) && value.time.hour < 24 && value.time.minute < 60 &&
	       value.time.second < 60 && value.time.nanosecond < 1_000_000_000
}

/* absolute_instant_is_valid checks UTC nanosecond bounds. */
absolute_instant_is_valid :: proc(value: Absolute_Instant) -> bool {
	return value.nanoseconds < 1_000_000_000
}

@(private)
timestamp_spec_is_valid :: proc(spec: Timestamp_Spec) -> bool {
	if !local_date_time_is_valid(spec.local) do return false
	if !spec.has_time && spec.local.time != (Civil_Time{}) do return false
	if spec.recurrence.kind != .Invalid && !recurrence_is_valid(spec.recurrence) do return false
	if spec.warning.unit != .Invalid && !calendar_interval_is_valid(spec.warning) do return false
	return true
}

@(private)
recurrence_is_valid :: proc(value: Recurrence) -> bool {
	return value.kind != .Invalid && calendar_interval_is_valid(value.interval)
}

@(private)
calendar_interval_is_valid :: proc(value: Calendar_Interval) -> bool {
	return value.amount > 0 && value.amount <= 10_000 && value.unit >= .Day && value.unit <= .Year
}

@(private)
time_interval_text :: proc(output: []u8, marker: string, value: Calendar_Interval) -> string {
	if !calendar_interval_is_valid(value) || len(output) == 0 do return ""
	unit := "d"
	#partial switch value.unit {
	case .Week:  unit = "w"
	case .Month: unit = "m"
	case .Year:  unit = "y"
	}
	cursor := 0
	if !time_buffer_write_byte(output, &cursor, ' ') ||
	   !time_buffer_write_string(output, &cursor, marker) ||
	   !time_buffer_write_u64(output, &cursor, u64(value.amount), 0) ||
	   !time_buffer_write_string(output, &cursor, unit) {
		return ""
	}
	return string(output[:cursor])
}

@(private)
civil_date_is_leap_year :: proc(year: i32) -> bool {
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

@(private)
civil_days_in_month :: proc(year: i32, month: u8) -> int {
	days := [12]int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	result := days[int(month) - 1]
	if month == 2 && civil_date_is_leap_year(year) do result += 1
	return result
}

@(private)
civil_date_weekday :: proc(date: Civil_Date) -> int {
	offsets := [12]int{0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
	year := int(date.year)
	if date.month < 3 do year -= 1
	return (year + year / 4 - year / 100 + year / 400 + offsets[int(date.month) - 1] + int(date.day)) % 7
}

@(private)
local_date_time_compare :: proc(left, right: Local_Date_Time) -> int {
	if left.date.year != right.date.year do return -1 if left.date.year < right.date.year else 1
	if left.date.month != right.date.month do return -1 if left.date.month < right.date.month else 1
	if left.date.day != right.date.day do return -1 if left.date.day < right.date.day else 1
	if left.time.hour != right.time.hour do return -1 if left.time.hour < right.time.hour else 1
	if left.time.minute != right.time.minute do return -1 if left.time.minute < right.time.minute else 1
	if left.time.second != right.time.second do return -1 if left.time.second < right.time.second else 1
	if left.time.nanosecond != right.time.nanosecond do return -1 if left.time.nanosecond < right.time.nanosecond else 1
	return 0
}

@(private)
local_date_time_add :: proc(
	value: Local_Date_Time,
	interval: Calendar_Interval,
	policy: Invalid_Date_Policy,
) -> (Local_Date_Time, bool) {
	result := value
	switch interval.unit {
	case .Day, .Week:
		days := interval.amount
		if interval.unit == .Week {
			if days > max(u32) / 7 do return {}, false
			days *= 7
		}
		for _ in 0 ..< int(days) {
			result.date.day += 1
			if int(result.date.day) > civil_days_in_month(result.date.year, result.date.month) {
				result.date.day = 1
				result.date.month += 1
				if result.date.month > 12 {
					result.date.month = 1
					result.date.year += 1
					if result.date.year > 9_999 do return {}, false
				}
			}
		}
	case .Month, .Year:
		year, month := result.date.year, i64(result.date.month)
		if interval.unit == .Month {
			total := i64(year) * 12 + month - 1 + i64(interval.amount)
			year, month = i32(total / 12), total % 12 + 1
		} else {
			if interval.amount > u32(max(i32)) || year > max(i32) - i32(interval.amount) do return {}, false
			year += i32(interval.amount)
		}
		if year > 9_999 do return {}, false
		maximum := civil_days_in_month(year, u8(month))
		if int(result.date.day) > maximum {
			if policy == .Reject do return {}, false
			result.date.day = u8(maximum)
		}
		result.date.year, result.date.month = year, u8(month)
	case .Invalid:
		return {}, false
	}
	return result, local_date_time_is_valid(result)
}

@(private)
time_workflow_failure :: proc(operation_id: Operation_ID, code: Failure_Code) -> Failure {
	return {operation_id = operation_id, kind = .Time, code = code, field = .Time}
}

@(private)
time_buffer_write_byte :: proc(output: []u8, cursor: ^int, value: byte) -> bool {
	if cursor^ < 0 || cursor^ >= len(output) do return false
	output[cursor^] = value
	cursor^ += 1
	return true
}

@(private)
time_buffer_write_string :: proc(output: []u8, cursor: ^int, value: string) -> bool {
	if cursor^ < 0 || len(value) > len(output) - cursor^ do return false
	cursor^ += copy(output[cursor^:], value)
	return true
}

@(private)
time_buffer_write_u64 :: proc(output: []u8, cursor: ^int, value: u64, minimum_width: int) -> bool {
	digits: [20]u8
	count := 0
	remaining := value
	for {
		digits[count] = u8(remaining % 10) + '0'
		count += 1
		remaining /= 10
		if remaining == 0 do break
	}
	for count < minimum_width {
		digits[count] = '0'
		count += 1
	}
	if count > len(output) - cursor^ do return false
	for index := count - 1; index >= 0; index -= 1 {
		output[cursor^] = digits[index]
		cursor^ += 1
	}
	return true
}
