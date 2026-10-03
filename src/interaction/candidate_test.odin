// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:mem"
import "core:testing"

/* Verifies matching, ranking, movement, local recency, cancellation, and cleanup. */
@(test)
session_lifecycle_checks_rank_and_generation :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	definitions := candidate_test_definitions()
	session: Candidate_Session
	result, initialized, failure := candidate_session_init(
		&session,
		candidate_test_config(101, allocator, allocator),
		candidate_test_source(definitions[:], 1),
		"alpha project",
	)
	testing.expectf(t, initialized, "candidate init failed with %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	view, viewed, view_failure := candidate_session_view(&session)
	testing.expectf(t, viewed, "candidate view failed with %v", view_failure.code)
	testing.expect_value(t, len(view.rows), 3)
	if len(view.rows) == 3 {
		testing.expect_value(t, view.rows[0].label, "Alpha Project")
		testing.expect_value(t, view.rows[0].match_class, Candidate_Match_Class.Exact_Label)
		testing.expect_value(t, view.rows[1].label, "Project Alpha")
		testing.expect_value(t, view.rows[1].match_class, Candidate_Match_Class.Prefix_Or_Boundary)
		testing.expect_value(t, view.rows[2].label, "Other xalpha xproject")
		testing.expect_value(t, view.rows[2].match_class, Candidate_Match_Class.Literal)
	}
	initial_generation := result.session_generation
	move_result, moved, move_failure := candidate_session_move(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		1,
	)
	testing.expectf(t, moved, "candidate move failed with %v", move_failure.code)
	testing.expect_value(t, move_result.identity, definitions[0].identity)
	_, stale, stale_failure := candidate_session_move(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = initial_generation},
		1,
	)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Candidate_Failure_Code.Stale_Session)
	view, _, _ = candidate_session_view(&session)
	_, recorded, record_failure := candidate_session_record_success(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		definitions[0].identity,
	)
	testing.expectf(t, recorded, "candidate recency failed with %v", record_failure.code)
	view, _, _ = candidate_session_view(&session)
	_, queried, query_failure := candidate_session_set_query(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		"",
	)
	testing.expectf(t, queried, "empty query failed with %v", query_failure.code)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, len(view.rows), 5)
	if len(view.rows) == 5 {
		testing.expect_value(t, view.rows[0].identity, definitions[0].identity)
	}
	_, cancelled, cancel_failure := candidate_session_cancel(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
	)
	testing.expectf(t, cancelled, "candidate cancellation failed with %v", cancel_failure.code)
	view, _, _ = candidate_session_view(&session)
	testing.expect(t, view.cancelled)
	_, moved_after_cancel, cancelled_failure := candidate_session_move(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		1,
	)
	testing.expect(t, !moved_after_cancel)
	testing.expect_value(t, cancelled_failure.code, Candidate_Failure_Code.Cancelled)
	_, closed, close_failure := candidate_session_close(&session)
	testing.expectf(t, closed, "candidate close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies admitted patterns and invalid-pattern literal fallback remain distinct. */
@(test)
session_falls_back_to_literal_patterns :: proc(t: ^testing.T) {
	definitions := candidate_test_definitions()
	session: Candidate_Session
	_, initialized, _ := candidate_session_init(
		&session,
		candidate_test_config(102, context.allocator, context.temp_allocator),
		candidate_test_source(definitions[:], 1),
		"^beta-[0-9]+$",
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer candidate_session_close(&session)
	view, viewed, _ := candidate_session_view(&session)
	testing.expect(t, viewed)
	testing.expect_value(t, len(view.rows), 1)
	if len(view.rows) == 1 {
		testing.expect_value(t, view.rows[0].label, "Beta-42")
		testing.expect_value(t, view.rows[0].match_class, Candidate_Match_Class.Pattern)
	}
	_, queried, failure := candidate_session_set_query(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		"[",
	)
	testing.expectf(t, queried, "invalid-pattern fallback failed with %v", failure.code)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, len(view.rows), 1)
	if len(view.rows) == 1 {
		testing.expect_value(t, view.rows[0].label, "Literal [ Token")
		testing.expect_value(
			t,
			view.rows[0].match_class,
			Candidate_Match_Class.Prefix_Or_Boundary,
		)
	}
}

/* Verifies a changed query selects the first newly ranked row. */
@(test)
session_query_change_selects_first_ranked_row :: proc(t: ^testing.T) {
	definitions := candidate_test_definitions()
	session: Candidate_Session
	_, initialized, _ := candidate_session_init(
		&session,
		candidate_test_config(109, context.allocator, context.temp_allocator),
		candidate_test_source(definitions[:], 1),
		"alpha project",
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer candidate_session_close(&session)
	view, _, _ := candidate_session_view(&session)
	_, moved, move_failure := candidate_session_move(
		&session,
		Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		2,
	)
	testing.expectf(t, moved, "candidate move failed with %v", move_failure.code)
	view, _, _ = candidate_session_view(&session)
	prior_selection := view.rows[view.selected_row].identity
	_, queried, query_failure := candidate_session_set_query(
		&session,
		Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		"alpha",
	)
	testing.expectf(t, queried, "candidate query failed with %v", query_failure.code)
	view, _, _ = candidate_session_view(&session)
	testing.expect(t, view.has_selection)
	testing.expect_value(t, view.selected_row, u32(0))
	if len(view.rows) > 0 {
		testing.expect(t, view.rows[0].identity != prior_selection)
	}
}

/* Verifies complete refresh preserves stable selection and rejects stale source generations. */
@(test)
session_refresh_is_atomic_and_preserves_identity :: proc(t: ^testing.T) {
	definitions := candidate_test_definitions()
	session: Candidate_Session
	_, initialized, _ := candidate_session_init(
		&session,
		candidate_test_config(103, context.allocator, context.temp_allocator),
		candidate_test_source(definitions[:], 1),
		"",
	)
	testing.expect(t, initialized)
	if !initialized {
		return
	}
	defer candidate_session_close(&session)
	view, _, _ := candidate_session_view(&session)
	_, moved, _ := candidate_session_move(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		2,
	)
	testing.expect(t, moved)
	view, _, _ = candidate_session_view(&session)
	selected := view.rows[view.selected_row].identity
	refreshed_definitions := [4]Candidate_Descriptor_Definition {
		definitions[3],
		definitions[2],
		definitions[1],
		definitions[0],
	}
	_, refreshed, refresh_failure := candidate_session_refresh(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		candidate_test_source(refreshed_definitions[:], 2),
	)
	testing.expectf(t, refreshed, "candidate refresh failed with %v", refresh_failure.code)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, view.rows[view.selected_row].identity, selected)
	before_generation := view.session_generation
	_, stale, stale_failure := candidate_session_refresh(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = view.session_generation},
		candidate_test_source(refreshed_definitions[:], 2),
	)
	testing.expect(t, !stale)
	testing.expect_value(t, stale_failure.code, Candidate_Failure_Code.Stale_Source)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, view.session_generation, before_generation)
}

