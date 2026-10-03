// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_extension_focused

import bridge "../../src/bridge"
import hosting "../../src/hosting"
import ksawery "../../src/ksawery"
import odra "../../src/ksawery_module"
import "core:testing"

/* Verifies the focused harness reaches every native package in the extension boundary. */
@(test)
extension_boundary_packages_are_available :: proc(t: ^testing.T) {
	testing.expect(t, bridge.MAX_UI_ROLE_PROVIDERS >= 1)
	testing.expect(t, size_of(hosting.Runtime) > 0)
	testing.expect(t, size_of(odra.Ksawery_Process_Coordinator) > 0)
	testing.expect(t, ksawery.process_limits_are_valid(ksawery.DEFAULT_PROCESS_LIMITS))
}

/* Verifies copied repository observations remain the foundation for provider turns. */
@(test)
extension_boundary_starts_from_copied_repository_truth :: proc(t: ^testing.T) {
	repository: ksawery.Repository_Context
	testing.expect(t, ksawery.repository_context_assign(&repository, "/tmp/odra-ksawery-extension-focused"))
	output := transmute([]u8)(string(
		"# branch.oid 0123456789012345678901234567890123456789\x00" +
		"# branch.head main\x00",
	))
	observation, opened, failure := ksawery.status_observation_open(
		repository,
		ksawery.Observation_Generation(1),
		output,
		nil,
		ksawery.DEFAULT_PROCESS_LIMITS,
	)
	testing.expectf(t, opened, "status observation failed with %v", failure)
	if !opened do return
	defer ksawery.status_observation_close(&observation)
	descriptor, described := ksawery.status_observation_descriptor(&observation)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.repository, repository)
	testing.expect_value(t, descriptor.generation, ksawery.Observation_Generation(1))
}
