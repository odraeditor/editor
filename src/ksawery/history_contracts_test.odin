// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:mem"
import "core:testing"

HISTORY_TEST_SHA1 :: "0123456789abcdef0123456789abcdef01234567"
HISTORY_TEST_SHA256 :: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

@(private)
history_test_identity :: proc(text: string = HISTORY_TEST_SHA1) -> (Revision_Identity, bool) {
	identity: Revision_Identity
	return identity, revision_identity_assign(&identity, text)
}

/* Verifies revision identity rejects abbreviated, noncanonical, and malformed object names. */
@(test)
history_revision_identity_requires_full_canonical_object_names :: proc(t: ^testing.T) {
	identity, assigned := history_test_identity()
	testing.expect(t, assigned)
	if assigned {
		testing.expect(t, revision_identity_is_valid(identity))
		testing.expect_value(t, revision_identity_string(&identity), HISTORY_TEST_SHA1)
	}
	sha256, sha256_assigned := history_test_identity(HISTORY_TEST_SHA256)
	testing.expect(t, sha256_assigned && revision_identity_is_valid(sha256))

	invalid: Revision_Identity
	testing.expect(t, !revision_identity_assign(&invalid, HISTORY_TEST_SHA1[:12]))
	testing.expect(t, !revision_identity_assign(&invalid, "0123456789abcdef0123456789abcdef0123456g"))
	testing.expect(t, !revision_identity_assign(&invalid, "0123456789ABCDEF0123456789abcdef01234567"))
}

/* Verifies measured History limits retain representable topology and bounded parser work. */
@(test)
history_limits_require_consistent_page_topology_and_parser_budgets :: proc(t: ^testing.T) {
	testing.expect(t, history_limits_are_valid(DEFAULT_HISTORY_LIMITS))

	too_many_revisions := DEFAULT_HISTORY_LIMITS
	too_many_revisions.page_revisions = MAX_HISTORY_PAGE_REVISIONS + 1
	testing.expect(t, !history_limits_are_valid(too_many_revisions))

	too_small_topology := DEFAULT_HISTORY_LIMITS
	too_small_topology.topology_bytes = history_topology_bytes_required(too_small_topology.page_revisions) - 1
	testing.expect(t, !history_limits_are_valid(too_small_topology))

	too_small_temporary := DEFAULT_HISTORY_LIMITS
	too_small_temporary.temporary_bytes = too_small_temporary.metadata_bytes +
	                                     too_small_temporary.topology_bytes - 1
	testing.expect(t, !history_limits_are_valid(too_small_temporary))
}

/* Verifies continuation preserves exact observed HEAD and page-anchor identity. */
@(test)
history_requests_distinguish_initial_and_exact_continued_pages :: proc(t: ^testing.T) {
	testing.expect(t, history_continuation_is_valid({}))
	request := History_Request{limits = DEFAULT_HISTORY_LIMITS}
	testing.expect(t, history_request_is_valid(request))

	head, head_assigned := history_test_identity()
	after, after_assigned := history_test_identity(HISTORY_TEST_SHA256)
	testing.expect(t, head_assigned && after_assigned)
	if !head_assigned || !after_assigned do return
	request.continuation = {head = head, after = after, skipped = DEFAULT_HISTORY_PAGE_REVISIONS}
	testing.expect(t, history_request_is_valid(request))
	request.continuation.skipped = 0
	testing.expect(t, !history_request_is_valid(request))
	request.continuation.skipped = DEFAULT_HISTORY_PAGE_REVISIONS
	request.continuation.head = {}
	testing.expect(t, !history_request_is_valid(request))
}

/* Verifies selection and marks remain bound to one exact History generation. */
@(test)
history_selection_keeps_revision_and_parent_identity_nonpositional :: proc(t: ^testing.T) {
	revision, revision_assigned := history_test_identity()
	parent, parent_assigned := history_test_identity(HISTORY_TEST_SHA256)
	testing.expect(t, revision_assigned && parent_assigned)
	if !revision_assigned || !parent_assigned do return
	target := History_Target{generation = History_Generation(7), revision = revision}
	selection := History_Selection {
		generation = History_Generation(7),
		current = {kind = .Parent, revision = target, parent = parent},
		marked = target,
	}
	testing.expect(t, history_selection_is_valid(selection))
	selection.marked.generation = History_Generation(8)
	testing.expect(t, !history_selection_is_valid(selection))
}

/* Verifies unborn and available observations cannot share incomplete descriptor shapes. */
@(test)
history_descriptors_require_complete_available_or_unborn_state :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example")
	testing.expect(t, ready)
	if !ready do return

	unborn := History_Observation_Descriptor {
		repository = repository,
		generation = History_Generation(1),
		state = .Unborn,
	}
	testing.expect(t, history_observation_descriptor_is_valid(unborn))

	head, head_assigned := history_test_identity()
	after, after_assigned := history_test_identity(HISTORY_TEST_SHA256)
	testing.expect(t, head_assigned && after_assigned)
	if !head_assigned || !after_assigned do return
	available := History_Observation_Descriptor {
		repository = repository,
		generation = History_Generation(2),
		state = .Available,
		head = head,
		revision_count = 2,
		parent_links = 1,
		metadata_bytes = 192,
		message_bytes = 32,
		topology_bytes = history_topology_bytes_required(2),
		temporary_bytes = 4 * KIBIBYTE,
		continuation = {head = head, after = after, skipped = 2},
	}
	testing.expect(t, history_observation_descriptor_is_valid(available))
	available.head = {}
	testing.expect(t, !history_observation_descriptor_is_valid(available))
}

