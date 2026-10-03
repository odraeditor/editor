// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package product_module_focused

import "../../src/product_module"
import "core:crypto/sha2"
import "core:os"
import "core:testing"

FIXTURE_PATH :: #config(
	ODRA_PRODUCT_MODULE_FIXTURE,
	"../../.build/product-module-fixture/libodra-product-module-fixture.so",
)
FILE_MANAGEMENT_FIXTURE_PATH :: #config(
	ODRA_PRODUCT_MODULE_FILE_MANAGEMENT_FIXTURE,
	"../../.build/product-module-fixture/libodra-product-module-file-management-fixture.so",
)
WORKSPACE_HIERARCHY_FIXTURE_PATH :: #config(
	ODRA_PRODUCT_MODULE_WORKSPACE_HIERARCHY_FIXTURE,
	"../../.build/product-module-fixture/libodra-product-module-workspace-hierarchy-fixture.so",
)
STRUCTURED_DOCUMENT_FIXTURE_PATH :: #config(
	ODRA_PRODUCT_MODULE_STRUCTURED_DOCUMENT_FIXTURE,
	"../../.build/product-module-fixture/libodra-product-module-structured-document-fixture.so",
)

@(test)
/* product_module_runtime_verifies_loads_invokes_and_closes_fixture verifies the public ABI lifecycle. */
product_module_runtime_verifies_loads_invokes_and_closes_fixture :: proc(t: ^testing.T) {
	artifact := fixture_artifact(t)
	runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&runtime, &artifact)
	testing.expect(t, loaded)
	testing.expect_value(t, load_failure.code, product_module.Failure_Code.None)
	inspection, inspected := product_module.inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.lifecycle, product_module.Lifecycle.Loaded)
	testing.expect_value(t, inspection.role, product_module.Role.Source_Control)
	testing.expect_value(t, string(inspection.identity[:inspection.identity_length]), "fixture.source-control")

	opened, open_failure := product_module.open(&runtime, fixture_host_call, 17)
	testing.expect(t, opened)
	testing.expect_value(t, open_failure.code, product_module.Failure_Code.None)
	output: [64]u8
	written, called, call_failure := product_module.call(
		&runtime,
		.Invoke,
		transmute([]u8)(string("status")),
		output[:],
	)
	testing.expect(t, called)
	testing.expect_value(t, call_failure.code, product_module.Failure_Code.None)
	testing.expect_value(t, string(output[:written]), "status")

	closed, close_failure := product_module.close(&runtime)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, product_module.Failure_Code.None)
	inspection, inspected = product_module.inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.lifecycle, product_module.Lifecycle.Closed)
}

@(test)
/* product_module_runtime_rejects_integrity_symbol_abi_and_role_mismatches verifies load containment. */
product_module_runtime_rejects_integrity_symbol_abi_and_role_mismatches :: proc(t: ^testing.T) {
	artifact := fixture_artifact(t)

	tampered := artifact
	tampered.digest[0] = tampered.digest[0] ~ 0xff
	expect_load_failure(t, &tampered, .Artifact_Digest)

	missing_symbol := artifact
	missing_symbol.entrypoint_length = u16(copy(
		missing_symbol.entrypoint[:],
		"odra_missing_entrypoint",
	))
	expect_load_failure(t, &missing_symbol, .Symbol_Missing)

	wrong_abi := artifact
	wrong_abi.abi_minimum = product_module.ABI_VERSION + 1
	wrong_abi.abi_maximum = product_module.ABI_VERSION + 1
	expect_load_failure(t, &wrong_abi, .Invalid_Artifact)

	wrong_role := artifact
	wrong_role.role = .Invalid
	expect_load_failure(t, &wrong_role, .Invalid_Artifact)
}

@(test)
/* product_module_runtime_accepts_independent_replacements_for_every_public_role verifies role-neutral loading. */
product_module_runtime_accepts_independent_replacements_for_every_public_role :: proc(t: ^testing.T) {
	expect_replacement(t, FIXTURE_PATH, "fixture.source-control", .Source_Control)
	expect_replacement(t, FILE_MANAGEMENT_FIXTURE_PATH, "fixture.file-management", .File_Management)
	expect_replacement(
		t,
		WORKSPACE_HIERARCHY_FIXTURE_PATH,
		"fixture.workspace-hierarchy",
		.Workspace_Hierarchy,
	)
	expect_replacement(
		t,
		STRUCTURED_DOCUMENT_FIXTURE_PATH,
		"fixture.structured-document",
		.Structured_Document,
	)
}

expect_replacement :: proc(
	t: ^testing.T,
	path, identity: string,
	role: product_module.Role,
) {
	artifact := artifact_for(t, path, identity, role)
	runtime: product_module.Runtime
	loaded, load_failure := product_module.load(&runtime, &artifact)
	testing.expect(t, loaded)
	testing.expect_value(t, load_failure.code, product_module.Failure_Code.None)
	if !loaded do return
	inspection, inspected := product_module.inspect(&runtime)
	testing.expect(t, inspected)
	testing.expect_value(t, inspection.role, role)
	testing.expect_value(
		t,
		string(inspection.identity[:inspection.identity_length]),
		identity,
	)
	closed, close_failure := product_module.close(&runtime)
	testing.expect(t, closed)
	testing.expect_value(t, close_failure.code, product_module.Failure_Code.None)
}

fixture_host_call :: proc "c" (
	capability: u64,
	operation: product_module.Host_Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> product_module.Status {
	if capability != 17 || operation != .Diagnostic || output_length == nil ||
	   input_length > output_capacity {
		return .Denied
	}
	if input_length > 0 {
		if input == nil || output == nil do return .Invalid_Argument
		copy(([^]u8)(output)[:int(output_capacity)], ([^]u8)(input)[:int(input_length)])
	}
	output_length^ = input_length
	return .Ok
}

fixture_artifact :: proc(t: ^testing.T) -> product_module.Artifact {
	return artifact_for(t, FIXTURE_PATH, "fixture.source-control", .Source_Control)
}

artifact_for :: proc(
	t: ^testing.T,
	path, identity: string,
	role: product_module.Role,
) -> product_module.Artifact {
	content, read_error := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_error == nil)
	defer delete(content)
	artifact: product_module.Artifact
	artifact.identity_length = u16(copy(artifact.identity[:], identity))
	artifact.version_length = u16(copy(artifact.version[:], "1.0.0"))
	artifact.path_length = u16(copy(artifact.path[:], path))
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, content)
	sha2.final(&ctx, artifact.digest[:])
	artifact.size = u64(len(content))
	artifact.entrypoint_length = u16(copy(
		artifact.entrypoint[:],
		"odra_product_module_entrypoint",
	))
	artifact.abi_minimum = product_module.ABI_VERSION
	artifact.abi_maximum = product_module.ABI_VERSION
	artifact.role = role
	return artifact
}

expect_load_failure :: proc(
	t: ^testing.T,
	artifact: ^product_module.Artifact,
	expected: product_module.Failure_Code,
) {
	runtime: product_module.Runtime
	loaded, failure := product_module.load(&runtime, artifact)
	testing.expect(t, !loaded)
	testing.expect_value(t, failure.code, expected)
}
