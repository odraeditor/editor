// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:sys/linux"

@(private)
local_resource_identity :: proc(path: string) -> (Resource_ID, bool, i32) {
	path_buffer: [MAX_PATH_STORAGE_BYTES + 1]u8
	if len(path) == 0 || len(path) > MAX_PATH_STORAGE_BYTES {
		return {}, false, i32(linux.Errno.ENAMETOOLONG)
	}
	copy(path_buffer[:], transmute([]u8)path)
	stat: linux.Stat
	errno := linux.lstat(cstring(&path_buffer[0]), &stat)
	if errno != .NONE do return {}, false, i32(errno)
	identity := Resource_ID {
		provider = LOCAL_PROVIDER_ID,
		device = u64(stat.dev),
		inode = u64(stat.ino),
	}
	return identity, resource_id_valid(identity), 0
}
