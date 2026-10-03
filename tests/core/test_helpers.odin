// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package core_tests

import "../../src/editor"
import "core:testing"

@(private)
expect_buffer_text :: proc(t: ^testing.T, buffer: ^editor.Buffer, expected: string) {
	observed := make([]byte, len(expected))
	defer delete(observed)
	_, ok, failure := editor.buffer_inspect(
		buffer,
		editor.Byte_Offset(0),
		editor.Byte_Offset(len(expected)),
		observed,
	)
	testing.expect(t, ok)
	testing.expect_value(t, failure.code, editor.Failure_Code.None)
	testing.expect_value(t, string(observed), expected)
}

@(private)
apply_record :: proc(
	base: string,
	start, removed_bytes: u64,
	replacement: string,
) -> string {
	result_length := len(base) - int(removed_bytes) + len(replacement)
	result := make([]byte, result_length)
	prefix := int(start)
	copy(result[:prefix], base[:prefix])
	copy(result[prefix:prefix + len(replacement)], replacement)
	copy(
		result[prefix + len(replacement):],
		base[prefix + int(removed_bytes):],
	)
	return string(result)
}
