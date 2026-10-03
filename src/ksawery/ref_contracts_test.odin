// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:testing"

REF_TEST_SHA1 :: "0123456789abcdef0123456789abcdef01234567"

@(private)
ref_contracts_test_repository :: proc() -> (Repository_Context, bool) {
	repository: Repository_Context
	return repository, repository_context_assign(&repository, "/work/refs")
}

@(private)
ref_contracts_test_identity :: proc(
	repository: Repository_Context,
	generation: Ref_Generation,
	kind: Ref_Kind,
	name: string,
) -> (Ref_Identity, bool) {
	identity := Ref_Identity {
		repository = repository,
		generation = generation,
		kind = kind,
		object_type = .Commit,
	}
	if kind == .Tag do identity.object_type = .Tag
	return identity, ref_name_assign(&identity.name, name) && revision_identity_assign(&identity.object, REF_TEST_SHA1)
}

@(private)
ref_contracts_test_remote :: proc(
	repository: Repository_Context,
	generation: Ref_Generation,
	name: string,
) -> (Remote_Identity, bool) {
	remote := Remote_Identity {repository = repository, generation = generation}
	return remote, remote_name_assign(&remote.name, name)
}

/* Verifies complete ref names remain category-bound and never admit labels as identities. */
@(test)
ref_names_require_complete_category_bound_identities :: proc(t: ^testing.T) {
	repository, ready := ref_contracts_test_repository()
	testing.expect(t, ready)
	if !ready do return
	branch, branch_ready := ref_contracts_test_identity(repository, Ref_Generation(3), .Local_Branch, "refs/heads/main")
	testing.expect(t, branch_ready && ref_identity_is_valid(branch))
	remote, remote_ready := ref_contracts_test_identity(repository, Ref_Generation(3), .Remote_Tracking_Branch, "refs/remotes/origin/main")
	testing.expect(t, remote_ready && ref_identity_is_valid(remote))
	tag, tag_ready := ref_contracts_test_identity(repository, Ref_Generation(3), .Tag, "refs/tags/v0.1.0")
	testing.expect(t, tag_ready && ref_identity_is_valid(tag))

	invalid: Ref_Name
	testing.expect(t, !ref_name_assign(&invalid, "main"))
	testing.expect(t, !ref_name_assign(&invalid, "refs/heads/main\nother"))
	if branch_ready {
		branch.kind = .Tag
		testing.expect(t, !ref_identity_is_valid(branch))
	}
}

/* Verifies measured Ref limits reject excessive entry, remote, metadata, and temporary envelopes. */
@(test)
ref_limits_require_bounded_entry_and_retained_resource_envelopes :: proc(t: ^testing.T) {
	testing.expect(t, ref_limits_are_valid(DEFAULT_REF_LIMITS))

	too_many_entries := DEFAULT_REF_LIMITS
	too_many_entries.entries = MAX_REF_ENTRIES + 1
	testing.expect(t, !ref_limits_are_valid(too_many_entries))

	too_many_remotes := DEFAULT_REF_LIMITS
	too_many_remotes.remotes = MAX_REMOTE_ENTRIES + 1
	testing.expect(t, !ref_limits_are_valid(too_many_remotes))

	too_little_metadata := DEFAULT_REF_LIMITS
	too_little_metadata.metadata_bytes = MIN_REF_METADATA_BYTES - 1
	testing.expect(t, !ref_limits_are_valid(too_little_metadata))

	too_little_temporary := DEFAULT_REF_LIMITS
	too_little_temporary.temporary_bytes = too_little_temporary.metadata_bytes - 1
	testing.expect(t, !ref_limits_are_valid(too_little_temporary))
}

