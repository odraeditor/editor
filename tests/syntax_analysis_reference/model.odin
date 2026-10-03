// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package syntax_analysis_reference provides an independent fixed-array oracle
// for language-provider selection and exact-revision syntax publication.
package syntax_analysis_reference

MAX_PROVIDERS :: 8
MAX_SPANS :: 64

Provider_State :: enum u8 {
	Invalid,
	Registered,
	Confirmed,
	Failed,
}

Failure_Code :: enum u8 {
	None,
	Invalid_Model,
	Invalid_Provider,
	Duplicate_Provider,
	Provider_Limit,
	Provider_Not_Confirmed,
	Stale_Selection,
	Syntax_Disabled,
	Span_Limit,
}

Provider_Handle :: struct {
	id:         u16,
	generation: u64,
}

Provider :: struct {
	handle: Provider_Handle,
	key:    u32,
	state:  Provider_State,
	live:   bool,
}

Selection :: struct {
	generation: u64,
	active:     Provider_Handle,
	factory:    Provider_Handle,
	disabled:   bool,
}

Syntax_Snapshot :: struct {
	buffer_id:            u64,
	source_revision:      u64,
	selection_generation: u64,
	provider:             Provider_Handle,
	span_count:           u32,
	confirmed:            bool,
}

Failure :: struct {
	code:     Failure_Code,
	provider: Provider_Handle,
	limit:    u64,
	actual:   u64,
}

Model :: struct {
	providers:      [MAX_PROVIDERS]Provider,
	provider_count: u16,
	selection:      Selection,
	snapshot:       Syntax_Snapshot,
	closed:         bool,
}

model_init :: proc(factory_key: u32) -> (model: Model, ok: bool) {
	if factory_key == 0 do return {}, false
	factory := Provider_Handle{id = 1, generation = 1}
	model.providers[0] = Provider {
		handle = factory,
		key = factory_key,
		state = .Confirmed,
		live = true,
	}
	model.provider_count = 1
	model.selection = Selection {
		generation = 1,
		active = factory,
		factory = factory,
	}
	return model, true
}

model_register :: proc(
	model: ^Model,
	key: u32,
) -> (handle: Provider_Handle, ok: bool, failure: Failure) {
	if !model_live(model) || key == 0 {
		return {}, false, Failure{code = .Invalid_Model}
	}
	for provider in model.providers {
		if provider.live && provider.key == key {
			return {}, false, Failure{
				code = .Duplicate_Provider,
				provider = provider.handle,
			}
		}
	}
	if model.provider_count >= MAX_PROVIDERS {
		return {}, false, Failure{
			code = .Provider_Limit,
			limit = MAX_PROVIDERS,
			actual = u64(model.provider_count) + 1,
		}
	}
	for &provider in model.providers {
		if provider.live do continue
		handle = Provider_Handle{id = model.provider_count + 1, generation = 1}
		provider = Provider {
			handle = handle,
			key = key,
			state = .Registered,
			live = true,
		}
		model.provider_count += 1
		return handle, true, {}
	}
	return {}, false, Failure{code = .Provider_Limit, limit = MAX_PROVIDERS}
}

model_confirm :: proc(
	model: ^Model,
	handle: Provider_Handle,
) -> (confirmed: Provider_Handle, ok: bool, failure: Failure) {
	provider := model_provider(model, handle)
	if provider == nil {
		return {}, false, Failure{code = .Invalid_Provider, provider = handle}
	}
	if provider.state != .Registered {
		return {}, false, Failure{code = .Invalid_Provider, provider = handle}
	}
	provider.handle.generation += 1
	provider.state = .Confirmed
	return provider.handle, true, {}
}

