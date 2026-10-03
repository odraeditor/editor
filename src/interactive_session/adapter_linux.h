// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#ifndef ODRA_INTERACTIVE_SESSION_ADAPTER_LINUX_H
#define ODRA_INTERACTIVE_SESSION_ADAPTER_LINUX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    ODRA_PTY_OK = 0,
    ODRA_PTY_INVALID_ARGUMENT = 1,
    ODRA_PTY_EXECUTABLE_INVALID = 2,
    ODRA_PTY_WORKING_DIRECTORY_INVALID = 3,
    ODRA_PTY_ALLOCATION_FAILED = 4,
    ODRA_PTY_OPEN_FAILED = 5,
    ODRA_PTY_CONFIGURE_FAILED = 6,
    ODRA_PTY_SPAWN_FAILED = 7,
    ODRA_PTY_NONBLOCKING_FAILED = 8,
    ODRA_PTY_RESIZE_FAILED = 9,
    ODRA_PTY_READ_FAILED = 10,
    ODRA_PTY_WRITE_FAILED = 11,
    ODRA_PTY_SIGNAL_FAILED = 12,
    ODRA_PTY_REAP_FAILED = 13,
    ODRA_PTY_CLOSED = 14,
    ODRA_PTY_WOULD_BLOCK = 15,
    ODRA_PTY_END_OF_FILE = 16,
    ODRA_PTY_BUFFER_TOO_SMALL = 17,
} OdraPtyResult;

typedef struct OdraPtyProcess OdraPtyProcess;

typedef enum {
    ODRA_PTY_SIGNAL_INTERRUPT = 0,
    ODRA_PTY_SIGNAL_TERMINATE = 1,
    ODRA_PTY_SIGNAL_KILL = 2,
    ODRA_PTY_SIGNAL_HANGUP = 3,
} OdraPtySignal;

typedef struct {
    int32_t process_id;
    int32_t process_group_id;
    uint8_t open_descriptors;
    bool live;
    bool reaped;
} OdraPtyProcessInfo;

OdraPtyResult odra_pty_user_shell(
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written);
OdraPtyResult odra_pty_process_start(
    const char* executable,
    const char* const* arguments,
    size_t argument_count,
    const char* const* environment,
    size_t environment_count,
    const char* working_directory,
    uint16_t columns,
    uint16_t rows,
    OdraPtyProcess** out_process,
    int32_t* out_errno);
OdraPtyResult odra_pty_process_read(
    OdraPtyProcess* process,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_read,
    int32_t* out_errno);
OdraPtyResult odra_pty_process_write(
    OdraPtyProcess* process,
    const uint8_t* input,
    size_t input_length,
    size_t* out_written,
    int32_t* out_errno);
OdraPtyResult odra_pty_process_resize(
    OdraPtyProcess* process,
    uint16_t columns,
    uint16_t rows,
    int32_t* out_errno);
OdraPtyResult odra_pty_process_poll(
    OdraPtyProcess* process,
    bool* out_exited,
    bool* out_signalled,
    int32_t* out_status,
    int32_t* out_errno);
OdraPtyResult odra_pty_process_signal(
    OdraPtyProcess* process,
    int32_t signal_number,
    int32_t* out_errno);
OdraPtyResult odra_pty_process_inspect(
    OdraPtyProcess* process,
    OdraPtyProcessInfo* out_info);
OdraPtyResult odra_pty_process_close(
    OdraPtyProcess** process,
    int32_t* out_errno);

#endif
