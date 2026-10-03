// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "core:testing"

/* Verifies confirmed configurations have content-addressed generations. */
@(test)
jan_configuration_generations_are_content_addressed :: proc(t: ^testing.T) {
	factory := jan_factory_configuration(1)
	testing.expect(t, jan_configuration_is_valid(factory))

	configured := factory
	testing.expect(t, jan_configuration_list_clear(&configured.task_keywords))
	testing.expect(t, jan_configuration_list_append(&configured.task_keywords, "READY"))
	testing.expect(t, jan_configuration_list_append(&configured.task_keywords, "DONE"))
	testing.expect(t, jan_configuration_confirm(&configured, 2))
	testing.expect(t, jan_configuration_is_valid(configured))
	testing.expect(t, configured.identity != factory.identity)
	testing.expect(t, configured.identity.digest != factory.identity.digest)

	configured.radio_links = false
	testing.expect(t, !jan_configuration_is_valid(configured))
}

/* Verifies malformed or duplicate bounded name sets cannot be confirmed. */
@(test)
jan_configuration_rejects_invalid_name_sets :: proc(t: ^testing.T) {
	configuration := jan_factory_configuration(1)
	testing.expect(t, jan_configuration_list_clear(&configuration.task_keywords))
	testing.expect(t, jan_configuration_list_append(&configuration.task_keywords, "TODO"))
	testing.expect(t, jan_configuration_list_append(&configuration.task_keywords, "TODO"))
	testing.expect(t, !jan_configuration_confirm(&configuration, 2))

	configuration = jan_factory_configuration(1)
	testing.expect(t, !jan_configuration_list_append(&configuration.entities, ""))
	too_long: [JAN_CONFIGURATION_VALUE_BYTES + 1]u8
	for &byte in too_long do byte = 'x'
	testing.expect(t, !jan_configuration_list_append(&configuration.entities, string(too_long[:])))
}
