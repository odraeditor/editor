// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../result_set"
import "core:testing"

@(test)
/* result_capability_rejects_stale_and_wrong_provider_publications. */
result_capability_rejects_bad_publications :: proc(t: ^testing.T) {
	registry: result_set.Registry
	ready, _ := result_set.registry_init(
		&registry,
		result_set.Config{limits = result_set.DEFAULT_LIMITS, allocator = context.allocator},
	)
	testing.expect(t, ready)
	if !ready do return
	defer result_set.registry_close(&registry)
	ctx := Result_Capability_Context {
		editor_session_id = 71,
		access = {.Inspect, .Publish, .Move},
		registry = &registry,
		set_id = 9,
		provider_source_id = 15,
		capability_generation = 3,
	}
	scope, scoped, _ := result_capability_scope(ctx)
	testing.expect(t, scoped)
	wrong := result_set.Publication {
		set_id = 9,
		source = {id = 16, generation = 1, kind = .Programmable},
		completeness = .Complete,
		edit_capability = .Read_Only,
	}
	_, published, failure := result_capability_publish(ctx, scope, wrong)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, result_set.Failure_Code.Invalid_Publication)

	publication := wrong
	publication.source.id = 15
	_, published, failure = result_capability_publish(ctx, scope, publication)
	testing.expectf(t, published, "publication failed: %v", failure.code)
	_, published, failure = result_capability_publish(ctx, scope, publication)
	testing.expect(t, !published)
	testing.expect_value(t, failure.code, result_set.Failure_Code.Stale_Generation)
}
