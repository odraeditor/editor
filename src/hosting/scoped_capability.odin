// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package hosting

/* Scoped_Capability_Kind identifies the typed facade using the shared transport. */
Scoped_Capability_Kind :: enum i32 {
	Transaction    = 1,
	Transfer       = 2,
	Search         = 3,
	Buffer_Session = 4,
	Reserved_5     = 5,
	Layout         = 6,
	UI_Role        = 7,
	Theme          = 8,
	Structural     = 9,
	Language_Service = 10,
	Result = 11,
	Status_Bar = 12,
	Terminal = 13,
}

/*
Scoped_Capability_Callback_Procedure serves one synchronous bounded domain operation.
The generation and token are valid only for the active owner-thread call extent.
*/
Scoped_Capability_Callback_Procedure :: proc "c" (
	user_data: rawptr,
	kind: Scoped_Capability_Kind,
	generation, token, domain_context: u64,
	operation: i32,
	arg0, arg1: u64,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length, value: ^u64,
	failure_code: ^u32,
	limit, actual: ^u64,
) -> i32
