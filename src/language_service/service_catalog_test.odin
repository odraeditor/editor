// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import language "../language"
import "base:runtime"
import "core:mem"
import "core:testing"

@(private)
SERVICE_CATALOG_TEST_REGISTRY :: Registry_Handle{id = 101, generation = 103}

@(private)
service_catalog_test_language :: proc(id: language.Language_ID) -> language.Language_Identity {
	return {
		id = id,
		generation = 1,
		name = {length = 4},
	}
}

@(private)
service_catalog_test_definition :: proc(
	id: Definition_ID,
	identity: string,
	languages: []language.Language_Identity,
	source: Service_Contribution_Source,
	scope := "",
	default_selection := false,
	enabled := true,
) -> Service_Catalog_Definition_Candidate {
	scope_kind := Service_Scope_Kind.Global
	if source == .Package do scope_kind = .Package
	if source == .Project do scope_kind = .Project_Membership
	return {
		definition = {
			registry = SERVICE_CATALOG_TEST_REGISTRY,
			id = id,
			generation = 1,
		},
		identity = identity,
		languages = languages,
		source = source,
		scope_kind = scope_kind,
		scope = scope,
		source_generation = 1,
		policy = {enabled = enabled, default_selection = default_selection},
		provenance = "service catalog test",
	}
}

@(private)
service_catalog_test_query :: proc(
	language_identity: language.Language_Identity,
	membership := "project-a",
) -> Service_Resolution_Query {
	return {
		language = language_identity,
		project_membership = membership,
		resolved_root = "/work/project-a",
		project_trusted = true,
	}
}

/* Verifies explicit Project and personal selections outrank default policy. */
@(test)
service_catalog_resolves_explicit_selections_by_authority :: proc(t: ^testing.T) {
	odin := service_catalog_test_language(1)
	languages := [?]language.Language_Identity{odin}
	definitions := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(1, "ols", languages[:], .Factory, "", true),
		service_catalog_test_definition(2, "odin-lsp", languages[:], .Package, "package-a"),
		service_catalog_test_definition(3, "project-lsp", languages[:], .Project, "project-a"),
	}
	selections := [?]Service_Explicit_Selection_Candidate {
		{
			language = odin,
			service_identity = "odin-lsp",
			source = .Personal,
			scope_kind = .Global,
			source_generation = 1,
		},
		{
			language = odin,
			service_identity = "project-lsp",
			source = .Project,
			scope_kind = .Project_Membership,
			scope = "project-a",
			source_generation = 1,
		},
	}
	catalog: Service_Catalog
	initialized, _ := service_catalog_init(&catalog, 107, SERVICE_CATALOG_TEST_REGISTRY)
	testing.expect(t, initialized)
	if !initialized do return
	defer service_catalog_close(&catalog)

	confirmed, failure := service_catalog_confirm(
		&catalog,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = definitions[:], selections = selections[:]},
	)
	testing.expectf(t, confirmed, "catalog confirmation failed: %v", failure.code)
	trace, resolved, resolve_failure := service_catalog_resolve(&catalog, service_catalog_test_query(odin))
	testing.expectf(t, resolved, "catalog resolution failed: %v", resolve_failure.code)
	testing.expect_value(t, trace.kind, Service_Selection_Kind.Explicit_Project)
	testing.expect_value(t, trace.selected.id, Definition_ID(3))

	other_trace, other_resolved, _ := service_catalog_resolve(
		&catalog,
		service_catalog_test_query(odin, "project-b"),
	)
	testing.expect(t, other_resolved)
	testing.expect_value(t, other_trace.kind, Service_Selection_Kind.Explicit_Personal)
	testing.expect_value(t, other_trace.selected.id, Definition_ID(2))
}

/* Verifies package identity conflicts are symmetric and retain factory fallback. */
@(test)
service_catalog_preserves_fallback_across_package_conflicts :: proc(t: ^testing.T) {
	odin := service_catalog_test_language(1)
	languages := [?]language.Language_Identity{odin}
	definitions := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(11, "ols", languages[:], .Factory, "", true),
		service_catalog_test_definition(13, "ols", languages[:], .Package, "package-a", true),
		service_catalog_test_definition(17, "ols", languages[:], .Package, "package-b", true),
	}
	catalog: Service_Catalog
	initialized, _ := service_catalog_init(&catalog, 109, SERVICE_CATALOG_TEST_REGISTRY)
	testing.expect(t, initialized)
	if !initialized do return
	defer service_catalog_close(&catalog)

	inspection: Service_Catalog_Inspection
	confirmed, failure := service_catalog_confirm(
		&catalog,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = definitions[:]},
		&inspection,
	)
	testing.expectf(t, confirmed, "catalog confirmation failed: %v", failure.code)
	testing.expect_value(t, inspection.conflict_count, u16(1))
	testing.expect_value(t, inspection.participant_count, u16(2))
	testing.expect_value(t, inspection.conflicts[0].fallback.id, Definition_ID(11))
	trace, resolved, _ := service_catalog_resolve(&catalog, service_catalog_test_query(odin))
	testing.expect(t, resolved)
	testing.expect_value(t, trace.selected.id, Definition_ID(11))
	testing.expect_value(t, trace.conflicted, u16(2))
}

