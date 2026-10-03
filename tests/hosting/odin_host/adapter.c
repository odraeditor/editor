// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include <chezscheme.h>
#include <racketcs.h>

#include "probe_module.c"

#ifndef ODRA_RACKET_BOOT_DIR
#error "ODRA_RACKET_BOOT_DIR must identify the Racket CS boot-image directory"
#endif

enum odra_racket_probe_state {
    ODRA_RACKET_PROBE_UNINITIALIZED = 0,
    ODRA_RACKET_PROBE_READY = 1,
    ODRA_RACKET_PROBE_STOPPED = 2,
};

enum odra_racket_probe_call_result {
    ODRA_RACKET_PROBE_CALL_OK = 0,
    ODRA_RACKET_PROBE_CALL_FAILURE = 1,
    ODRA_RACKET_PROBE_CALL_UNAVAILABLE = 2,
};

static enum odra_racket_probe_state odra_racket_probe_state = ODRA_RACKET_PROBE_UNINITIALIZED;

static int odra_racket_probe_boot_path(
    char *destination,
    size_t capacity,
    const char *boot_directory,
    const char *name
) {
    int written = snprintf(destination, capacity, "%s/%s", boot_directory, name);
    return written >= 0 && (size_t)written < capacity;
}

static int odra_racket_probe_readable_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return 0;
    }

    return fclose(file) == 0;
}

// odra_racket_probe_boot_at starts Racket CS from one explicit boot-image directory.
int odra_racket_probe_boot_at(const char *boot_directory) {
    if (odra_racket_probe_state == ODRA_RACKET_PROBE_READY) {
        return 1;
    }
    if (odra_racket_probe_state == ODRA_RACKET_PROBE_STOPPED || boot_directory == NULL) {
        return 0;
    }

    racket_boot_arguments_t arguments;
    char petite_boot[4096];
    char scheme_boot[4096];
    char racket_boot_image[4096];

    memset(&arguments, 0, sizeof(arguments));
    if (!odra_racket_probe_boot_path(
            petite_boot, sizeof(petite_boot), boot_directory, "petite.boot") ||
        !odra_racket_probe_boot_path(
            scheme_boot, sizeof(scheme_boot), boot_directory, "scheme.boot") ||
        !odra_racket_probe_boot_path(
            racket_boot_image, sizeof(racket_boot_image), boot_directory, "racket.boot") ||
        !odra_racket_probe_readable_file(petite_boot) ||
        !odra_racket_probe_readable_file(scheme_boot) ||
        !odra_racket_probe_readable_file(racket_boot_image)) {
        return 0;
    }

    arguments.exec_file = "odra-odin-host-probe";
    arguments.boot1_path = petite_boot;
    arguments.boot2_path = scheme_boot;
    arguments.boot3_path = racket_boot_image;
    racket_boot(&arguments);
    declare_modules();
    odra_racket_probe_state = ODRA_RACKET_PROBE_READY;
    return 1;
}

// odra_racket_probe_boot starts Racket CS from the discovered installation path.
int odra_racket_probe_boot(void) {
    return odra_racket_probe_boot_at(ODRA_RACKET_BOOT_DIR);
}

// odra_racket_probe_call invokes one module scenario and contains reported failures.
int odra_racket_probe_call(int64_t input, int32_t scenario, int64_t *output) {
    if (output == NULL || odra_racket_probe_state != ODRA_RACKET_PROBE_READY) {
        return ODRA_RACKET_PROBE_CALL_UNAVAILABLE;
    }

    ptr call_arguments = Scons(Sinteger64(scenario), Scons(Sinteger64(input), Snil));
    // Keep values retained by C stable across Racket calls that may collect.
    Slock_object(call_arguments);
    ptr module_path = Scons(
        Sstring_to_symbol("quote"),
        Scons(Sstring_to_symbol("probe"), Snil));
    ptr procedure = Scar(racket_dynamic_require(
        module_path,
        Sstring_to_symbol("probe-dispatch")));
    Slock_object(procedure);
    ptr result = Scar(racket_apply(procedure, call_arguments));
    Sunlock_object(procedure);
    Sunlock_object(call_arguments);
    if (Scar(result) != Strue) {
        return ODRA_RACKET_PROBE_CALL_FAILURE;
    }

    *output = Sinteger64_value(Scar(Scdr(result)));
    return ODRA_RACKET_PROBE_CALL_OK;
}

