// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#define _GNU_SOURCE

#include "adapter_linux.h"

#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

extern char** environ;

struct OdraPtyProcess {
    int master;
    pid_t process_id;
    pid_t process_group_id;
    bool live;
    bool reaped;
};

static void set_errno_output(int32_t* output, int value) {
    if (output != NULL) {
        *output = value;
    }
}

static bool executable_path(const char* path) {
    struct stat status;
    return path != NULL && path[0] == '/' && stat(path, &status) == 0 &&
        S_ISREG(status.st_mode) && access(path, X_OK) == 0;
}

static bool directory_path(const char* path) {
    struct stat status;
    return path != NULL && path[0] == '/' && stat(path, &status) == 0 &&
        S_ISDIR(status.st_mode) && access(path, X_OK) == 0;
}

static void kill_child(pid_t child) {
    if (kill(-child, SIGKILL) < 0 && errno == ESRCH) {
        (void) kill(child, SIGKILL);
    }
}

static OdraPtyResult configure_nonblocking(int descriptor, int32_t* out_errno) {
    int flags = fcntl(descriptor, F_GETFL);
    if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_NONBLOCKING_FAILED;
    }
    return ODRA_PTY_OK;
}

static OdraPtyResult configure_geometry(
    int descriptor,
    uint16_t columns,
    uint16_t rows,
    int32_t* out_errno) {
    if (columns == 0 || rows == 0) {
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    struct winsize size = {
        .ws_row = rows,
        .ws_col = columns,
    };
    if (ioctl(descriptor, TIOCSWINSZ, &size) < 0) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_RESIZE_FAILED;
    }
    return ODRA_PTY_OK;
}

