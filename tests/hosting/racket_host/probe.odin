// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package racket_host_probe exposes the minimal C ABI used by the Racket-host probe.
package racket_host_probe

// odra_racket_host_probe_round_trip returns the successor of one signed scalar value.
@(export)
odra_racket_host_probe_round_trip :: proc "c" (input: i64) -> i64 {
	return input + 1
}

// odra_racket_host_probe_fill writes one bounded native query payload.
@(export)
odra_racket_host_probe_fill :: proc "c" (output: rawptr, length: u64) -> i32 {
	if output == nil || length > 1024 * 1024 {
		return 0
	}

	bytes := ([^]u8)(output)[:int(length)]
	for &value in bytes {
		value = 'a'
	}
	return 1
}

// odra_racket_host_probe_accept validates one transformed payload returned to Odin.
@(export)
odra_racket_host_probe_accept :: proc "c" (input: rawptr, length: u64) -> i32 {
	if input == nil || length > 1024 * 1024 {
		return 0
	}

	bytes := ([^]u8)(input)[:int(length)]
	for value in bytes {
		if value != 'a' {
			return 0
		}
	}
	return 1
}