/* Verifies complete replacement and factory restoration stay query-scoped. */
@(test)
service_catalog_restores_factory_for_one_language_scope :: proc(t: ^testing.T) {
	odin := service_catalog_test_language(1)
	racket := service_catalog_test_language(2)
	odin_languages := [?]language.Language_Identity{odin}
	racket_languages := [?]language.Language_Identity{racket}
	definitions := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(21, "ols", odin_languages[:], .Factory, "", true),
		service_catalog_test_definition(23, "ols", odin_languages[:], .Personal),
		service_catalog_test_definition(29, "racket-lsp", racket_languages[:], .Factory, "", true),
	}
	catalog: Service_Catalog
	initialized, _ := service_catalog_init(&catalog, 113, SERVICE_CATALOG_TEST_REGISTRY)
	testing.expect(t, initialized)
	if !initialized do return
	defer service_catalog_close(&catalog)
	confirmed, _ := service_catalog_confirm(
		&catalog,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = definitions[:]},
	)
	testing.expect(t, confirmed)

	normal, resolved, _ := service_catalog_resolve(&catalog, service_catalog_test_query(odin))
	testing.expect(t, resolved)
	testing.expect_value(t, normal.selected.id, Definition_ID(23))
	restored, restored_ok, _ := service_catalog_restore_factory(&catalog, service_catalog_test_query(odin))
	testing.expect(t, restored_ok)
	testing.expect_value(t, restored.kind, Service_Selection_Kind.Factory_Restoration)
	testing.expect_value(t, restored.selected.id, Definition_ID(21))
	racket_trace, racket_resolved, _ := service_catalog_resolve(&catalog, service_catalog_test_query(racket))
	testing.expect(t, racket_resolved)
	testing.expect_value(t, racket_trace.selected.id, Definition_ID(29))
}

/* Verifies a rejected duplicate generation preserves the confirmed snapshot. */
@(test)
service_catalog_rejects_duplicate_identity_atomically :: proc(t: ^testing.T) {
	odin := service_catalog_test_language(1)
	languages := [?]language.Language_Identity{odin}
	baseline := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(31, "ols", languages[:], .Factory, "", true),
	}
	duplicate := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(37, "ols", languages[:], .Personal),
		service_catalog_test_definition(41, "ols", languages[:], .Personal),
	}
	catalog: Service_Catalog
	initialized, _ := service_catalog_init(&catalog, 127, SERVICE_CATALOG_TEST_REGISTRY)
	testing.expect(t, initialized)
	if !initialized do return
	defer service_catalog_close(&catalog)
	confirmed, _ := service_catalog_confirm(
		&catalog,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = baseline[:]},
	)
	testing.expect(t, confirmed)
	inspection: Service_Catalog_Inspection
	accepted, failure := service_catalog_confirm(
		&catalog,
		1,
		{generation = 2, language_catalog_generation = 1, definitions = duplicate[:]},
		&inspection,
	)
	testing.expect(t, !accepted)
	testing.expect_value(t, failure.code, Service_Catalog_Failure_Code.Duplicate_Identity)
	testing.expect_value(t, inspection.catalog_generation, Service_Catalog_Generation(1))
}

