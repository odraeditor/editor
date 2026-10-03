// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../display"
import "../hosting"
import "../interaction"
import "../status_bar"
import "core:testing"

/* Verifies Racket publishes copied segments that compose without a hot callback. */
verify_racket_status_bar_provider :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	registry: status_bar.Registry
	ready, ready_failure := status_bar.registry_init(
		&registry,
		status_bar.Registry_ID(71),
	)
	testing.expectf(t, ready, "Status Bar registry initialization failed: %v", ready_failure.code)
	if !ready do return
	defer status_bar.registry_close(&registry)

	commands: interaction.Command_Registry
	commands_ready, commands_failure := built_in_command_registry_init(
		&commands,
		interaction.Registry_Generation(73),
		context.allocator,
	)
	testing.expectf(t, commands_ready, "command registry initialization failed: %v", commands_failure.code)
	if !commands_ready do return
	defer interaction.command_registry_close(&commands)

	turn, published, failure := racket_status_bar_turn(
		racket_runtime,
		&registry,
		&commands,
		79,
		83,
		89,
		0,
	)
	testing.expectf(t, published, "Racket Status Bar publication failed: %v", failure)
	if !published do return
	testing.expect_value(t, turn.calls, u16(4))

	inspection, inspected, inspect_failure := status_bar.registry_inspect(&registry)
	testing.expectf(t, inspected, "Status Bar registry inspection failed: %v", inspect_failure.code)
	if !inspected do return
	testing.expect_value(t, inspection.usage.providers, u16(1))
	testing.expect_value(t, inspection.usage.segments, u16(1))
	segment, found, segment_failure := status_bar.registry_segment_at(&registry, 0)
	testing.expectf(t, found, "Status Bar segment lookup failed: %v", segment_failure.code)
	if !found do return
	testing.expect_value(t, segment.definition.full_text, "Racket")

	request := status_bar.Factory_Request {
		generation = status_bar.Generation(97),
		width_cells = 40,
		buffer = {
			generation = status_bar.Generation(97),
			identity = 101,
			revision = 103,
			label = "main.odin",
			writable = true,
			point_offset = 0,
			text_bytes = 0,
			line = 1,
			line_count = 1,
			column = 1,
		},
		programmable = []status_bar.Segment_Definition{segment.definition},
		profile = display.unicode17_profile(),
		allocator = context.allocator,
		limits = status_bar.DEFAULT_LIMITS,
	}
	view, composed, compose_failure := status_bar.compose_factory(request)
	testing.expectf(
		t,
		composed,
		"programmable Status Bar composition failed: %v/%v segment=%v id=%v group=%v role=%v omitted=%v text=%q",
		compose_failure.operation,
		compose_failure.code,
		compose_failure.segment,
		segment.definition.id,
		segment.definition.group,
		segment.definition.style_role,
		segment.definition.omittable,
		segment.definition.full_text,
	)
	if composed {
		contributed := false
		for presented in view.segments {
			if presented.id == segment.definition.id {
				contributed = true
				break
			}
		}
		testing.expect(t, contributed)
		status_bar.view_close(&view)
	}
}
