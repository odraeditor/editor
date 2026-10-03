// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"

/* Generation_Activation owns one compatible command, profile, and context-map generation. */
Generation_Activation :: struct {
	registry:       Command_Registry,
	profile:        Profile_Activation,
	context_maps:   Context_Map_Stack,
	generation:     Registry_Generation,
	ready:          bool,
}

/* generation_activation_complete validates every interaction owner before publication. */
generation_activation_complete :: proc(
	activation: ^Generation_Activation,
	generation: Registry_Generation,
	definition: Profile_Catalog_Definition,
	active_context: Active_Context,
	context_id: Context_ID,
	allocator: runtime.Allocator,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	if activation.ready || activation.registry.state == nil || generation == 0 {
		return false, Failure_Context{code = .Invalid_Registry, registry_generation = generation}
	}
	stats, registry_ok, registry_failure := command_registry_stats(&activation.registry)
	if !registry_ok || stats.generation != generation {
		return false, registry_failure
	}
	profile_activation_init(&activation.profile)
	candidate_pending: Pending_State
	profile_ok, profile_failure := profile_activation_replace_catalog(
		&activation.profile,
		&activation.registry,
		definition,
		active_context,
		&candidate_pending,
		DEFAULT_PROFILE_COMPATIBILITY_POLICY,
		DEFAULT_RESOLUTION_POLICY,
		allocator,
	)
	if !profile_ok {
		_, _ = profile_activation_close(&activation.profile)
		return false, profile_failure
	}
	contexts_ok, contexts_failure := context_map_stack_init(
		&activation.context_maps,
		context_id,
		&activation.registry,
		allocator,
	)
	if !contexts_ok {
		_, _ = profile_activation_close(&activation.profile)
		return false, contexts_failure
	}
	activation.generation = generation
	activation.ready = true
	return true, {}
}

/* generation_activation_publish replaces one complete compatible generation. */
generation_activation_publish :: proc(
	active: ^Generation_Activation,
	candidate: ^Generation_Activation,
	pending: ^Pending_State,
	context_pending: ^Context_Pending_State,
) -> (ok: bool, failure: Failure_Context) {
	assert(active != nil)
	assert(candidate != nil)
	assert(pending != nil)
	assert(context_pending != nil)
	if !candidate.ready || candidate.generation == 0 ||
	   (active.ready && candidate.generation <= active.generation) {
		return false, Failure_Context {
			code = .Stale_Registry,
			registry_generation = candidate.generation,
		}
	}
	retired := active^
	active^ = candidate^
	candidate^ = {}
	pending_clear(pending)
	context_pending^ = {}
	if retired.ready {
		closed, close_failure := generation_activation_close(&retired)
		assert(closed, "published interaction generation failed to retire")
		if !closed do return true, close_failure
	}
	return true, {}
}

/* generation_activation_close releases every owner in dependency order. */
generation_activation_close :: proc(
	activation: ^Generation_Activation,
) -> (ok: bool, failure: Failure_Context) {
	assert(activation != nil)
	if activation.context_maps.state != nil {
		closed, context_failure := context_map_stack_close(&activation.context_maps)
		if !closed do return false, context_failure
	}
	if activation.profile.ready && !activation.profile.closed {
		closed, profile_failure := profile_activation_close(&activation.profile)
		if !closed do return false, profile_failure
	}
	if activation.registry.state != nil {
		closed, registry_failure := command_registry_close(&activation.registry)
		if !closed do return false, registry_failure
	}
	activation^ = {}
	return true, {}
}
