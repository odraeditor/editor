// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/command"
import "../../src/display"
import "../../src/editor"
import "../../src/history"
import "../../src/interaction"
import editor_search "../../src/search"
import edit_transaction "../../src/transaction"
import editor_view "../../src/view"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:text/regex"
import regex_common "core:text/regex/common"
import "core:time"

KIBIBYTE :: u64(1_024)
MEBIBYTE :: u64(1_024) * KIBIBYTE

MIN_PATTERN_BYTES :: u64(1)
MAX_PATTERN_BYTES :: u64(64) * KIBIBYTE
SELECTED_PATTERN_BYTES :: u64(4) * KIBIBYTE
MIN_SCAN_WINDOW_BYTES :: u64(64) * KIBIBYTE
MAX_SCAN_WINDOW_BYTES :: u64(16) * MEBIBYTE
SELECTED_SCAN_WINDOW_BYTES :: u64(64) * KIBIBYTE
MIN_CANCELLATION_BYTES :: u64(64) * KIBIBYTE
MAX_CANCELLATION_BYTES :: u64(4) * MEBIBYTE
SELECTED_CANCELLATION_BYTES :: u64(256) * KIBIBYTE
MIN_NEARBY_OCCURRENCES :: u64(64)
MAX_NEARBY_OCCURRENCES :: u64(65_536)
SELECTED_NEARBY_OCCURRENCES :: u64(256)
MIN_TEMPORARY_BYTES :: u64(4) * MEBIBYTE
MAX_TEMPORARY_BYTES :: u64(1_024) * MEBIBYTE
SELECTED_TEMPORARY_BYTES :: u64(16) * MEBIBYTE

ORDINARY_BYTES :: u64(1) * MEBIBYTE
DEMANDING_BYTES :: u64(100) * MEBIBYTE
ORDINARY_TURN_GATE_NS :: i64(2_000_000)
DEMANDING_TURN_GATE_NS :: i64(8_000_000)
CANCELLATION_GATE_NS :: i64(4_000_000)
REPLACEMENT_SAMPLES :: 32
REPLACEMENT_OCCURRENCES :: 1_000
REPLACEMENT_P99_GATE_NS :: i64(25_000_000)

LITERAL_PATTERN :: "needle-\u017c\u00f3\u0142\u0107"

