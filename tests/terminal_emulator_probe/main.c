// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#include "adapter.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int check(bool condition, const char* message, int code) {
    if (!condition) {
        fprintf(stderr, "terminal emulator probe: %s\n", message);
        return code;
    }
    return 0;
}

static bool contains_bytes(
    const uint8_t* bytes,
    size_t length,
    const uint8_t* expected,
    size_t expected_length) {
    if (expected_length > length) {
        return false;
    }
    for (size_t offset = 0; offset <= length - expected_length; offset += 1) {
        if (memcmp(bytes + offset, expected, expected_length) == 0) {
            return true;
        }
    }
    return false;
}

int main(void) {
    bool supported = false;
    const OdraTerminalEmulatorFeature required_features[] = {
        ODRA_TERMINAL_EMULATOR_FEATURE_KEY_ENCODING,
        ODRA_TERMINAL_EMULATOR_FEATURE_MOUSE_ENCODING,
        ODRA_TERMINAL_EMULATOR_FEATURE_SELECTION,
        ODRA_TERMINAL_EMULATOR_FEATURE_SNAPSHOT,
        ODRA_TERMINAL_EMULATOR_FEATURE_KITTY_GRAPHICS,
    };
    for (size_t index = 0; index < sizeof(required_features) / sizeof(required_features[0]); index += 1) {
        if (check(
                odra_terminal_emulator_feature(required_features[index], &supported) ==
                    ODRA_TERMINAL_EMULATOR_OK && supported,
                "required feature unavailable",
                10)) {
            return 10;
        }
    }
    if (check(
            odra_terminal_emulator_feature(ODRA_TERMINAL_EMULATOR_FEATURE_SIMD, &supported) ==
                ODRA_TERMINAL_EMULATOR_OK && !supported,
            "SIMD policy mismatch",
            11)) {
        return 11;
    }
    if (check(
            odra_terminal_emulator_feature(99, &supported) ==
                ODRA_TERMINAL_EMULATOR_UNSUPPORTED,
            "unsupported feature accepted",
            12)) {
        return 12;
    }

    OdraTerminalEmulatorOptions options = {
        .columns = 80,
        .rows = 24,
        .cell_width_pixels = 8,
        .cell_height_pixels = 16,
        .scrollback_max_bytes = 32u * 1024u * 1024u,
        .scrollback_max_lines = 100000u,
    };
    OdraTerminalEmulatorRef ref = {0};
    if (check(
            odra_terminal_emulator_open(NULL, &ref) ==
                ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT,
            "null options accepted",
            20)) {
        return 20;
    }
    OdraTerminalEmulatorOptions fault_options = options;
    fault_options.allocation_fail_after = 1;
    if (check(
            odra_terminal_emulator_open(&fault_options, &ref) ==
                ODRA_TERMINAL_EMULATOR_ALLOCATION_FAILED && ref.slot == 0,
            "allocation fault was not contained",
            21)) {
        return 21;
    }
    if (check(
            odra_terminal_emulator_open(&options, &ref) == ODRA_TERMINAL_EMULATOR_OK &&
                ref.slot != 0 && ref.generation != 0,
            "terminal creation failed",
            22)) {
        return 22;
    }

    const uint8_t malformed[] = {0x1b};
    if (check(
            odra_terminal_emulator_write(ref, malformed, sizeof(malformed)) ==
                ODRA_TERMINAL_EMULATOR_OK,
            "partial control sequence rejected",
            30)) {
        return 30;
    }
    const uint8_t content[] = "cHello\r\nWorld\a\x1b[6n";
    if (check(
            odra_terminal_emulator_write(ref, content, sizeof(content) - 1) ==
                ODRA_TERMINAL_EMULATOR_OK,
            "terminal write failed",
            31)) {
        return 31;
    }
    if (check(
            odra_terminal_emulator_write(ref, NULL, 1) ==
                ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT,
            "null input accepted",
            32)) {
        return 32;
    }

    OdraTerminalEmulatorRenderState render = {0};
    if (check(
            odra_terminal_emulator_render(ref, &render) == ODRA_TERMINAL_EMULATOR_OK &&
                render.columns == 80 && render.rows == 24,
            "initial render state mismatch",
            40)) {
        return 40;
    }
    if (check(
            odra_terminal_emulator_resize(ref, 120, 40, 9, 18) ==
                ODRA_TERMINAL_EMULATOR_OK &&
                odra_terminal_emulator_render(ref, &render) == ODRA_TERMINAL_EMULATOR_OK &&
                render.columns == 120 && render.rows == 40,
            "resized render state mismatch",
            41)) {
        return 41;
    }
    if (check(
            odra_terminal_emulator_resize(ref, 0, 40, 9, 18) ==
                ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT,
            "invalid geometry accepted",
            42)) {
        return 42;
    }

    uint8_t input[64] = {0};
    size_t written = 0;
    const uint8_t key_text[] = "x";
    if (check(
            odra_terminal_emulator_encode_key(
                ref,
                ODRA_TERMINAL_EMULATOR_KEY_CHARACTER,
                ODRA_TERMINAL_EMULATOR_KEY_PRESS,
                0,
                key_text,
                sizeof(key_text) - 1,
                input,
                sizeof(input),
                &written) == ODRA_TERMINAL_EMULATOR_OK &&
                written == 1 && input[0] == 'x',
            "key encoding mismatch",
            50)) {
        return 50;
    }
    if (check(
            odra_terminal_emulator_encode_key(
                ref, 99, ODRA_TERMINAL_EMULATOR_KEY_PRESS, 0,
                NULL, 0, input, sizeof(input), &written) ==
                ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT,
            "foreign key enum leaked through adapter",
            51)) {
        return 51;
    }
    if (check(
            odra_terminal_emulator_encode_mouse(
                ref,
                ODRA_TERMINAL_EMULATOR_MOUSE_MOTION,
                ODRA_TERMINAL_EMULATOR_MOUSE_NONE,
                0,
                4,
                8,
                input,
                sizeof(input),
                &written) == ODRA_TERMINAL_EMULATOR_OK,
            "mouse encoding failed",
            52)) {
        return 52;
    }

    uint8_t selection[128] = {0};
    if (check(
            odra_terminal_emulator_select_all(ref, selection, sizeof(selection), &written) ==
                ODRA_TERMINAL_EMULATOR_OK &&
                written >= 10 &&
                contains_bytes(selection, written, (const uint8_t*) "Hello", 5),
            "selection copy mismatch",
            60)) {
        return 60;
    }
    size_t snapshot_size = 0;
    if (check(
            odra_terminal_emulator_snapshot(ref, NULL, 0, &snapshot_size) ==
                ODRA_TERMINAL_EMULATOR_BUFFER_TOO_SMALL && snapshot_size > 0,
            "snapshot size query failed",
            61)) {
        return 61;
    }
    uint8_t* snapshot = malloc(snapshot_size);
    if (check(snapshot != NULL, "snapshot allocation failed", 62)) {
        return 62;
    }
    if (check(
            odra_terminal_emulator_snapshot(ref, snapshot, snapshot_size, &written) ==
                ODRA_TERMINAL_EMULATOR_OK && written == snapshot_size,
            "snapshot encoding failed",
            63)) {
        free(snapshot);
        return 63;
    }
    free(snapshot);

    OdraTerminalEmulatorEffects effects = {0};
    if (check(
            odra_terminal_emulator_effects(ref, &effects) == ODRA_TERMINAL_EMULATOR_OK &&
                effects.bell_count == 1 && effects.writeback_count >= 1 &&
                effects.writeback_bytes > 0 && effects.writeback_pending_bytes > 0 &&
                effects.writeback_dropped_bytes == 0,
            "effect accounting mismatch",
            70)) {
        return 70;
    }
    uint8_t writeback[64] = {0};
    size_t writeback_written = 0;
    size_t writeback_pending = 0;
    if (check(
            odra_terminal_emulator_writeback_copy(
                ref,
                writeback,
                sizeof(writeback),
                &writeback_written,
                &writeback_pending) == ODRA_TERMINAL_EMULATOR_OK &&
                writeback_written > 0 && writeback_written == writeback_pending &&
                writeback[0] == 0x1b,
            "writeback copy mismatch",
            71)) {
        return 71;
    }
    if (check(
            odra_terminal_emulator_writeback_consume(ref, writeback_written) ==
                    ODRA_TERMINAL_EMULATOR_OK &&
                odra_terminal_emulator_effects(ref, &effects) ==
                    ODRA_TERMINAL_EMULATOR_OK &&
                effects.writeback_pending_bytes == 0,
            "writeback consume mismatch",
            72)) {
        return 72;
    }
    const size_t query_bytes = ODRA_TERMINAL_EMULATOR_WRITEBACK_CAPACITY;
    uint8_t* queries = malloc(query_bytes);
    if (check(queries != NULL, "writeback overflow fixture allocation failed", 73)) {
        return 73;
    }
    for (size_t offset = 0; offset < query_bytes; offset += 4) {
        memcpy(queries + offset, "\x1b[6n", 4);
    }
    OdraTerminalEmulatorResult overflow_write =
        odra_terminal_emulator_write(ref, queries, query_bytes);
    free(queries);
    if (check(
            overflow_write == ODRA_TERMINAL_EMULATOR_OK &&
                odra_terminal_emulator_effects(ref, &effects) ==
                    ODRA_TERMINAL_EMULATOR_OK &&
                effects.writeback_pending_bytes ==
                    ODRA_TERMINAL_EMULATOR_WRITEBACK_CAPACITY &&
                effects.writeback_dropped_bytes > 0,
            "writeback overflow was not bounded",
            74)) {
        return 74;
    }
    if (check(
            odra_terminal_emulator_writeback_consume(
                ref,
                ODRA_TERMINAL_EMULATOR_WRITEBACK_CAPACITY) ==
                ODRA_TERMINAL_EMULATOR_OK,
            "bounded writeback overflow cleanup failed",
            75)) {
        return 75;
    }
    uint64_t image_generation = 0;
    if (check(
            odra_terminal_emulator_image_generation(ref, &image_generation) ==
                ODRA_TERMINAL_EMULATOR_OK,
            "image storage unavailable",
            76)) {
        return 76;
    }

    OdraTerminalEmulatorStats stats = {0};
    if (check(
            odra_terminal_emulator_stats(ref, &stats) == ODRA_TERMINAL_EMULATOR_OK &&
                stats.live && stats.allocations > 0 && stats.live_bytes > 0,
            "live allocation accounting mismatch",
            80)) {
        return 80;
    }
    OdraTerminalEmulatorRef stale = ref;
    if (check(
            odra_terminal_emulator_close(ref) == ODRA_TERMINAL_EMULATOR_OK &&
                odra_terminal_emulator_close(ref) == ODRA_TERMINAL_EMULATOR_STALE_HANDLE,
            "terminal cleanup was not exact once",
            81)) {
        return 81;
    }
    if (check(
            odra_terminal_emulator_stats(stale, &stats) == ODRA_TERMINAL_EMULATOR_OK &&
                !stats.live && stats.live_bytes == 0 && stats.allocations == stats.frees,
            "closed allocation accounting mismatch",
            82)) {
        return 82;
    }
    if (check(
            odra_terminal_emulator_write(stale, NULL, 0) ==
                ODRA_TERMINAL_EMULATOR_STALE_HANDLE,
            "stale terminal accepted input",
            83)) {
        return 83;
    }

    for (size_t iteration = 0; iteration < 64; iteration += 1) {
        if (odra_terminal_emulator_open(&options, &ref) != ODRA_TERMINAL_EMULATOR_OK ||
            odra_terminal_emulator_close(ref) != ODRA_TERMINAL_EMULATOR_OK ||
            odra_terminal_emulator_stats(ref, &stats) != ODRA_TERMINAL_EMULATOR_OK ||
            stats.live_bytes != 0 || stats.allocations != stats.frees) {
            return check(false, "repeated lifecycle leaked resources", 90);
        }
    }
    if (check(ref.generation != stale.generation, "generation was not advanced", 91)) {
        return 91;
    }

    printf(
        "terminal_emulator_probe=passed cycles=65 peak_bytes=%llu image_generation=%llu\n",
        (unsigned long long) stats.peak_bytes,
        (unsigned long long) image_generation);
    return 0;
}
