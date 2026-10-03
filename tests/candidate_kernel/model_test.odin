// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package candidate_kernel

import interaction "../../src/interaction"
import candidate_reference "../candidate_reference"
import "core:fmt"
import "core:mem"
import "core:testing"

/* Verifies generated literal projections agree with the independent candidate oracle. */
@(test)
candidate_kernel_matches_reference_model :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	labels: [64][96]byte
	production: [64]interaction.Candidate_Descriptor_Definition
	reference: [64]candidate_reference.Candidate
	for index in 0 ..< len(production) {
		label := fmt.bprintf(
			labels[index][:],
			"alpha module-%02d project group-%02d",
			index,
			index % 8,
		)
		identity := interaction.Candidate_Identity {
			kind = 1,
			primary = u64(index + 1),
		}
		production[index] = interaction.Candidate_Descriptor_Definition {
			identity = identity,
			label = label,
			action = {
				kind = .Invoke_Command,
				owner_generation = 1,
				primary = u64(index + 1),
			},
			availability = .Available,
			recency = u64(index % 11),
		}
		reference[index] = candidate_reference.Candidate {
			identity = {
				kind = identity.kind,
				primary = identity.primary,
				secondary = identity.secondary,
			},
			label = label,
			folded_label = label,
			recency = u64(index % 11),
		}
	}
	session: interaction.Candidate_Session
	_, initialized, failure := interaction.candidate_session_init(
		&session,
		interaction.Candidate_Config {
			session_id = 301,
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = allocator,
		},
		interaction.Candidate_Source_Definition {
			kind = .Test,
			scope_identity = 1,
			scope_generation = 1,
			source_generation = 1,
			descriptors = production[:],
		},
	)
	testing.expectf(t, initialized, "production candidate init failed with %v", failure.code)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	queries := [?]string {
		"",
		"alpha",
		"module-07",
		"group-03 project",
		"project alpha group-05",
		"absent",
	}
	expected: [64]candidate_reference.Projection
	for query in queries {
		view, viewed, _ := interaction.candidate_session_view(&session)
		testing.expect(t, viewed)
		_, queried, query_failure := interaction.candidate_session_set_query(
			&session,
			interaction.Candidate_Request {
				session_id = view.session_id,
				session_generation = view.session_generation,
			},
			query,
		)
		testing.expectf(t, queried, "production query %q failed with %v", query, query_failure.code)
		view, viewed, _ = interaction.candidate_session_view(&session)
		testing.expect(t, viewed)
		expected_count, modeled, model_failure := candidate_reference.filter(
			reference[:],
			query,
			expected[:],
			allocator,
		)
		testing.expectf(t, modeled, "reference query %q failed with %v", query, model_failure.code)
		testing.expect_value(t, len(view.rows), expected_count)
		if len(view.rows) != expected_count {
			continue
		}
		for row, index in view.rows {
			projection := expected[index]
			testing.expect_value(t, row.identity.primary, projection.identity.primary)
			testing.expect_value(t, u8(row.match_class), u8(projection.match_class))
		}
	}
	_, closed, close_failure := interaction.candidate_session_close(&session)
	testing.expectf(t, closed, "production candidate close failed with %v", close_failure.code)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	mem.tracking_allocator_destroy(&tracking)
}