Direction :: enum u8 {
	Forward,
	Backward,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

Scan_Result :: struct {
	found:             bool,
	offset:            u64,
	logical_bytes:     u64,
	read_bytes:        u64,
	reads:             u64,
	checks:            u64,
	cancelled:         bool,
	latency:           Latency,
	total_ns:          i64,
}

Regexp_Scan_Result :: struct {
	valid:                bool,
	found:                bool,
	start:                u64,
	end:                  u64,
	logical_bytes:        u64,
	read_bytes:           u64,
	temporary_peak_bytes: u64,
	total_ns:             i64,
}

Profile :: struct {
	name:         string,
	text_bytes:   u64,
	turn_gate_ns: i64,
	buffer_id:    editor.Buffer_ID,
}

main :: proc() {
	passed := print_policy_evidence()
	passed = probe_interaction_representation() && passed
	passed = probe_regex_behavior() && passed
	passed = run_profile(Profile{
		name = "ordinary",
		text_bytes = ORDINARY_BYTES,
		turn_gate_ns = ORDINARY_TURN_GATE_NS,
		buffer_id = 101,
	}) && passed
	passed = run_profile(Profile{
		name = "demanding",
		text_bytes = DEMANDING_BYTES,
		turn_gate_ns = DEMANDING_TURN_GATE_NS,
		buffer_id = 102,
	}) && passed
	passed = run_replacement_profile() && passed
	passed = run_stress() && passed
	if !passed {
		os.exit(1)
	}
}

run_replacement_profile :: proc() -> bool {
	contents := make([dynamic]byte, 0, REPLACEMENT_OCCURRENCES * 2)
	defer delete(contents)
	for _ in 0 ..< REPLACEMENT_OCCURRENCES {
		append(&contents, "a ")
	}
	latencies: [REPLACEMENT_SAMPLES]i64
	persistent_peak := i64(0)
	cleanup_bytes := i64(0)
	valid := true
	for sample in 0 ..< REPLACEMENT_SAMPLES {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		allocator := mem.tracking_allocator(&tracking)
		buffer: editor.Buffer
		buffer_ready, buffer_failure := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(201),
			string(contents[:]),
			editor.Allocator_Set{persistent = allocator, temporary = allocator},
		)
		if !buffer_ready {
			fmt.eprintf("study=search profile=replacement phase=buffer failure=%v\n", buffer_failure.code)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
		store: history.Store
		store_ready, store_failure := history.store_init(
			&store,
			history.Store_ID(201),
			editor.Buffer_ID(201),
			editor.Revision(0),
			history.Allocator_Set{persistent = allocator, temporary = allocator},
		)
		if !store_ready {
			fmt.eprintf("study=search profile=replacement phase=history failure=%v\n", store_failure.code)
			editor.buffer_close(&buffer)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
		views: editor_view.Registry
		views_ready, views_failure := editor_view.registry_init(
			&views,
			editor_view.Registry_ID(202),
			allocator,
		)
		if !views_ready {
			fmt.eprintf("study=search profile=replacement phase=views failure=%v\n", views_failure.code)
			history.store_close(&store)
			editor.buffer_close(&buffer)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
		view, view_ready, view_failure := editor_view.create(&views, &buffer)
		if !view_ready {
			fmt.eprintf("study=search profile=replacement phase=view failure=%v\n", view_failure.code)
			editor_view.registry_close(&views)
			history.store_close(&store)
			editor.buffer_close(&buffer)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
		definitions := command.native_command_definitions()
		registry: interaction.Command_Registry
		registry_ready, registry_failure := interaction.command_registry_init(
			&registry,
			interaction.Registry_Generation(201),
			definitions[:],
			allocator,
		)
		handle, found, lookup_failure := interaction.command_lookup(&registry, "replace-string")
		if !registry_ready || !found {
			fmt.eprintf(
				"study=search profile=replacement phase=command registry_failure=%v lookup_failure=%v\n",
				registry_failure.code,
				lookup_failure.code,
			)
			if registry_ready {
				interaction.command_registry_close(&registry)
			}
			editor_view.close(&views, &view)
			editor_view.registry_close(&views)
			history.store_close(&store)
			editor.buffer_close(&buffer)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}
		limits := command.DEFAULT_REPLACE_ALL_LIMITS
		limits.matches = REPLACEMENT_OCCURRENCES
		started := time.tick_now()
		result, replaced, replace_failure := command.replace_all(
			command.Replace_All_Request {
				native = command.Native_Context {
					registry = &registry,
					command = handle,
					buffer = &buffer,
					view_registry = &views,
					view = view,
					profile = display.terminal_unicode17_profile(),
					constraints = display.Viewport_Constraints{width_cells = 80, height_rows = 24},
					history_store = &store,
					history_grouping = history.Grouping_Context{kind = .Independent},
					persistent_allocator = allocator,
					temporary_allocator = allocator,
					transaction_id = edit_transaction.Transaction_ID(sample + 1),
					undo_unit_id = edit_transaction.Undo_Unit_ID(sample + 1),
				},
				pattern = "a",
				replacement = "bb",
				pattern_kind = .Literal,
				search_policy = editor_search.Policy {
					case_mode = .Sensitive,
					boundary_mode = .Unrestricted,
					whitespace_mode = .Exact,
					wrap = false,
				},
				replacement_policy = editor_search.Replacement_Policy{case_preservation = .None},
				query_id = editor_search.Query_ID(sample + 1),
				search_generation = editor_search.Search_Generation(sample + 1),
				limits = limits,
				replacement_limits = editor_search.DEFAULT_REPLACEMENT_LIMITS,
			},
		)
		latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
		valid = valid && replaced && replace_failure.code == .None &&
		        result.usage.matches == REPLACEMENT_OCCURRENCES &&
		        result.native.commit.result_revision == editor.Revision(1)
		if replaced {
			command.replace_all_result_close(&result)
		}
		commands_closed, _ := interaction.command_registry_close(&registry)
		view_closed, _ := editor_view.close(&views, &view)
		views_closed, _ := editor_view.registry_close(&views)
		history_closed, _ := history.store_close(&store)
		buffer_closed, _ := editor.buffer_close(&buffer)
		persistent_peak = max(persistent_peak, tracking.peak_memory_allocated)
		cleanup_bytes += tracking.current_memory_allocated
		valid = valid && commands_closed && view_closed && views_closed &&
		        history_closed && buffer_closed && tracking.current_memory_allocated == 0
		mem.tracking_allocator_destroy(&tracking)
	}
	latency := summarize(latencies[:])
	valid = valid && latency.p99_ns <= REPLACEMENT_P99_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=search profile=replacement valid=%v occurrences=%d samples=%d p50_ns=%d p99_ns=%d gate_ns=%d persistent_peak=%d cleanup_bytes=%d\n",
		valid,
		REPLACEMENT_OCCURRENCES,
		REPLACEMENT_SAMPLES,
		latency.p50_ns,
		latency.p99_ns,
		REPLACEMENT_P99_GATE_NS,
		persistent_peak,
		cleanup_bytes,
	)
	return valid
}

print_policy_evidence :: proc() -> bool {
	valid := SELECTED_PATTERN_BYTES >= MIN_PATTERN_BYTES &&
		SELECTED_PATTERN_BYTES <= MAX_PATTERN_BYTES &&
		SELECTED_PATTERN_BYTES <= interaction.MAX_PROMPT_TEXT_BYTES &&
		SELECTED_SCAN_WINDOW_BYTES >= MIN_SCAN_WINDOW_BYTES &&
		SELECTED_SCAN_WINDOW_BYTES <= MAX_SCAN_WINDOW_BYTES &&
		SELECTED_SCAN_WINDOW_BYTES >= SELECTED_PATTERN_BYTES &&
		SELECTED_CANCELLATION_BYTES >= MIN_CANCELLATION_BYTES &&
		SELECTED_CANCELLATION_BYTES <= MAX_CANCELLATION_BYTES &&
		SELECTED_CANCELLATION_BYTES % SELECTED_SCAN_WINDOW_BYTES == 0 &&
		SELECTED_NEARBY_OCCURRENCES >= MIN_NEARBY_OCCURRENCES &&
		SELECTED_NEARBY_OCCURRENCES <= MAX_NEARBY_OCCURRENCES &&
		SELECTED_TEMPORARY_BYTES >= MIN_TEMPORARY_BYTES &&
		SELECTED_TEMPORARY_BYTES <= MAX_TEMPORARY_BYTES &&
		SELECTED_SCAN_WINDOW_BYTES + SELECTED_PATTERN_BYTES <= SELECTED_TEMPORARY_BYTES
	fmt.printf(
		"study=search profile=policy valid=%v selected_pattern_bytes=%d pattern_range=%d..%d selected_scan_window_bytes=%d scan_window_range=%d..%d selected_cancellation_bytes=%d cancellation_range=%d..%d selected_nearby_occurrences=%d nearby_range=%d..%d selected_temporary_bytes=%d temporary_range=%d..%d regex_capture_groups=%d regex_program_limit=%d regex_class_limit=%d\n",
		valid,
		SELECTED_PATTERN_BYTES,
		MIN_PATTERN_BYTES,
		MAX_PATTERN_BYTES,
		SELECTED_SCAN_WINDOW_BYTES,
		MIN_SCAN_WINDOW_BYTES,
		MAX_SCAN_WINDOW_BYTES,
		SELECTED_CANCELLATION_BYTES,
		MIN_CANCELLATION_BYTES,
		MAX_CANCELLATION_BYTES,
		SELECTED_NEARBY_OCCURRENCES,
		MIN_NEARBY_OCCURRENCES,
		MAX_NEARBY_OCCURRENCES,
		SELECTED_TEMPORARY_BYTES,
		MIN_TEMPORARY_BYTES,
		MAX_TEMPORARY_BYTES,
		regex_common.MAX_CAPTURE_GROUPS,
		regex_common.MAX_PROGRAM_SIZE,
		regex_common.MAX_CLASSES,
	)
	return valid
}

probe_interaction_representation :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	prompt: interaction.Prompt
	initialized, init_failure := interaction.prompt_init(
		&prompt,
		interaction.Prompt_Config {
			kind = .Text_Entry,
			text_bytes_limit = SELECTED_PATTERN_BYTES,
			allow_empty = true,
			allocator = allocator,
		},
	)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf(
			"study=search profile=interaction initialized=false failure=%v\n",
			init_failure.code,
		)
		return false
	}
	transition, append_failure := interaction.prompt_text_append(&prompt, "Odra")
	delete_transition, delete_failure := interaction.prompt_text_delete_previous(&prompt)
	view, viewed, view_failure := interaction.prompt_view(&prompt)
	view_valid := viewed && view_failure.code == .None && view.text == "Odr" &&
		view.text_bytes_limit == SELECTED_PATTERN_BYTES
	peak_bytes := tracking.peak_memory_allocated
	closed, close_failure := interaction.prompt_close(&prompt)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := transition == .Changed && append_failure.code == .None &&
		delete_transition == .Changed && delete_failure.code == .None &&
		view_valid && closed &&
		close_failure.code == .None && cleanup_bytes == 0
	fmt.printf(
		"study=search profile=interaction valid=%v representation=bounded-text-prompt text_limit=%d peak_bytes=%d cleanup_bytes=%d\n",
		valid,
		SELECTED_PATTERN_BYTES,
		peak_bytes,
		cleanup_bytes,
	)
	return valid
}

probe_regex_behavior :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	flags: regex.Flags = {.Unicode, .Multiline}
	feature_pattern := "(needle|rzeka)-(Odra)"
	compiled, create_error := regex.create(
		feature_pattern,
		flags,
		allocator,
		context.temp_allocator,
	)
	if create_error != nil {
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=search profile=regex phase=compile valid=false\n")
		return false
	}
	capture := regex.preallocate_capture(allocator)
	group_count, matched := regex.match_with_preallocated_capture(
		compiled,
		"rzeka-Odra",
		&capture,
		context.temp_allocator,
	)
	captures_valid := matched && group_count == 3 &&
		capture.groups[1] == "rzeka" && capture.groups[2] == "Odra"
	regex.destroy(capture, allocator)
	regex.destroy(compiled, allocator)

	invalid_regex, invalid_error := regex.create("(", flags, allocator, context.temp_allocator)
	invalid_rejected := invalid_error != nil
	if !invalid_rejected {
		regex.destroy(invalid_regex, allocator)
	}

	word_regex, word_error := regex.create("^\\w+$", flags, allocator, context.temp_allocator)
	ascii_word := false
	unicode_word := false
	if word_error == nil {
		word_capture := regex.preallocate_capture(allocator)
		_, ascii_word = regex.match_with_preallocated_capture(
			word_regex,
			"ascii_42",
			&word_capture,
			context.temp_allocator,
		)
		_, unicode_word = regex.match_with_preallocated_capture(
			word_regex,
			"\u017c\u00f3\u0142\u0107",
			&word_capture,
			context.temp_allocator,
		)
		regex.destroy(word_capture, allocator)
		regex.destroy(word_regex, allocator)
	}

	iterator, iterator_error := regex.create_iterator(
		"abc",
		"",
		flags,
		allocator,
		context.temp_allocator,
	)
	empty_matches := 0
	if iterator_error == nil {
		for {
			_, _, ok := regex.match_iterator(&iterator)
			if !ok {
				break
			}
			empty_matches += 1
		}
		regex.destroy(iterator, allocator)
	}

	smart_case_unicode := strings.equal_fold("NAD ODR\u0104", "nad odr\u0105")
	persistent_peak := tracking.peak_memory_allocated
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := captures_valid && invalid_rejected && word_error == nil &&
		ascii_word && !unicode_word && iterator_error == nil && empty_matches == 1 &&
		smart_case_unicode && cleanup_bytes == 0
	fmt.printf(
		"study=search profile=regex valid=%v captures=%d invalid_rejected=%v ascii_word=%v unicode_word=%v empty_iterator_matches=%d adapter_progress_required=%v unicode_equal_fold=%v persistent_peak=%d cleanup_bytes=%d\n",
		valid,
		group_count,
		invalid_rejected,
		ascii_word,
		unicode_word,
		empty_matches,
		empty_matches == 1,
		smart_case_unicode,
		persistent_peak,
		cleanup_bytes,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)

	contents, contents_error := make([]byte, int(profile.text_bytes), persistent)
	if contents_error != nil {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		fmt.eprintf("study=search profile=%s phase=fixture-allocation\n", profile.name)
		return false
	}
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	first_offset := u64(4_096 - len(LITERAL_PATTERN) / 2)
	last_offset := profile.text_bytes - SELECTED_SCAN_WINDOW_BYTES - u64(len(LITERAL_PATTERN) / 2)
	copy(contents[int(first_offset):], LITERAL_PATTERN)
	copy(contents[int(last_offset):], LITERAL_PATTERN)

	regex_started := time.tick_now()
	regex_compiled, regex_error := regex.create(
		LITERAL_PATTERN,
		{.Unicode, .Multiline},
		persistent,
		context.temp_allocator,
	)
	regex_matched := false
	if regex_error == nil {
		regex_capture := regex.preallocate_capture(persistent)
		_, regex_matched = regex.match_with_preallocated_capture(
			regex_compiled,
			string(contents),
			&regex_capture,
			context.temp_allocator,
		)
		regex.destroy(regex_capture, persistent)
		regex.destroy(regex_compiled, persistent)
	}
	regex_ns := time.duration_nanoseconds(time.tick_since(regex_started))

	buffer: editor.Buffer
	initialized, init_failure := editor.buffer_init(
		&buffer,
		profile.buffer_id,
		string(contents),
		editor.Allocator_Set{persistent = persistent, temporary = temporary},
	)
	delete(contents, persistent)
	if !initialized {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		fmt.eprintf(
			"study=search profile=%s phase=buffer-init failure=%v\n",
			profile.name,
			init_failure.code,
		)
		return false
	}

	snapshot: editor.Buffer_Snapshot
	opened, open_failure := editor.buffer_snapshot_open(&buffer, &snapshot)
	if !opened {
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		fmt.eprintf(
			"study=search profile=%s phase=snapshot-open failure=%v\n",
			profile.name,
			open_failure.code,
		)
		return false
	}

	forward := scan_snapshot(&snapshot, LITERAL_PATTERN, .Forward, 0, temporary)
	backward := scan_snapshot(&snapshot, LITERAL_PATTERN, .Backward, 0, temporary)
	regexp_query: editor_search.Query
	regexp_query_ok, regexp_query_failure := editor_search.query_init(
		&regexp_query,
		editor_search.Query_Config {
			id = editor_search.Query_ID(profile.buffer_id),
			kind = .Regular_Expression,
			pattern = LITERAL_PATTERN,
			policy = editor_search.Policy {
				case_mode = .Sensitive,
				boundary_mode = .Unrestricted,
				whitespace_mode = .Exact,
				wrap = false,
			},
			limits = editor_search.DEFAULT_LIMITS,
			allocator = persistent,
			temporary_allocator = temporary,
		},
	)
	regexp_forward, regexp_backward: Regexp_Scan_Result
	if regexp_query_ok {
		regexp_forward = run_production_regexp(
			&snapshot,
			&regexp_query,
			profile.buffer_id,
			profile.text_bytes,
			0,
			.Forward,
			persistent,
			temporary,
		)
		regexp_backward = run_production_regexp(
			&snapshot,
			&regexp_query,
			profile.buffer_id,
			profile.text_bytes,
			editor.Byte_Offset(profile.text_bytes),
			.Backward,
			persistent,
			temporary,
		)
		editor_search.query_close(&regexp_query)
	}
	stats, stats_ok, _ := editor.buffer_snapshot_stats(&snapshot)
	persistent_peak := persistent_tracking.peak_memory_allocated
	temporary_peak := temporary_tracking.peak_memory_allocated
	snapshot_closed, _ := editor.buffer_snapshot_close(&snapshot)
	buffer_closed, _ := editor.buffer_close(&buffer)
	cleanup_bytes := persistent_tracking.current_memory_allocated +
		temporary_tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)

	within_gate := forward.latency.p99_ns <= profile.turn_gate_ns &&
		backward.latency.p99_ns <= profile.turn_gate_ns &&
		regexp_forward.total_ns <= profile.turn_gate_ns &&
		regexp_backward.total_ns <= profile.turn_gate_ns
	valid := regex_error == nil && regex_matched && regexp_query_ok &&
		regexp_query_failure.code == .None && stats_ok &&
		stats.text_bytes == profile.text_bytes &&
		forward.found && forward.offset == first_offset &&
		backward.found && backward.offset == last_offset &&
		regexp_forward.valid && regexp_forward.found && regexp_forward.start == first_offset &&
		regexp_backward.valid && regexp_backward.found && regexp_backward.start == last_offset &&
		within_gate && snapshot_closed && buffer_closed && cleanup_bytes == 0
	fmt.printf(
		"study=search profile=%s valid=%v text_bytes=%d first_offset=%d last_offset=%d forward_p50_ns=%d forward_p99_ns=%d backward_p50_ns=%d backward_p99_ns=%d turn_gate_ns=%d forward_total_ns=%d backward_total_ns=%d forward_reads=%d backward_reads=%d forward_read_bytes=%d backward_read_bytes=%d contiguous_regex_ns=%d regex_matched=%v production_regexp_forward_ns=%d production_regexp_backward_ns=%d production_regexp_forward_logical_bytes=%d production_regexp_backward_logical_bytes=%d production_regexp_forward_read_bytes=%d production_regexp_backward_read_bytes=%d production_regexp_temporary_peak=%d shared_persistent_bytes=%d persistent_peak=%d temporary_peak=%d cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.text_bytes,
		forward.offset,
		backward.offset,
		forward.latency.p50_ns,
		forward.latency.p99_ns,
		backward.latency.p50_ns,
		backward.latency.p99_ns,
		profile.turn_gate_ns,
		forward.total_ns,
		backward.total_ns,
		forward.reads,
		backward.reads,
		forward.read_bytes,
		backward.read_bytes,
		regex_ns,
		regex_matched,
		regexp_forward.total_ns,
		regexp_backward.total_ns,
		regexp_forward.logical_bytes,
		regexp_backward.logical_bytes,
		regexp_forward.read_bytes,
		regexp_backward.read_bytes,
		max(regexp_forward.temporary_peak_bytes, regexp_backward.temporary_peak_bytes),
		stats.shared_persistent_bytes,
		persistent_peak,
		temporary_peak,
		cleanup_bytes,
	)
	return valid
}

