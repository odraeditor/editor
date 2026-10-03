// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../result_set"

/* Result_Access identifies independently granted programmable result operations. */
Result_Access :: enum u8 {
	Inspect,
	Publish,
	Move,
}

/* Result_Access_Set is one immutable authority grant. */
Result_Access_Set :: bit_set[Result_Access; u8]

/* Result_Capability_Scope binds one turn to one result generation. */
Result_Capability_Scope :: struct {
	editor_session_id:     Editor_Session_ID,
	access:                Result_Access_Set,
	set_id:                result_set.Result_Set_ID,
	set_generation:        result_set.Result_Set_Generation,
	capability_generation: u64,
}

/* Result_Capability_Context borrows the registry owned by one editor session. */
Result_Capability_Context :: struct {
	editor_session_id:     Editor_Session_ID,
	access:                Result_Access_Set,
	registry:              ^result_set.Registry,
	set_id:                result_set.Result_Set_ID,
	provider_source_id:    result_set.Source_ID,
	capability_generation: u64,
}

/* result_capability_scope captures the current immutable generation identity. */
result_capability_scope :: proc(
	ctx: Result_Capability_Context,
) -> (Result_Capability_Scope, bool, result_set.Failure) {
	if ctx.editor_session_id == Editor_Session_ID(0) || ctx.registry == nil ||
	   ctx.set_id == result_set.Result_Set_ID(0) ||
	   ctx.provider_source_id == result_set.Source_ID(0) || ctx.capability_generation == 0 ||
	   card(ctx.access) == 0 {
		return {}, false, result_set.Failure{code = .Invalid_Registry, set_id = ctx.set_id}
	}
	_, inspected, failure := result_set.registry_inspect(ctx.registry)
	if !inspected do return {}, false, failure
	generation := result_set.Result_Set_Generation(0)
	view, found, view_failure := result_set.registry_view(ctx.registry, ctx.set_id)
	if found {
		generation = view.generation
	} else if view_failure.code != .Set_Not_Found {
		return {}, false, view_failure
	}
	return Result_Capability_Scope {
		editor_session_id = ctx.editor_session_id,
		access = ctx.access,
		set_id = ctx.set_id,
		set_generation = generation,
		capability_generation = ctx.capability_generation,
	}, true, {}
}

/* result_capability_inspect returns one borrowed immutable view after exact validation. */
result_capability_inspect :: proc(
	ctx: Result_Capability_Context,
	expected: Result_Capability_Scope,
) -> (result_set.View, bool, result_set.Failure) {
	actual, valid, failure := result_capability_validate(ctx, expected, .Inspect)
	if !valid do return {}, false, failure
	if actual.set_generation == result_set.Result_Set_Generation(0) {
		return {}, false, result_set.Failure{code = .Set_Not_Found, set_id = actual.set_id}
	}
	return result_set.registry_view(ctx.registry, actual.set_id)
}

/* result_capability_publish admits one complete copied programmable generation. */
result_capability_publish :: proc(
	ctx: Result_Capability_Context,
	expected: Result_Capability_Scope,
	publication: result_set.Publication,
) -> (result_set.Result, bool, result_set.Failure) {
	actual, valid, failure := result_capability_validate(ctx, expected, .Publish)
	if !valid do return {}, false, failure
	if publication.set_id != actual.set_id ||
	   publication.expected_generation != actual.set_generation ||
	   publication.source.id != ctx.provider_source_id ||
	   publication.source.kind != .Programmable {
		return {}, false, result_set.Failure {
			code = .Invalid_Publication,
			set_id = publication.set_id,
			generation = publication.expected_generation,
		}
	}
	return result_set.registry_publish(ctx.registry, publication)
}

/* result_capability_move changes only canonical selection under checked scope. */
result_capability_move :: proc(
	ctx: Result_Capability_Context,
	expected: Result_Capability_Scope,
	movement: result_set.Movement,
) -> (result_set.Result, bool, result_set.Failure) {
	actual, valid, failure := result_capability_validate(ctx, expected, .Move)
	if !valid do return {}, false, failure
	return result_set.registry_move(ctx.registry, actual.set_id, actual.set_generation, movement)
}

@(private)
result_capability_validate :: proc(
	ctx: Result_Capability_Context,
	expected: Result_Capability_Scope,
	required: Result_Access,
) -> (Result_Capability_Scope, bool, result_set.Failure) {
	actual, scoped, failure := result_capability_scope(ctx)
	if !scoped do return {}, false, failure
	if required not_in ctx.access {
		return {}, false, result_set.Failure{code = .Invalid_Publication, set_id = ctx.set_id}
	}
	if expected.editor_session_id != actual.editor_session_id ||
	   expected.access != actual.access || expected.set_id != actual.set_id ||
	   expected.capability_generation != actual.capability_generation {
		return {}, false, result_set.Failure{code = .Invalid_Registry, set_id = expected.set_id}
	}
	if expected.set_generation != actual.set_generation {
		return {}, false, result_set.Failure {
			code = .Stale_Generation,
			set_id = expected.set_id,
			generation = expected.set_generation,
			limit = u64(expected.set_generation),
			actual = u64(actual.set_generation),
		}
	}
	return actual, true, {}
}