model_replace :: proc(
	model: ^Model,
	expected_generation: u64,
	handle: Provider_Handle,
) -> (selection: Selection, ok: bool, failure: Failure) {
	if !model_live(model) do return {}, false, Failure{code = .Invalid_Model}
	if model.selection.generation != expected_generation {
		return {}, false, Failure{code = .Stale_Selection, provider = handle}
	}
	provider := model_provider(model, handle)
	if provider == nil {
		return {}, false, Failure{code = .Invalid_Provider, provider = handle}
	}
	if provider.state != .Confirmed {
		return {}, false, Failure{code = .Provider_Not_Confirmed, provider = handle}
	}
	model.selection.generation += 1
	model.selection.active = provider.handle
	model.selection.disabled = false
	model.snapshot = {}
	return model.selection, true, {}
}

model_disable :: proc(
	model: ^Model,
	expected_generation: u64,
) -> (selection: Selection, ok: bool, failure: Failure) {
	if !model_live(model) do return {}, false, Failure{code = .Invalid_Model}
	if model.selection.generation != expected_generation {
		return {}, false, Failure{code = .Stale_Selection}
	}
	model.selection.generation += 1
	model.selection.active = {}
	model.selection.disabled = true
	model.snapshot = {}
	return model.selection, true, {}
}

model_restore :: proc(
	model: ^Model,
	expected_generation: u64,
) -> (selection: Selection, ok: bool, failure: Failure) {
	return model_replace(model, expected_generation, model.selection.factory)
}

model_fail_active :: proc(
	model: ^Model,
	expected_generation: u64,
) -> (selection: Selection, ok: bool, failure: Failure) {
	if !model_live(model) do return {}, false, Failure{code = .Invalid_Model}
	if model.selection.generation != expected_generation {
		return {}, false, Failure{code = .Stale_Selection}
	}
	active := model_provider(model, model.selection.active)
	if active == nil {
		return {}, false, Failure{code = .Invalid_Provider}
	}
	if active.handle != model.selection.factory {
		active.handle.generation += 1
		active.state = .Failed
	}
	model.selection.generation += 1
	model.selection.active = model.selection.factory
	model.selection.disabled = false
	model.snapshot = {}
	return model.selection, true, {}
}

model_publish_snapshot :: proc(
	model: ^Model,
	expected_selection: u64,
	buffer_id, source_revision: u64,
	span_count: u32,
) -> (snapshot: Syntax_Snapshot, ok: bool, failure: Failure) {
	if !model_live(model) || buffer_id == 0 || source_revision == 0 {
		return {}, false, Failure{code = .Invalid_Model}
	}
	if model.selection.generation != expected_selection {
		return {}, false, Failure{code = .Stale_Selection}
	}
	if model.selection.disabled || model.selection.active.id == 0 {
		return {}, false, Failure{code = .Syntax_Disabled}
	}
	if span_count > MAX_SPANS {
		return {}, false, Failure{
			code = .Span_Limit,
			limit = MAX_SPANS,
			actual = u64(span_count),
		}
	}
	model.snapshot = Syntax_Snapshot {
		buffer_id = buffer_id,
		source_revision = source_revision,
		selection_generation = expected_selection,
		provider = model.selection.active,
		span_count = span_count,
		confirmed = true,
	}
	return model.snapshot, true, {}
}

model_close :: proc(model: ^Model) -> bool {
	if !model_live(model) do return false
	model^ = Model{closed = true}
	return true
}

model_valid :: proc(model: ^Model) -> bool {
	if !model_live(model) do return false
	factory := model_provider(model, model.selection.factory)
	if factory == nil || factory.state != .Confirmed do return false
	if model.selection.disabled {
		return model.selection.active == Provider_Handle{} && !model.snapshot.confirmed
	}
	active := model_provider(model, model.selection.active)
	if active == nil || active.state != .Confirmed do return false
	if model.snapshot.confirmed {
		return model.snapshot.selection_generation == model.selection.generation &&
			model.snapshot.provider == model.selection.active
	}
	return true
}

model_live :: proc(model: ^Model) -> bool {
	return model != nil && !model.closed && model.selection.generation != 0
}

model_provider :: proc(model: ^Model, handle: Provider_Handle) -> ^Provider {
	if model == nil || handle.id == 0 do return nil
	for &provider in model.providers {
		if provider.live && provider.handle == handle do return &provider
	}
	return nil
}
