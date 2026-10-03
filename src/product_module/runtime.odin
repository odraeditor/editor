// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package product_module

import "core:crypto/sha2"
import "core:dynlib"
import "core:os"
import "core:path/filepath"

/* Runtime owns one verified library and one optional active module instance. */
Runtime :: struct {
	library:        dynlib.Library,
	descriptor:     Descriptor,
	instance:       u64,
	lifecycle:      Lifecycle,
	latest_failure: Failure,
}

/* load verifies one artifact before resolving and validating its entrypoint. */
load :: proc(runtime: ^Runtime, artifact: ^Artifact) -> (bool, Failure) {
	if runtime == nil || artifact == nil || runtime.lifecycle != .Invalid || !artifact_is_valid(artifact) {
		return false, runtime_fail(runtime, {code = .Invalid_Artifact})
	}
	path := artifact_path(artifact)
	info, info_error := os.stat(path, context.temp_allocator)
	if info_error != nil || info.type != .Regular {
		return false, runtime_fail(runtime, {code = .Artifact_Missing})
	}
	defer os.file_info_delete(info, context.temp_allocator)
	if u64(info.size) != artifact.size {
		return false, runtime_fail(runtime, {code = .Artifact_Size, limit = artifact.size, actual = u64(info.size)})
	}
	content, read_error := os.read_entire_file(path, context.allocator)
	if read_error != nil {
		return false, runtime_fail(runtime, {code = .Artifact_Missing})
	}
	defer delete(content)
	digest := bytes_digest(content)
	if digest != artifact.digest {
		return false, runtime_fail(runtime, {code = .Artifact_Digest})
	}
	library, loaded := dynlib.load_library(path)
	if !loaded {
		return false, runtime_fail(runtime, {code = .Library_Load})
	}
	entry_address, found := dynlib.symbol_address(library, artifact_entrypoint(artifact))
	if !found {
		_ = dynlib.unload_library(library)
		return false, runtime_fail(runtime, {code = .Symbol_Missing})
	}
	entry := cast(Entrypoint)entry_address
	descriptor: Descriptor
	status := entry(&descriptor, size_of(Descriptor))
	if status != .Ok {
		_ = dynlib.unload_library(library)
		return false, runtime_fail(runtime, {code = .Descriptor, status = status})
	}
	valid, descriptor_failure := descriptor_is_valid(&descriptor, artifact.role)
	if !valid {
		_ = dynlib.unload_library(library)
		return false, runtime_fail(runtime, descriptor_failure)
	}
	if descriptor_identity(&descriptor) != artifact_identity(artifact) {
		_ = dynlib.unload_library(library)
		return false, runtime_fail(runtime, {code = .Identity})
	}
	if descriptor_version(&descriptor) != artifact_version(artifact) {
		_ = dynlib.unload_library(library)
		return false, runtime_fail(runtime, {code = .Version})
	}
	if descriptor.abi_minimum != artifact.abi_minimum ||
	   descriptor.abi_maximum != artifact.abi_maximum {
		_ = dynlib.unload_library(library)
		return false, runtime_fail(runtime, {code = .ABI})
	}
	runtime.library = library
	runtime.descriptor = descriptor
	runtime.lifecycle = .Loaded
	return true, {}
}

/* open creates one inactive instance using only the declared host callback. */
open :: proc(runtime: ^Runtime, host_call: Host_Call, capability: u64) -> (bool, Failure) {
	if runtime == nil || runtime.lifecycle != .Loaded || host_call == nil || capability == 0 {
		return false, runtime_fail(runtime, {code = .Open, status = .Invalid_Argument})
	}
	instance: u64
	status := runtime.descriptor.open(host_call, capability, &instance)
	if status != .Ok || instance == 0 {
		return false, runtime_fail(runtime, {code = .Open, status = status})
	}
	runtime.instance = instance
	runtime.lifecycle = .Active
	return true, {}
}