/* Verifies admission and query allocation failures publish no partial session or leaked storage. */
@(test)
session_alloc_failures_are_atomic_and_released :: proc(t: ^testing.T) {
	definitions := candidate_test_definitions()
	failures: u32
	successes: u32
	for fail_after in 0 ..< 96 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Resolver_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		allocator := resolver_failing_allocator(&failing)
		session: Candidate_Session
		_, initialized, _ := candidate_session_init(
			&session,
			candidate_test_config(104, allocator, context.temp_allocator),
			candidate_test_source(definitions[:], 1),
			"[",
		)
		if initialized {
			successes += 1
			_, _, _ = candidate_session_close(&session)
		} else {
			failures += 1
			testing.expect(t, session.state == nil)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, failures > 0)
	testing.expect(t, successes > 0)
}

/* Verifies Unicode folding, retained accounting, and query bounds preserve prior state. */
@(test)
session_reports_unicode_query_bounds :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	fields := [?]string{"Polish city"}
	annotations := [?]Candidate_Annotation_Definition {
		{kind = .Description, text = "Unicode label"},
	}
	definitions := [?]Candidate_Descriptor_Definition {
		{
			identity = {kind = 2, primary = 1},
			label = "ŁÓDŹ",
			searchable_fields = fields[:],
			annotations = annotations[:],
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 1},
			availability = .Available,
		},
	}
	session: Candidate_Session
	_, initialized, failure := candidate_session_init(
		&session,
		candidate_test_config(105, allocator, allocator),
		candidate_test_source(definitions[:], 1),
		"łódź",
	)
	testing.expectf(t, initialized, "Unicode candidate init failed with %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	view, viewed, _ := candidate_session_view(&session)
	testing.expect(t, viewed)
	testing.expect_value(t, len(view.rows), 1)
	if len(view.rows) == 1 {
		testing.expect_value(t, view.rows[0].match_class, Candidate_Match_Class.Exact_Label)
	}
	testing.expect_value(t, view.accounting.candidates, u32(1))
	testing.expect_value(t, view.accounting.label_bytes, u64(len("ŁÓDŹ")))
	testing.expect_value(t, view.accounting.searchable_bytes, u64(len(fields[0])))
	testing.expect_value(t, view.accounting.annotation_bytes, u64(len(annotations[0].text)))
	testing.expect_value(t, view.accounting.query_bytes, u32(len("łódź")))
	testing.expect_value(t, view.accounting.query_components, u8(1))
	testing.expect_value(t, view.accounting.filtered_indices, u32(1))
	generation := view.session_generation
	oversized: [MAX_CANDIDATE_QUERY_BYTES + 1]byte
	for &value in oversized {
		value = 'x'
	}
	_, accepted, query_failure := candidate_session_set_query(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = generation},
		string(oversized[:]),
	)
	testing.expect(t, !accepted)
	testing.expect_value(t, query_failure.code, Candidate_Failure_Code.Query_Limit)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, view.session_generation, generation)
	_, accepted, query_failure = candidate_session_set_query(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = generation},
		"a b c d e f g h i",
	)
	testing.expect(t, !accepted)
	testing.expect_value(t, query_failure.code, Candidate_Failure_Code.Component_Limit)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, view.session_generation, generation)
	_, closed, close_failure := candidate_session_close(&session)
	testing.expectf(t, closed, "Unicode candidate close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies maximum source recency is normalized before publishing a new success. */
@(test)
session_renormalizes_recency_without_overflow :: proc(t: ^testing.T) {
	definitions := [?]Candidate_Descriptor_Definition {
		{
			identity = {kind = 3, primary = 1},
			label = "First",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 1},
			availability = .Available,
			recency = max(u64),
		},
		{
			identity = {kind = 3, primary = 2},
			label = "Second",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 2},
			availability = .Available,
			recency = max(u64) - 1,
		},
	}
	session: Candidate_Session
	_, initialized, failure := candidate_session_init(
		&session,
		candidate_test_config(106, context.allocator, context.temp_allocator),
		candidate_test_source(definitions[:], 1),
	)
	testing.expectf(t, initialized, "overflow candidate init failed with %v", failure.code)
	if !initialized {
		return
	}
	defer candidate_session_close(&session)
	view, _, _ := candidate_session_view(&session)
	_, recorded, record_failure := candidate_session_record_success(
		&session,
		Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		definitions[1].identity,
	)
	testing.expectf(t, recorded, "overflow recency failed with %v", record_failure.code)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, len(view.rows), 2)
	if len(view.rows) == 2 {
		testing.expect_value(t, view.rows[0].identity, definitions[1].identity)
		testing.expect_value(t, view.rows[0].recency, u64(3))
		testing.expect_value(t, view.rows[1].recency, u64(2))
	}
}

