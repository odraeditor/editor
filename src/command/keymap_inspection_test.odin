// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "core:testing"

/* Verifies inspection commands are registered as Racket-owned interactive identities. */
@(test)
keymap_commands_enter_registry :: proc(t: ^testing.T) {
	definitions := test_racket_command_definitions()
	testing.expect_value(t, len(definitions), TEST_RACKET_COMMAND_COUNT)
	expected := [?]string {
		"describe-key",
		"where-is",
		"describe-bindings",
		"describe-keymap",
		"describe-keymap-conflicts",
		"describe-keymap-state",
	}
	for name, index in expected {
		definition := definitions[index]
		testing.expect_value(t, definition.name, name)
		testing.expect_value(t, definition.implementation, interaction.Implementation_Class.Racket)
		testing.expect(t, definition.interactive)
		testing.expect_value(t, definition.provenance.source, "src/command/keymap-inspection.rkt")
	}
}

/* Verifies the command facade returns copied keymap inspection and contained failures. */
@(test)
keymap_inspection_facade_exposes_active_bindings :: proc(t: ^testing.T) {
	definitions := test_built_in_command_definitions()
	registry: interaction.Command_Registry
	ready, registry_failure := interaction.command_registry_init(
		&registry,
		interaction.Registry_Generation(701),
		definitions[:],
		context.allocator,
	)
	testing.expectf(t, ready, "registry initialization failed: %v", registry_failure.code)
	if !ready {
		return
	}
	defer interaction.command_registry_close(&registry)

	provenance := interaction.Definition_Provenance {
		provider = "test",
		source = "keymap-inspection-test",
	}
	bindings := [?]interaction.Layered_Binding_Definition {{
		sequence = {
			strokes = {0 = {
				kind = .Unicode_Scalar,
				scalar = 'a',
			}},
			stroke_count = 1,
		},
		command_name = "request-editor-exit",
		operation = .Bind,
		provenance = provenance,
	}}
	maps := [?]interaction.Map_Definition {{
		identity = {id = interaction.Map_ID(71), revision = interaction.Map_Revision(1)},
		name = "test-map",
		precedence = .Factory_Fallback,
		bindings = bindings[:],
		unmatched_input_policy = .Text_Input,
		provenance = provenance,
	}}
	profile := interaction.Profile_Definition {
		identity = {id = interaction.Profile_ID(71), revision = interaction.Profile_Revision(1)},
		name = "test-profile",
		maps = maps[:],
		text_fallback_name = "insert-text",
	}
	activation: interaction.Profile_Activation
	interaction.profile_activation_init(&activation)
	defer interaction.profile_activation_close(&activation)
	pending: interaction.Pending_State
	published, publish_failure := interaction.profile_activation_replace(
		&activation,
		&registry,
		profile,
		interaction.Active_Context {
			identity = {
				id = interaction.Context_ID(71),
				generation = interaction.Context_Generation(1),
			},
		},
		&pending,
		interaction.DEFAULT_RESOLUTION_POLICY,
		context.allocator,
	)
	testing.expectf(t, published, "profile activation failed: %v", publish_failure.code)
	if !published {
		return
	}

	result, inspected, failure := keymap_inspection_run(Keymap_Inspection_Request {
		registry = &registry,
		activation = &activation,
		pending = &pending,
		query = {
			kind = .Sequence,
			sequence = {
				strokes = {0 = {kind = .Unicode_Scalar, scalar = 'a'}},
				stroke_count = 1,
			},
		},
		allocator = context.allocator,
	})
	testing.expectf(t, inspected, "inspection facade failed: %v", failure.interaction_code)
	if inspected {
		testing.expect_value(t, len(result.records), 1)
		if len(result.records) == 1 {
			testing.expect_value(t, result.records[0].command_name, "request-editor-exit")
			testing.expect_value(t, result.records[0].map_name, "test-map")
		}
		testing.expect(t, interaction.inspection_result_close(&result))
	}

	_, inspected, failure = keymap_inspection_run(Keymap_Inspection_Request {
		registry = &registry,
		activation = &activation,
		pending = &pending,
		query = {kind = .Command, command_name = "missing-command"},
		allocator = context.allocator,
	})
	testing.expect(t, !inspected)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Command)
	testing.expect_value(t, failure.interaction_code, interaction.Failure_Code.Unknown_Command)
}