/* call executes one bounded operation without exposing the foreign instance. */
call :: proc(
	runtime: ^Runtime,
	operation: Operation,
	input: []u8,
	output: []u8,
) -> (written: int, ok: bool, failure: Failure) {
	if runtime == nil || runtime.lifecycle != .Active || operation == .Invalid ||
	   u64(len(input)) > MAX_CALL_BYTES || u64(len(output)) > MAX_CALL_BYTES {
		failure = runtime_fail(runtime, {code = .Call, status = .Invalid_Argument})
		return
	}
	output_length: u64
	status := runtime.descriptor.call(
		runtime.instance,
		operation,
		raw_data(input),
		u64(len(input)),
		raw_data(output),
		u64(len(output)),
		&output_length,
	)
	if status != .Ok {
		failure = runtime_reject_call(runtime, {code = .Call, status = status})
		return
	}
	if output_length > u64(len(output)) {
		failure = runtime_fail(runtime, {code = .Call, status = .Limit, limit = u64(len(output)), actual = output_length})
		return
	}
	return int(output_length), true, {}
}

/* close releases the instance before unloading its owning library. */
close :: proc(runtime: ^Runtime) -> (bool, Failure) {
	if runtime == nil || runtime.lifecycle == .Invalid || runtime.lifecycle == .Closed {
		return false, runtime_fail(runtime, {code = .Close, status = .Invalid_Argument})
	}
	if runtime.instance != 0 {
		status := runtime.descriptor.close(runtime.instance)
		if status != .Ok {
			return false, runtime_fail(runtime, {code = .Close, status = status})
		}
		runtime.instance = 0
	}
	if runtime.library != nil && !dynlib.unload_library(runtime.library) {
		return false, runtime_fail(runtime, {code = .Close, status = .Failed})
	}
	runtime.library = nil
	runtime.lifecycle = .Closed
	return true, {}
}

/* inspect copies module identity and lifecycle without a library or instance handle. */
inspect :: proc(runtime: ^Runtime) -> (Inspection, bool) {
	if runtime == nil || runtime.lifecycle == .Invalid do return {}, false
	return Inspection {
		lifecycle = runtime.lifecycle,
		role = runtime.descriptor.role,
		identity = runtime.descriptor.identity,
		identity_length = runtime.descriptor.identity_length,
		version = runtime.descriptor.version,
		version_length = runtime.descriptor.version_length,
		abi_minimum = runtime.descriptor.abi_minimum,
		abi_maximum = runtime.descriptor.abi_maximum,
		latest_failure = runtime.latest_failure,
	}, true
}

@(private)
artifact_is_valid :: proc(artifact: ^Artifact) -> bool {
	path := artifact_path(artifact)
	entrypoint := artifact_entrypoint(artifact)
	identity := artifact_identity(artifact)
	version := artifact_version(artifact)
	return len(path) > 0 && filepath.is_abs(path) && len(entrypoint) > 0 &&
	       semantic_identity_is_valid(transmute([]u8)identity) &&
	       semantic_version_is_valid(transmute([]u8)version) &&
	       artifact.size > 0 && artifact.size <= MAX_ARTIFACT_BYTES &&
	       artifact.abi_minimum > 0 && artifact.abi_minimum <= artifact.abi_maximum &&
	       ABI_VERSION >= artifact.abi_minimum && ABI_VERSION <= artifact.abi_maximum &&
	       artifact.role != .Invalid
}

@(private)
bytes_digest :: proc(bytes: []u8) -> [32]u8 {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	digest: [32]u8
	sha2.final(&ctx, digest[:])
	return digest
}

@(private)
runtime_fail :: proc(runtime: ^Runtime, failure: Failure) -> Failure {
	if runtime != nil {
		runtime.latest_failure = failure
		if runtime.lifecycle != .Closed do runtime.lifecycle = .Failed
	}
	return failure
}

@(private)
runtime_reject_call :: proc(runtime: ^Runtime, failure: Failure) -> Failure {
	if runtime != nil {
		runtime.latest_failure = failure
		if failure.status == .Failed || failure.status == .Incompatible_ABI {
			runtime.lifecycle = .Failed
		}
	}
	return failure
}
