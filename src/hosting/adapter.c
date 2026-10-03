// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#define _XOPEN_SOURCE 700

#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <threads.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chezscheme.h>
#include <racketcs.h>

#ifndef ODRA_RACKET_RUNTIME_MODULE
#define ODRA_RACKET_RUNTIME_MODULE "runtime_module.c"
#endif

#include ODRA_RACKET_RUNTIME_MODULE
#include "runtime_boundary_manifest.h"
#include "scoped_capability_transport.c"

#ifndef ODRA_RACKET_BOOT_DIR
#error "ODRA_RACKET_BOOT_DIR must identify the Racket CS boot-image directory"
#endif

#ifndef ODRA_RACKET_COLLECTS_DIR
#error "ODRA_RACKET_COLLECTS_DIR must identify the Racket collection directory"
#endif

#ifndef ODRA_RACKET_CONFIG_DIR
#error "ODRA_RACKET_CONFIG_DIR must identify the Racket configuration directory"
#endif

#define ODRA_RUNTIME_RESOURCE_PATH_CAPACITY 4096
#define ODRA_RUNTIME_BUNDLE_BOOT_RELATIVE "lib/odra/racket/lib"
#define ODRA_RUNTIME_BUNDLE_COLLECTS_RELATIVE "share/odra/racket/collects"
#define ODRA_RUNTIME_BUNDLE_CONFIG_RELATIVE "share/odra/racket/etc"

#ifndef ODRA_RACKET_EXPECTED_START_SYMBOL
#define ODRA_RACKET_EXPECTED_START_SYMBOL "odra-runtime-ready"
#endif

#ifndef ODRA_RACKET_EXPECTED_STOP_SYMBOL
#define ODRA_RACKET_EXPECTED_STOP_SYMBOL "odra-runtime-stopped"
#endif

enum odra_runtime_adapter_state {
    ODRA_RUNTIME_ADAPTER_UNINITIALIZED = 0,
    ODRA_RUNTIME_ADAPTER_READY = 1,
    ODRA_RUNTIME_ADAPTER_FAILED = 2,
    ODRA_RUNTIME_ADAPTER_STOPPED = 3,
};

enum odra_runtime_adapter_result {
    ODRA_RUNTIME_ADAPTER_OK = 0,
    ODRA_RUNTIME_ADAPTER_INVALID_STATE = 1,
    ODRA_RUNTIME_ADAPTER_MISSING_BOOT_IMAGE = 2,
    ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT = 3,
    ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION = 4,
    ODRA_RUNTIME_ADAPTER_COMMAND_REJECTION = 5,
};

static enum odra_runtime_adapter_state odra_runtime_state =
    ODRA_RUNTIME_ADAPTER_UNINITIALIZED;

#define ODRA_DECLARE_RUNTIME_PROCEDURE(name, module, procedure, test_only) \
    static ptr odra_runtime_##name##_procedure = 0;
ODRA_RUNTIME_BOUNDARY_PROCEDURES(ODRA_DECLARE_RUNTIME_PROCEDURE)
#undef ODRA_DECLARE_RUNTIME_PROCEDURE

struct odra_runtime_boundary_entry {
    ptr *root;
    const char *module_name;
    const char *procedure_name;
    int test_only;
};

#define ODRA_RUNTIME_BOUNDARY_ENTRY(name, module, procedure, test_only) \
    {&odra_runtime_##name##_procedure, module, procedure, test_only},
static const struct odra_runtime_boundary_entry odra_runtime_boundary[] = {
    ODRA_RUNTIME_BOUNDARY_PROCEDURES(ODRA_RUNTIME_BOUNDARY_ENTRY)
};
#undef ODRA_RUNTIME_BOUNDARY_ENTRY

#define ODRA_RUNTIME_BOUNDARY_COUNT \
    (sizeof(odra_runtime_boundary) / sizeof(odra_runtime_boundary[0]))

static uint64_t odra_runtime_boundary_load_count = 0;
static uint64_t odra_runtime_boundary_release_count = 0;

#define ODRA_HISTORY_POLICY_FIELD_COUNT 13
#define ODRA_DISPLAY_POLICY_ACTION_CAPACITY 32
#define ODRA_DISPLAY_POLICY_FIELD_COUNT 35

struct odra_history_policy_record {
    uint64_t generation;
    uint64_t fields[ODRA_HISTORY_POLICY_FIELD_COUNT];
};

struct odra_display_policy_record {
    uint64_t generation;
    uint64_t action_count;
    uint64_t actions[ODRA_DISPLAY_POLICY_ACTION_CAPACITY];
    uint64_t split_height_threshold;
    uint64_t split_width_threshold;
};

static void odra_runtime_racket_diagnostic(
    ptr racket_diagnostic,
    char *diagnostic,
    uint64_t diagnostic_capacity
);

static int odra_runtime_list_parts(ptr value, ptr *parts, uint64_t part_count);
static int odra_runtime_integer_value(ptr value, uint64_t *output);

static void odra_runtime_diagnostic(
    char *diagnostic,
    uint64_t capacity,
    const char *message
) {
    if (diagnostic == NULL || capacity == 0) {
        return;
    }

    size_t message_length = strlen(message);
    size_t copied = message_length < capacity - 1 ? message_length : capacity - 1;
    memcpy(diagnostic, message, copied);
    diagnostic[copied] = '\0';
}

static int odra_runtime_join_path(
    char *destination,
    size_t capacity,
    const char *directory,
    const char *name
) {
    int written = snprintf(destination, capacity, "%s/%s", directory, name);
    return written >= 0 && (size_t)written < capacity;
}

static int odra_runtime_readable_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return 0;
    }

    return fclose(file) == 0;
}

static int odra_runtime_readable_directory(const char *path) {
    struct stat status;
    return path != NULL && stat(path, &status) == 0 && S_ISDIR(status.st_mode);
}

static int odra_runtime_path_has_parent_segment(const char *path) {
    const char *cursor = path;
    while (cursor != NULL && *cursor != '\0') {
        while (*cursor == '/') {
            cursor += 1;
        }
        const char *end = strchr(cursor, '/');
        size_t length = end == NULL ? strlen(cursor) : (size_t)(end - cursor);
        if (length == 2 && cursor[0] == '.' && cursor[1] == '.') {
            return 1;
        }
        cursor = end;
    }
    return 0;
}

static int odra_runtime_copy_resource_path(
    char *destination,
    size_t destination_capacity,
    const uint8_t *source,
    uint64_t source_length
) {
    if (destination == NULL || destination_capacity == 0 || source == NULL ||
        source_length == 0 || source_length >= destination_capacity ||
        source_length > (uint64_t)SIZE_MAX || source[0] != '/' ||
        memchr(source, '\0', (size_t)source_length) != NULL) {
        return 0;
    }
    memcpy(destination, source, (size_t)source_length);
    destination[source_length] = '\0';
    return !odra_runtime_path_has_parent_segment(destination);
}

static int odra_runtime_path_inside(const char *root, const char *path) {
    size_t root_length = strlen(root);
    return strncmp(root, path, root_length) == 0 &&
        (path[root_length] == '/' || path[root_length] == '\0');
}

