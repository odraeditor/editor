// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"
import "core:mem"
import "core:testing"

/* Verifies one atomic candidate confirms several provider-independent identities. */
@(test)
language_catalog_confirms_multiple_definitions :: proc(t: ^testing.T) {
	odin_suffixes := [?]string{".odin"}
	jan_suffixes := [?]string{".org", ".jan"}
	racket_exact := [?]string{"info.rkt"}
	racket_suffixes := [?]string{".rkt"}
	definitions := [?]Language_Definition_Candidate {
		{
			identity = "racket",
			display_name = "Racket",
			source = .Factory,
			source_generation = 1,
			exact_filenames = racket_exact[:],
			suffixes = racket_suffixes[:],
			provenance = "Odra factory",
		},
		{
			identity = "odin",
			display_name = "Odin",
			source = .Factory,
			source_generation = 1,
			suffixes = odin_suffixes[:],
			provenance = "Odra factory",
		},
		{
			identity = "jan",
			display_name = "Jan",
			source = .Factory,
			source_generation = 1,
			suffixes = jan_suffixes[:],
			provenance = "Odra factory",
		},
	}
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 71)
	testing.expect(t, initialized)
	if !initialized do return
	defer language_catalog_close(&catalog)

	inspection, confirmed, failure := language_catalog_confirm(
		&catalog,
		0,
		Language_Catalog_Candidate{generation = 1, definitions = definitions[:]},
	)
	testing.expect(t, confirmed)
	testing.expect_value(t, failure.code, Language_Catalog_Failure_Code.None)
	testing.expect_value(t, inspection.definition_count, u16(3))
	testing.expect_value(t, inspection.selector_count, u16(5))
	testing.expect_value(t, language_name_string(&inspection.definitions[0].language.name), "jan")
	testing.expect_value(t, language_name_string(&inspection.definitions[1].language.name), "odin")
	testing.expect_value(t, language_name_string(&inspection.definitions[2].language.name), "racket")

	association, resolved, resolve_failure := language_catalog_resolve(&catalog, "/work/info.rkt")
	testing.expect(t, resolved)
	testing.expect_value(t, resolve_failure.code, Language_Catalog_Failure_Code.None)
	testing.expect_value(t, language_name_string(&association.language.name), "racket")
	testing.expect_value(t, association.kind, Language_Selector_Kind.Exact_Filename)
}

/* Verifies a rejected candidate preserves the last confirmed immutable snapshot. */
@(test)
language_catalog_rejection_preserves_confirmed_generation :: proc(t: ^testing.T) {
	odin_suffixes := [?]string{".odin"}
	baseline := [?]Language_Definition_Candidate {{
		identity = "odin",
		display_name = "Odin",
		source = .Factory,
		source_generation = 1,
		suffixes = odin_suffixes[:],
		provenance = "Odra factory",
	}}
	duplicate := [?]Language_Definition_Candidate {baseline[0], baseline[0]}
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 72)
	testing.expect(t, initialized)
	if !initialized do return
	defer language_catalog_close(&catalog)

	_, confirmed, _ := language_catalog_confirm(
		&catalog,
		0,
		Language_Catalog_Candidate{generation = 1, definitions = baseline[:]},
	)
	stale_inspection, stale_accepted, stale_failure := language_catalog_confirm(
		&catalog,
		1,
		Language_Catalog_Candidate{generation = 1, definitions = baseline[:]},
	)
	inspection, rejected, failure := language_catalog_confirm(
		&catalog,
		1,
		Language_Catalog_Candidate{generation = 2, definitions = duplicate[:]},
	)
	testing.expect(t, confirmed && !stale_accepted && !rejected)
	testing.expect_value(t, stale_failure.code, Language_Catalog_Failure_Code.Stale_Generation)
	testing.expect_value(t, stale_inspection.catalog_generation, Language_Catalog_Generation(1))
	testing.expect_value(t, stale_inspection.definition_count, u16(1))
	testing.expect_value(t, failure.code, Language_Catalog_Failure_Code.Duplicate_Identity)
	testing.expect_value(t, inspection.catalog_generation, Language_Catalog_Generation(1))
	testing.expect_value(t, inspection.definition_count, u16(1))
	testing.expect_value(t, inspection.latest_rejection.code, failure.code)
}

