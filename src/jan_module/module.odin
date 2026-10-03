// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_module

import "../product_module"
import "../jan_computation"
import "../jan_editing"
import "../jan_planning"
import "base:runtime"

Module_Instance :: struct {
	host_call:  product_module.Host_Call,
	capability: u64,
	active:     bool,
	configuration:             jan_editing.Editing_Configuration,
	planning_configuration:    jan_planning.Configuration,
	computation_configuration: jan_computation.Configuration,
	next_operation_id:         u64,
	next_rewrite_id:           u64,
	local_visibility:          jan_editing.Visibility_State,
	global_visibility:         jan_editing.Visibility_State,
	surface_target:            u64,
	presentation_generation:   u64,
	surface_active:            bool,
	surface_point_selection:   bool,
	surface_revision:          u64,
	surface_point_count:       u16,
	surface_points:            [256]u64,
}

@(export)
odra_product_module_entrypoint :: proc "c" (
	descriptor: ^product_module.Descriptor,
	descriptor_size: u64,
) -> product_module.Status {
	if descriptor == nil || descriptor_size != size_of(product_module.Descriptor) {
		return .Invalid_Argument
	}
	value: product_module.Descriptor
	value.struct_size = size_of(product_module.Descriptor)
	value.abi_minimum = product_module.ABI_VERSION
	value.abi_maximum = product_module.ABI_VERSION
	value.role = .Structured_Document
	value.identity_length = u16(copy(value.identity[:], "odra.jan"))
	value.version_length = u16(copy(value.version[:], "1.0.0"))
	value.open = module_open
	value.call = module_call
	value.close = module_close
	descriptor^ = value
	return .Ok
}

@(private)
module_open :: proc "c" (
	host_call: product_module.Host_Call,
	capability: u64,
	instance: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if host_call == nil || capability == 0 || instance == nil do return .Invalid_Argument
	state := new(Module_Instance)
	if state == nil do return .Failed
	state.host_call = host_call
	state.capability = capability
	instance^ = u64(uintptr(state))
	return .Ok
}

@(private)
module_call :: proc "c" (
	instance: u64,
	operation: product_module.Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 || output_length == nil || input_length > product_module.MAX_CALL_BYTES ||
	   output_capacity > product_module.MAX_CALL_BYTES {
		return .Invalid_Argument
	}
	_ = input
	_ = output
	output_length^ = 0
	state := (^Module_Instance)(uintptr(instance))
	switch operation {
	case .Activate:
		if !workflow_init(state) do return .Failed
		state.active = true
		return .Ok
	case .Deactivate:
		workflow_close(state)
		state.active = false
		return .Ok
	case .Invoke:
		if !state.active do return .Unavailable
		if input_length == 0 || input == nil do return .Invalid_Argument
		return workflow_invoke(state, ([^]u8)(input)[:int(input_length)])
	case .Select:
		if !state.active || input == nil || input_length != size_of(product_module.Selection_Request) {
			return .Invalid_Argument
		}
		selection := (^product_module.Selection_Request)(rawptr(input))
		if selection.schema_version != product_module.UI_LIST_SCHEMA_VERSION || selection.item_id == 0 {
			return .Invalid_Argument
		}
		return workflow_select_surface(state, selection.item_id)
	case .Input:
		if input_length == 0 || input == nil do return .Invalid_Argument
		return workflow_input(state, ([^]u8)(input)[:int(input_length)])
	case .Step, .Inspect, .Configure:
		return .Unavailable if !state.active else .Ok
	case .Invalid:
		return .Invalid_Argument
	}
	return .Invalid_Argument
}

@(private)
module_close :: proc "c" (instance: u64) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 do return .Invalid_Argument
	state := (^Module_Instance)(uintptr(instance))
	workflow_close(state)
	free(state)
	return .Ok
}