static int odra_runtime_bundle_resource_paths(
    char *boot_directory,
    char *collects_directory,
    char *config_directory
) {
    char executable[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    ssize_t executable_length = readlink(
        "/proc/self/exe",
        executable,
        sizeof(executable) - 1);
    if (executable_length <= 0 || (size_t)executable_length >= sizeof(executable)) {
        return 0;
    }
    executable[executable_length] = '\0';
    char *separator = strrchr(executable, '/');
    if (separator == NULL || separator == executable) {
        return 0;
    }
    *separator = '\0';

    char root_candidate[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    char bundle_root[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    if (!odra_runtime_join_path(
            root_candidate,
            sizeof(root_candidate),
            executable,
            "..") ||
        realpath(root_candidate, bundle_root) == NULL) {
        return 0;
    }

    const char *relative_paths[] = {
        ODRA_RUNTIME_BUNDLE_BOOT_RELATIVE,
        ODRA_RUNTIME_BUNDLE_COLLECTS_RELATIVE,
        ODRA_RUNTIME_BUNDLE_CONFIG_RELATIVE,
    };
    char *resolved_paths[] = {
        boot_directory,
        collects_directory,
        config_directory,
    };
    for (size_t index = 0; index < 3; index += 1) {
        char candidate[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
        if (!odra_runtime_join_path(
                candidate,
                sizeof(candidate),
                bundle_root,
                relative_paths[index]) ||
            realpath(candidate, resolved_paths[index]) == NULL ||
            !odra_runtime_path_inside(bundle_root, resolved_paths[index])) {
            return 0;
        }
    }
    return 1;
}

static int odra_runtime_call_lifecycle(
    const char *procedure_name,
    const char *expected_symbol
) {
    ptr module_path = Scons(
        Sstring_to_symbol("quote"),
        Scons(Sstring_to_symbol("runtime-boundary"), Snil));
    ptr procedure = Scar(racket_dynamic_require(
        module_path,
        Sstring_to_symbol(procedure_name)));
    Slock_object(procedure);
    ptr result = Scar(racket_apply(procedure, Snil));
    Sunlock_object(procedure);
    return result == Sstring_to_symbol(expected_symbol);
}

static int odra_runtime_call_start(
    const uint8_t *schema,
    uint64_t schema_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (schema == NULL || schema_length == 0 || schema_length > (uint64_t)INTPTR_MAX) {
        return 0;
    }
    ptr module_path = Scons(
        Sstring_to_symbol("quote"),
        Scons(Sstring_to_symbol("runtime-boundary"), Snil));
    ptr procedure = Scar(racket_dynamic_require(
        module_path,
        Sstring_to_symbol("runtime-start")));
    Slock_object(procedure);
    ptr schema_value = Smake_bytevector((iptr)schema_length, 0);
    memcpy(Sbytevector_data(schema_value), schema, (size_t)schema_length);
    ptr arguments = Scons(schema_value, Snil);
    Slock_object(arguments);
    ptr result = Scar(racket_apply(procedure, arguments));
    Slock_object(result);
    Sunlock_object(arguments);
    Sunlock_object(procedure);
    if (result == Sstring_to_symbol(ODRA_RACKET_EXPECTED_START_SYMBOL)) {
        Sunlock_object(result);
        return 1;
    }
    if (Sbytevectorp(result)) {
        odra_runtime_racket_diagnostic(result, diagnostic, diagnostic_capacity);
    }
    Sunlock_object(result);
    return 0;
}

static ptr odra_runtime_load_procedure(
    const char *module_name,
    const char *procedure_name
) {
    ptr module_path = Scons(
        Sstring_to_symbol("quote"),
        Scons(Sstring_to_symbol(module_name), Snil));
    ptr procedure = Scar(racket_dynamic_require(
        module_path,
        Sstring_to_symbol(procedure_name)));
    Slock_object(procedure);
    return procedure;
}

static int odra_runtime_boundary_entry_is_enabled(
    const struct odra_runtime_boundary_entry *entry
) {
#ifdef ODRA_RACKET_TEST_PROBES
    (void)entry;
    return 1;
#else
    return !entry->test_only;
#endif
}

static void odra_runtime_release_procedures(void) {
    for (size_t index = 0; index < ODRA_RUNTIME_BOUNDARY_COUNT; index += 1) {
        ptr *root = odra_runtime_boundary[index].root;
        if (*root != 0) {
            Sunlock_object(*root);
            *root = 0;
            odra_runtime_boundary_release_count += 1;
        }
    }
}

static void odra_runtime_boundary_diagnostic(
    const struct odra_runtime_boundary_entry *entry,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    char message[512];
    int written = snprintf(
        message,
        sizeof(message),
        "Racket boundary procedure is unavailable: %s/%s",
        entry->module_name,
        entry->procedure_name);
    if (written < 0 || (size_t)written >= sizeof(message)) {
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket boundary procedure is unavailable");
        return;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, message);
}

static int odra_runtime_load_procedures(
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    for (size_t index = 0; index < ODRA_RUNTIME_BOUNDARY_COUNT; index += 1) {
        const struct odra_runtime_boundary_entry *entry =
            &odra_runtime_boundary[index];
        if (!odra_runtime_boundary_entry_is_enabled(entry)) {
            continue;
        }
#ifdef ODRA_RACKET_MISSING_BOUNDARY_PROCEDURE
        if (strcmp(
                entry->procedure_name,
                ODRA_RACKET_MISSING_BOUNDARY_PROCEDURE) == 0) {
            odra_runtime_boundary_diagnostic(
                entry,
                diagnostic,
                diagnostic_capacity);
            odra_runtime_release_procedures();
            return 0;
        }
#endif
        *entry->root = odra_runtime_load_procedure(
            entry->module_name,
            entry->procedure_name);
        if (*entry->root == 0) {
            odra_runtime_boundary_diagnostic(
                entry,
                diagnostic,
                diagnostic_capacity);
            odra_runtime_release_procedures();
            return 0;
        }
        odra_runtime_boundary_load_count += 1;
    }
    return 1;
}

static ptr odra_runtime_capability_turn_procedure(
    int32_t scenario,
    ptr production_turn,
    ptr test_probe
) {
    return scenario == 0 ? production_turn : test_probe;
}

static ptr odra_runtime_capability_turn_arguments(
    int32_t scenario,
    uint64_t generation,
    uint64_t token
) {
    ptr arguments = Scons(Sunsigned64(generation), Scons(Sunsigned64(token), Snil));
    if (scenario != 0) {
        arguments = Scons(Sinteger64(scenario), arguments);
    }
    return arguments;
}

static ptr odra_runtime_turn_arguments_with_scenario(
    int32_t scenario,
    ptr arguments
) {
    return scenario == 0 ? arguments : Scons(Sinteger64(scenario), arguments);
}

// odra_racket_runtime_load_keymap_profile copies one complete candidate batch.
int32_t odra_racket_runtime_load_keymap_profile(
    int32_t scenario,
    uint64_t registry_generation,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_keymap_profile_procedure,
        odra_runtime_keymap_profile_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || registry_generation == 0 ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for keymap profile transfer");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario, Scons(Sunsigned64(registry_generation), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[4];
    if (!odra_runtime_list_parts(envelope, parts, 4) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2]) || !Sbytevectorp(parts[3])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket keymap profile returned an invalid result envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[3], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }

    uint64_t echoed_generation;
    if (!odra_runtime_integer_value(parts[1], &echoed_generation) ||
        echoed_generation != registry_generation) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket keymap profile returned a mismatched registry generation");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[2]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket keymap profile exceeds copied candidate storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[2]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_load_command_catalog copies one complete command batch.
int32_t odra_racket_runtime_load_command_catalog(
    int32_t scenario,
    uint64_t registry_generation,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_command_catalog_procedure,
        odra_runtime_command_catalog_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || registry_generation == 0 ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for command catalog transfer");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario, Scons(Sunsigned64(registry_generation), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[4];
    if (!odra_runtime_list_parts(envelope, parts, 4) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2]) || !Sbytevectorp(parts[3])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket command catalog returned an invalid result envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[3], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }

    uint64_t echoed_generation;
    if (!odra_runtime_integer_value(parts[1], &echoed_generation) ||
        echoed_generation != registry_generation) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket command catalog returned a mismatched registry generation");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[2]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket command catalog exceeds copied candidate storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[2]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

static int odra_runtime_result_parts(
    ptr envelope,
    ptr *success,
    ptr *value,
    ptr *diagnostic
) {
    if (!Spairp(envelope)) {
        return 0;
    }
    *success = Scar(envelope);
    ptr remaining = Scdr(envelope);
    if (!Spairp(remaining)) {
        return 0;
    }
    *value = Scar(remaining);
    remaining = Scdr(remaining);
    if (!Spairp(remaining)) {
        return 0;
    }
    *diagnostic = Scar(remaining);
    return Snullp(Scdr(remaining));
}

static int odra_runtime_list_parts(ptr value, ptr *parts, uint64_t part_count) {
    for (uint64_t index = 0; index < part_count; index += 1) {
        if (!Spairp(value)) {
            return 0;
        }
        parts[index] = Scar(value);
        value = Scdr(value);
    }
    return Snullp(value);
}

static int odra_runtime_integer_value(ptr value, uint64_t *output) {
    Suint64_t parsed;
    const char *reason = NULL;
    if (output == NULL ||
        !Stry_unsigned64_value(value, &parsed, &reason)) {
        return 0;
    }
    *output = (uint64_t)parsed;
    return 1;
}

// odra_racket_runtime_history_policy copies one complete policy through Racket.
int32_t odra_racket_runtime_history_policy(
    int32_t scenario,
    const struct odra_history_policy_record *input,
    struct odra_history_policy_record *output,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_history_policy_procedure,
        odra_runtime_history_policy_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || input == NULL ||
        output == NULL || input->generation == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for history policy transfer");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr fields = Snil;
    for (uint64_t index = ODRA_HISTORY_POLICY_FIELD_COUNT; index > 0; index -= 1) {
        if (!Snullp(fields)) {
            Slock_object(fields);
        }
        ptr field = Sunsigned64(input->fields[index - 1]);
        Slock_object(field);
        ptr next = Scons(field, fields);
        Sunlock_object(field);
        if (!Snullp(fields)) {
            Sunlock_object(fields);
        }
        fields = next;
    }
    Slock_object(fields);
    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario,
        Scons(Sunsigned64(input->generation), Scons(fields, Snil)));
    Slock_object(arguments);
    Sunlock_object(fields);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[4];
    if (!odra_runtime_list_parts(envelope, parts, 4) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[3])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket history policy returned an invalid result envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[3], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }

    struct odra_history_policy_record candidate = {0};
    if (!odra_runtime_integer_value(parts[1], &candidate.generation) ||
        candidate.generation != input->generation) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket history policy returned a mismatched generation");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    ptr policy_parts[ODRA_HISTORY_POLICY_FIELD_COUNT];
    if (!odra_runtime_list_parts(
            parts[2], policy_parts, ODRA_HISTORY_POLICY_FIELD_COUNT)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket history policy returned an invalid field set");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    for (uint64_t index = 0; index < ODRA_HISTORY_POLICY_FIELD_COUNT; index += 1) {
        if (!odra_runtime_integer_value(policy_parts[index], &candidate.fields[index])) {
            odra_runtime_diagnostic(
                diagnostic, diagnostic_capacity,
                "Racket history policy returned a non-integer field");
            return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
        }
    }

    *output = candidate;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_display_policy copies one complete policy through Racket.
int32_t odra_racket_runtime_display_policy(
    int32_t scenario,
    const struct odra_display_policy_record *input,
    struct odra_display_policy_record *output,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_display_policy_procedure,
        odra_runtime_display_policy_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || input == NULL ||
        output == NULL || input->generation == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for display policy transfer");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t input_fields[ODRA_DISPLAY_POLICY_FIELD_COUNT] = {0};
    input_fields[0] = input->action_count;
    for (uint64_t index = 0; index < ODRA_DISPLAY_POLICY_ACTION_CAPACITY; index += 1) {
        input_fields[index + 1] = input->actions[index];
    }
    input_fields[33] = input->split_height_threshold;
    input_fields[34] = input->split_width_threshold;

    ptr fields = Snil;
    for (uint64_t index = ODRA_DISPLAY_POLICY_FIELD_COUNT; index > 0; index -= 1) {
        if (!Snullp(fields)) {
            Slock_object(fields);
        }
        ptr field = Sunsigned64(input_fields[index - 1]);
        Slock_object(field);
        ptr next = Scons(field, fields);
        Sunlock_object(field);
        if (!Snullp(fields)) {
            Sunlock_object(fields);
        }
        fields = next;
    }
    Slock_object(fields);
    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario,
        Scons(Sunsigned64(input->generation), Scons(fields, Snil)));
    Slock_object(arguments);
    Sunlock_object(fields);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[4];
    if (!odra_runtime_list_parts(envelope, parts, 4) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[3])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket display policy returned an invalid result envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[3], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }

    struct odra_display_policy_record candidate = {0};
    if (!odra_runtime_integer_value(parts[1], &candidate.generation) ||
        candidate.generation != input->generation) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket display policy returned a mismatched generation");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    ptr policy_parts[ODRA_DISPLAY_POLICY_FIELD_COUNT];
    if (!odra_runtime_list_parts(
            parts[2], policy_parts, ODRA_DISPLAY_POLICY_FIELD_COUNT)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket display policy returned an invalid field set");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    uint64_t candidate_fields[ODRA_DISPLAY_POLICY_FIELD_COUNT] = {0};
    for (uint64_t index = 0; index < ODRA_DISPLAY_POLICY_FIELD_COUNT; index += 1) {
        if (!odra_runtime_integer_value(policy_parts[index], &candidate_fields[index])) {
            odra_runtime_diagnostic(
                diagnostic, diagnostic_capacity,
                "Racket display policy returned a non-integer field");
            return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
        }
    }
    candidate.action_count = candidate_fields[0];
    for (uint64_t index = 0; index < ODRA_DISPLAY_POLICY_ACTION_CAPACITY; index += 1) {
        candidate.actions[index] = candidate_fields[index + 1];
    }
    candidate.split_height_threshold = candidate_fields[33];
    candidate.split_width_threshold = candidate_fields[34];

    *output = candidate;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_uppercase_line invokes the rooted programmable command once.
int odra_racket_runtime_uppercase_line(
    int32_t scenario,
    uint64_t capability,
    uint64_t buffer_id,
    uint64_t revision,
    uint64_t start,
    uint64_t end,
    const uint8_t *input,
    uint64_t input_length,
    uint64_t *result_start,
    uint64_t *result_end,
    uint8_t *replacement,
    uint64_t replacement_capacity,
    uint64_t *replacement_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_uppercase_procedure,
        odra_runtime_uppercase_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 ||
        (input == NULL && input_length != 0) || result_start == NULL ||
        result_end == NULL || replacement == NULL || replacement_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for uppercase commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr input_value = Smake_bytevector((iptr)input_length, 0);
    Slock_object(input_value);
    if (input_length != 0) {
        memcpy(Sbytevector_data(input_value), input, (size_t)input_length);
    }
    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario,
        Scons(
            Sunsigned64(capability),
            Scons(
                Sunsigned64(buffer_id),
                Scons(
                    Sunsigned64(revision),
                    Scons(
                        Sunsigned64(start),
                        Scons(Sunsigned64(end), Scons(input_value, Snil)))))));
    Slock_object(arguments);
    Sunlock_object(input_value);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[8];
    if (!odra_runtime_list_parts(envelope, parts, 8) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[6]) ||
        !Sbytevectorp(parts[7])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket uppercase command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[7], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }

    uint64_t echoed_capability;
    uint64_t echoed_buffer_id;
    uint64_t echoed_revision;
    if (!odra_runtime_integer_value(parts[1], &echoed_capability) ||
        !odra_runtime_integer_value(parts[2], &echoed_buffer_id) ||
        !odra_runtime_integer_value(parts[3], &echoed_revision) ||
        !odra_runtime_integer_value(parts[4], result_start) ||
        !odra_runtime_integer_value(parts[5], result_end) ||
        echoed_capability != capability || echoed_buffer_id != buffer_id ||
        echoed_revision != revision || *result_start != start || *result_end != end) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket uppercase command returned mismatched identity");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[6]);
    if (length > replacement_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket uppercase replacement exceeds output capacity");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(replacement, Sbytevector_data(parts[6]), (size_t)length);
    *replacement_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_transaction_probe runs one command-scoped facade scenario.
int odra_racket_runtime_transaction_probe(
    int32_t scenario,
    uint64_t token,
    uint64_t command_id,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_transaction_turn_procedure,
        odra_runtime_transaction_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL ||
        token == 0 || command_id == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for transaction commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_TRANSACTION, token, command_id,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for transaction commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket transaction command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_transaction_command invokes one facade-backed command.
int odra_racket_runtime_transaction_command(
    int32_t scenario,
    uint64_t token,
    uint64_t command_id,
    const uint8_t *command_name,
    uint64_t command_name_length,
    uint64_t start,
    uint64_t end,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_transaction_command_procedure,
        odra_runtime_transaction_command_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL ||
        token == 0 || command_id == 0 || command_name == NULL ||
        command_name_length == 0 || start > end) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for transaction commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_TRANSACTION, token, command_id,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for transaction commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr command_value = Smake_bytevector((iptr)command_name_length, 0);
    Slock_object(command_value);
    memcpy(Sbytevector_data(command_value), command_name, (size_t)command_name_length);
    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario,
        Scons(
            command_value,
            Scons(
                Sunsigned64(generation),
                Scons(
                    Sunsigned64(token),
                    Scons(Sunsigned64(start), Scons(Sunsigned64(end), Snil))))));
    Slock_object(arguments);
    Sunlock_object(command_value);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket transaction command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    if (parts[1] != Strue) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket transaction command returned an invalid success result");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_personal_command invokes one retained personal procedure.
int odra_racket_runtime_personal_command(
    uint64_t token,
    uint64_t command_id,
    const uint8_t *command_name,
    uint64_t command_name_length,
    const uint8_t *document_path,
    uint64_t document_path_length,
    const uint8_t *project_root,
    uint64_t project_root_length,
    const uint8_t *candidate_selection,
    uint64_t candidate_selection_length,
    uint64_t route_generation,
    uint64_t route_slot,
    uint64_t revision,
    uint64_t point,
    int32_t region_present,
    uint64_t region_start,
    uint64_t region_end,
    uint64_t line_start,
    uint64_t line_end,
    uint64_t buffer_end,
    uint64_t effects,
    int32_t cancelled,
    odra_scoped_capability_callback callback,
    void *user_data,
    uint8_t *result,
    uint64_t result_capacity,
    uint64_t *result_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_personal_command_procedure;
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0 || command_id == 0 ||
        command_name == NULL || command_name_length == 0 ||
        (document_path == NULL && document_path_length != 0) ||
        (project_root == NULL && project_root_length != 0) ||
        (candidate_selection == NULL && candidate_selection_length != 0) ||
        route_generation == 0 || route_slot == 0 ||
        point > buffer_end || line_start > line_end || line_end > buffer_end ||
        (region_present != 0 && region_present != 1) ||
        (region_present == 1 &&
         (region_start > region_end || region_end > buffer_end)) ||
        (cancelled != 0 && cancelled != 1) ||
        result == NULL || result_capacity == 0 || result_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter received an invalid personal command context");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t capability_generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_TRANSACTION, token, command_id,
            callback, user_data, &capability_generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for personal commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr command_value = Smake_bytevector((iptr)command_name_length, 0);
    ptr document_value = Smake_bytevector((iptr)document_path_length, 0);
    ptr project_value = Smake_bytevector((iptr)project_root_length, 0);
    ptr selection_value = Smake_bytevector((iptr)candidate_selection_length, 0);
    Slock_object(command_value);
    Slock_object(document_value);
    Slock_object(project_value);
    Slock_object(selection_value);
    memcpy(Sbytevector_data(command_value), command_name, (size_t)command_name_length);
    if (document_path_length != 0) {
        memcpy(Sbytevector_data(document_value), document_path, (size_t)document_path_length);
    }
    if (project_root_length != 0) {
        memcpy(Sbytevector_data(project_value), project_root, (size_t)project_root_length);
    }
    if (candidate_selection_length != 0) {
        memcpy(Sbytevector_data(selection_value), candidate_selection,
               (size_t)candidate_selection_length);
    }
    ptr arguments = Snil;
    arguments = Scons(cancelled == 1 ? Strue : Sfalse, arguments);
    arguments = Scons(Sunsigned64(effects), arguments);
    arguments = Scons(Sunsigned64(buffer_end), arguments);
    arguments = Scons(Sunsigned64(line_end), arguments);
    arguments = Scons(Sunsigned64(line_start), arguments);
    arguments = Scons(region_present == 1 ? Sunsigned64(region_end) : Sfalse, arguments);
    arguments = Scons(region_present == 1 ? Sunsigned64(region_start) : Sfalse, arguments);
    arguments = Scons(Sunsigned64(point), arguments);
    arguments = Scons(Sunsigned64(revision), arguments);
    arguments = Scons(Sunsigned64(token), arguments);
    arguments = Scons(Sunsigned64(capability_generation), arguments);
    arguments = Scons(Sunsigned64(route_slot), arguments);
    arguments = Scons(Sunsigned64(route_generation), arguments);
    arguments = Scons(selection_value, arguments);
    arguments = Scons(project_value, arguments);
    arguments = Scons(document_value, arguments);
    arguments = Scons(command_value, arguments);
    Slock_object(arguments);
    Sunlock_object(command_value);
    Sunlock_object(document_value);
    Sunlock_object(project_value);
    Sunlock_object(selection_value);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[4];
    if (!odra_runtime_list_parts(envelope, parts, 4) ||
        !Sbooleanp(parts[0]) || !Sbooleanp(parts[1]) ||
        !Sbytevectorp(parts[2]) || !Sbytevectorp(parts[3])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    if (parts[1] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_COMMAND_REJECTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[3]);
    if (length > result_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal command result exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (length != 0) {
        memcpy(result, Sbytevector_data(parts[3]), (size_t)length);
    }
    *result_length = length;
    odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_transfer_probe runs one dynamically scoped transfer scenario.
int odra_racket_runtime_transfer_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_transfer_turn_procedure,
        odra_runtime_transfer_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for transfer commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_TRANSFER, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for transfer commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket transfer command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_search_probe runs one dynamically scoped search scenario.
int odra_racket_runtime_search_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_search_turn_procedure,
        odra_runtime_search_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for search commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_SEARCH, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for search commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket search command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_buffer_session_probe runs one dynamically scoped session scenario.
int odra_racket_runtime_buffer_session_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_buffer_session_turn_procedure,
        odra_runtime_buffer_session_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL ||
        token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for buffer session commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_BUFFER_SESSION, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for buffer session commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket buffer session returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_project_directory_resolution copies current Project matches.
int odra_racket_runtime_project_directory_resolution(
    const uint8_t *projects_directory,
    uint64_t projects_directory_length,
    const uint8_t *directory,
    uint64_t directory_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_project_directory_resolution_procedure == 0 ||
        projects_directory == NULL || projects_directory_length == 0 ||
        projects_directory_length > (uint64_t)INTPTR_MAX ||
        directory == NULL || directory_length == 0 ||
        directory_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Project directory resolution");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr projects_value = Smake_bytevector((iptr)projects_directory_length, 0);
    memcpy(Sbytevector_data(projects_value), projects_directory,
           (size_t)projects_directory_length);
    ptr directory_value = Smake_bytevector((iptr)directory_length, 0);
    memcpy(Sbytevector_data(directory_value), directory, (size_t)directory_length);
    ptr arguments = Scons(projects_value, Scons(directory_value, Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_project_directory_resolution_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project directory resolution returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project directory resolution exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_project_catalog_resolution copies valid registered Projects.
int odra_racket_runtime_project_catalog_resolution(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_project_catalog_resolution_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Project catalog resolution");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr arguments = Scons(configuration_value, Snil);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_project_catalog_resolution_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project catalog resolution returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project catalog resolution exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_platform_roots copies one resolved platform-root record.
int odra_racket_runtime_platform_roots(
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_platform_roots_procedure == 0 ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for platform-root resolution");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr envelope = Scar(racket_apply(odra_runtime_platform_roots_procedure, Snil));
    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket platform-root resolution returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket platform-root resolution exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_personal_configuration_startup copies one startup init.rkt result.
int odra_racket_runtime_personal_configuration_startup(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_personal_configuration_startup_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for personal configuration startup");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr arguments = Scons(configuration_value, Snil);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_personal_configuration_startup_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal configuration startup returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal configuration startup exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_personal_configuration_reload copies one reload candidate result.
int odra_racket_runtime_personal_configuration_reload(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    uint64_t expected_generation,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_personal_configuration_reload_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX || expected_generation == 0 ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for personal configuration reload");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr arguments = Scons(
        configuration_value,
        Scons(Sunsigned64(expected_generation), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_personal_configuration_reload_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal configuration reload returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal configuration reload exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_provider_invoke dispatches one bounded semantic provider request.
int odra_racket_runtime_provider_invoke(
    const uint8_t *service,
    uint64_t service_length,
    uint64_t generation,
    uint64_t operation,
    const uint8_t *name,
    uint64_t name_length,
    const uint8_t *payload,
    uint64_t payload_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_provider_invoke_procedure == 0 ||
        service == NULL || service_length == 0 ||
        service_length > (uint64_t)INTPTR_MAX ||
        name_length > (uint64_t)INTPTR_MAX ||
        payload_length > (uint64_t)INTPTR_MAX ||
        (name_length > 0 && name == NULL) ||
        (payload_length > 0 && payload == NULL) ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for provider invocation");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr service_value = Smake_bytevector((iptr)service_length, 0);
    memcpy(Sbytevector_data(service_value), service, (size_t)service_length);
    ptr name_value = Smake_bytevector((iptr)name_length, 0);
    if (name_length > 0) {
        memcpy(Sbytevector_data(name_value), name, (size_t)name_length);
    }
    ptr payload_value = Smake_bytevector((iptr)payload_length, 0);
    if (payload_length > 0) {
        memcpy(Sbytevector_data(payload_value), payload, (size_t)payload_length);
    }
    ptr arguments = Scons(
        service_value,
        Scons(
            Sunsigned64(generation),
            Scons(
                Sunsigned64(operation),
                Scons(name_value, Scons(payload_value, Snil)))));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_provider_invoke_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket provider invocation returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket provider invocation exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (length > 0) {
        memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    }
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}
// odra_racket_runtime_personal_generation_transition confirms or discards one candidate.
int odra_racket_runtime_personal_generation_transition(
    uint64_t transition,
    uint64_t generation,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_personal_generation_transition_procedure == 0 ||
        transition == 0 || generation == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for personal generation transition");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = Scons(
        Sunsigned64(transition),
        Scons(Sunsigned64(generation), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_personal_generation_transition_procedure, arguments));
    Sunlock_object(arguments);
    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbooleanp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal generation transition returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    if (parts[1] != Strue) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket personal generation transition returned an invalid result");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_project_promotion publishes one explicitly named Dir identity.
int odra_racket_runtime_project_promotion(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *directory,
    uint64_t directory_length,
    const uint8_t *name,
    uint64_t name_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_project_promotion_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        directory == NULL || directory_length == 0 ||
        directory_length > (uint64_t)INTPTR_MAX ||
        name == NULL || name_length == 0 || name_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Project promotion");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr directory_value = Smake_bytevector((iptr)directory_length, 0);
    memcpy(Sbytevector_data(directory_value), directory, (size_t)directory_length);
    ptr name_value = Smake_bytevector((iptr)name_length, 0);
    memcpy(Sbytevector_data(name_value), name, (size_t)name_length);
    ptr arguments = Scons(
        configuration_value,
        Scons(directory_value, Scons(name_value, Snil)));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(odra_runtime_project_promotion_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project promotion returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project promotion exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_project_rename publishes one checked Project display name.
int odra_racket_runtime_project_rename(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *directory,
    uint64_t directory_length,
    const uint8_t *name,
    uint64_t name_length,
    uint64_t generation,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_project_rename_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        directory == NULL || directory_length == 0 ||
        directory_length > (uint64_t)INTPTR_MAX ||
        name == NULL || name_length == 0 || name_length > (uint64_t)INTPTR_MAX ||
        generation == 0 || output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Project rename");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr directory_value = Smake_bytevector((iptr)directory_length, 0);
    memcpy(Sbytevector_data(directory_value), directory, (size_t)directory_length);
    ptr name_value = Smake_bytevector((iptr)name_length, 0);
    memcpy(Sbytevector_data(name_value), name, (size_t)name_length);
    ptr arguments = Scons(
        configuration_value,
        Scons(directory_value,
              Scons(name_value, Scons(Sunsigned64(generation), Snil))));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(odra_runtime_project_rename_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project rename returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project rename exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_project_unregister removes one exact global Project reference.
int odra_racket_runtime_project_unregister(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *id,
    uint64_t id_length,
    const uint8_t *root,
    uint64_t root_length,
    uint64_t generation,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_project_unregister_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        id == NULL || id_length == 0 || id_length > (uint64_t)INTPTR_MAX ||
        root == NULL || root_length == 0 || root_length > (uint64_t)INTPTR_MAX ||
        generation == 0 ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Project unregister");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr id_value = Smake_bytevector((iptr)id_length, 0);
    memcpy(Sbytevector_data(id_value), id, (size_t)id_length);
    ptr root_value = Smake_bytevector((iptr)root_length, 0);
    memcpy(Sbytevector_data(root_value), root, (size_t)root_length);
    ptr arguments = Scons(
        configuration_value,
        Scons(id_value, Scons(root_value, Scons(Sunsigned64(generation), Snil))));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(odra_runtime_project_unregister_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project unregister returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Project unregister exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_promotion_suppression inspects or updates one global Dir preference.
int odra_racket_runtime_promotion_suppression(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *directory,
    uint64_t directory_length,
    uint64_t action,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_promotion_suppression_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        directory == NULL || directory_length == 0 ||
        directory_length > (uint64_t)INTPTR_MAX || action < 1 || action > 3 ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for promotion suppression");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr directory_value = Smake_bytevector((iptr)directory_length, 0);
    memcpy(Sbytevector_data(directory_value), directory, (size_t)directory_length);
    ptr arguments = Scons(
        configuration_value,
        Scons(directory_value, Scons(Sunsigned64(action), Snil)));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_promotion_suppression_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket promotion suppression returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket promotion suppression exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_workspace_command copies one bounded programmable Workspace exchange.
int odra_racket_runtime_workspace_command(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *request,
    uint64_t request_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_workspace_command_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        request == NULL || request_length == 0 || request_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Workspace commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr request_value = Smake_bytevector((iptr)request_length, 0);
    memcpy(Sbytevector_data(request_value), request, (size_t)request_length);
    ptr arguments = Scons(configuration_value, Scons(request_value, Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(odra_runtime_workspace_command_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Workspace command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Workspace command exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_named_location_command copies one bounded named-location exchange.
int odra_racket_runtime_named_location_command(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *request,
    uint64_t request_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_named_location_command_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        request == NULL || request_length == 0 || request_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for named-location commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr request_value = Smake_bytevector((iptr)request_length, 0);
    memcpy(Sbytevector_data(request_value), request, (size_t)request_length);
    ptr arguments = Scons(configuration_value, Scons(request_value, Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(odra_runtime_named_location_command_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket named-location command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket named-location command exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_named_slot_command copies one bounded named-slot exchange.
int odra_racket_runtime_named_slot_command(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *request,
    uint64_t request_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_named_slot_command_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        request == NULL || request_length == 0 || request_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for named-slot commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr request_value = Smake_bytevector((iptr)request_length, 0);
    memcpy(Sbytevector_data(request_value), request, (size_t)request_length);
    ptr arguments = Scons(configuration_value, Scons(request_value, Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(odra_runtime_named_slot_command_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket named-slot command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket named-slot command exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_package_catalog_command copies one bounded catalog exchange.
int odra_racket_runtime_package_catalog_command(
    const uint8_t *configuration_root,
    uint64_t configuration_root_length,
    const uint8_t *request,
    uint64_t request_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_package_catalog_command_procedure == 0 ||
        configuration_root == NULL || configuration_root_length == 0 ||
        configuration_root_length > (uint64_t)INTPTR_MAX ||
        request == NULL || request_length == 0 || request_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for package-catalog commands");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr configuration_value = Smake_bytevector((iptr)configuration_root_length, 0);
    memcpy(Sbytevector_data(configuration_value), configuration_root,
           (size_t)configuration_root_length);
    ptr request_value = Smake_bytevector((iptr)request_length, 0);
    memcpy(Sbytevector_data(request_value), request, (size_t)request_length);
    ptr arguments = Scons(configuration_value, Scons(request_value, Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(odra_runtime_package_catalog_command_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket package-catalog command returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket package-catalog command exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_candidate_usage_load copies one bounded Project history observation.
int odra_racket_runtime_candidate_usage_load(
    const uint8_t *state_root,
    uint64_t state_root_length,
    const uint8_t *project_id,
    uint64_t project_id_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_candidate_usage_load_procedure == 0 ||
        state_root == NULL || state_root_length == 0 ||
        state_root_length > (uint64_t)INTPTR_MAX ||
        project_id == NULL || project_id_length == 0 ||
        project_id_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for candidate usage loading");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr root_value = Smake_bytevector((iptr)state_root_length, 0);
    memcpy(Sbytevector_data(root_value), state_root, (size_t)state_root_length);
    ptr project_value = Smake_bytevector((iptr)project_id_length, 0);
    memcpy(Sbytevector_data(project_value), project_id, (size_t)project_id_length);
    ptr arguments = Scons(root_value, Scons(project_value, Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_candidate_usage_load_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket candidate usage load returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket candidate usage load exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_candidate_usage_publish persists one exact native history snapshot.
int odra_racket_runtime_candidate_usage_publish(
    const uint8_t *state_root,
    uint64_t state_root_length,
    const uint8_t *project_id,
    uint64_t project_id_length,
    const uint8_t *request,
    uint64_t request_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        odra_runtime_candidate_usage_publish_procedure == 0 ||
        state_root == NULL || state_root_length == 0 ||
        state_root_length > (uint64_t)INTPTR_MAX ||
        project_id == NULL || project_id_length == 0 ||
        project_id_length > (uint64_t)INTPTR_MAX ||
        request == NULL || request_length == 0 || request_length > (uint64_t)INTPTR_MAX ||
        output == NULL || output_capacity == 0 || output_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for candidate usage persistence");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr root_value = Smake_bytevector((iptr)state_root_length, 0);
    memcpy(Sbytevector_data(root_value), state_root, (size_t)state_root_length);
    ptr project_value = Smake_bytevector((iptr)project_id_length, 0);
    memcpy(Sbytevector_data(project_value), project_id, (size_t)project_id_length);
    ptr request_value = Smake_bytevector((iptr)request_length, 0);
    memcpy(Sbytevector_data(request_value), request, (size_t)request_length);
    ptr arguments = Scons(
        root_value, Scons(project_value, Scons(request_value, Snil)));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(
        odra_runtime_candidate_usage_publish_procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[1]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket candidate usage persistence returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    uint64_t length = (uint64_t)Sbytevector_length(parts[1]);
    if (length == 0 || length > output_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket candidate usage persistence exceeds copied storage");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(output, Sbytevector_data(parts[1]), (size_t)length);
    *output_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_layout_probe runs one dynamically scoped layout scenario.
int odra_racket_runtime_layout_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_layout_turn_procedure,
        odra_runtime_layout_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for layout capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_LAYOUT, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for layout capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket layout capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_ui_role_probe runs one dynamically scoped UI role scenario.
int odra_racket_runtime_ui_role_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_ui_role_turn_procedure,
        odra_runtime_ui_role_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for UI role capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_UI_ROLE, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for UI role capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket UI role capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_theme_probe runs one dynamically scoped theme scenario.
int odra_racket_runtime_theme_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_theme_turn_procedure,
        odra_runtime_theme_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for theme capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_THEME, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for theme capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket theme capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_structural_probe runs one dynamically scoped structural scenario.
int odra_racket_runtime_structural_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_structural_turn_procedure,
        odra_runtime_structural_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for structural capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_STRUCTURAL, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for structural capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket structural capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_language_service_probe runs one dynamically scoped service scenario.
int odra_racket_runtime_language_service_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_language_service_turn_procedure,
        odra_runtime_language_service_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for language-service capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_LANGUAGE_SERVICE, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for language-service capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = odra_runtime_capability_turn_arguments(
        scenario, generation, token);
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket language-service capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_result_probe runs one dynamically scoped result-provider scenario.
int odra_racket_runtime_result_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_result_turn_procedure;
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for result capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_RESULT, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for result capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    (void)scenario;
    ptr arguments = Scons(Sunsigned64(generation), Scons(Sunsigned64(token), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket result capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_status_bar_probe runs one dynamically scoped Status Bar scenario.
int odra_racket_runtime_status_bar_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_status_bar_turn_procedure;
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Status Bar capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_STATUS_BAR, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for Status Bar capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    (void)scenario;
    ptr arguments = Scons(Sunsigned64(generation), Scons(Sunsigned64(token), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket Status Bar capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_terminal_probe runs one dynamically scoped terminal scenario.
int odra_racket_runtime_terminal_probe(
    int32_t scenario,
    uint64_t token,
    odra_scoped_capability_callback callback,
    void *user_data,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure;
    if (scenario == 0) {
        procedure = odra_runtime_terminal_turn_procedure;
    } else if (scenario == 1) {
        procedure = odra_runtime_terminal_delivery_turn_procedure;
    } else {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket terminal capability scenario is unavailable");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || callback == NULL || token == 0) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for terminal capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    uint64_t generation;
    if (!odra_scoped_capability_begin(
            ODRA_SCOPED_CAPABILITY_TERMINAL, token, 0,
            callback, user_data, &generation)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for terminal capabilities");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    ptr arguments = Scons(Sunsigned64(generation), Scons(Sunsigned64(token), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);
    odra_scoped_capability_end();

    ptr parts[3];
    if (!odra_runtime_list_parts(envelope, parts, 3) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[2])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket terminal capability returned an invalid envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[2], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

static void odra_runtime_racket_diagnostic(
    ptr racket_diagnostic,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    uint64_t length = (uint64_t)Sbytevector_length(racket_diagnostic);
    if (diagnostic == NULL || diagnostic_capacity == 0) {
        return;
    }
    uint64_t copied = length < diagnostic_capacity - 1
        ? length
        : diagnostic_capacity - 1;
    memcpy(diagnostic, Sbytevector_data(racket_diagnostic), (size_t)copied);
    diagnostic[copied] = '\0';
}

// odra_racket_runtime_boundary_stats reports rooted-procedure lifecycle counts.
int odra_racket_runtime_boundary_stats(
    uint64_t *live,
    uint64_t *loaded,
    uint64_t *released
) {
    if (live == NULL || loaded == NULL || released == NULL) {
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }
    *live = 0;
    for (size_t index = 0; index < ODRA_RUNTIME_BOUNDARY_COUNT; index += 1) {
        if (*odra_runtime_boundary[index].root != 0) {
            *live += 1;
        }
    }
    *loaded = odra_runtime_boundary_load_count;
    *released = odra_runtime_boundary_release_count;
    return ODRA_RUNTIME_ADAPTER_OK;
}

static int odra_racket_runtime_start_at(
    const uint8_t *schema,
    uint64_t schema_length,
    const char *boot_directory,
    const char *collects_directory,
    const char *config_directory,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_UNINITIALIZED) {
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket runtime adapter is not uninitialized");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    char petite_boot[4096];
    char scheme_boot[4096];
    char racket_boot_image[4096];
    if (!odra_runtime_readable_directory(boot_directory) ||
        !odra_runtime_readable_directory(collects_directory) ||
        !odra_runtime_readable_directory(config_directory) ||
        !odra_runtime_join_path(
            petite_boot, sizeof(petite_boot), boot_directory, "petite.boot") ||
        !odra_runtime_join_path(
            scheme_boot, sizeof(scheme_boot), boot_directory, "scheme.boot") ||
        !odra_runtime_join_path(
            racket_boot_image, sizeof(racket_boot_image), boot_directory, "racket.boot") ||
        !odra_runtime_readable_file(petite_boot) ||
        !odra_runtime_readable_file(scheme_boot) ||
        !odra_runtime_readable_file(racket_boot_image)) {
        odra_runtime_state = ODRA_RUNTIME_ADAPTER_FAILED;
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket runtime resources are unavailable");
        return ODRA_RUNTIME_ADAPTER_MISSING_BOOT_IMAGE;
    }

    racket_boot_arguments_t arguments;
    memset(&arguments, 0, sizeof(arguments));
    arguments.exec_file = "odra";
    arguments.boot1_path = petite_boot;
    arguments.boot2_path = scheme_boot;
    arguments.boot3_path = racket_boot_image;
    arguments.collects_dir = collects_directory;
    arguments.config_dir = config_directory;
    racket_boot(&arguments);
    Sforeign_symbol(
        "odra_racket_scoped_capability_call",
        (void *)(uintptr_t)&odra_racket_scoped_capability_call);
    declare_modules();

    if (!odra_runtime_call_start(
            schema,
            schema_length,
            diagnostic,
            diagnostic_capacity)) {
        Sscheme_deinit();
        odra_runtime_state = ODRA_RUNTIME_ADAPTER_FAILED;
        if (diagnostic != NULL && diagnostic_capacity > 0 && diagnostic[0] == '\0') {
            odra_runtime_diagnostic(
                diagnostic,
                diagnostic_capacity,
                "Odra built-in Racket module returned an invalid startup result");
        }
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (!odra_runtime_load_procedures(diagnostic, diagnostic_capacity)) {
        Sscheme_deinit();
        odra_runtime_state = ODRA_RUNTIME_ADAPTER_FAILED;
        if (diagnostic != NULL && diagnostic_capacity > 0 && diagnostic[0] == '\0') {
            odra_runtime_diagnostic(
                diagnostic,
                diagnostic_capacity,
                "Odra built-in Racket procedures are unavailable");
        }
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }

    odra_runtime_state = ODRA_RUNTIME_ADAPTER_READY;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_start boots the development runtime from configured host paths.
int odra_racket_runtime_start(
    const uint8_t *schema,
    uint64_t schema_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    return odra_racket_runtime_start_at(
        schema,
        schema_length,
        ODRA_RACKET_BOOT_DIR,
        ODRA_RACKET_COLLECTS_DIR,
        ODRA_RACKET_CONFIG_DIR,
        diagnostic,
        diagnostic_capacity);
}

// odra_racket_runtime_start_with_resources boots from explicit absolute test paths.
int odra_racket_runtime_start_with_resources(
    const uint8_t *schema,
    uint64_t schema_length,
    const uint8_t *boot_directory,
    uint64_t boot_directory_length,
    const uint8_t *collects_directory,
    uint64_t collects_directory_length,
    const uint8_t *config_directory,
    uint64_t config_directory_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    char boot_path[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    char collects_path[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    char config_path[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    if (!odra_runtime_copy_resource_path(
            boot_path,
            sizeof(boot_path),
            boot_directory,
            boot_directory_length) ||
        !odra_runtime_copy_resource_path(
            collects_path,
            sizeof(collects_path),
            collects_directory,
            collects_directory_length) ||
        !odra_runtime_copy_resource_path(
            config_path,
            sizeof(config_path),
            config_directory,
            config_directory_length)) {
        odra_runtime_state = ODRA_RUNTIME_ADAPTER_FAILED;
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket runtime resource paths are invalid");
        return ODRA_RUNTIME_ADAPTER_MISSING_BOOT_IMAGE;
    }
    return odra_racket_runtime_start_at(
        schema,
        schema_length,
        boot_path,
        collects_path,
        config_path,
        diagnostic,
        diagnostic_capacity);
}

// odra_racket_runtime_start_bundled resolves resources from the executable bundle.
int odra_racket_runtime_start_bundled(
    const uint8_t *schema,
    uint64_t schema_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    char boot_directory[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    char collects_directory[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    char config_directory[ODRA_RUNTIME_RESOURCE_PATH_CAPACITY];
    if (!odra_runtime_bundle_resource_paths(
            boot_directory,
            collects_directory,
            config_directory)) {
        odra_runtime_state = ODRA_RUNTIME_ADAPTER_FAILED;
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket bundle resources are unavailable or escape the bundle root");
        return ODRA_RUNTIME_ADAPTER_MISSING_BOOT_IMAGE;
    }
    return odra_racket_runtime_start_at(
        schema,
        schema_length,
        boot_directory,
        collects_directory,
        config_directory,
        diagnostic,
        diagnostic_capacity);
}

// odra_racket_runtime_call_scalar invokes one checked built-in scalar operation.
int odra_racket_runtime_call_scalar(
    int32_t scenario,
    int64_t input,
    int64_t *output,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_call_procedure,
        odra_runtime_call_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 || output == NULL) {
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket runtime adapter is not ready for calls");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario, Scons(Sinteger64(input), Snil));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr success;
    ptr value;
    ptr racket_diagnostic;
    if (!odra_runtime_result_parts(envelope, &success, &value, &racket_diagnostic) ||
        !Sbooleanp(success) || !Sbytevectorp(racket_diagnostic)) {
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket call returned an invalid result envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }

    if (success == Sfalse) {
        odra_runtime_racket_diagnostic(
            racket_diagnostic, diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }

    if (!Sfixnump(value) && !Sbignump(value)) {
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket call returned a non-integer scalar");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }

    *output = Sinteger64_value(value);
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_command_request asks Racket for one bounded inspection range.
int odra_racket_runtime_command_request(
    int32_t scenario,
    uint64_t capability,
    uint64_t buffer_id,
    uint64_t revision,
    uint64_t *start,
    uint64_t *end,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_command_request_procedure,
        odra_runtime_command_request_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 ||
        start == NULL || end == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for command requests");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario,
        Scons(
            Sunsigned64(capability),
            Scons(Sunsigned64(buffer_id), Scons(Sunsigned64(revision), Snil))));
    Slock_object(arguments);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[4];
    if (!odra_runtime_list_parts(envelope, parts, 4) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[3])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket command returned an invalid inspection envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[3], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }
    if (!odra_runtime_integer_value(parts[1], start) ||
        !odra_runtime_integer_value(parts[2], end)) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket command returned a non-integer inspection range");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_command_transform returns one copied replacement request.
int odra_racket_runtime_command_transform(
    int32_t scenario,
    uint64_t capability,
    uint64_t buffer_id,
    uint64_t revision,
    uint64_t start,
    uint64_t end,
    const uint8_t *input,
    uint64_t input_length,
    uint64_t *result_start,
    uint64_t *result_end,
    uint8_t *replacement,
    uint64_t replacement_capacity,
    uint64_t *replacement_length,
    char *diagnostic,
    uint64_t diagnostic_capacity
) {
    ptr procedure = odra_runtime_capability_turn_procedure(
        scenario,
        odra_runtime_command_transform_procedure,
        odra_runtime_command_transform_probe_procedure);
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY ||
        procedure == 0 ||
        (input == NULL && input_length != 0) || result_start == NULL ||
        result_end == NULL || replacement == NULL || replacement_length == NULL) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket runtime adapter is not ready for command transforms");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    ptr input_value = Smake_bytevector((iptr)input_length, 0);
    Slock_object(input_value);
    if (input_length != 0) {
        memcpy(Sbytevector_data(input_value), input, (size_t)input_length);
    }
    ptr arguments = odra_runtime_turn_arguments_with_scenario(
        scenario,
        Scons(
            Sunsigned64(capability),
            Scons(
                Sunsigned64(buffer_id),
                Scons(
                    Sunsigned64(revision),
                    Scons(
                        Sunsigned64(start),
                        Scons(Sunsigned64(end), Scons(input_value, Snil)))))));
    Slock_object(arguments);
    Sunlock_object(input_value);
    ptr envelope = Scar(racket_apply(procedure, arguments));
    Sunlock_object(arguments);

    ptr parts[8];
    if (!odra_runtime_list_parts(envelope, parts, 8) ||
        !Sbooleanp(parts[0]) || !Sbytevectorp(parts[6]) ||
        !Sbytevectorp(parts[7])) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket command returned an invalid replacement envelope");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    if (parts[0] == Sfalse) {
        odra_runtime_racket_diagnostic(parts[7], diagnostic, diagnostic_capacity);
        return ODRA_RUNTIME_ADAPTER_RACKET_EXCEPTION;
    }

    uint64_t echoed_capability;
    uint64_t echoed_buffer_id;
    uint64_t echoed_revision;
    if (!odra_runtime_integer_value(parts[1], &echoed_capability) ||
        !odra_runtime_integer_value(parts[2], &echoed_buffer_id) ||
        !odra_runtime_integer_value(parts[3], &echoed_revision) ||
        !odra_runtime_integer_value(parts[4], result_start) ||
        !odra_runtime_integer_value(parts[5], result_end) ||
        echoed_capability != capability || echoed_buffer_id != buffer_id ||
        echoed_revision != revision) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket command returned a mismatched replacement identity");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }

    uint64_t length = (uint64_t)Sbytevector_length(parts[6]);
    if (length > replacement_capacity) {
        odra_runtime_diagnostic(
            diagnostic, diagnostic_capacity,
            "Racket replacement exceeds the command output capacity");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }
    memcpy(replacement, Sbytevector_data(parts[6]), (size_t)length);
    *replacement_length = length;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}

// odra_racket_runtime_stop stops the built-in module and releases Racket CS once.
int odra_racket_runtime_stop(char *diagnostic, uint64_t diagnostic_capacity) {
    if (odra_runtime_state != ODRA_RUNTIME_ADAPTER_READY) {
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Racket runtime adapter is not ready");
        return ODRA_RUNTIME_ADAPTER_INVALID_STATE;
    }

    int stopped = odra_runtime_call_lifecycle(
        "runtime-stop",
        ODRA_RACKET_EXPECTED_STOP_SYMBOL);
    odra_runtime_release_procedures();
    Sscheme_deinit();
    if (!stopped) {
        odra_runtime_state = ODRA_RUNTIME_ADAPTER_FAILED;
        odra_runtime_diagnostic(
            diagnostic,
            diagnostic_capacity,
            "Odra built-in Racket module returned an invalid shutdown result");
        return ODRA_RUNTIME_ADAPTER_WRONG_MODULE_RESULT;
    }

    odra_runtime_state = ODRA_RUNTIME_ADAPTER_STOPPED;
    odra_runtime_diagnostic(diagnostic, diagnostic_capacity, "");
    return ODRA_RUNTIME_ADAPTER_OK;
}
