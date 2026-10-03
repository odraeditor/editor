// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:mem"
import "core:testing"

/* Verifies native and Racket commands retain canonical annotations and actions. */
@(test)
adapt_and_project_complete_catalog :: proc(t: ^testing.T) {
	registry, snapshot, catalog, ready := command_candidates_test_catalog(t)
	if !ready {
		return
	}
	defer {
		command_catalog_close(&catalog)
		snapshot_close(&snapshot)
		command_registry_close(&registry)
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	source, adapted, adaptation_failure := command_candidate_source_build(&catalog, allocator)
	testing.expectf(t, adapted, "command candidate adaptation failed with %v", adaptation_failure.code)
	if !adapted {
		return
	}
	testing.expect_value(t, source.definition.kind, Candidate_Source_Kind.Commands)
	testing.expect_value(t, source.definition.scope_identity, u64(11))
	testing.expect_value(t, source.definition.source_generation, u64(17))
	testing.expect_value(t, len(source.descriptors), 3)
	if len(source.descriptors) == 3 {
		native := source.descriptors[0]
		racket := source.descriptors[1]
		region := source.descriptors[2]
		testing.expect_value(t, native.label, "native-command")
		testing.expect_value(t, native.annotations[0].kind, Candidate_Annotation_Kind.Binding)
		testing.expect_value(t, native.annotations[0].text, "n")
		testing.expect_value(t, native.annotations[1].text, "odra-native")
		testing.expect_value(t, native.annotations[2].text, "available")
		testing.expect_value(t, native.annotations[3].text, "Native action.")
		testing.expect_value(t, native.durable_category, Candidate_Durable_Category.Command)
		testing.expect_value(t, native.durable_key, "native-command")
		native_handle, native_ok := command_candidate_action_handle(native.action)
		testing.expect(t, native_ok)
		testing.expect_value(t, native_handle, catalog.entries[0].metadata.handle)
		testing.expect_value(t, racket.label, "racket-command")
		testing.expect_value(t, racket.annotations[0].text, "")
		testing.expect_value(t, racket.annotations[1].text, "odra-racket")
		testing.expect_value(t, region.availability, Candidate_Availability.Unavailable)
		testing.expect_value(
			t,
			region.annotations[2].text,
			"unavailable: Requires an active region.",
		)
	}

	session: Candidate_Session
	_, initialized, initialization_failure := candidate_session_init(
		&session,
		Candidate_Config {
			session_id = 701,
			limits = DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = allocator,
		},
		source.definition,
		"Racket action",
	)
	testing.expectf(t, initialized, "command candidate session failed with %v", initialization_failure.code)
	command_candidate_source_close(&source)
	if !initialized {
		return
	}
	defer candidate_session_close(&session)
	view, viewed, view_failure := candidate_session_view(&session)
	testing.expectf(t, viewed, "command candidate view failed with %v", view_failure.code)
	testing.expect_value(t, len(view.rows), 1)
	if len(view.rows) == 1 {
		testing.expect_value(t, view.rows[0].label, "racket-command")
	}

	label_storage: [MAX_CANDIDATE_PROMPT_LABEL_BYTES]u8
	label, label_ok := candidate_prompt_label(view, label_storage[:])
	testing.expect(t, label_ok)
	testing.expect_value(t, label, "Commands [active editor context] 1/1 M-x ")

	candidate_session_close(&session)
	session = {}
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

/* Verifies adapter and projection allocation failures publish no partial owned storage. */
@(test)
command_candidates_release_failed_temporary_work :: proc(t: ^testing.T) {
	registry, snapshot, catalog, ready := command_candidates_test_catalog(t)
	if !ready {
		return
	}
	defer {
		command_catalog_close(&catalog)
		snapshot_close(&snapshot)
		command_registry_close(&registry)
	}
	failures, successes: u32
	for fail_after in 0 ..< 6 {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Resolver_Failing_Allocator {
			backing = mem.tracking_allocator(&tracking),
			fail_after = u64(fail_after),
		}
		source, adapted, failure := command_candidate_source_build(
			&catalog,
			resolver_failing_allocator(&failing),
		)
		if adapted {
			successes += 1
			testing.expect(t, command_candidate_source_close(&source))
		} else {
			failures += 1
			testing.expect_value(t, failure.code, Candidate_Failure_Code.Persistent_Memory_Limit)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}
	testing.expect(t, failures > 0 && successes > 0)
}

@(private)
command_candidates_test_catalog :: proc(
	t: ^testing.T,
) -> (registry: Command_Registry, snapshot: Resolution_Snapshot, catalog: Command_Catalog, ok: bool) {
	definitions := [4]Command_Definition {
		command_candidates_test_definition("native-command", "Native action.", .Native, "odra-native", {}),
		command_candidates_test_definition("racket-command", "Racket action.", .Racket, "odra-racket", {}),
		command_candidates_test_definition(
			"region-command",
			"Region action.",
			.Native,
			"odra-native",
			{.Active_Region},
		),
		{
			name = "insert-text",
			route = test_command_route("insert-text"),
			implementation = .Native,
			invocation = .Text_Input,
			text_requirement = .Required,
		},
	}
	registry_ok, registry_failure := command_registry_init(&registry, 11, definitions[:], context.allocator)
	testing.expectf(t, registry_ok, "command registry failed with %v", registry_failure.code)
	if !registry_ok {
		return {}, {}, {}, false
	}
	bindings := [1]Binding_Definition{command_catalog_test_binding('n', "native-command")}
	snapshot_ok, snapshot_failure := snapshot_compile(
		&snapshot,
		&registry,
		17,
		Keymap_Definition {
			registry_generation = 11,
			bindings = bindings[:],
			text_fallback_name = "insert-text",
		},
		context.allocator,
	)
	testing.expectf(t, snapshot_ok, "command snapshot failed with %v", snapshot_failure.code)
	if !snapshot_ok {
		command_registry_close(&registry)
		return {}, {}, {}, false
	}
	catalog_ok: bool
	catalog_failure: Failure_Context
	catalog, catalog_ok, catalog_failure = command_catalog_build(
		&registry,
		&snapshot,
		Command_Catalog_Context{active_buffer = true},
		context.allocator,
	)
	testing.expectf(t, catalog_ok, "command catalog failed with %v", catalog_failure.code)
	if !catalog_ok {
		snapshot_close(&snapshot)
		command_registry_close(&registry)
		return {}, {}, {}, false
	}
	return registry, snapshot, catalog, true
}

@(private)
command_candidates_test_definition :: proc(
	name, description: string,
	implementation: Implementation_Class,
	provider: string,
	requirements: Command_Requirements,
) -> Command_Definition {
	return Command_Definition {
		name = name,
		route = test_command_route(name),
		implementation = implementation,
		invocation = .Ordinary,
		text_requirement = .Prohibited,
		description = description,
		interactive = true,
		requirements = requirements,
		provenance = {provider = provider, source = "command-candidates-test"},
	}
}
