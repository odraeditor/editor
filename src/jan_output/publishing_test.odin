// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:testing"

/* Verifies bounded project admission and deterministic root-scoped discovery. */
@(test)
publishing_projects_discover_only_admitted_sources :: proc(t: ^testing.T) {
	components := [1]string{"shared-site"}
	roots := [2]Publishing_Source_Root {
		{resource_id = 11, resource_revision = 3, recursive = true, include_prefix = "docs/", exclude_prefix = "docs/drafts/", suffix = ".org"},
		{resource_id = 13, resource_revision = 5, recursive = true, include_prefix = "assets/", suffix = ".css"},
	}
	project := publication_test_project(components[:], roots[:])
	testing.expect(t, publishing_project_is_valid(project))
	candidates := [4]Publication_Source_Candidate {
		publication_test_candidate(0, 101, 201, "docs/z.org", false),
		publication_test_candidate(0, 103, 203, "docs/a.org", false),
		publication_test_candidate(0, 105, 205, "docs/drafts/hidden.org", false),
		publication_test_candidate(1, 107, 207, "assets/site.css", true),
	}
	selected: [4]u16
	count, ok, _ := discover_publication_sources(project, candidates[:], selected[:])
	testing.expect(t, ok)
	testing.expect_value(t, count, u16(3))
	testing.expect_value(t, candidates[selected[0]].relative_path, "assets/site.css")
	testing.expect_value(t, candidates[selected[1]].relative_path, "docs/a.org")
	testing.expect_value(t, candidates[selected[2]].relative_path, "docs/z.org")

	candidates[0].relative_path = "../escape.org"
	_, invalid_ok, failure := discover_publication_sources(project, candidates[:], selected[:])
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
	candidates[0].relative_path = "docs/z.org"
	roots[0].recursive = false
	candidates[0].depth = 2
	_, recursive_ok, recursive_failure := discover_publication_sources(project, candidates[:], selected[:])
	testing.expect(t, !recursive_ok)
	testing.expect_value(t, recursive_failure.code, Failure_Code.Malformed)
}

/* Verifies component projects are complete, acyclic, and dependency ordered. */
@(test)
publishing_project_composition_is_deterministic :: proc(t: ^testing.T) {
	roots := [1]Publishing_Source_Root {{resource_id = 11, resource_revision = 3, recursive = true, suffix = ".org"}}
	no_components := []string{}
	site_components := [2]string{"core", "theme"}
	core := publication_test_project(no_components, roots[:])
	core.identity = "core"
	theme := publication_test_project(no_components, roots[:])
	theme.identity = "theme"
	site := publication_test_project(site_components[:], roots[:])
	projects := [3]Publishing_Project_Definition {site, theme, core}
	ordered: [3]u16
	resolved: [3]bool
	count, ok, _ := order_publishing_projects(projects[:], ordered[:], resolved[:])
	testing.expect(t, ok)
	testing.expect_value(t, count, u16(3))
	testing.expect_value(t, projects[ordered[0]].identity, "core")
	testing.expect_value(t, projects[ordered[1]].identity, "theme")
	testing.expect_value(t, projects[ordered[2]].identity, "site")

	missing_components := [1]string{"missing"}
	projects[0].component_identities = missing_components[:]
	_, missing_ok, failure := order_publishing_projects(projects[:], ordered[:], resolved[:])
	testing.expect(t, !missing_ok)
	testing.expect_value(t, failure.code, Failure_Code.Missing)

	core_components := [1]string{"site"}
	projects[0].component_identities = site_components[:]
	projects[2].component_identities = core_components[:]
	_, cycle_ok, cycle_failure := order_publishing_projects(projects[:], ordered[:], resolved[:])
	testing.expect(t, !cycle_ok)
	testing.expect_value(t, cycle_failure.code, Failure_Code.Cycle)
}