OdraPtyResult odra_pty_user_shell(
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written) {
    if (out_written == NULL || (output == NULL && output_capacity != 0)) {
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    *out_written = 0;
    const char* shell = getenv("SHELL");
    if (!executable_path(shell)) {
        struct passwd password;
        struct passwd* resolved = NULL;
        long requested = sysconf(_SC_GETPW_R_SIZE_MAX);
        size_t capacity = requested > 0 ? (size_t) requested : 16 * 1024;
        char* storage = malloc(capacity);
        if (storage == NULL) {
            return ODRA_PTY_ALLOCATION_FAILED;
        }
        int result = getpwuid_r(getuid(), &password, storage, capacity, &resolved);
        if (result == 0 && resolved != NULL && executable_path(resolved->pw_shell)) {
            shell = resolved->pw_shell;
        } else {
            shell = "/bin/sh";
        }
        size_t length = strlen(shell);
        if (length + 1 > output_capacity) {
            *out_written = length;
            free(storage);
            return ODRA_PTY_BUFFER_TOO_SMALL;
        }
        memcpy(output, shell, length);
        *out_written = length;
        free(storage);
        return ODRA_PTY_OK;
    }
    size_t length = strlen(shell);
    if (length + 1 > output_capacity) {
        *out_written = length;
        return ODRA_PTY_BUFFER_TOO_SMALL;
    }
    memcpy(output, shell, length);
    *out_written = length;
    return ODRA_PTY_OK;
}

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
    int32_t* out_errno) {
    if (out_process == NULL || arguments == NULL ||
        argument_count == 0 || columns == 0 || rows == 0) {
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    *out_process = NULL;
    set_errno_output(out_errno, 0);
    if (!executable_path(executable)) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_EXECUTABLE_INVALID;
    }
    if (!directory_path(working_directory)) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_WORKING_DIRECTORY_INVALID;
    }

    int master = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (master < 0) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_OPEN_FAILED;
    }
    if (grantpt(master) < 0 || unlockpt(master) < 0) {
        set_errno_output(out_errno, errno);
        close(master);
        return ODRA_PTY_CONFIGURE_FAILED;
    }
    char slave_name[256];
    int name_result = ptsname_r(master, slave_name, sizeof(slave_name));
    if (name_result != 0) {
        set_errno_output(out_errno, name_result);
        close(master);
        return ODRA_PTY_CONFIGURE_FAILED;
    }
    int slave = open(slave_name, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (slave < 0) {
        set_errno_output(out_errno, errno);
        close(master);
        return ODRA_PTY_OPEN_FAILED;
    }
    OdraPtyResult geometry_result = configure_geometry(slave, columns, rows, out_errno);
    if (geometry_result != ODRA_PTY_OK) {
        close(slave);
        close(master);
        return geometry_result;
    }

    int startup[2];
    if (pipe2(startup, O_CLOEXEC) < 0) {
        set_errno_output(out_errno, errno);
        close(slave);
        close(master);
        return ODRA_PTY_SPAWN_FAILED;
    }
    pid_t child = fork();
    if (child < 0) {
        set_errno_output(out_errno, errno);
        close(startup[0]);
        close(startup[1]);
        close(slave);
        close(master);
        return ODRA_PTY_SPAWN_FAILED;
    }
    if (child == 0) {
        close(startup[0]);
        close(master);
        int child_error = 0;
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0 ||
            dup2(slave, STDIN_FILENO) < 0 ||
            dup2(slave, STDOUT_FILENO) < 0 ||
            dup2(slave, STDERR_FILENO) < 0 ||
            chdir(working_directory) < 0) {
            child_error = errno;
        }
        if (slave > STDERR_FILENO) {
            close(slave);
        }
        if (child_error == 0) {
            char* const* child_environment = environment_count == 0
                ? environ
                : (char* const*) environment;
            execve(executable, (char* const*) arguments, child_environment);
            child_error = errno;
        }
        (void) write(startup[1], &child_error, sizeof(child_error));
        _exit(127);
    }

    close(startup[1]);
    close(slave);
    int child_error = 0;
    ssize_t startup_bytes;
    do {
        startup_bytes = read(startup[0], &child_error, sizeof(child_error));
    } while (startup_bytes < 0 && errno == EINTR);
    close(startup[0]);
    if (startup_bytes > 0) {
        int ignored_status = 0;
        (void) waitpid(child, &ignored_status, 0);
        set_errno_output(out_errno, child_error);
        close(master);
        return ODRA_PTY_SPAWN_FAILED;
    }
    if (startup_bytes < 0) {
        int saved = errno;
        kill_child(child);
        (void) waitpid(child, NULL, 0);
        set_errno_output(out_errno, saved);
        close(master);
        return ODRA_PTY_SPAWN_FAILED;
    }
    OdraPtyResult nonblocking_result = configure_nonblocking(master, out_errno);
    if (nonblocking_result != ODRA_PTY_OK) {
        kill_child(child);
        (void) waitpid(child, NULL, 0);
        close(master);
        return nonblocking_result;
    }

    OdraPtyProcess* process = calloc(1, sizeof(*process));
    if (process == NULL) {
        kill_child(child);
        (void) waitpid(child, NULL, 0);
        close(master);
        return ODRA_PTY_ALLOCATION_FAILED;
    }
    process->master = master;
    process->process_id = child;
    process->process_group_id = child;
    process->live = true;
    *out_process = process;
    return ODRA_PTY_OK;
}