// odra_racket_probe_transform copies one bounded byte payload through Racket.
int odra_racket_probe_transform(
    const uint8_t *input,
    uint64_t length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *written
) {
    if (odra_racket_probe_state != ODRA_RACKET_PROBE_READY ||
        input == NULL || output == NULL || written == NULL ||
        length > 1024 * 1024 || output_capacity < length) {
        return ODRA_RACKET_PROBE_CALL_UNAVAILABLE;
    }

    ptr input_value = Smake_bytevector((iptr)length, 0);
    // Root the payload until the rooted argument list owns its reachability.
    Slock_object(input_value);
    memcpy(Sbytevector_data(input_value), input, (size_t)length);
    ptr call_arguments = Scons(input_value, Snil);
    Slock_object(call_arguments);
    Sunlock_object(input_value);
    ptr module_path = Scons(
        Sstring_to_symbol("quote"),
        Scons(Sstring_to_symbol("probe"), Snil));
    ptr procedure = Scar(racket_dynamic_require(
        module_path,
        Sstring_to_symbol("probe-transform")));
    Slock_object(procedure);
    ptr result = Scar(racket_apply(procedure, call_arguments));
    Sunlock_object(procedure);
    Sunlock_object(call_arguments);
    if (!Sbytevectorp(result) || Sbytevector_length(result) != (iptr)length) {
        return ODRA_RACKET_PROBE_CALL_FAILURE;
    }

    memcpy(output, Sbytevector_data(result), (size_t)length);
    *written = length;
    return ODRA_RACKET_PROBE_CALL_OK;
}

// odra_racket_probe_force_collection completes one full Racket collection.
int odra_racket_probe_force_collection(void) {
    if (odra_racket_probe_state != ODRA_RACKET_PROBE_READY) {
        return 0;
    }

    ptr module_path = Scons(
        Sstring_to_symbol("quote"),
        Scons(Sstring_to_symbol("probe"), Snil));
    ptr procedure = Scar(racket_dynamic_require(
        module_path,
        Sstring_to_symbol("probe-force-collection")));
    racket_apply(procedure, Snil);
    return 1;
}

// odra_racket_probe_cumulative_memory_bytes returns Racket allocation since boot.
int odra_racket_probe_cumulative_memory_bytes(uint64_t *allocated_bytes) {
    if (odra_racket_probe_state != ODRA_RACKET_PROBE_READY || allocated_bytes == NULL) {
        return 0;
    }

    ptr module_path = Scons(
        Sstring_to_symbol("quote"),
        Scons(Sstring_to_symbol("probe"), Snil));
    ptr procedure = Scar(racket_dynamic_require(
        module_path,
        Sstring_to_symbol("probe-cumulative-memory-use")));
    ptr result = Scar(racket_apply(procedure, Snil));
    *allocated_bytes = (uint64_t)Sinteger64_value(result);
    return 1;
}

// odra_racket_probe_rss_kib returns current Linux resident memory in KiB.
uint64_t odra_racket_probe_rss_kib(void) {
    FILE *status = fopen("/proc/self/status", "r");
    if (status == NULL) {
        return 0;
    }

    char line[256];
    uint64_t rss_kib = 0;
    while (fgets(line, sizeof(line), status) != NULL) {
        if (sscanf(line, "VmRSS: %" SCNu64 " kB", &rss_kib) == 1) {
            break;
        }
    }
    fclose(status);
    return rss_kib;
}

// odra_racket_probe_shutdown releases the embedded runtime exactly once.
int odra_racket_probe_shutdown(void) {
    if (odra_racket_probe_state != ODRA_RACKET_PROBE_READY) {
        return 0;
    }

    Sscheme_deinit();
    odra_racket_probe_state = ODRA_RACKET_PROBE_STOPPED;
    return 1;
}