/* Verifies canonical records and selection do not depend on candidate order. */
@(test)
service_catalog_resolution_is_order_independent :: proc(t: ^testing.T) {
	odin := service_catalog_test_language(1)
	languages := [?]language.Language_Identity{odin}
	forward := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(43, "ols", languages[:], .Factory, "", true),
		service_catalog_test_definition(47, "odin-lsp", languages[:], .Package, "package-a"),
		service_catalog_test_definition(53, "personal-lsp", languages[:], .Personal, "", true),
	}
	reverse := [?]Service_Catalog_Definition_Candidate{forward[2], forward[1], forward[0]}
	left: Service_Catalog
	right: Service_Catalog
	left_ready, _ := service_catalog_init(&left, 131, SERVICE_CATALOG_TEST_REGISTRY)
	right_ready, _ := service_catalog_init(&right, 137, SERVICE_CATALOG_TEST_REGISTRY)
	testing.expect(t, left_ready && right_ready)
	if !left_ready || !right_ready do return
	defer service_catalog_close(&left)
	defer service_catalog_close(&right)
	left_inspection: Service_Catalog_Inspection
	left_confirmed, _ := service_catalog_confirm(
		&left,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = forward[:]},
		&left_inspection,
	)
	right_inspection: Service_Catalog_Inspection
	right_confirmed, _ := service_catalog_confirm(
		&right,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = reverse[:]},
		&right_inspection,
	)
	testing.expect(t, left_confirmed && right_confirmed)
	testing.expect_value(t, left_inspection.definition_count, right_inspection.definition_count)
	for index in 0 ..< int(left_inspection.definition_count) {
		testing.expect_value(
			t,
			left_inspection.definitions[index].definition,
			right_inspection.definitions[index].definition,
		)
	}
	left_trace, left_resolved, _ := service_catalog_resolve(&left, service_catalog_test_query(odin))
	right_trace, right_resolved, _ := service_catalog_resolve(&right, service_catalog_test_query(odin))
	testing.expect(t, left_resolved && right_resolved)
	testing.expect_value(t, left_trace.selected, right_trace.selected)
	testing.expect_value(t, left_trace.selected.id, Definition_ID(53))
}

/* Verifies stale, ambiguous, and invalid explicit generations preserve state. */
@(test)
service_catalog_rejected_generations_preserve_confirmed_state :: proc(t: ^testing.T) {
	odin := service_catalog_test_language(1)
	languages := [?]language.Language_Identity{odin}
	baseline := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(59, "ols", languages[:], .Factory, "", true),
	}
	ambiguous := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(61, "alpha-lsp", languages[:], .Personal, "", true),
		service_catalog_test_definition(67, "beta-lsp", languages[:], .Personal, "", true),
	}
	invalid_selection := [?]Service_Explicit_Selection_Candidate {{
		language = odin,
		service_identity = "missing-lsp",
		source = .Personal,
		scope_kind = .Global,
		source_generation = 2,
	}}
	catalog: Service_Catalog
	initialized, _ := service_catalog_init(&catalog, 139, SERVICE_CATALOG_TEST_REGISTRY)
	testing.expect(t, initialized)
	if !initialized do return
	defer service_catalog_close(&catalog)
	confirmed, _ := service_catalog_confirm(
		&catalog,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = baseline[:]},
	)
	testing.expect(t, confirmed)
	ambiguous_inspection: Service_Catalog_Inspection
	ambiguous_accepted, ambiguous_failure := service_catalog_confirm(
		&catalog,
		1,
		{generation = 2, language_catalog_generation = 1, definitions = ambiguous[:]},
		&ambiguous_inspection,
	)
	testing.expect(t, !ambiguous_accepted)
	testing.expect_value(t, ambiguous_failure.code, Service_Catalog_Failure_Code.Ambiguous_Default)
	testing.expect_value(t, ambiguous_inspection.catalog_generation, Service_Catalog_Generation(1))
	invalid_inspection: Service_Catalog_Inspection
	invalid_accepted, invalid_failure := service_catalog_confirm(
		&catalog,
		1,
		{
			generation = 2,
			language_catalog_generation = 1,
			definitions = baseline[:],
			selections = invalid_selection[:],
		},
		&invalid_inspection,
	)
	testing.expect(t, !invalid_accepted)
	testing.expect_value(t, invalid_failure.code, Service_Catalog_Failure_Code.Invalid_Explicit_Selection)
	testing.expect_value(t, invalid_inspection.catalog_generation, Service_Catalog_Generation(1))
	stale_inspection: Service_Catalog_Inspection
	stale_accepted, stale_failure := service_catalog_confirm(
		&catalog,
		1,
		{generation = 1, language_catalog_generation = 1, definitions = baseline[:]},
		&stale_inspection,
	)
	testing.expect(t, !stale_accepted)
	testing.expect_value(t, stale_failure.code, Service_Catalog_Failure_Code.Stale_Generation)
	testing.expect_value(t, stale_inspection.catalog_generation, Service_Catalog_Generation(1))
}