/* Verifies complete manifests account for generated, static, reused, link, and stale outputs. */
@(test)
publication_manifests_are_complete_before_writes :: proc(t: ^testing.T) {
	components := [1]string{"shared-site"}
	roots := [2]Publishing_Source_Root {
		{resource_id = 11, resource_revision = 3, recursive = true, include_prefix = "docs/", suffix = ".org"},
		{resource_id = 13, resource_revision = 5, recursive = true, include_prefix = "assets/", suffix = ".css"},
	}
	project := publication_test_project(components[:], roots[:])
	candidates := [3]Publication_Source_Candidate {
		publication_test_candidate(0, 101, 201, "docs/z.org", false),
		publication_test_candidate(0, 103, 203, "docs/a.org", false),
		publication_test_candidate(1, 107, 207, "assets/site.css", true),
	}
	selected: [3]u16
	count, discovered, _ := discover_publication_sources(project, candidates[:], selected[:])
	testing.expect(t, discovered)
	cached := [1]Cached_Publication_Output {publication_test_cached(candidates[selected[1]])}
	links := [1]Publication_Link_Record {{source_resource_id = 103, target_resource_id = 101,
		rewritten_target_resource_id = 201, valid = true}}
	existing := [3]Existing_Publication_Output {
		{resource_id = 201, project_identity = "site", project_generation = project.generation, generated_by_project = true},
		{resource_id = 301, project_identity = "site", project_generation = project.generation, generated_by_project = true},
		{resource_id = 303, project_identity = "other-site", project_generation = 1, generated_by_project = true},
	}
	entries: [5]Publication_Manifest_Entry
	stale: [3]Stale_Output_Decision
	request := Publication_Manifest_Request {operation_id = 81, manifest_id = 83,
		project_generation = project.generation, backend_generation = 17, filter_generation = 19,
		limits = DEFAULT_LIMITS, explicit = true}
	request.synthetic_digest[0] = 1
	manifest, ok, _ := prepare_publication_manifest(request, project, candidates[:], selected[:count], links[:],
		cached[:], existing[:], entries[:], stale[:])
	testing.expect(t, ok)
	testing.expect(t, manifest.complete)
	testing.expect_value(t, manifest.record.entry_count, u32(5))
	testing.expect_value(t, manifest.record.state, Manifest_State.Candidate)
	testing.expect_value(t, manifest.generated_count, u32(4))
	testing.expect_value(t, manifest.static_count, u32(1))
	testing.expect_value(t, manifest.reused_count, u32(1))
	testing.expect_value(t, manifest.stale_count, u32(2))
	testing.expect_value(t, manifest.delete_count, u32(1))
	testing.expect_value(t, stale[0].action, Stale_Output_Action.Delete)
	testing.expect_value(t, stale[1].action, Stale_Output_Action.Preserve)
	testing.expect_value(t, entries[1].source_digest, candidates[selected[1]].source_digest)
	testing.expect_value(t, entries[3].source_digest, request.synthetic_digest)

	changed := cached[0]
	changed.tool_digest[0] += 1
	testing.expect(t, !publication_output_matches(candidates[selected[1]], changed))
	links[0].valid = false
	_, invalid_ok, failure := prepare_publication_manifest(request, project, candidates[:], selected[:count], links[:],
		cached[:], existing[:], entries[:], stale[:])
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, failure.code, Failure_Code.Validation)
}

/* Verifies local success cannot become remote publication without remote confirmation. */
@(test)
publication_runs_separate_local_and_remote_outcomes :: proc(t: ^testing.T) {
	initial_local := Publication_Run {manifest_id = 91, entry_count = 3, maximum_attempts = 1, state = .Prepared}
	local, ok, _ := publication_run_advance(initial_local, .Start_Local)
	testing.expect(t, ok)
	local, ok, _ = publication_run_advance(local, .Local_Succeeded, 3)
	testing.expect(t, ok)
	testing.expect_value(t, local.state, Publication_Run_State.Local_Complete)
	_, published_without_remote, _ := publication_run_advance(local, .Remote_Succeeded, 3)
	testing.expect(t, !published_without_remote)
	local, ok, _ = publication_run_advance(local, .Close)
	testing.expect(t, ok)
	testing.expect_value(t, local.state, Publication_Run_State.Closed)

	remote := Publication_Run {manifest_id = 93, entry_count = 3, maximum_attempts = 3, remote_required = true, state = .Prepared}
	remote, ok, _ = publication_run_advance(remote, .Start_Local)
	remote, ok, _ = publication_run_advance(remote, .Local_Succeeded, 3)
	testing.expect_value(t, remote.state, Publication_Run_State.Local_Complete)
	remote, ok, _ = publication_run_advance(remote, .Start_Remote)
	remote, ok, _ = publication_run_advance(remote, .Remote_Progress, 2)
	remote, ok, _ = publication_run_advance(remote, .Remote_Failed, 1)
	testing.expect(t, ok)
	testing.expect_value(t, remote.state, Publication_Run_State.Remote_Partial)
	remote, ok, _ = publication_run_advance(remote, .Retry)
	testing.expect_value(t, remote.attempt, u16(2))
	remote, ok, _ = publication_run_advance(remote, .Remote_Succeeded, 3)
	testing.expect(t, ok)
	testing.expect_value(t, remote.state, Publication_Run_State.Published)
}