/* Verifies semantic composition keeps the selected, marked, HEAD, and destructive order visible without color. */
@(test)
history_presentation_precedence_has_matching_non_color_cues :: proc(t: ^testing.T) {
	state := Presentation_State {
		surface = .History,
		subject = .Revision,
		current = true,
		marked = true,
		head = true,
		destructive = true,
	}
	role, composed := presentation_role_compose(state)
	testing.expect(t, composed && presentation_role_is_valid(role))
	if !composed do return
	testing.expect_value(t, role.emphasis, Presentation_Emphasis.Current)
	testing.expect_value(t, role.cue, Presentation_Cue.Current)

	state.current = false
	role, composed = presentation_role_compose(state)
	testing.expect(t, composed && presentation_role_is_valid(role))
	if composed do testing.expect_value(t, role.emphasis, Presentation_Emphasis.Marked)

	state.marked = false
	role, composed = presentation_role_compose(state)
	testing.expect(t, composed && presentation_role_is_valid(role))
	if composed do testing.expect_value(t, role.emphasis, Presentation_Emphasis.Head)

	state.head = false
	role, composed = presentation_role_compose(state)
	testing.expect(t, composed && presentation_role_is_valid(role))
	if composed do testing.expect_value(t, role.emphasis, Presentation_Emphasis.Destructive)
}

/* Verifies Status keeps its existing semantic base while using the shared composition contract. */
@(test)
status_presentation_uses_shared_neutral_role_contract :: proc(t: ^testing.T) {
	role, composed := presentation_role_compose({surface = .Status, subject = .Path})
	testing.expect(t, composed && presentation_role_is_valid(role))
	if composed {
		testing.expect_value(t, role.emphasis, Presentation_Emphasis.None)
		testing.expect_value(t, role.cue, Presentation_Cue.None)
	}
}

/* Verifies History navigation follows immutable revision and parent identities rather than rendered rows. */
@(test)
history_navigation_moves_through_exact_revision_and_parent_items :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example")
	testing.expect(t, ready)
	if !ready do return
	output := transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA1 + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00root\x00root body\x00" +
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00child\x00child body\x00",
	))
	observation, opened, failure := history_observation_open(
		repository, History_Generation(8), output, {limits = DEFAULT_HISTORY_LIMITS}, context.allocator,
	)
	testing.expectf(t, opened, "history parse failed with %v", failure)
	if !opened do return
	defer history_observation_close(&observation)
	selection, selected := history_selection_begin(&observation)
	testing.expect(t, selected && history_selection_is_current(&observation, selection))
	if !selected do return
	testing.expect_value(t, selection.current.kind, History_Item_Kind.Revision)
	first_identity := selection.current.revision.revision
	testing.expect_value(t, revision_identity_string(&first_identity), HISTORY_TEST_SHA1)
	next_selection, moved, move_failure := history_selection_move(&observation, selection, .Next)
	testing.expectf(t, moved, "history navigation failed with %v", move_failure)
	testing.expect_value(t, next_selection.current.kind, History_Item_Kind.Revision)
	next_selection, moved, move_failure = history_selection_move(&observation, next_selection, .Next)
	testing.expectf(t, moved, "history parent navigation failed with %v", move_failure)
	testing.expect_value(t, next_selection.current.kind, History_Item_Kind.Parent)
	parent := next_selection.current.parent
	testing.expect_value(t, revision_identity_string(&parent), HISTORY_TEST_SHA1)
}

/* Verifies bounded NUL-delimited records retain exact revision identities and owned metadata. */
@(test)
history_observation_parses_exact_revision_records_and_releases_storage :: proc(t: ^testing.T) {
	repository: Repository_Context
	ready := repository_context_assign(&repository, "/work/example")
	testing.expect(t, ready)
	if !ready do return
	output := transmute([]u8)(string(
		"\x1e" + HISTORY_TEST_SHA1 + "\x00\x00Ada\x00ada@example.invalid\x002026-01-01T00:00:00+00:00\x002026-01-01T00:00:00+00:00\x00root\x00root body\x00" +
		"\x1e" + HISTORY_TEST_SHA256 + "\x00" + HISTORY_TEST_SHA1 + "\x00Ada\x00ada@example.invalid\x002026-01-02T00:00:00+00:00\x002026-01-02T00:00:00+00:00\x00child\x00child body\x00",
	))
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	observation, opened, failure := history_observation_open(
		repository,
		History_Generation(4),
		output,
		{limits = DEFAULT_HISTORY_LIMITS},
		allocator,
	)
	testing.expectf(t, opened, "history parse failed with %v", failure)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	descriptor, described := history_observation_descriptor(&observation)
	testing.expect(t, described)
	if described {
		testing.expect_value(t, descriptor.state, History_State.Available)
		testing.expect_value(t, descriptor.revision_count, u32(2))
		testing.expect_value(t, descriptor.parent_links, u32(1))
	}
	child, found := history_observation_revision(&observation, 1)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, child.parent_count, u8(1))
		subject, copied := history_observation_text(&observation, child.subject)
		testing.expect(t, copied)
		if copied do testing.expect_value(t, string(subject), "child")
	}
	history_observation_close(&observation)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