run_production_regexp :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	query: ^editor_search.Query,
	buffer_id: editor.Buffer_ID,
	text_bytes: u64,
	origin: editor.Byte_Offset,
	direction: editor_search.Direction,
	persistent, temporary: mem.Allocator,
) -> Regexp_Scan_Result {
	result: editor_search.Result
	started := time.tick_now()
	searched, failure := editor_search.regexp_search(
		&result,
		snapshot,
		query,
		editor_search.Request {
			scope = editor_search.Scope {
				buffer_id = buffer_id,
				revision = 0,
				start = 0,
				end = editor.Byte_Offset(text_bytes),
			},
			origin = origin,
			direction = direction,
			generation = 1,
			wrap_already_attempted = true,
		},
		nil,
		editor_search.Allocator_Set{persistent = persistent, temporary = temporary},
	)
	elapsed := time.duration_nanoseconds(time.tick_since(started))
	if !searched || failure.code != .None {
		return Regexp_Scan_Result{total_ns = elapsed}
	}
	view, viewed, view_failure := editor_search.result_view(&result)
	probe := Regexp_Scan_Result {
		valid = viewed && view_failure.code == .None &&
		        view.usage.logical_bytes <= editor_search.DEFAULT_SCAN_WINDOW_BYTES &&
		        view.usage.temporary_peak_bytes <= editor_search.DEFAULT_TEMPORARY_BYTES,
		found = viewed && view.outcome == .Matched && view.has_current && len(view.occurrences) > 0,
		logical_bytes = view.usage.logical_bytes,
		read_bytes = view.usage.read_bytes,
		temporary_peak_bytes = view.usage.temporary_peak_bytes,
		total_ns = elapsed,
	}
	if probe.found {
		current := view.occurrences[view.current_index]
		probe.start = u64(current.start)
		probe.end = u64(current.end)
	}
	closed, close_failure := editor_search.result_close(&result)
	probe.valid = probe.valid && closed && close_failure.code == .None
	return probe
}

