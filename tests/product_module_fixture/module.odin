// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package product_module_fixture

import "../../src/product_module"
import "base:runtime"

FILE_MANAGEMENT_ROLE :: #config(ODRA_PRODUCT_MODULE_FILE_MANAGEMENT, false)
WORKSPACE_HIERARCHY_ROLE :: #config(ODRA_PRODUCT_MODULE_WORKSPACE_HIERARCHY, false)
STRUCTURED_DOCUMENT_ROLE :: #config(ODRA_PRODUCT_MODULE_STRUCTURED_DOCUMENT, false)

Fixture_Instance :: struct {
	host_call:  product_module.Host_Call,
	capability: u64,
	turns:      u64,
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
	value.role = fixture_role()
	identity := fixture_identity()
	value.identity_length = u16(copy(value.identity[:], identity))
	value.version_length = u16(copy(value.version[:], "1.0.0"))
	value.open = fixture_open
	value.call = fixture_call
	value.close = fixture_close
	descriptor^ = value
	return .Ok
}

fixture_role :: proc "contextless" () -> product_module.Role {
	if STRUCTURED_DOCUMENT_ROLE do return .Structured_Document
	if WORKSPACE_HIERARCHY_ROLE do return .Workspace_Hierarchy
	if FILE_MANAGEMENT_ROLE do return .File_Management
	return .Source_Control
}

fixture_identity :: proc "contextless" () -> string {
	if STRUCTURED_DOCUMENT_ROLE do return "fixture.structured-document"
	if WORKSPACE_HIERARCHY_ROLE do return "fixture.workspace-hierarchy"
	if FILE_MANAGEMENT_ROLE do return "fixture.file-management"
	return "fixture.source-control"
}

fixture_open :: proc "c" (
	host_call: product_module.Host_Call,
	capability: u64,
	instance: ^u64,
) -> product_module.Status {
	context = runtime.default_context()
	if host_call == nil || capability == 0 || instance == nil do return .Invalid_Argument
	state := new(Fixture_Instance)
	if state == nil do return .Failed
	state.host_call = host_call
	state.capability = capability
	instance^ = u64(uintptr(state))
	return .Ok
}

fixture_call :: proc "c" (
	instance: u64,
	operation: product_module.Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> product_module.Status {
	if instance == 0 || output_length == nil || input_length > product_module.MAX_CALL_BYTES ||
	   output_capacity > product_module.MAX_CALL_BYTES {
		return .Invalid_Argument
	}
	state := (^Fixture_Instance)(uintptr(instance))
	state.turns += 1
	if operation == .Activate || operation == .Invoke {
		status := state.host_call(
			state.capability,
			.Diagnostic,
			input,
			input_length,
			output,
			output_capacity,
			output_length,
		)
		return status
	}
	output_length^ = 0
	return .Ok
}

fixture_close :: proc "c" (instance: u64) -> product_module.Status {
	context = runtime.default_context()
	if instance == 0 do return .Invalid_Argument
	free((^Fixture_Instance)(uintptr(instance)))
	return .Ok
}