OdraPtyResult odra_pty_process_read(
    OdraPtyProcess* process,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_read,
    int32_t* out_errno) {
    if (process == NULL || output == NULL || output_capacity == 0 || out_read == NULL) {
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    *out_read = 0;
    ssize_t count = read(process->master, output, output_capacity);
    if (count > 0) {
        *out_read = (size_t) count;
        return ODRA_PTY_OK;
    }
    if (count == 0) {
        return ODRA_PTY_END_OF_FILE;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
        return ODRA_PTY_WOULD_BLOCK;
    }
    if (errno == EIO) {
        return ODRA_PTY_END_OF_FILE;
    }
    set_errno_output(out_errno, errno);
    return ODRA_PTY_READ_FAILED;
}

OdraPtyResult odra_pty_process_write(
    OdraPtyProcess* process,
    const uint8_t* input,
    size_t input_length,
    size_t* out_written,
    int32_t* out_errno) {
    if (process == NULL || input == NULL || input_length == 0 || out_written == NULL) {
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    *out_written = 0;
    ssize_t count = write(process->master, input, input_length);
    if (count >= 0) {
        *out_written = (size_t) count;
        return ODRA_PTY_OK;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
        return ODRA_PTY_WOULD_BLOCK;
    }
    set_errno_output(out_errno, errno);
    return ODRA_PTY_WRITE_FAILED;
}

OdraPtyResult odra_pty_process_resize(
    OdraPtyProcess* process,
    uint16_t columns,
    uint16_t rows,
    int32_t* out_errno) {
    if (process == NULL || !process->live) {
        return ODRA_PTY_CLOSED;
    }
    OdraPtyResult result = configure_geometry(process->master, columns, rows, out_errno);
    if (result == ODRA_PTY_OK && kill(-process->process_group_id, SIGWINCH) < 0 && errno != ESRCH) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_RESIZE_FAILED;
    }
    return result;
}

OdraPtyResult odra_pty_process_poll(
    OdraPtyProcess* process,
    bool* out_exited,
    bool* out_signalled,
    int32_t* out_status,
    int32_t* out_errno) {
    if (process == NULL || out_exited == NULL || out_signalled == NULL || out_status == NULL) {
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    *out_exited = false;
    *out_signalled = false;
    *out_status = 0;
    if (!process->live) {
        return ODRA_PTY_OK;
    }
    int status = 0;
    pid_t result = waitpid(process->process_id, &status, WNOHANG);
    if (result == 0) {
        return ODRA_PTY_OK;
    }
    if (result < 0) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_REAP_FAILED;
    }
    process->live = false;
    process->reaped = true;
    if (WIFEXITED(status)) {
        *out_exited = true;
        *out_status = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        *out_exited = true;
        *out_signalled = true;
        *out_status = WTERMSIG(status);
    }
    return ODRA_PTY_OK;
}

OdraPtyResult odra_pty_process_signal(
    OdraPtyProcess* process,
    int32_t signal_number,
    int32_t* out_errno) {
    if (process == NULL || !process->live) {
        return ODRA_PTY_CLOSED;
    }
    int native_signal = 0;
    switch ((OdraPtySignal) signal_number) {
    case ODRA_PTY_SIGNAL_INTERRUPT:
        native_signal = SIGINT;
        break;
    case ODRA_PTY_SIGNAL_TERMINATE:
        native_signal = SIGTERM;
        break;
    case ODRA_PTY_SIGNAL_KILL:
        native_signal = SIGKILL;
        break;
    case ODRA_PTY_SIGNAL_HANGUP:
        native_signal = SIGHUP;
        break;
    default:
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    if (kill(-process->process_group_id, native_signal) < 0) {
        set_errno_output(out_errno, errno);
        return ODRA_PTY_SIGNAL_FAILED;
    }
    return ODRA_PTY_OK;
}

OdraPtyResult odra_pty_process_inspect(
    OdraPtyProcess* process,
    OdraPtyProcessInfo* out_info) {
    if (process == NULL || out_info == NULL) {
        return ODRA_PTY_INVALID_ARGUMENT;
    }
    *out_info = (OdraPtyProcessInfo) {
        .process_id = process->process_id,
        .process_group_id = process->process_group_id,
        .open_descriptors = process->master >= 0 ? 1 : 0,
        .live = process->live,
        .reaped = process->reaped,
    };
    return ODRA_PTY_OK;
}

OdraPtyResult odra_pty_process_close(
    OdraPtyProcess** process_pointer,
    int32_t* out_errno) {
    if (process_pointer == NULL || *process_pointer == NULL) {
        return ODRA_PTY_CLOSED;
    }
    OdraPtyProcess* process = *process_pointer;
    OdraPtyResult result = ODRA_PTY_OK;
    if (process->live) {
        if (kill(-process->process_group_id, SIGKILL) < 0 && errno != ESRCH) {
            set_errno_output(out_errno, errno);
            result = ODRA_PTY_SIGNAL_FAILED;
        }
        int status = 0;
        while (waitpid(process->process_id, &status, 0) < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno != ECHILD && result == ODRA_PTY_OK) {
                set_errno_output(out_errno, errno);
                result = ODRA_PTY_REAP_FAILED;
            }
            break;
        }
        process->live = false;
        process->reaped = true;
    }
    if (process->master >= 0) {
        if (close(process->master) < 0 && result == ODRA_PTY_OK) {
            set_errno_output(out_errno, errno);
            result = ODRA_PTY_CLOSED;
        }
        process->master = -1;
    }
    free(process);
    *process_pointer = NULL;
    return result;
}