/* Verifies partial delivery can choose reconciliation instead of blind retry. */
@(test)
publication_partial_outcomes_have_reconciliation_boundary :: proc(t: ^testing.T) {
	run := Publication_Run {manifest_id = 95, entry_count = 4, local_completed = 4,
		remote_uploaded = 2, remote_failed = 2, maximum_attempts = 3,
		remote_required = true, state = .Remote_Partial, attempt = 1}
	next, ok, _ := publication_run_advance(run, .Reconcile)
	testing.expect(t, ok)
	testing.expect_value(t, next.state, Publication_Run_State.Reconciliation_Required)
	closed, closed_ok, _ := publication_run_advance(next, .Close)
	testing.expect(t, closed_ok)
	testing.expect_value(t, closed.state, Publication_Run_State.Closed)
	exhausted := run
	exhausted.state = .Retry_Ready
	exhausted.attempt = exhausted.maximum_attempts
	_, retry_ok, retry_failure := publication_run_advance(exhausted, .Retry)
	testing.expect(t, !retry_ok)
	testing.expect_value(t, retry_failure.code, Failure_Code.Conflict)
}

/* Verifies temporary cleanup and retention never remove protected or current outputs. */
@(test)
publication_cleanup_and_retention_are_exact :: proc(t: ^testing.T) {
	temporaries := []Temporary_Resource {
		{resource_id = 1, kind = .Directory, created = true, cleaned = true},
		{resource_id = 2, kind = .Log, created = true, cleaned = true},
	}
	retention := []Publication_Retention_Record {
		{resource_id = 3, generation = 7, expired = true, removed = true},
		{resource_id = 4, generation = 9, expired = true, protected = true},
		{resource_id = 5, generation = 11},
	}
	testing.expect(t, publication_cleanup_complete(temporaries, retention))
	retention[1].removed = true
	testing.expect(t, !publication_cleanup_complete(temporaries, retention))
	retention[1].removed = false
	temporaries[1].cleaned = false
	testing.expect(t, !publication_cleanup_complete(temporaries, retention))
}

@(private = "file")
publication_test_project :: proc(components: []string, roots: []Publishing_Source_Root) -> Publishing_Project_Definition {
	project := Publishing_Project_Definition {identity = "site", generation = 7,
		component_identities = components, source_roots = roots, destination_resource_id = 17,
		destination_revision = 19, action = .Build_And_Upload, backend = "html", copy_static = true,
		link_policy = .Rewrite_And_Validate, generate_sitemap = true, sitemap_resource_id = 401,
		generate_index = true, index_resource_id = 403, use_cache = true, use_timestamps = true,
		remote_provider_identity = "test-upload", remote_provider_generation = 23,
		maximum_concurrency = 4, failure_policy = .Stop, cleanup_required = true,
		retention_generations = 3}
	project.shared_options_digest[0] = 1
	project.backend_options_digest[0] = 2
	return project
}

@(private = "file")
publication_test_candidate :: proc(root_index: u16, resource_id, output_resource_id: u64, path: string, static: bool) -> Publication_Source_Candidate {
	candidate := Publication_Source_Candidate {root_index = root_index, resource_id = resource_id,
		depth = 1,
		resource_revision = resource_id + 1, relative_path = path, output_resource_id = output_resource_id,
		output_revision = output_resource_id + 1, byte_count = 512, static = static, link_count = 1}
	candidate.source_digest[0] = 1
	candidate.dependency_digest[0] = 2
	candidate.backend_digest[0] = 3
	candidate.filter_digest[0] = 4
	candidate.setting_digest[0] = 5
	candidate.tool_digest[0] = 6
	return candidate
}

@(private = "file")
publication_test_cached :: proc(candidate: Publication_Source_Candidate) -> Cached_Publication_Output {
	return {output_resource_id = candidate.output_resource_id, source_digest = candidate.source_digest,
		dependency_digest = candidate.dependency_digest, backend_digest = candidate.backend_digest,
		filter_digest = candidate.filter_digest, setting_digest = candidate.setting_digest,
		tool_digest = candidate.tool_digest, complete = true}
}
