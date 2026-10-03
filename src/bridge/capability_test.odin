// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../editor"
import edit_transaction "../transaction"
import "core:testing"

/* Verifies checked inspection and stale-generation rejection without pointer exposure. */
@(test)
capabilities_copy_requested_revision :: proc(t: ^testing.T) {
	registry: Buffer_Capability_Registry
	initialized, init_failure := buffer_capability_registry_init(&registry, Registry_ID(7))
	testing.expect_value(t, init_failure.code, Failure_Code.None)
	testing.expect(t, initialized)

	buffer: editor.Buffer
	buffer_ready, buffer_failure := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(9),
		"hello odra",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect_value(t, buffer_failure.code, editor.Failure_Code.None)
	testing.expect(t, buffer_ready)
	if !buffer_ready {
		return
	}
	defer editor.buffer_close(&buffer)

	capability, identity, acquired, acquire_failure := buffer_capability_acquire(&registry, &buffer)
	testing.expect_value(t, acquire_failure.code, Failure_Code.None)
	testing.expect(t, acquired)
	testing.expect_value(t, identity.buffer_id, editor.Buffer_ID(9))
	testing.expect_value(t, identity.revision, editor.Revision(0))
	testing.expect_value(t, identity.text_bytes, u64(10))

	observed: [4]byte
	copied, inspected, inspect_failure := buffer_capability_inspect(
		&registry,
		capability,
		identity.buffer_id,
		identity.revision,
		Byte_Range {start = 6, end = 10},
		observed[:],
	)
	testing.expect_value(t, inspect_failure.code, Failure_Code.None)
	testing.expect(t, inspected)
	testing.expect_value(t, copied, u64(4))
	testing.expect_value(t, string(observed[:]), "odra")

	_, inspected, inspect_failure = buffer_capability_inspect(
		&registry,
		capability,
		editor.Buffer_ID(10),
		identity.revision,
		Byte_Range {start = 6, end = 10},
		observed[:],
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Wrong_Buffer)

	_, inspected, inspect_failure = buffer_capability_inspect(
		&registry,
		capability,
		identity.buffer_id,
		editor.Revision(1),
		Byte_Range {start = 6, end = 10},
		observed[:],
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Stale_Revision)

	closed, close_failure := buffer_capability_registry_close(&registry)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.Retained_Capabilities)
	testing.expect_value(t, close_failure.actual, u64(1))

	old_capability := capability
	released, release_failure := buffer_capability_release(&registry, &capability)
	testing.expect_value(t, release_failure.code, Failure_Code.None)
	testing.expect(t, released)
	testing.expect_value(t, capability, Buffer_Capability(0))

	_, inspected, inspect_failure = buffer_capability_inspect(
		&registry,
		old_capability,
		identity.buffer_id,
		identity.revision,
		Byte_Range {start = 6, end = 10},
		observed[:],
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Stale_Capability)

	new_capability, _, reacquired, _ := buffer_capability_acquire(&registry, &buffer)
	testing.expect(t, reacquired)
	testing.expect(t, new_capability != old_capability)

	other_registry: Buffer_Capability_Registry
	initialized, init_failure = buffer_capability_registry_init(&other_registry, Registry_ID(8))
	testing.expect(t, initialized)
	_, inspected, inspect_failure = buffer_capability_inspect(
		&other_registry,
		new_capability,
		identity.buffer_id,
		identity.revision,
		Byte_Range {start = 6, end = 10},
		observed[:],
	)
	testing.expect(t, !inspected)
	testing.expect_value(t, inspect_failure.code, Failure_Code.Wrong_Registry)
	closed, close_failure = buffer_capability_registry_close(&other_registry)
	testing.expect(t, closed)

	released, release_failure = buffer_capability_release(&registry, &new_capability)
	testing.expect(t, released)

	closed, close_failure = buffer_capability_registry_close(&registry)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect(t, closed)
}

/* Verifies checked bridge editing delegates publication to one retained transaction root. */
@(test)
publication_uses_transaction_coordinator :: proc(t: ^testing.T) {
	registry: Buffer_Capability_Registry
	initialized, _ := buffer_capability_registry_init(&registry, Registry_ID(21))
	testing.expect(t, initialized)
	buffer: editor.Buffer
	buffer_ready, _ := editor.buffer_init(
		&buffer,
		editor.Buffer_ID(22),
		"hello odra",
		editor.Allocator_Set {
			persistent = context.allocator,
			temporary = context.temp_allocator,
		},
	)
	testing.expect(t, buffer_ready)
	capability, identity, acquired, _ := buffer_capability_acquire(&registry, &buffer)
	testing.expect(t, acquired)
	result, published, publish_failure := buffer_capability_splice(
		&registry,
		capability,
		identity.buffer_id,
		identity.revision,
		Byte_Range{start = 6, end = 10},
		"ODRA",
		Publication_Request {
			transaction_id = edit_transaction.Transaction_ID(22),
			undo_unit_id = edit_transaction.Undo_Unit_ID(22),
			origin = edit_transaction.Origin{kind = .Racket, descriptor = "bridge-test"},
			command = "uppercase-range",
			persistent_allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
	)
	testing.expectf(t, published, "publication failed with %v", publish_failure.code)
	testing.expect_value(t, result.commit.transaction_id, edit_transaction.Transaction_ID(22))
	testing.expect_value(t, result.commit.result_revision, editor.Revision(1))
	testing.expect_value(t, len(result.commit.splices), 1)
	observed: [10]byte
	_, inspected, _ := editor.buffer_inspect(&buffer, 0, 10, observed[:])
	testing.expect(t, inspected)
	testing.expect_value(t, string(observed[:]), "hello ODRA")
	publication_result_close(&result)
	buffer_capability_release(&registry, &capability)
	buffer_capability_registry_close(&registry)
	editor.buffer_close(&buffer)
}
