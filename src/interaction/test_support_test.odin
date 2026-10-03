// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

@(private)
test_command_route :: proc(name: string) -> Command_Route {
	hash := u32(2_166_136_261)
	for byte in transmute([]u8)name {
		hash = (hash ~ u32(byte)) * 16_777_619
	}
	provider := u16(hash >> 16)
	operation := u16(hash)
	if provider == 0 {
		provider = 1
	}
	if operation == 0 {
		operation = 1
	}
	return {provider = Command_Provider_ID(provider), operation = operation}
}