/* Verifies failed recency projection leaves the published ranking unchanged. */
@(test)
session_recency_failure_preserves_prior_ranking :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Resolver_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = max(u64),
	}
	allocator := resolver_failing_allocator(&failing)
	definitions := [?]Candidate_Descriptor_Definition {
		{
			identity = {kind = 4, primary = 1},
			label = "A [ one",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 1},
			availability = .Available,
			recency = 2,
		},
		{
			identity = {kind = 4, primary = 2},
			label = "B [ two",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 2},
			availability = .Available,
			recency = 1,
		},
	}
	session: Candidate_Session
	_, initialized, failure := candidate_session_init(
		&session,
		candidate_test_config(107, allocator, context.temp_allocator),
		candidate_test_source(definitions[:], 1),
		"[",
	)
	testing.expectf(t, initialized, "atomic recency init failed with %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	view, _, _ := candidate_session_view(&session)
	generation := view.session_generation
	failing.fail_after = failing.successful_allocations
	_, recorded, record_failure := candidate_session_record_success(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = generation},
		definitions[1].identity,
	)
	testing.expect(t, !recorded)
	testing.expect_value(t, record_failure.code, Candidate_Failure_Code.Persistent_Memory_Limit)
	failing.fail_after = max(u64)
	_, queried, query_failure := candidate_session_set_query(
		&session,
		Candidate_Request{session_id = view.session_id, session_generation = generation},
		"[",
	)
	testing.expectf(t, queried, "post-fault query failed with %v", query_failure.code)
	view, _, _ = candidate_session_view(&session)
	testing.expect_value(t, len(view.rows), 2)
	if len(view.rows) == 2 {
		testing.expect_value(t, view.rows[0].identity, definitions[0].identity)
	}
	_, _, _ = candidate_session_close(&session)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies temporary admission failure releases already copied persistent storage. */
