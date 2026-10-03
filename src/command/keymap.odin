// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "../interaction"
import "base:runtime"

/*
racket_profile_reload replaces the session catalog from one complete Racket candidate.
The transport candidate is released before return; activation retains its own copy.
*/
racket_profile_reload :: proc(
	racket_runtime: ^hosting.Runtime,
	command_registry: ^interaction.Command_Registry,
	activation: ^interaction.Profile_Activation,
	active_context: interaction.Active_Context,
	pending: ^interaction.Pending_State,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	if racket_runtime == nil || command_registry == nil || activation == nil || pending == nil {
		return false, Failure_Context{code = .Invalid_Command}
	}
	registry_stats, registry_ok, registry_failure := interaction.command_registry_stats(
		command_registry,
	)
	if !registry_ok {
		return false, Failure_Context {
			code = .Invalid_Command,
			interaction_code = registry_failure.code,
		}
	}
	candidate, loaded, load_failure := hosting.runtime_load_keymap_profile(
		racket_runtime,
		u64(registry_stats.generation),
		allocator,
	)
	if !loaded {
		return false, hosting_failure_context({}, load_failure)
	}
	defer hosting.keymap_profile_candidate_close(&candidate)
	definition, adapted := hosting.keymap_profile_candidate_catalog_definition(&candidate)
	if !adapted {
		return false, Failure_Context{code = .Wrong_Result}
	}
	published, activation_failure := interaction.profile_activation_replace_catalog(
		activation,
		command_registry,
		definition,
		active_context,
		pending,
		interaction.DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		interaction.DEFAULT_RESOLUTION_POLICY,
		allocator,
	)
	if !published {
		return false, Failure_Context {
			code = .Invalid_Command,
			interaction_code = activation_failure.code,
			limit = activation_failure.limit,
			actual = activation_failure.actual,
		}
	}
	return true, {}
}
