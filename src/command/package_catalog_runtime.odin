// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "base:runtime"
import endian "core:encoding/endian"

/* PACKAGE_CATALOG_RUNTIME_SCHEMA_VERSION identifies the copied runtime contract. */
PACKAGE_CATALOG_RUNTIME_SCHEMA_VERSION :: u64(1)
/* PACKAGE_CATALOG_RUNTIME_REQUEST_HEADER_BYTES is the fixed request prefix. */
PACKAGE_CATALOG_RUNTIME_REQUEST_HEADER_BYTES :: 40
/* PACKAGE_CATALOG_RUNTIME_RESULT_HEADER_BYTES is the fixed result prefix. */
PACKAGE_CATALOG_RUNTIME_RESULT_HEADER_BYTES :: 56
/* MAX_PACKAGE_CATALOG_RUNTIME_ARGUMENT_BYTES bounds one prompt value. */
MAX_PACKAGE_CATALOG_RUNTIME_ARGUMENT_BYTES :: 4096

/* Package_Catalog_Runtime_Action selects one catalog runtime operation. */
Package_Catalog_Runtime_Action :: enum u64 {
	Invalid,
	List,
	Preview_Add,
	Add,
	Disable,
	Remove,
	Refresh,
	Search,
	Describe,
	Doctor,
	Package_List,
	Package_Discover,
	Package_Describe,
	Package_Install,
	Package_Enable,
	Package_Disable,
	Package_Update,
	Package_Rollback,
	Package_Remove,
	Package_Cleanup,
	Package_Doctor,
}

/* Package_Catalog_Runtime_Status identifies one structured runtime result. */
Package_Catalog_Runtime_Status :: enum u64 {
	Invalid,
	Success,
	Confirmation,
	Failure,
}

/* Package_Catalog_Runtime_Result owns copied result text until explicit close. */
Package_Catalog_Runtime_Result :: struct {
	state:       rawptr,
	status:      Package_Catalog_Runtime_Status,
	generation:  u64,
	item_count:  u64,
	identity:    string,
	detail:      string,
}

@(private)
Package_Catalog_Runtime_Result_State :: struct {
	storage:   []byte,
	allocator: runtime.Allocator,
}

/* package_catalog_runtime_command executes one bounded embedded-runtime request. */
package_catalog_runtime_command :: proc(
	racket_runtime: ^hosting.Runtime,
	configuration_root: string,
	action: Package_Catalog_Runtime_Action,
	argument: string,
	confirmed: bool,
	allocator: runtime.Allocator,
) -> (Package_Catalog_Runtime_Result, bool, Failure_Context) {
	if racket_runtime == nil || len(configuration_root) == 0 || action == .Invalid ||
	   len(argument) > MAX_PACKAGE_CATALOG_RUNTIME_ARGUMENT_BYTES ||
	   ((action != .List && action != .Doctor && action != .Package_List &&
	     action != .Package_Discover &&
	     action != .Package_Cleanup && action != .Package_Doctor) &&
	    len(argument) == 0) {
		return {}, false, Failure_Context{code = .Invalid_Request}
	}
	request_length := PACKAGE_CATALOG_RUNTIME_REQUEST_HEADER_BYTES + len(argument)
	request, request_error := make([]byte, request_length, allocator)
	if request_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit}
	}
	defer delete(request, allocator)
	values := [?]u64 {
		PACKAGE_CATALOG_RUNTIME_SCHEMA_VERSION,
		u64(action),
		u64(len(argument)),
		1 if confirmed else 0,
		0,
	}
	for value, index in values {
		assert(endian.put_u64(request[index * 8:], .Little, value))
	}
	copy(
		request[PACKAGE_CATALOG_RUNTIME_REQUEST_HEADER_BYTES:],
		transmute([]u8)argument,
	)
	output, output_error := make(
		[]byte,
		hosting.MAX_PACKAGE_CATALOG_COMMAND_BYTES,
		allocator,
	)
	if output_error != nil {
		return {}, false, Failure_Context{code = .Temporary_Memory_Limit}
	}
	defer delete(output, allocator)
	output_length, transferred, transfer_failure := hosting.runtime_package_catalog_command(
		racket_runtime,
		configuration_root,
		request,
		output,
	)
	if !transferred {
		return {}, false, hosting_failure_context({}, transfer_failure)
	}
	result, decoded := package_catalog_runtime_result_decode(
		output[:int(output_length)],
		action,
		allocator,
	)
	if !decoded {
		return {}, false, Failure_Context{code = .Wrong_Result}
	}
	return result, true, {}
}

/* package_catalog_runtime_result_close releases one copied runtime result. */
package_catalog_runtime_result_close :: proc(result: ^Package_Catalog_Runtime_Result) -> bool {
	if result == nil || result.state == nil do return false
	state := (^Package_Catalog_Runtime_Result_State)(result.state)
	allocator := state.allocator
	delete(state.storage, allocator)
	free(state, allocator)
	result^ = {}
	return true
}

@(private)
package_catalog_runtime_result_decode :: proc(
	input: []byte,
	action: Package_Catalog_Runtime_Action,
	allocator: runtime.Allocator,
) -> (result: Package_Catalog_Runtime_Result, ok: bool) {
	if len(input) < PACKAGE_CATALOG_RUNTIME_RESULT_HEADER_BYTES do return {}, false
	header: [7]u64
	for &value, index in header {
		value, ok = endian.get_u64(input[index * 8:], .Little)
		if !ok do return {}, false
	}
	if header[0] != PACKAGE_CATALOG_RUNTIME_SCHEMA_VERSION ||
	   header[1] != u64(action) ||
	   header[2] < u64(Package_Catalog_Runtime_Status.Success) ||
	   header[2] > u64(Package_Catalog_Runtime_Status.Failure) ||
	   header[5] > MAX_PACKAGE_CATALOG_RUNTIME_ARGUMENT_BYTES ||
	   header[6] > hosting.MAX_PACKAGE_CATALOG_COMMAND_BYTES ||
	   u64(PACKAGE_CATALOG_RUNTIME_RESULT_HEADER_BYTES) + header[5] + header[6] !=
	   u64(len(input)) {
		return {}, false
	}
	state, state_error := new(Package_Catalog_Runtime_Result_State, allocator)
	if state_error != nil do return {}, false
	state.allocator = allocator
	state.storage, state_error = make([]byte, len(input), allocator)
	if state_error != nil {
		free(state, allocator)
		return {}, false
	}
	copy(state.storage, input)
	text := state.storage[PACKAGE_CATALOG_RUNTIME_RESULT_HEADER_BYTES:]
	identity_end := int(header[5])
	result = {
		state = state,
		status = Package_Catalog_Runtime_Status(header[2]),
		generation = header[3],
		item_count = header[4],
		identity = string(text[:identity_end]),
		detail = string(text[identity_end:]),
	}
	return result, true
}
