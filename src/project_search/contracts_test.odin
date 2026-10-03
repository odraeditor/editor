// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_search

import "../project"
import "../search"
import "core:testing"

@(test)
/* Ensures requests require current Project and membership generations. */
request_requires_exact_project :: proc(t: ^testing.T) {
	request, roots, includes, excludes := test_request()
	_ = roots
	_ = includes
	_ = excludes
	testing.expect(t, request_is_valid(request))
	stale := request
	stale.roots[0].membership.project.generation += 1
	testing.expect(t, !request_is_valid(stale))
	duplicate := request
	duplicate.roots = []Root{request.roots[0], request.roots[0]}
	testing.expect(t, !request_is_valid(duplicate))
}

@(test)
/* Ensures search policy and work limits are explicit and bounded. */
policies_and_limits_are_explicit_and_bounded :: proc(t: ^testing.T) {
	request, roots, includes, excludes := test_request()
	_ = roots
	_ = includes
	_ = excludes
	testing.expect(t, policy_is_valid(request.policy, request.limits))
	request.policy.hidden = .Invalid
	testing.expect(t, !request_is_valid(request))
	request, roots, includes, excludes = test_request()
	request.limits.files = MAX_FILES + 1
	testing.expect(t, !request_is_valid(request))
	request, roots, includes, excludes = test_request()
	request.policy.include_patterns = []string{""}
	testing.expect(t, !request_is_valid(request))
}

@(test)
/* Ensures fingerprints and matches retain source-backed navigation authority. */
matches_retain_navigation_authority :: proc(t: ^testing.T) {
	request, roots, includes, excludes := test_request()
	_ = roots
	_ = includes
	_ = excludes
	fingerprint := Source_Fingerprint{present = true, device = 1, inode = 2, size = 20,
		modified_seconds = 3, modified_nanoseconds = 4}
	match := Match{id = 1, file = 2, root = request.roots[0].membership,
		path = "/project/main.odin", fingerprint = fingerprint, start = 4, end = 9}
	testing.expect(t, source_fingerprint_is_valid(fingerprint))
	testing.expect(t, match_is_valid(match, request))
	match.end = 21
	testing.expect(t, !match_is_valid(match, request))
}

@(test)
/* Ensures cancellation and lifecycle controls reject stale generations. */
cancellation_and_lifecycle_are_generation_scoped :: proc(t: ^testing.T) {
	cancellation := Cancellation{generation = 7}
	testing.expect(t, !cancellation_request(&cancellation, 6))
	testing.expect(t, cancellation_request(&cancellation, 7))
	testing.expect(t, cancellation_is_requested(&cancellation, 7))
	provider := Provider{id = 1, generation = 1, lifecycle = .Prepared}
	testing.expect(t, provider_transition(&provider, .Prepared, .Running))
	testing.expect(t, !provider_transition(&provider, .Prepared, .Complete))
	testing.expect(t, provider_transition(&provider, .Running, .Complete))
	testing.expect(t, provider_transition(&provider, .Complete, .Closed))
}

@(private)
test_request :: proc() -> (Request, [1]Root, [1]string, [1]string) {
	owner := project.Owner_Handle{id = 1, generation = 1}
	project_handle := project.Project_Handle{owner = owner, id = 2, generation = 3}
	membership := project.Membership_Handle{project = project_handle, id = 4, slot = 0, generation = 5}
	path: project.Directory_Path
	path.length = u32(copy(path.bytes[:], "/project"))
	roots := [1]Root{{membership = membership, path = path}}
	includes := [1]string{"*.odin"}
	excludes := [1]string{"vendor/*"}
	request := Request{
		id = 1,
		generation = 1,
		provider = 1,
		provider_generation = 1,
		project = project_handle,
		query_id = 1,
		pattern_kind = .Literal,
		pattern = "needle",
		policy = {
			search = search.DEFAULT_POLICY,
			hidden = .Exclude,
			ignored = .Respect,
			binary = .Exclude,
			include_patterns = includes[:],
			exclude_patterns = excludes[:],
		},
		search_limits = search.DEFAULT_LIMITS,
		limits = DEFAULT_LIMITS,
		roots = roots[:],
	}
	return request, roots, includes, excludes
}
