// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package document

import "base:runtime"
import "core:sys/linux"

@(private)
Platform_Handle :: distinct i32

@(private)
Platform_File_Kind :: enum u8 {
	Unknown,
	Regular,
	Directory,
	Symbolic_Link,
	Other,
}

@(private)
Platform_Error_Code :: enum u8 {
	None,
	Not_Found,
	Exists,
	Permission,
	Interrupted,
	Other,
}

@(private)
Platform_Error :: struct {
	code:          Platform_Error_Code,
	platform_code: i32,
}

@(private)
Platform_Metadata :: struct {
	kind:                 Platform_File_Kind,
	identity:             File_Identity,
	size:                 u64,
	modified_seconds:     i64,
	modified_nanoseconds: i32,
	mode:                 u32,
}

@(private)
Open_IO :: struct {
	inspect:        proc(path: string, follow: bool, allocator: runtime.Allocator) -> (Platform_Metadata, Platform_Error),
	open_read:      proc(path: string, allocator: runtime.Allocator) -> (Platform_Handle, Platform_Error),
	inspect_handle: proc(handle: Platform_Handle) -> (Platform_Metadata, Platform_Error),
	read:           proc(handle: Platform_Handle, destination: []u8) -> (int, Platform_Error),
	close:          proc(handle: Platform_Handle) -> Platform_Error,
}

@(private)
Save_IO :: struct {
	inspect:          proc(path: string, follow: bool, allocator: runtime.Allocator) -> (Platform_Metadata, Platform_Error),
	create_exclusive: proc(path: string, mode: u32) -> (Platform_Handle, Platform_Error),
	set_mode:         proc(handle: Platform_Handle, mode: u32) -> Platform_Error,
	write:            proc(handle: Platform_Handle, source: []u8) -> (int, Platform_Error),
	sync:             proc(handle: Platform_Handle) -> Platform_Error,
	close:            proc(handle: Platform_Handle) -> Platform_Error,
	rename:           proc(old_path, new_path: string) -> Platform_Error,
	open_directory:   proc(path: string) -> (Platform_Handle, Platform_Error),
	unlink:           proc(path: string) -> Platform_Error,
}

@(private)
linux_open_io :: proc() -> Open_IO {
	return Open_IO {
		inspect = linux_inspect,
		open_read = linux_open_read,
		inspect_handle = linux_inspect_handle,
		read = linux_read,
		close = linux_close,
	}
}

@(private)
linux_save_io :: proc() -> Save_IO {
	return Save_IO {
		inspect = linux_inspect,
		create_exclusive = linux_create_exclusive,
		set_mode = linux_set_mode,
		write = linux_write,
		sync = linux_sync,
		close = linux_close,
		rename = linux_rename,
		open_directory = linux_open_directory,
		unlink = linux_unlink,
	}
}

@(private)
linux_inspect :: proc(
	path: string,
	follow: bool,
	allocator: runtime.Allocator,
) -> (Platform_Metadata, Platform_Error) {
	_ = allocator
	path_buffer: [4_097]u8
	if len(path) == 0 || len(path) >= len(path_buffer) {
		return {}, Platform_Error{code = .Other, platform_code = i32(linux.Errno.ENAMETOOLONG)}
	}
	copy(path_buffer[:], path)
	cpath := cstring(&path_buffer[0])
	stat: linux.Stat
	errno := linux.stat(cpath, &stat) if follow else linux.lstat(cpath, &stat)
	if errno != .NONE {
		return {}, linux_platform_error(errno)
	}
	return linux_metadata(stat), {}
}

@(private)
linux_open_read :: proc(
	path: string,
	allocator: runtime.Allocator,
) -> (Platform_Handle, Platform_Error) {
	_ = allocator
	path_buffer: [4_097]u8
	if len(path) == 0 || len(path) >= len(path_buffer) {
		return Platform_Handle(-1), Platform_Error{code = .Other, platform_code = i32(linux.Errno.ENAMETOOLONG)}
	}
	copy(path_buffer[:], path)
	cpath := cstring(&path_buffer[0])
	fd, errno := linux.open(cpath, {.NOFOLLOW, .CLOEXEC, .LARGEFILE})
	if errno != .NONE {
		return Platform_Handle(-1), linux_platform_error(errno)
	}
	return Platform_Handle(fd), {}
}

@(private)
linux_create_exclusive :: proc(path: string, mode: u32) -> (Platform_Handle, Platform_Error) {
	path_buffer: [4_097]u8
	if len(path) == 0 || len(path) >= len(path_buffer) {
		return Platform_Handle(-1), Platform_Error{code = .Other, platform_code = i32(linux.Errno.ENAMETOOLONG)}
	}
	copy(path_buffer[:], path)
	fd, errno := linux.open(
		cstring(&path_buffer[0]),
		{.WRONLY, .CREAT, .EXCL, .NOFOLLOW, .CLOEXEC, .LARGEFILE},
		transmute(linux.Mode)mode,
	)
	if errno != .NONE {
		return Platform_Handle(-1), linux_platform_error(errno)
	}
	return Platform_Handle(fd), {}
}

