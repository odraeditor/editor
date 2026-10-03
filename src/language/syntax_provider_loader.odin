// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"
import "../language_bundle"
import "core:crypto/sha2"
import "core:dynlib"
import "core:os"

/* MAX_NATIVE_GRAMMAR_BYTES bounds one verified grammar shared library. */
MAX_NATIVE_GRAMMAR_BYTES :: 256 * MEBIBYTE

@(private)
Syntax_Grammar_Entrypoint :: proc "c" () -> rawptr

/* Syntax_Provider_Runtime owns one grammar library and all dependent values. */
Syntax_Provider_Runtime :: struct {
	record:           Syntax_Provider_Record,
	owner:            Tree_Sitter_Owner,
	status:           Syntax_Provider_Status,
	grammar_abi:      u32,
	language_version: u32,
	query_bytes:      u64,
	latest_failure:   Failure,
}

/* syntax_provider_load verifies before loading and transfers library ownership. */
syntax_provider_load :: proc(
	runtime: ^Syntax_Provider_Runtime,
	record: ^Syntax_Provider_Record,
	parser_generation: Parser_Generation,
	allocator := context.allocator,
	cancellation: Syntax_Provider_Cancellation = {},
) -> (ok: bool, failure: Failure) {
	if runtime == nil || record == nil || runtime.status == .Loaded {
		return false, syntax_provider_loader_failure(.Load_Grammar, .Invalid_Provider)
	}
	runtime^ = Syntax_Provider_Runtime {status = .Prepared}
	if syntax_provider_cancelled(cancellation) do return syntax_provider_load_reject(runtime, .Cancelled)
	if !syntax_native_authority_granted(record.authority) {
		return syntax_provider_load_reject(runtime, .Native_Grammar_Unauthorized)
	}
	if !syntax_provider_target_is_current(record.grammar.platform, record.grammar.architecture) {
		return syntax_provider_load_reject(runtime, .Unsupported_Platform)
	}
	path := syntax_artifact_path_view(&record.grammar.path)
	verified, verify_failure := syntax_artifact_verify(
		path,
		record.grammar.digest,
		record.grammar.size,
		MAX_NATIVE_GRAMMAR_BYTES,
		allocator,
		cancellation,
	)
	if !verified {
		runtime.status = .Failed
		runtime.latest_failure = verify_failure
		return false, verify_failure
	}
	if syntax_provider_cancelled(cancellation) do return syntax_provider_load_reject(runtime, .Cancelled)

	library, loaded := dynlib.load_library(path)
	if !loaded do return syntax_provider_load_reject(runtime, .Library_Load_Failed)
	entrypoint := syntax_entrypoint_view(&record.grammar.entrypoint)
	address, found := dynlib.symbol_address(library, entrypoint)
	if !found {
		_ = dynlib.unload_library(library)
		return syntax_provider_load_reject(runtime, .Grammar_Symbol_Missing)
	}
	entry := cast(Syntax_Grammar_Entrypoint)address
	language := entry()
	if language == nil {
		_ = dynlib.unload_library(library)
		return syntax_provider_load_reject(runtime, .Parser_Initialization)
	}
	abi := ts_language_abi_version(language)
	if abi < TREE_SITTER_MINIMUM_ABI || abi > TREE_SITTER_RUNTIME_ABI ||
	   abi < record.grammar.minimum_abi || abi > record.grammar.maximum_abi {
		_ = dynlib.unload_library(library)
		failure = syntax_provider_loader_failure(.Load_Grammar, .Grammar_ABI_Incompatible)
		failure.limit = u64(record.grammar.maximum_abi)
		failure.actual = u64(abi)
		runtime.status = .Failed
		runtime.latest_failure = failure
		return false, failure
	}
	language_version := abi
	if language_version < record.grammar.minimum_language_version ||
	   language_version > record.grammar.maximum_language_version {
		_ = dynlib.unload_library(library)
		failure = syntax_provider_loader_failure(.Load_Grammar, .Grammar_Language_Version_Incompatible)
		failure.limit = u64(record.grammar.maximum_language_version)
		failure.actual = u64(language_version)
		runtime.status = .Failed
		runtime.latest_failure = failure
		return false, failure
	}
	owner_ready, owner_failure := tree_sitter_owner_init_language(
		&runtime.owner,
		language,
		parser_generation,
		library,
		allocator,
	)
	if !owner_ready {
		owner_failure.operation = .Load_Grammar
		runtime.status = .Failed
		runtime.latest_failure = owner_failure
		return false, owner_failure
	}
	runtime.record = record^
	runtime.status = .Loaded
	runtime.grammar_abi = abi
	runtime.language_version = language_version
	return true, {}
}

/* syntax_provider_replace loads a candidate before releasing the active runtime. */
syntax_provider_replace :: proc(
	active: ^Syntax_Provider_Runtime,
	record: ^Syntax_Provider_Record,
	parser_generation: Parser_Generation,
	allocator := context.allocator,
	cancellation: Syntax_Provider_Cancellation = {},
) -> (ok: bool, failure: Failure) {
	if active == nil || active.status != .Loaded {
		return false, syntax_provider_loader_failure(.Replace, .Invalid_Provider)
	}
	candidate: Syntax_Provider_Runtime
	loaded, load_failure := syntax_provider_load(&candidate, record, parser_generation, allocator, cancellation)
	if !loaded do return false, load_failure
	closed, close_failure := syntax_provider_close(active)
	if !closed {
		_, _ = syntax_provider_close(&candidate)
		return false, close_failure
	}
	active^ = candidate
	return true, {}
}