@(test)
temp_failure_releases_session_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	failing := Resolver_Failing_Allocator{backing = context.allocator, fail_after = 0}
	definitions := candidate_test_definitions()
	session: Candidate_Session
	_, initialized, failure := candidate_session_init(
		&session,
		candidate_test_config(
			108,
			mem.tracking_allocator(&tracking),
			resolver_failing_allocator(&failing),
		),
		candidate_test_source(definitions[:], 1),
		"[",
	)
	testing.expect(t, !initialized)
	testing.expect_value(t, failure.code, Candidate_Failure_Code.Temporary_Memory_Limit)
	testing.expect(t, session.state == nil)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
candidate_test_config :: proc(
	id: u64,
	persistent_allocator, temporary_allocator: mem.Allocator,
) -> Candidate_Config {
	return Candidate_Config {
		session_id = Candidate_Session_ID(id),
		limits = DEFAULT_CANDIDATE_LIMITS,
		persistent_allocator = persistent_allocator,
		temporary_allocator = temporary_allocator,
	}
}

@(private)
candidate_test_source :: proc(
	definitions: []Candidate_Descriptor_Definition,
	generation: u64,
) -> Candidate_Source_Definition {
	return Candidate_Source_Definition {
		kind = .Test,
		scope_identity = 1,
		scope_generation = generation,
		source_generation = generation,
		descriptors = definitions,
	}
}

@(private)
candidate_test_definitions :: proc() -> [5]Candidate_Descriptor_Definition {
	return {
		{
			identity = {kind = 1, primary = 3},
			label = "Project Alpha",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 3},
			availability = .Available,
			recency = 4,
		},
		{
			identity = {kind = 1, primary = 2},
			label = "Alpha Project",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 2},
			availability = .Available,
			recency = 8,
		},
		{
			identity = {kind = 1, primary = 1},
			label = "Other xalpha xproject",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 1},
			availability = .Available,
			recency = 9,
		},
		{
			identity = {kind = 1, primary = 4},
			label = "Beta-42",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 4},
			availability = .Available,
		},
		{
			identity = {kind = 1, primary = 5},
			label = "Literal [ Token",
			action = {kind = .Invoke_Command, owner_generation = 1, primary = 5},
			availability = .Available,
		},
	}
}