/* Verifies HEAD and tracking state preserve exact observation-bound ref identity. */
@(test)
ref_head_and_tracking_relationships_require_exact_generation_and_counts :: proc(t: ^testing.T) {
	repository, ready := ref_contracts_test_repository()
	testing.expect(t, ready)
	if !ready do return
	branch, branch_ready := ref_contracts_test_identity(repository, Ref_Generation(7), .Local_Branch, "refs/heads/main")
	upstream, upstream_ready := ref_contracts_test_identity(repository, Ref_Generation(7), .Remote_Tracking_Branch, "refs/remotes/origin/main")
	testing.expect(t, branch_ready && upstream_ready)
	if !branch_ready || !upstream_ready do return

	head := Head_Observation {state = .Symbolic, branch = branch, object = branch.object}
	testing.expect(t, head_observation_is_valid(head))
	head.object = {}
	testing.expect(t, !head_observation_is_valid(head))

	relationship := Tracking_Relationship {local = branch, upstream = upstream, state = .Diverged, ahead = 2, behind = 1}
	testing.expect(t, tracking_relationship_is_valid(relationship))
	relationship.behind = 0
	testing.expect(t, !tracking_relationship_is_valid(relationship))
	relationship = {local = branch, state = .Missing}
	testing.expect(t, tracking_relationship_is_valid(relationship))
	relationship.upstream = upstream
	testing.expect(t, !tracking_relationship_is_valid(relationship))
}

/* Verifies Ref descriptors and semantic selection distinguish complete, truncated, and stale state. */
@(test)
ref_descriptors_and_selection_preserve_observation_ownership :: proc(t: ^testing.T) {
	repository, ready := ref_contracts_test_repository()
	testing.expect(t, ready)
	if !ready do return
	branch, branch_ready := ref_contracts_test_identity(repository, Ref_Generation(11), .Local_Branch, "refs/heads/main")
	upstream, upstream_ready := ref_contracts_test_identity(repository, Ref_Generation(11), .Remote_Tracking_Branch, "refs/remotes/origin/main")
	remote, remote_ready := ref_contracts_test_remote(repository, Ref_Generation(11), "origin")
	testing.expect(t, branch_ready && upstream_ready && remote_ready)
	if !branch_ready || !upstream_ready || !remote_ready do return
	testing.expect(t, ref_identity_is_valid(upstream))

	descriptor := Ref_Observation_Descriptor {
		repository = repository,
		generation = Ref_Generation(11),
		state = .Available,
		head = {state = .Symbolic, branch = branch, object = branch.object},
		local_branch_count = 1,
		remote_tracking_count = 1,
		tag_count = 1,
		remote_count = 1,
		tracking_relationships = 1,
		metadata_bytes = 128,
		temporary_bytes = 256,
	}
	testing.expect(t, ref_observation_descriptor_is_valid(descriptor))
	descriptor.state = .Truncated
	testing.expect(t, ref_observation_descriptor_is_valid(descriptor))
	descriptor.tracking_relationships = 2
	testing.expect(t, !ref_observation_descriptor_is_valid(descriptor))

	selection := Ref_Selection {
		generation = Ref_Generation(11),
		current = {kind = .Ref, reference = branch},
		marked = branch,
	}
	testing.expect(t, ref_selection_is_valid(selection))
	selection.current = {kind = .Remote, remote = remote}
	testing.expect(t, ref_selection_is_valid(selection))
	selection.marked.generation = Ref_Generation(12)
	testing.expect(t, !ref_selection_is_valid(selection))
}

/* Verifies Ref semantic presentation retains non-color cues for selected branches and remotes. */
@(test)
ref_presentation_uses_shared_selected_and_head_role_contract :: proc(t: ^testing.T) {
	role, composed := presentation_role_compose({
		surface = .Refs,
		subject = .Branch,
		current = true,
		head = true,
	})
	testing.expect(t, composed && presentation_role_is_valid(role))
	if composed {
		testing.expect_value(t, role.emphasis, Presentation_Emphasis.Current)
		testing.expect_value(t, role.cue, Presentation_Cue.Current)
	}
	remote, remote_composed := presentation_role_compose({surface = .Refs, subject = .Remote})
	testing.expect(t, remote_composed && presentation_role_is_valid(remote))
}