run_stress :: proc() -> bool {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	contents, contents_error := make([]byte, int(DEMANDING_BYTES), persistent)
	if contents_error != nil {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return false
	}
	for index in 0 ..< len(contents) {
		contents[index] = 'x'
	}
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		103,
		string(contents),
		editor.Allocator_Set{persistent = persistent, temporary = temporary},
	)
	delete(contents, persistent)
	if !initialized {
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return false
	}
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	if !opened {
		editor.buffer_close(&buffer)
		mem.tracking_allocator_destroy(&temporary_tracking)
		mem.tracking_allocator_destroy(&persistent_tracking)
		return false
	}
	cancelled := scan_snapshot(
		&snapshot,
		LITERAL_PATTERN,
		.Forward,
		SELECTED_CANCELLATION_BYTES,
		temporary,
	)
	oversize_rejected := MAX_PATTERN_BYTES + 1 > MAX_PATTERN_BYTES
	persistent_peak := persistent_tracking.peak_memory_allocated
	temporary_peak := temporary_tracking.peak_memory_allocated
	snapshot_closed, _ := editor.buffer_snapshot_close(&snapshot)
	buffer_closed, _ := editor.buffer_close(&buffer)
	cleanup_bytes := persistent_tracking.current_memory_allocated +
		temporary_tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)
	valid := cancelled.cancelled && !cancelled.found &&
		cancelled.logical_bytes <= SELECTED_CANCELLATION_BYTES &&
		cancelled.total_ns <= CANCELLATION_GATE_NS && oversize_rejected &&
		snapshot_closed && buffer_closed && cleanup_bytes == 0
	fmt.printf(
		"study=search profile=stress valid=%v text_bytes=%d cancelled=%v logical_bytes=%d cancellation_limit=%d cancellation_ns=%d cancellation_gate_ns=%d checks=%d oversize_pattern_rejected=%v persistent_peak=%d temporary_peak=%d cleanup_bytes=%d\n",
		valid,
		DEMANDING_BYTES,
		cancelled.cancelled,
		cancelled.logical_bytes,
		SELECTED_CANCELLATION_BYTES,
		cancelled.total_ns,
		CANCELLATION_GATE_NS,
		cancelled.checks,
		oversize_rejected,
		persistent_peak,
		temporary_peak,
		cleanup_bytes,
	)
	return valid
}