/* syntax_provider_inspect copies state without foreign pointers or handles. */
syntax_provider_inspect :: proc(
	runtime: ^Syntax_Provider_Runtime,
) -> (inspection: Syntax_Provider_Inspection, ok: bool) {
	if runtime == nil || runtime.status == .Invalid do return {}, false
	parser_ready, library_owned := false, false
	if runtime.status == .Loaded {
		stats, inspected, _ := tree_sitter_owner_stats(&runtime.owner)
		parser_ready = inspected && stats.lifecycle == .Ready
		library_owned = runtime.owner.state != nil && !runtime.owner.closed
	}
	return Syntax_Provider_Inspection {
		status = runtime.status,
		identity = runtime.record.identity,
		language = runtime.record.language,
		grammar_digest = runtime.record.grammar.digest,
		grammar_abi = runtime.grammar_abi,
		language_version = runtime.language_version,
		query_count = runtime.record.query_count,
		mapping_count = runtime.record.mapping_count,
		query_bytes = runtime.query_bytes,
		parser_ready = parser_ready,
		library_owned = library_owned,
		latest_failure = runtime.latest_failure,
	}, true
}

/* syntax_provider_close releases parser values before unloading the grammar. */
syntax_provider_close :: proc(
	runtime: ^Syntax_Provider_Runtime,
) -> (ok: bool, failure: Failure) {
	if runtime == nil || runtime.status != .Loaded {
		return false, syntax_provider_loader_failure(.Close, .Invalid_Provider)
	}
	closed, close_failure := tree_sitter_owner_close(&runtime.owner)
	record := runtime.record
	runtime^ = Syntax_Provider_Runtime {record = record, status = .Closed}
	if !closed {
		close_failure.operation = .Close
		runtime.latest_failure = close_failure
		return false, close_failure
	}
	return true, {}
}

/* syntax_artifact_verify checks a regular file's exact size and SHA-256 digest. */
syntax_artifact_verify :: proc(
	path: string,
	expected_digest: [32]u8,
	expected_size: u64,
	maximum_size: u64,
	allocator := context.allocator,
	cancellation: Syntax_Provider_Cancellation = {},
) -> (ok: bool, failure: Failure) {
	bytes, loaded, load_failure := syntax_artifact_read_verified(
		path, expected_digest, expected_size, maximum_size, .Load_Grammar, allocator, cancellation,
	)
	if loaded do delete(bytes, allocator)
	return loaded, load_failure
}

@(private)
syntax_artifact_read_verified :: proc(
	path: string,
	expected_digest: [32]u8,
	expected_size: u64,
	maximum_size: u64,
	operation: Operation,
	allocator: runtime.Allocator,
	cancellation: Syntax_Provider_Cancellation,
) -> (bytes: []u8, ok: bool, failure: Failure) {
	if syntax_provider_cancelled(cancellation) {
		return nil, false, syntax_provider_loader_failure(operation, .Cancelled)
	}
	info, stat_error := os.lstat(path, context.temp_allocator)
	if stat_error != nil || info.type != .Regular {
		return nil, false, syntax_provider_loader_failure(operation, .Artifact_Missing)
	}
	if info.size < 0 || u64(info.size) != expected_size || expected_size > maximum_size {
		failure = syntax_provider_loader_failure(operation, .Artifact_Size_Mismatch)
		failure.limit = expected_size
		failure.actual = u64(max(info.size, 0))
		return nil, false, failure
	}
	file_bytes, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		if _, allocation_error := read_error.(runtime.Allocator_Error); allocation_error {
			return nil, false, syntax_provider_loader_failure(operation, .Allocation)
		}
		return nil, false, syntax_provider_loader_failure(operation, .Artifact_Missing)
	}
	bytes = file_bytes
	if syntax_provider_cancelled(cancellation) {
		delete(bytes, allocator)
		return nil, false, syntax_provider_loader_failure(operation, .Cancelled)
	}
	actual := syntax_bytes_digest(bytes)
	if actual != expected_digest {
		delete(bytes, allocator)
		return nil, false, syntax_provider_loader_failure(operation, .Artifact_Digest_Mismatch)
	}
	return bytes, true, {}
}

/* syntax_bytes_digest computes the SHA-256 identity used for immutable artifacts. */
syntax_bytes_digest :: proc(bytes: []u8) -> [32]u8 {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, bytes)
	digest: [32]u8
	sha2.final(&ctx, digest[:])
	return digest
}

@(private)
syntax_provider_target_is_current :: proc(
	platform: language_bundle.Bundle_Platform,
	architecture: language_bundle.Bundle_Architecture,
) -> bool {
	current_platform := language_bundle.Bundle_Platform.Invalid
	when ODIN_OS == .Linux do current_platform = .Linux
	when ODIN_OS == .Darwin do current_platform = .Darwin
	when ODIN_OS == .Windows do current_platform = .Windows
	current_architecture := language_bundle.Bundle_Architecture.Invalid
	when ODIN_ARCH == .amd64 do current_architecture = .X86_64
	when ODIN_ARCH == .arm64 do current_architecture = .Aarch64
	return platform == current_platform && architecture == current_architecture
}

@(private)
syntax_provider_load_reject :: proc(
	runtime: ^Syntax_Provider_Runtime,
	code: Failure_Code,
) -> (bool, Failure) {
	failure := syntax_provider_loader_failure(.Load_Grammar, code)
	if runtime != nil {
		runtime.status = .Failed
		runtime.latest_failure = failure
	}
	return false, failure
}

@(private)
syntax_provider_loader_failure :: proc(operation: Operation, code: Failure_Code) -> Failure {
	return Failure {operation = operation, code = code}
}

@(private)
syntax_provider_cancelled :: proc(cancellation: Syntax_Provider_Cancellation) -> bool {
	return cancellation.check != nil && cancellation.check(cancellation.user_data)
}
