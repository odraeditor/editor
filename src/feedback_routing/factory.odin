// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback_routing

import "../ui"

/* FACTORY_STATUS_DESTINATION identifies the maintained root-edge status sink. */
FACTORY_STATUS_DESTINATION :: Destination_ID(1)
/* FACTORY_FLOATING_DESTINATION identifies the maintained transient notification sink. */
FACTORY_FLOATING_DESTINATION :: Destination_ID(2)
/* FACTORY_HISTORY_DESTINATION identifies the maintained retained history sink. */
FACTORY_HISTORY_DESTINATION :: Destination_ID(3)
/* FACTORY_DIAGNOSTIC_DESTINATION identifies the maintained diagnostic sink. */
FACTORY_DIAGNOSTIC_DESTINATION :: Destination_ID(4)

/* factory_configuration returns the maintained initial route table. */
factory_configuration :: proc(
	generation: Configuration_Generation,
	contextual_profile: ui.Presentation_Profile_Handle,
) -> Configuration_Proposal {
	compact_name, _ := text_copy("compact-status")
	notification_name, _ := text_copy("notification")
	history_name, _ := text_copy("history")
	diagnostic_name, _ := text_copy("diagnostic")
	status_destination_name, _ := text_copy("status")
	floating_destination_name, _ := text_copy("floating")
	history_destination_name, _ := text_copy("history")
	diagnostic_destination_name, _ := text_copy("diagnostic")
	attention_route_name, _ := text_copy("safety-attention")
	error_safety_route_name, _ := text_copy("safety-error")
	retention_route_name, _ := text_copy("retained-history")
	progress_route_name, _ := text_copy("progress-status")
	warning_route_name, _ := text_copy("warning-notification")
	error_route_name, _ := text_copy("error-notification")
	completion_route_name, _ := text_copy("completion-notification")
	acknowledgement_route_name, _ := text_copy("acknowledgement-status")
	information_route_name, _ := text_copy("information-status")
	configuration := Configuration_Proposal {
		generation = generation,
		projection_count = 4,
		destination_count = 4,
		route_count = 9,
	}
	configuration.projections[0] = {
		id = 1,
		generation = 1,
		name = compact_name,
		maximum_bytes = 256,
		include_title = true,
		include_progress = true,
		textual_severity = false,
		information_role = .Status_Normal,
		warning_role = .Status_Alert,
		error_role = .Status_Alert,
		attention_role = .Status_Alert,
		progress_role = .Status_Active,
	}
	configuration.projections[1] = {
		id = 2,
		generation = 1,
		name = notification_name,
		maximum_bytes = 512,
		include_title = true,
		include_message = true,
		include_progress = true,
		include_actions = true,
		textual_severity = true,
		information_role = .Popup_Content,
		warning_role = .Diagnostic_Warning,
		error_role = .Diagnostic_Error,
		attention_role = .Popup_Diagnostic,
		progress_role = .Status_Active,
	}
	configuration.projections[2] = {
		id = 3,
		generation = 1,
		name = history_name,
		maximum_bytes = 1_024,
		include_title = true,
		include_message = true,
		include_progress = true,
		include_actions = true,
		include_source = true,
		textual_severity = true,
		information_role = .List_Normal,
		warning_role = .Diagnostic_Warning,
		error_role = .Diagnostic_Error,
		attention_role = .List_Emphasis,
		progress_role = .Status_Active,
	}
	configuration.projections[3] = {
		id = 4,
		generation = 1,
		name = diagnostic_name,
		maximum_bytes = 1_024,
		include_title = true,
		include_message = true,
		include_progress = true,
		include_actions = true,
		include_source = true,
		textual_severity = true,
		information_role = .Diagnostic_Information,
		warning_role = .Diagnostic_Warning,
		error_role = .Diagnostic_Error,
		attention_role = .Diagnostic_Rejected,
		progress_role = .Diagnostic_Information,
	}
	configuration.destinations[0] = {
		id = FACTORY_STATUS_DESTINATION,
		generation = 1,
		name = status_destination_name,
		kind = .Status,
		projection = 1,
		minimum_rows = 1,
		minimum_columns = 12,
		capacity = 1,
		content_bytes = 256,
		focus = .None,
		dismissal = {.Explicit, .Expiry, .Replacement, .Source_Closure, .Frontend_Loss},
		inspectable = true,
	}
	configuration.destinations[1] = {
		id = FACTORY_FLOATING_DESTINATION,
		generation = 1,
		name = floating_destination_name,
		kind = .Floating,
		projection = 2,
		fallback = FACTORY_STATUS_DESTINATION,
		required_capabilities = {.Cell_Geometry, .Clipping, .Popup_Overlap},
		minimum_rows = 3,
		minimum_columns = 18,
		capacity = 4,
		content_bytes = 512,
		focus = .Preserve,
		dismissal = {.Explicit, .Expiry, .Replacement, .Source_Closure, .Frontend_Loss},
		profile = contextual_profile,
		inspectable = true,
	}
	configuration.destinations[2] = {
		id = FACTORY_HISTORY_DESTINATION,
		generation = 1,
		name = history_destination_name,
		kind = .History,
		projection = 3,
		fallback = FACTORY_STATUS_DESTINATION,
		minimum_rows = 4,
		minimum_columns = 30,
		capacity = 256,
		content_bytes = 1_024,
		focus = .Transfer,
		dismissal = {.Explicit, .Frontend_Loss},
		inspectable = true,
	}
	configuration.destinations[3] = {
		id = FACTORY_DIAGNOSTIC_DESTINATION,
		generation = 1,
		name = diagnostic_destination_name,
		kind = .Diagnostic,
		projection = 4,
		fallback = FACTORY_STATUS_DESTINATION,
		minimum_rows = 1,
		minimum_columns = 12,
		capacity = 32,
		content_bytes = 1_024,
		focus = .None,
		dismissal = {.Explicit, .Replacement, .Source_Closure, .Frontend_Loss},
		inspectable = true,
	}
	configuration.routes[0] = {
		id = 1, generation = 1, name = attention_route_name, layer = .Safety,
		order = 0, protected = true, enabled = true,
		matcher = {match_attention = true, attention = .Required},
		resolution = .Continue, destinations = {0 = FACTORY_DIAGNOSTIC_DESTINATION}, destination_count = 1,
	}
	configuration.routes[1] = {
		id = 2, generation = 1, name = error_safety_route_name, layer = .Safety,
		order = 1, protected = true, enabled = true,
		matcher = {match_severity = true, severity = .Error},
		resolution = .Continue, destinations = {0 = FACTORY_DIAGNOSTIC_DESTINATION}, destination_count = 1,
	}
	configuration.routes[2] = {
		id = 3, generation = 1, name = retention_route_name, layer = .Factory,
		order = 0, enabled = true,
		matcher = {match_retention = true, retention = .History},
		resolution = .Continue, destinations = {0 = FACTORY_HISTORY_DESTINATION}, destination_count = 1,
	}
	configuration.routes[3] = {
		id = 4, generation = 1, name = progress_route_name, layer = .Factory,
		order = 10, enabled = true,
		matcher = {match_class = true, class = .Progress},
		resolution = .Terminal, destinations = {0 = FACTORY_STATUS_DESTINATION}, destination_count = 1,
	}
	configuration.routes[4] = {
		id = 5, generation = 1, name = warning_route_name, layer = .Factory,
		order = 20, enabled = true,
		matcher = {match_severity = true, severity = .Warning},
		resolution = .Terminal, destinations = {0 = FACTORY_FLOATING_DESTINATION}, destination_count = 1,
	}
	configuration.routes[5] = {
		id = 6, generation = 1, name = error_route_name, layer = .Factory,
		order = 21, enabled = true,
		matcher = {match_severity = true, severity = .Error},
		resolution = .Terminal, destinations = {0 = FACTORY_FLOATING_DESTINATION}, destination_count = 1,
	}
	configuration.routes[6] = {
		id = 7, generation = 1, name = completion_route_name, layer = .Factory,
		order = 30, enabled = true,
		matcher = {match_class = true, class = .Completion},
		resolution = .Terminal, destinations = {0 = FACTORY_FLOATING_DESTINATION}, destination_count = 1,
	}
	configuration.routes[7] = {
		id = 8, generation = 1, name = acknowledgement_route_name, layer = .Factory,
		order = 40, enabled = true,
		matcher = {match_class = true, class = .Acknowledgement},
		resolution = .Terminal, destinations = {0 = FACTORY_STATUS_DESTINATION}, destination_count = 1,
	}
	configuration.routes[8] = {
		id = 9, generation = 1, name = information_route_name, layer = .Factory,
		order = 50, enabled = true,
		matcher = {match_class = true, class = .Information},
		resolution = .Terminal, destinations = {0 = FACTORY_STATUS_DESTINATION}, destination_count = 1,
	}
	return configuration
}