@(private)
linux_set_mode :: proc(handle: Platform_Handle, mode: u32) -> Platform_Error {
	return linux_platform_error(linux.fchmod(linux.Fd(handle), transmute(linux.Mode)mode))
}

@(private)
linux_write :: proc(handle: Platform_Handle, source: []u8) -> (int, Platform_Error) {
	written, errno := linux.write(linux.Fd(handle), source)
	if errno != .NONE {
		return written, linux_platform_error(errno)
	}
	return written, {}
}

@(private)
linux_sync :: proc(handle: Platform_Handle) -> Platform_Error {
	return linux_platform_error(linux.fsync(linux.Fd(handle)))
}

@(private)
linux_rename :: proc(old_path, new_path: string) -> Platform_Error {
	old_buffer: [4_097]u8
	new_buffer: [4_097]u8
	if len(old_path) == 0 || len(old_path) >= len(old_buffer) ||
	   len(new_path) == 0 || len(new_path) >= len(new_buffer) {
		return Platform_Error{code = .Other, platform_code = i32(linux.Errno.ENAMETOOLONG)}
	}
	copy(old_buffer[:], old_path)
	copy(new_buffer[:], new_path)
	return linux_platform_error(linux.rename(cstring(&old_buffer[0]), cstring(&new_buffer[0])))
}

@(private)
linux_open_directory :: proc(path: string) -> (Platform_Handle, Platform_Error) {
	path_buffer: [4_097]u8
	if len(path) == 0 || len(path) >= len(path_buffer) {
		return Platform_Handle(-1), Platform_Error{code = .Other, platform_code = i32(linux.Errno.ENAMETOOLONG)}
	}
	copy(path_buffer[:], path)
	fd, errno := linux.open(cstring(&path_buffer[0]), {.DIRECTORY, .CLOEXEC})
	if errno != .NONE {
		return Platform_Handle(-1), linux_platform_error(errno)
	}
	return Platform_Handle(fd), {}
}

@(private)
linux_unlink :: proc(path: string) -> Platform_Error {
	path_buffer: [4_097]u8
	if len(path) == 0 || len(path) >= len(path_buffer) {
		return Platform_Error{code = .Other, platform_code = i32(linux.Errno.ENAMETOOLONG)}
	}
	copy(path_buffer[:], path)
	return linux_platform_error(linux.unlink(cstring(&path_buffer[0])))
}

@(private)
linux_inspect_handle :: proc(handle: Platform_Handle) -> (Platform_Metadata, Platform_Error) {
	stat: linux.Stat
	errno := linux.fstat(linux.Fd(handle), &stat)
	if errno != .NONE {
		return {}, linux_platform_error(errno)
	}
	return linux_metadata(stat), {}
}

@(private)
linux_read :: proc(handle: Platform_Handle, destination: []u8) -> (int, Platform_Error) {
	read_count, errno := linux.read(linux.Fd(handle), destination)
	if errno != .NONE {
		return read_count, linux_platform_error(errno)
	}
	return read_count, {}
}

@(private)
linux_close :: proc(handle: Platform_Handle) -> Platform_Error {
	errno := linux.close(linux.Fd(handle))
	return linux_platform_error(errno)
}

@(private)
linux_metadata :: proc(stat: linux.Stat) -> Platform_Metadata {
	kind := Platform_File_Kind.Other
	switch {
	case linux.S_ISREG(stat.mode): kind = .Regular
	case linux.S_ISDIR(stat.mode): kind = .Directory
	case linux.S_ISLNK(stat.mode): kind = .Symbolic_Link
	}
	return Platform_Metadata {
		kind = kind,
		identity = File_Identity {
			device = u64(stat.dev),
			inode = u64(stat.ino),
		},
		size = u64(stat.size),
		modified_seconds = i64(stat.mtime.time_sec),
		modified_nanoseconds = i32(stat.mtime.time_nsec),
		mode = transmute(u32)stat.mode & 0o7777,
	}
}

@(private)
linux_platform_error :: proc(errno: linux.Errno) -> Platform_Error {
	if errno == .NONE {
		return {}
	}
	code := Platform_Error_Code.Other
	#partial switch errno {
	case .ENOENT: code = .Not_Found
	case .EEXIST: code = .Exists
	case .EACCES, .EPERM: code = .Permission
	case .EINTR: code = .Interrupted
	}
	return Platform_Error {
		code = code,
		platform_code = i32(errno),
	}
}
