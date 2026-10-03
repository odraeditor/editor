// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

import "core:testing"

@(private)
observation_test_stamp :: proc() -> Source_Stamp {
	return Source_Stamp {
		presentation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		owner_identity = 23,
		owner_generation = 29,
	}
}

@(private)
observation_test_context :: proc() -> Context_Observation {
	stamp := observation_test_stamp()
	encoding, _ := context_label_copy("UTF-8 LF")
	language_name, _ := context_label_copy("Odin")
	project_name, _ := context_label_copy("odra")
	workspace_name, _ := context_label_copy("editor")
	return Context_Observation {
		generation = 7,
		buffer_identity = 11,
		buffer_revision = 13,
		pane_identity = 17,
		pane_generation = 19,
		document = {present = true, stamp = stamp, encoding = encoding},
		diagnostics = {present = true, stamp = stamp, errors = 2, warnings = 3},
		language = {present = true, stamp = stamp, name = language_name, service_health = .Active},
		project = {present = true, stamp = stamp, name = project_name},
		workspace = {present = true, stamp = stamp, name = workspace_name},
		pane = {present = true, stamp = stamp, policy = .Hard_Dedicated},
	}
}

/* Verifies complete copied context admits only the exact presentation, pane, buffer, and owner stamps. */
@(test)
context_observation_rejects_cross_pane :: proc(t: ^testing.T) {
	observation := observation_test_context()
	testing.expect(t, context_observation_validate(observation, 7))
	observation.language.stamp.buffer_revision = 12
	testing.expect(t, !context_observation_validate(observation, 7))
	observation = observation_test_context()
	observation.project.stamp.pane_identity = 18
	testing.expect(t, !context_observation_validate(observation, 7))
	observation = observation_test_context()
	observation.workspace.stamp.owner_generation = 0
	testing.expect(t, !context_observation_validate(observation, 7))
	testing.expect(t, !context_observation_validate(observation, 8))
}

/* Verifies unavailable owners remain exactly absent and consume no synthetic identity. */
@(test)
context_observation_accepts_exact_absence :: proc(t: ^testing.T) {
	testing.expect(t, context_observation_validate({}, 7))
	partial := Context_Observation{buffer_identity = 1}
	testing.expect(t, !context_observation_validate(partial, 7))
	observation := observation_test_context()
	observation.alert = {}
	testing.expect(t, context_observation_validate(observation, 7))
}