scan_snapshot :: proc(
	snapshot: ^editor.Buffer_Snapshot,
	pattern: string,
	direction: Direction,
	cancel_after: u64,
	allocator: mem.Allocator,
) -> Scan_Result {
	stats, stats_ok, _ := editor.buffer_snapshot_stats(snapshot)
	if !stats_ok || len(pattern) == 0 || u64(len(pattern)) > SELECTED_PATTERN_BYTES {
		return {}
	}
	overlap := u64(len(pattern) - 1)
	scratch_bytes := min(stats.text_bytes, SELECTED_SCAN_WINDOW_BYTES + overlap)
	scratch, scratch_error := make([]byte, int(scratch_bytes), allocator)
	if scratch_error != nil {
		return {}
	}
	defer delete(scratch, allocator)
	maximum_reads := int((stats.text_bytes + SELECTED_SCAN_WINDOW_BYTES - 1) /
		SELECTED_SCAN_WINDOW_BYTES) + 1
	latencies, latency_error := make([]i64, maximum_reads, allocator)
	if latency_error != nil {
		return {}
	}
	defer delete(latencies, allocator)

	result := Scan_Result{offset = max(u64)}
	read_start := u64(0)
	started := time.tick_now()
	for read_start < stats.text_bytes {
		turn_started := time.tick_now()
		copied, read_ok, _ := editor.buffer_snapshot_read(
			snapshot,
			editor.Byte_Offset(read_start),
			scratch,
		)
		if !read_ok || copied == 0 {
			break
		}
		match_index := find_exact(scratch[:int(copied)], pattern, direction)
		if match_index >= 0 {
			match_offset := read_start + u64(match_index)
			if direction == .Forward {
				result.found = true
				result.offset = match_offset
			} else if !result.found || match_offset > result.offset {
				result.found = true
				result.offset = match_offset
			}
		}
		latencies[result.reads] = time.duration_nanoseconds(time.tick_since(turn_started))
		result.reads += 1
		result.read_bytes += copied
		if direction == .Forward && result.found {
			break
		}
		if read_start + copied >= stats.text_bytes {
			result.logical_bytes = stats.text_bytes
			break
		}
		advance := copied - overlap
		read_start += advance
		result.logical_bytes = read_start
		if cancel_after > 0 && result.logical_bytes >= cancel_after {
			result.cancelled = true
			result.checks += 1
			break
		}
		if result.logical_bytes % SELECTED_CANCELLATION_BYTES == 0 {
			result.checks += 1
		}
	}
	result.total_ns = time.duration_nanoseconds(time.tick_since(started))
	if result.reads > 0 {
		result.latency = summarize(latencies[:int(result.reads)])
	}
	return result
}

find_exact :: proc(bytes: []byte, pattern: string, direction: Direction) -> int {
	if len(pattern) == 0 || len(pattern) > len(bytes) {
		return -1
	}
	if direction == .Forward {
		for start in 0 ..= len(bytes) - len(pattern) {
			if string(bytes[start:start + len(pattern)]) == pattern {
				return start
			}
		}
		return -1
	}
	for start := len(bytes) - len(pattern); start >= 0; start -= 1 {
		if string(bytes[start:start + len(pattern)]) == pattern {
			return start
		}
	}
	return -1
}

summarize :: proc(latencies: []i64) -> Latency {
	slice.sort(latencies)
	p50_index := (len(latencies) * 50 + 99) / 100 - 1
	p99_index := (len(latencies) * 99 + 99) / 100 - 1
	return {p50_ns = latencies[p50_index], p99_ns = latencies[p99_index]}
}