/* Verifies exact, longest-suffix, source, and case rules match the reference model. */
@(test)
language_catalog_resolution_matches_reference_cases :: proc(t: ^testing.T) {
	generic_suffixes := [?]string{".gz"}
	tar_suffixes := [?]string{".tar.gz"}
	racket_suffixes := [?]string{".rkt"}
	special_exact := [?]string{"special.rkt"}
	personal_suffixes := [?]string{".scm"}
	factory_scheme_suffixes := [?]string{".scm"}
	definitions := [?]Language_Definition_Candidate {
		catalog_test_definition("generic", "Generic", .Factory, 1, nil, generic_suffixes[:]),
		catalog_test_definition("tar", "Tar", .Factory, 1, nil, tar_suffixes[:]),
		catalog_test_definition("racket", "Racket", .Factory, 1, nil, racket_suffixes[:]),
		catalog_test_definition("special", "Special", .Factory, 1, special_exact[:], nil),
		catalog_test_definition("scheme", "Scheme", .Personal, 4, nil, personal_suffixes[:]),
		catalog_test_definition("factory-scheme", "Factory Scheme", .Factory, 1, nil, factory_scheme_suffixes[:]),
	}
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 74)
	testing.expect(t, initialized)
	if !initialized do return
	defer language_catalog_close(&catalog)
	_, confirmed, _ := language_catalog_confirm(
		&catalog,
		0,
		Language_Catalog_Candidate{generation = 1, definitions = definitions[:]},
	)
	testing.expect(t, confirmed)
	if !confirmed do return

	longest, longest_ok, _ := language_catalog_resolve(&catalog, "/work/archive.tar.gz")
	exact, exact_ok, _ := language_catalog_resolve(&catalog, "/work/special.rkt")
	precedence, precedence_ok, _ := language_catalog_resolve(&catalog, "/work/main.scm")
	explicit, explicit_ok, _ := language_catalog_resolve(&catalog, "/work/archive.tar.gz", "racket")
	_, upper_ok, upper_failure := language_catalog_resolve(&catalog, "/work/main.RKT")
	_, upper_identity_ok, upper_identity_failure := language_catalog_resolve(
		&catalog,
		"/work/main.rkt",
		"Racket",
	)
	testing.expect(t, longest_ok && exact_ok && precedence_ok && explicit_ok && !upper_ok && !upper_identity_ok)
	testing.expect_value(t, language_name_string(&longest.language.name), "tar")
	testing.expect_value(t, longest.kind, Language_Selector_Kind.Filename_Suffix)
	testing.expect_value(t, language_name_string(&exact.language.name), "special")
	testing.expect_value(t, exact.kind, Language_Selector_Kind.Exact_Filename)
	testing.expect_value(t, language_name_string(&precedence.language.name), "scheme")
	testing.expect_value(t, precedence.source, Language_Contribution_Source.Personal)
	testing.expect_value(t, precedence.shadowed, u16(1))
	testing.expect_value(t, language_name_string(&explicit.language.name), "racket")
	testing.expect_value(t, explicit.kind, Language_Selector_Kind.Explicit)
	testing.expect_value(t, upper_failure.code, Language_Catalog_Failure_Code.No_Match)
	testing.expect_value(t, upper_identity_failure.code, Language_Catalog_Failure_Code.Unknown_Language)
}

/* Verifies duplicates and same-scope ambiguity reject without partial publication. */
@(test)
language_catalog_rejects_duplicate_and_ambiguous_selectors :: proc(t: ^testing.T) {
	duplicate_suffixes := [?]string{".rkt", ".rkt"}
	ambiguous_suffixes := [?]string{".rkt"}
	duplicate := [?]Language_Definition_Candidate {
		catalog_test_definition("racket", "Racket", .Factory, 1, nil, duplicate_suffixes[:]),
	}
	ambiguous := [?]Language_Definition_Candidate {
		catalog_test_definition("racket", "Racket", .Factory, 1, nil, ambiguous_suffixes[:]),
		catalog_test_definition("scheme", "Scheme", .Factory, 1, nil, ambiguous_suffixes[:]),
	}
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 75)
	testing.expect(t, initialized)
	if !initialized do return
	defer language_catalog_close(&catalog)

	_, duplicate_ok, duplicate_failure := language_catalog_confirm(
		&catalog,
		0,
		Language_Catalog_Candidate{generation = 1, definitions = duplicate[:]},
	)
	_, ambiguous_ok, ambiguous_failure := language_catalog_confirm(
		&catalog,
		0,
		Language_Catalog_Candidate{generation = 2, definitions = ambiguous[:]},
	)
	inspection, inspected, _ := language_catalog_inspect(&catalog)
	testing.expect(t, !duplicate_ok && !ambiguous_ok && inspected)
	testing.expect_value(t, duplicate_failure.code, Language_Catalog_Failure_Code.Duplicate_Selector)
	testing.expect_value(t, ambiguous_failure.code, Language_Catalog_Failure_Code.Ambiguous_Selector)
	testing.expect_value(t, inspection.catalog_generation, Language_Catalog_Generation(0))
	testing.expect_value(t, inspection.latest_rejection.code, ambiguous_failure.code)
}