/* Verifies disabled Project replacement and restoration affect one exact scope. */
@(test)
service_catalog_disable_and_restore_are_scope_local :: proc(t: ^testing.T) {
	odin := service_catalog_test_language(1)
	racket := service_catalog_test_language(2)
	odin_languages := [?]language.Language_Identity{odin}
	racket_languages := [?]language.Language_Identity{racket}
	definitions := [?]Service_Catalog_Definition_Candidate {
		service_catalog_test_definition(71, "ols", odin_languages[:], .Factory, "", true),
		service_catalog_test_definition(73, "ols", odin_languages[:], .Personal, "", true),
		service_catalog_test_definition(79, "ols", odin_languages[:], .Project, "project-a", false, false),
		service_catalog_test_definition(83, "racket-lsp", racket_languages[:], .Factory, "", true),
	}
	catalog: Service_Catalog
	initialized, _ := service_catalog_init(&catalog, 149, SERVICE_CATALOG_TEST_REGISTRY)
	testing.expect(t, initialized)
	if !initialized do return
	defer service_catalog_close(&catalog)
	confirmed, failure := service_catalog_confirm(
		&catalog,
		0,
		{generation = 1, language_catalog_generation = 1, definitions = definitions[:]},
	)
	testing.expectf(t, confirmed, "catalog confirmation failed: %v", failure.code)
	project_a, project_a_resolved, _ := service_catalog_resolve(
		&catalog,
		service_catalog_test_query(odin, "project-a"),
	)
	testing.expect(t, !project_a_resolved)
	testing.expect_value(t, project_a.state, Service_Resolution_State.Absent)
	project_b, project_b_resolved, _ := service_catalog_resolve(
		&catalog,
		service_catalog_test_query(odin, "project-b"),
	)
	testing.expect(t, project_b_resolved)
	testing.expect_value(t, project_b.selected.id, Definition_ID(73))
	restored, restored_ok, _ := service_catalog_restore_factory(
		&catalog,
		service_catalog_test_query(odin, "project-a"),
	)
	testing.expect(t, restored_ok)
	testing.expect_value(t, restored.selected.id, Definition_ID(71))
	racket_trace, racket_ok, _ := service_catalog_resolve(
		&catalog,
		service_catalog_test_query(racket, "project-a"),
	)
	testing.expect(t, racket_ok)
	testing.expect_value(t, racket_trace.selected.id, Definition_ID(83))
}

/* Verifies allocation failure and ordinary close retain no catalog storage. */
@(test)
service_catalog_allocation_and_cleanup_are_exact :: proc(t: ^testing.T) {
	failing := Service_Catalog_Test_Failing_Allocator {
		backing = context.allocator,
		fail_after = 1,
	}
	catalog: Service_Catalog
	initialized, _ := service_catalog_init(
		&catalog,
		151,
		SERVICE_CATALOG_TEST_REGISTRY,
		service_catalog_test_failing_allocator(&failing),
	)
	testing.expect(t, initialized)
	if initialized {
		confirmed, failure := service_catalog_confirm(
			&catalog,
			0,
			{generation = 1, language_catalog_generation = 1},
		)
		inspection: Service_Catalog_Inspection
		inspected, _ := service_catalog_inspect(&catalog, &inspection)
		testing.expect(t, !confirmed && inspected)
		testing.expect_value(t, failure.code, Service_Catalog_Failure_Code.Allocation)
		testing.expect_value(t, inspection.catalog_generation, Service_Catalog_Generation(0))
		_, _ = service_catalog_close(&catalog)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	tracked_allocator := mem.tracking_allocator(&tracking)
	tracked: Service_Catalog
	tracked_ready, _ := service_catalog_init(
		&tracked,
		157,
		SERVICE_CATALOG_TEST_REGISTRY,
		tracked_allocator,
	)
	closed := false
	if tracked_ready {
		confirmed, _ := service_catalog_confirm(
			&tracked,
			0,
			{generation = 1, language_catalog_generation = 1},
		)
		testing.expect(t, confirmed)
		closed, _ = service_catalog_close(&tracked)
	}
	retained := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, tracked_ready && closed)
	testing.expect_value(t, retained, i64(0))
}

@(private = "file")
Service_Catalog_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
service_catalog_test_failing_allocator :: proc(
	data: ^Service_Catalog_Test_Failing_Allocator,
) -> runtime.Allocator {
	return runtime.Allocator{procedure = service_catalog_test_failing_allocator_proc, data = data}
}

@(private = "file")
service_catalog_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Service_Catalog_Test_Failing_Allocator)allocator_data
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