/* Verifies canonical ordering gives new identities stable order-independent IDs. */
@(test)
language_catalog_identity_assignment_is_order_independent :: proc(t: ^testing.T) {
	odin_suffixes := [?]string{".odin"}
	racket_suffixes := [?]string{".rkt"}
	forward := [?]Language_Definition_Candidate {
		catalog_test_definition("racket", "Racket", .Factory, 1, nil, racket_suffixes[:]),
		catalog_test_definition("odin", "Odin", .Factory, 1, nil, odin_suffixes[:]),
	}
	reverse := [?]Language_Definition_Candidate {forward[1], forward[0]}
	left: Language_Catalog
	right: Language_Catalog
	left_ready, _ := language_catalog_init(&left, 76)
	right_ready, _ := language_catalog_init(&right, 77)
	testing.expect(t, left_ready && right_ready)
	if !left_ready || !right_ready do return
	defer language_catalog_close(&left)
	defer language_catalog_close(&right)
	left_inspection, left_ok, _ := language_catalog_confirm(
		&left, 0, Language_Catalog_Candidate{generation = 1, definitions = forward[:]})
	right_inspection, right_ok, _ := language_catalog_confirm(
		&right, 0, Language_Catalog_Candidate{generation = 1, definitions = reverse[:]})
	testing.expect(t, left_ok && right_ok)
	if !left_ok || !right_ok do return
	for index in 0 ..< int(left_inspection.definition_count) {
		testing.expect_value(
			t,
			left_inspection.definitions[index].language,
			right_inspection.definitions[index].language,
		)
	}
}

/* Verifies allocation faults and normal teardown preserve exact native accounting. */
@(test)
language_catalog_allocation_and_cleanup_are_exact :: proc(t: ^testing.T) {
	failing := Catalog_Test_Failing_Allocator{backing = context.allocator, fail_after = 1}
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 78, catalog_test_failing_allocator(&failing))
	testing.expect(t, initialized)
	if initialized {
		_, confirmed, failure := language_catalog_confirm(
			&catalog,
			0,
			Language_Catalog_Candidate{generation = 1},
		)
		inspection, inspected, _ := language_catalog_inspect(&catalog)
		testing.expect(t, !confirmed && inspected)
		testing.expect_value(t, failure.code, Language_Catalog_Failure_Code.Allocation)
		testing.expect_value(t, inspection.catalog_generation, Language_Catalog_Generation(0))
		_, _ = language_catalog_close(&catalog)
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	tracked_allocator := mem.tracking_allocator(&tracking)
	tracked: Language_Catalog
	tracked_ready, _ := language_catalog_init(&tracked, 79, tracked_allocator)
	closed := false
	if tracked_ready do closed, _ = language_catalog_close(&tracked)
	retained := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, tracked_ready && closed)
	testing.expect_value(t, retained, i64(0))
}

@(private = "file")
catalog_test_definition :: proc(
	identity, display_name: string,
	source: Language_Contribution_Source,
	source_generation: Language_Source_Generation,
	exact_filenames, suffixes: []string,
) -> Language_Definition_Candidate {
	return Language_Definition_Candidate {
		identity = identity,
		display_name = display_name,
		source = source,
		source_generation = source_generation,
		exact_filenames = exact_filenames,
		suffixes = suffixes,
		provenance = "catalog test fixture",
	}
}

@(private = "file")
Catalog_Test_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
catalog_test_failing_allocator :: proc(data: ^Catalog_Test_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = catalog_test_failing_allocator_proc, data = data}
}

@(private = "file")
catalog_test_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Catalog_Test_Failing_Allocator)allocator_data
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
