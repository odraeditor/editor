// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#include "adapter.h"

#include <ghostty/vt.h>

#include <stdatomic.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define ODRA_TERMINAL_EMULATOR_CAPACITY 32u

typedef struct {
    uint32_t generation;
    bool live;
    uint64_t fail_after;
    uint64_t allocation_attempts;
    uint64_t allocations;
    uint64_t frees;
    uint64_t live_bytes;
    uint64_t peak_bytes;
    GhosttyAllocator allocator;
    GhosttyTerminal terminal;
    GhosttyRenderState render_state;
    GhosttyRenderStateRowIterator row_iterator;
    GhosttyRenderStateRowCells row_cells;
    GhosttyKeyEncoder key_encoder;
    GhosttyKeyEvent key_event;
    GhosttyMouseEncoder mouse_encoder;
    GhosttyMouseEvent mouse_event;
    GhosttyKittyGraphicsPlacementIterator image_iterator;
    OdraTerminalEmulatorEffects effects;
    uint8_t writeback[ODRA_TERMINAL_EMULATOR_WRITEBACK_CAPACITY];
    size_t writeback_length;
    GhosttyTrackedGridRef semantic_anchors[ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY];
    uint32_t semantic_anchor_generations[ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY];
} OdraTerminalEmulatorSlot;

static OdraTerminalEmulatorSlot slots[ODRA_TERMINAL_EMULATOR_CAPACITY];
static atomic_flag slots_lock = ATOMIC_FLAG_INIT;

static void lock_slots(void) {
    while (atomic_flag_test_and_set_explicit(&slots_lock, memory_order_acquire)) {
    }
}

static void unlock_slots(void) {
    atomic_flag_clear_explicit(&slots_lock, memory_order_release);
}

static void* tracked_alloc(
    void* context,
    size_t length,
    uint8_t alignment,
    uintptr_t return_address) {
    (void) alignment;
    (void) return_address;
    OdraTerminalEmulatorSlot* slot = context;
    slot->allocation_attempts += 1;
    if (slot->fail_after != 0 && slot->allocation_attempts >= slot->fail_after) {
        return NULL;
    }
    void* memory = malloc(length);
    if (memory != NULL) {
        slot->allocations += 1;
        slot->live_bytes += length;
        if (slot->live_bytes > slot->peak_bytes) {
            slot->peak_bytes = slot->live_bytes;
        }
    }
    return memory;
}

static bool tracked_resize(
    void* context,
    void* memory,
    size_t memory_length,
    uint8_t alignment,
    size_t new_length,
    uintptr_t return_address) {
    (void) context;
    (void) memory;
    (void) memory_length;
    (void) alignment;
    (void) new_length;
    (void) return_address;
    return false;
}

static void* tracked_remap(
    void* context,
    void* memory,
    size_t memory_length,
    uint8_t alignment,
    size_t new_length,
    uintptr_t return_address) {
    (void) context;
    (void) memory;
    (void) memory_length;
    (void) alignment;
    (void) new_length;
    (void) return_address;
    return NULL;
}

static void tracked_free(
    void* context,
    void* memory,
    size_t memory_length,
    uint8_t alignment,
    uintptr_t return_address) {
    (void) alignment;
    (void) return_address;
    OdraTerminalEmulatorSlot* slot = context;
    if (memory != NULL) {
        free(memory);
        slot->frees += 1;
        if (memory_length <= slot->live_bytes) {
            slot->live_bytes -= memory_length;
        } else {
            slot->live_bytes = 0;
        }
    }
}

static const GhosttyAllocatorVtable tracked_allocator_vtable = {
    .alloc = tracked_alloc,
    .resize = tracked_resize,
    .remap = tracked_remap,
    .free = tracked_free,
};

static OdraTerminalEmulatorResult map_result(GhosttyResult result) {
    switch (result) {
    case GHOSTTY_SUCCESS:
        return ODRA_TERMINAL_EMULATOR_OK;
    case GHOSTTY_INVALID_VALUE:
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    case GHOSTTY_OUT_OF_MEMORY:
        return ODRA_TERMINAL_EMULATOR_ALLOCATION_FAILED;
    case GHOSTTY_OUT_OF_SPACE:
        return ODRA_TERMINAL_EMULATOR_BUFFER_TOO_SMALL;
    case GHOSTTY_NO_VALUE:
        return ODRA_TERMINAL_EMULATOR_UNAVAILABLE;
    case GHOSTTY_REJECTED:
        return ODRA_TERMINAL_EMULATOR_REJECTED;
    default:
        return ODRA_TERMINAL_EMULATOR_FOREIGN_FAILURE;
    }
}

static uint64_t saturated_add(uint64_t value, uint64_t increment) {
    return increment > UINT64_MAX - value ? UINT64_MAX : value + increment;
}

static bool translate_key(int32_t key, GhosttyKey* out_key) {
    switch ((OdraTerminalEmulatorKey) key) {
    case ODRA_TERMINAL_EMULATOR_KEY_CHARACTER:
        *out_key = GHOSTTY_KEY_UNIDENTIFIED;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_ENTER:
        *out_key = GHOSTTY_KEY_ENTER;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_ARROW_UP:
        *out_key = GHOSTTY_KEY_ARROW_UP;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_ARROW_DOWN:
        *out_key = GHOSTTY_KEY_ARROW_DOWN;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_ARROW_LEFT:
        *out_key = GHOSTTY_KEY_ARROW_LEFT;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_ARROW_RIGHT:
        *out_key = GHOSTTY_KEY_ARROW_RIGHT;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_TAB:
        *out_key = GHOSTTY_KEY_TAB;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_BACKSPACE:
        *out_key = GHOSTTY_KEY_BACKSPACE;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_DELETE:
        *out_key = GHOSTTY_KEY_DELETE;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_ESCAPE:
        *out_key = GHOSTTY_KEY_ESCAPE;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_HOME:
        *out_key = GHOSTTY_KEY_HOME;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_END:
        *out_key = GHOSTTY_KEY_END;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_PAGE_UP:
        *out_key = GHOSTTY_KEY_PAGE_UP;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_PAGE_DOWN:
        *out_key = GHOSTTY_KEY_PAGE_DOWN;
        return true;
    case ODRA_TERMINAL_EMULATOR_KEY_SPACE:
        *out_key = GHOSTTY_KEY_SPACE;
        return true;
    default:
        return false;
    }
}

static bool translate_modifiers(uint32_t modifiers, GhosttyMods* out_modifiers) {
    const uint32_t admitted = ODRA_TERMINAL_EMULATOR_MOD_SHIFT |
        ODRA_TERMINAL_EMULATOR_MOD_CONTROL |
        ODRA_TERMINAL_EMULATOR_MOD_ALT |
        ODRA_TERMINAL_EMULATOR_MOD_SUPER;
    if ((modifiers & ~admitted) != 0) {
        return false;
    }
    GhosttyMods translated = 0;
    if ((modifiers & ODRA_TERMINAL_EMULATOR_MOD_SHIFT) != 0) {
        translated |= GHOSTTY_MODS_SHIFT;
    }
    if ((modifiers & ODRA_TERMINAL_EMULATOR_MOD_CONTROL) != 0) {
        translated |= GHOSTTY_MODS_CTRL;
    }
    if ((modifiers & ODRA_TERMINAL_EMULATOR_MOD_ALT) != 0) {
        translated |= GHOSTTY_MODS_ALT;
    }
    if ((modifiers & ODRA_TERMINAL_EMULATOR_MOD_SUPER) != 0) {
        translated |= GHOSTTY_MODS_SUPER;
    }
    *out_modifiers = translated;
    return true;
}

static bool translate_mouse_action(int32_t action, GhosttyMouseAction* out_action) {
    switch ((OdraTerminalEmulatorMouseAction) action) {
    case ODRA_TERMINAL_EMULATOR_MOUSE_PRESS:
        *out_action = GHOSTTY_MOUSE_ACTION_PRESS;
        return true;
    case ODRA_TERMINAL_EMULATOR_MOUSE_RELEASE:
        *out_action = GHOSTTY_MOUSE_ACTION_RELEASE;
        return true;
    case ODRA_TERMINAL_EMULATOR_MOUSE_MOTION:
        *out_action = GHOSTTY_MOUSE_ACTION_MOTION;
        return true;
    default:
        return false;
    }
}

static bool translate_mouse_button(int32_t button, GhosttyMouseButton* out_button) {
    switch ((OdraTerminalEmulatorMouseButton) button) {
    case ODRA_TERMINAL_EMULATOR_MOUSE_LEFT:
        *out_button = GHOSTTY_MOUSE_BUTTON_LEFT;
        return true;
    case ODRA_TERMINAL_EMULATOR_MOUSE_RIGHT:
        *out_button = GHOSTTY_MOUSE_BUTTON_RIGHT;
        return true;
    case ODRA_TERMINAL_EMULATOR_MOUSE_MIDDLE:
        *out_button = GHOSTTY_MOUSE_BUTTON_MIDDLE;
        return true;
    case ODRA_TERMINAL_EMULATOR_MOUSE_WHEEL_UP:
        *out_button = GHOSTTY_MOUSE_BUTTON_FOUR;
        return true;
    case ODRA_TERMINAL_EMULATOR_MOUSE_WHEEL_DOWN:
        *out_button = GHOSTTY_MOUSE_BUTTON_FIVE;
        return true;
    default:
        return false;
    }
}

static void configure_mouse_size(
    OdraTerminalEmulatorSlot* slot,
    uint16_t columns,
    uint16_t rows,
    uint32_t cell_width_pixels,
    uint32_t cell_height_pixels) {
    GhosttyMouseEncoderSize size = GHOSTTY_INIT_SIZED(GhosttyMouseEncoderSize);
    size.screen_width = (uint32_t) columns * cell_width_pixels;
    size.screen_height = (uint32_t) rows * cell_height_pixels;
    size.cell_width = cell_width_pixels;
    size.cell_height = cell_height_pixels;
    ghostty_mouse_encoder_setopt(slot->mouse_encoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size);
}

static OdraTerminalEmulatorSlot* find_slot(OdraTerminalEmulatorRef ref) {
    if (ref.slot == 0 || ref.slot > ODRA_TERMINAL_EMULATOR_CAPACITY ||
        ref.generation == 0) {
        return NULL;
    }
    OdraTerminalEmulatorSlot* slot = &slots[ref.slot - 1];
    if (!slot->live || slot->generation != ref.generation) {
        return NULL;
    }
    return slot;
}

static void effect_bell(GhosttyTerminal terminal, void* userdata) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.bell_count = saturated_add(slot->effects.bell_count, 1);
}

static void effect_title_changed(GhosttyTerminal terminal, void* userdata) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.title_change_count = saturated_add(
        slot->effects.title_change_count, 1);
}

static void effect_pwd_changed(GhosttyTerminal terminal, void* userdata) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.pwd_change_count = saturated_add(
        slot->effects.pwd_change_count, 1);
}

static void effect_clipboard_write(
    GhosttyTerminal terminal,
    void* userdata,
    const GhosttyClipboardWrite* write) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.clipboard_write_denied_count = saturated_add(
        slot->effects.clipboard_write_denied_count, 1);
    if (write != NULL && write->reply != NULL) {
        GhosttyClipboardWriteReply reply = GHOSTTY_INIT_SIZED(GhosttyClipboardWriteReply);
        reply.result = GHOSTTY_CLIPBOARD_WRITE_RESULT_DENIED;
        write->reply(write, &reply);
    }
}

static void effect_clipboard_read(
    GhosttyTerminal terminal,
    void* userdata,
    const GhosttyClipboardRead* read) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.clipboard_read_denied_count = saturated_add(
        slot->effects.clipboard_read_denied_count, 1);
    if (read != NULL && read->reply != NULL) {
        GhosttyClipboardReadReply reply = GHOSTTY_INIT_SIZED(GhosttyClipboardReadReply);
        reply.result = GHOSTTY_CLIPBOARD_READ_RESULT_DENIED;
        read->reply(read, &reply);
    }
}

static void effect_notification(
    GhosttyTerminal terminal,
    void* userdata,
    const GhosttyTerminalDesktopNotification* notification) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.notification_denied_count = saturated_add(
        slot->effects.notification_denied_count, 1);
    if (notification != NULL &&
        notification->size >= offsetof(GhosttyTerminalDesktopNotification, body) +
            sizeof(notification->body)) {
        uint64_t bytes = notification->title.len > UINT64_MAX ?
            UINT64_MAX : (uint64_t) notification->title.len;
        bytes = saturated_add(
            bytes,
            notification->body.len > UINT64_MAX ?
                UINT64_MAX : (uint64_t) notification->body.len);
        slot->effects.notification_bytes = saturated_add(
            slot->effects.notification_bytes, bytes);
    }
}

static void effect_progress(
    GhosttyTerminal terminal,
    void* userdata,
    const GhosttyTerminalProgressReport* report) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.progress_count = saturated_add(slot->effects.progress_count, 1);
    if (report != NULL &&
        report->size >= offsetof(GhosttyTerminalProgressReport, progress) +
            sizeof(report->progress)) {
        slot->effects.progress_state = (uint64_t) report->state;
        slot->effects.progress_percent = (int64_t) report->progress;
    }
}

static void effect_unknown_sequence(
    GhosttyTerminal terminal,
    void* userdata,
    const GhosttyTerminalUnknownSequence* sequence) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.unknown_sequence_count = saturated_add(
        slot->effects.unknown_sequence_count, 1);
    if (sequence == NULL ||
        sequence->tag != GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_APC) {
        return;
    }
    size_t length = sequence->value.apc.content.len;
    slot->effects.unknown_sequence_bytes = saturated_add(
        slot->effects.unknown_sequence_bytes,
        length > UINT64_MAX ? UINT64_MAX : (uint64_t) length);
    if (sequence->value.apc.truncated) {
        slot->effects.unknown_truncated_count = saturated_add(
            slot->effects.unknown_truncated_count, 1);
    }
}

static void effect_writeback(
    GhosttyTerminal terminal,
    void* userdata,
    const uint8_t* bytes,
    size_t length) {
    (void) terminal;
    OdraTerminalEmulatorSlot* slot = userdata;
    slot->effects.writeback_count = saturated_add(slot->effects.writeback_count, 1);
    slot->effects.writeback_bytes = saturated_add(
        slot->effects.writeback_bytes,
        length > UINT64_MAX ? UINT64_MAX : (uint64_t) length);
    size_t available = ODRA_TERMINAL_EMULATOR_WRITEBACK_CAPACITY - slot->writeback_length;
    size_t copied = length < available ? length : available;
    if (copied > 0) {
        memcpy(slot->writeback + slot->writeback_length, bytes, copied);
        slot->writeback_length += copied;
    }
    slot->effects.writeback_pending_bytes = slot->writeback_length;
    slot->effects.writeback_dropped_bytes = saturated_add(
        slot->effects.writeback_dropped_bytes,
        length - copied > UINT64_MAX ? UINT64_MAX : (uint64_t) (length - copied));
}

static GhosttyResult configure_effects(OdraTerminalEmulatorSlot* slot) {
    GhosttyResult result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_USERDATA, slot);
    if (result != GHOSTTY_SUCCESS) return result;

    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_BELL, effect_bell);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, effect_writeback);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, effect_title_changed);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_PWD_CHANGED, effect_pwd_changed);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE, effect_clipboard_write);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_CLIPBOARD_READ, effect_clipboard_read);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION, effect_notification);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_PROGRESS_REPORT, effect_progress);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE, effect_unknown_sequence);
    if (result != GHOSTTY_SUCCESS) return result;

    size_t unknown_max_bytes = ODRA_TERMINAL_EMULATOR_UNKNOWN_CAPTURE_BYTES;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES, &unknown_max_bytes);
    if (result != GHOSTTY_SUCCESS) return result;
    size_t clipboard_write_max_bytes = ODRA_TERMINAL_EMULATOR_CLIPBOARD_WRITE_BYTES;
    result = ghostty_terminal_set(
        slot->terminal,
        GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE_MAX_BYTES,
        &clipboard_write_max_bytes);
    if (result != GHOSTTY_SUCCESS) return result;
    bool title_report = false;
    return ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_TITLE_REPORT, &title_report);
}

static GhosttyResult configure_images(OdraTerminalEmulatorSlot* slot) {
    uint64_t storage_bytes = ODRA_TERMINAL_EMULATOR_IMAGE_STORAGE_BYTES;
    GhosttyResult result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT, &storage_bytes);
    if (result != GHOSTTY_SUCCESS) return result;
    size_t encoded_bytes = ODRA_TERMINAL_EMULATOR_IMAGE_ENCODED_BYTES;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES_KITTY, &encoded_bytes);
    if (result != GHOSTTY_SUCCESS) return result;
    bool disabled = false;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_FILE, &disabled);
    if (result != GHOSTTY_SUCCESS) return result;
    result = ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_SHARED_MEM, &disabled);
    if (result != GHOSTTY_SUCCESS) return result;
    return ghostty_terminal_set(
        slot->terminal, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_TEMP_FILE, NULL);
}

static void release_slot(OdraTerminalEmulatorSlot* slot) {
    for (size_t index = 0; index < ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY; index += 1) {
        ghostty_tracked_grid_ref_free(slot->semantic_anchors[index]);
        slot->semantic_anchors[index] = NULL;
    }
    ghostty_mouse_event_free(slot->mouse_event);
    ghostty_kitty_graphics_placement_iterator_free(slot->image_iterator);
    ghostty_mouse_encoder_free(slot->mouse_encoder);
    ghostty_key_event_free(slot->key_event);
    ghostty_key_encoder_free(slot->key_encoder);
    ghostty_render_state_row_cells_free(slot->row_cells);
    ghostty_render_state_row_iterator_free(slot->row_iterator);
    ghostty_render_state_free(slot->render_state);
    ghostty_terminal_free(slot->terminal);
    slot->mouse_event = NULL;
    slot->image_iterator = NULL;
    slot->mouse_encoder = NULL;
    slot->key_event = NULL;
    slot->key_encoder = NULL;
    slot->render_state = NULL;
    slot->row_cells = NULL;
    slot->row_iterator = NULL;
    slot->terminal = NULL;
    slot->live = false;
}

OdraTerminalEmulatorResult odra_terminal_emulator_open(
    const OdraTerminalEmulatorOptions* options,
    OdraTerminalEmulatorRef* out_ref) {
    if (options == NULL || out_ref == NULL || options->columns == 0 || options->rows == 0) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_ref = (OdraTerminalEmulatorRef) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = NULL;
    uint32_t slot_index = 0;
    for (uint32_t index = 0; index < ODRA_TERMINAL_EMULATOR_CAPACITY; index += 1) {
        if (!slots[index].live && slots[index].terminal == NULL) {
            slot = &slots[index];
            slot_index = index;
            break;
        }
    }
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_UNAVAILABLE;
    }

    uint32_t generation = slot->generation + 1;
    if (generation == 0) {
        generation = 1;
    }
    memset(slot, 0, sizeof(*slot));
    slot->generation = generation;
    slot->fail_after = options->allocation_fail_after;
    slot->allocator.ctx = slot;
    slot->allocator.vtable = &tracked_allocator_vtable;

    GhosttyResult result = ghostty_terminal_new(
        &slot->allocator,
        &slot->terminal,
        options->columns,
        options->rows);
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_render_state_new(&slot->allocator, &slot->render_state);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_render_state_row_iterator_new(&slot->allocator, &slot->row_iterator);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_render_state_row_cells_new(&slot->allocator, &slot->row_cells);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_key_encoder_new(&slot->allocator, &slot->key_encoder);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_key_event_new(&slot->allocator, &slot->key_event);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_mouse_encoder_new(&slot->allocator, &slot->mouse_encoder);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_mouse_event_new(&slot->allocator, &slot->mouse_event);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_kitty_graphics_placement_iterator_new(
            &slot->allocator, &slot->image_iterator);
    }
    if (result != GHOSTTY_SUCCESS) {
        release_slot(slot);
        OdraTerminalEmulatorResult mapped = map_result(result);
        unlock_slots();
        return mapped;
    }

    size_t scrollback_max_bytes = (size_t) options->scrollback_max_bytes;
    if ((uint64_t) scrollback_max_bytes != options->scrollback_max_bytes) {
        release_slot(slot);
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    result = ghostty_terminal_set(
        slot->terminal,
        GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES,
        &scrollback_max_bytes);
    if (result != GHOSTTY_SUCCESS) {
        release_slot(slot);
        OdraTerminalEmulatorResult mapped = map_result(result);
        unlock_slots();
        return mapped;
    }
    size_t scrollback_max_lines = (size_t) options->scrollback_max_lines;
    if ((uint64_t) scrollback_max_lines != options->scrollback_max_lines) {
        release_slot(slot);
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    result = ghostty_terminal_set(
        slot->terminal,
        GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES,
        &scrollback_max_lines);
    if (result != GHOSTTY_SUCCESS) {
        release_slot(slot);
        OdraTerminalEmulatorResult mapped = map_result(result);
        unlock_slots();
        return mapped;
    }

    result = configure_effects(slot);
    if (result != GHOSTTY_SUCCESS) {
        release_slot(slot);
        OdraTerminalEmulatorResult mapped = map_result(result);
        unlock_slots();
        return mapped;
    }
    result = configure_images(slot);
    if (result != GHOSTTY_SUCCESS) {
        release_slot(slot);
        OdraTerminalEmulatorResult mapped = map_result(result);
        unlock_slots();
        return mapped;
    }
    result = ghostty_terminal_resize(
        slot->terminal,
        options->columns,
        options->rows,
        options->cell_width_pixels,
        options->cell_height_pixels);
    if (result == GHOSTTY_SUCCESS) {
        configure_mouse_size(
            slot,
            options->columns,
            options->rows,
            options->cell_width_pixels,
            options->cell_height_pixels);
    }
    if (result != GHOSTTY_SUCCESS) {
        release_slot(slot);
        OdraTerminalEmulatorResult mapped = map_result(result);
        unlock_slots();
        return mapped;
    }

    slot->live = true;
    out_ref->slot = slot_index + 1;
    out_ref->generation = slot->generation;
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_close(OdraTerminalEmulatorRef ref) {
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    release_slot(slot);
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_write(
    OdraTerminalEmulatorRef ref,
    const uint8_t* bytes,
    size_t length) {
    if (bytes == NULL && length != 0) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    ghostty_terminal_vt_write(slot->terminal, bytes, length);
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_resize(
    OdraTerminalEmulatorRef ref,
    uint16_t columns,
    uint16_t rows,
    uint32_t cell_width_pixels,
    uint32_t cell_height_pixels) {
    if (columns == 0 || rows == 0) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyResult foreign_result = ghostty_terminal_resize(
        slot->terminal, columns, rows, cell_width_pixels, cell_height_pixels);
    if (foreign_result == GHOSTTY_SUCCESS) {
        configure_mouse_size(slot, columns, rows, cell_width_pixels, cell_height_pixels);
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_render(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorRenderState* out_state) {
    if (out_state == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_state = (OdraTerminalEmulatorRenderState) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyResult foreign_result = ghostty_render_state_update(slot->render_state, slot->terminal);
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state, GHOSTTY_RENDER_STATE_DATA_COLS, &out_state->columns);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state, GHOSTTY_RENDER_STATE_DATA_ROWS, &out_state->rows);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state,
            GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE,
            &out_state->cursor_visible);
    }
    if (foreign_result == GHOSTTY_SUCCESS && out_state->cursor_visible) {
        foreign_result = ghostty_render_state_get(
            slot->render_state,
            GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X,
            &out_state->cursor_column);
    }
    if (foreign_result == GHOSTTY_SUCCESS && out_state->cursor_visible) {
        foreign_result = ghostty_render_state_get(
            slot->render_state,
            GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y,
            &out_state->cursor_row);
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

static OdraTerminalEmulatorColor copy_color(GhosttyColorRgb color) {
    return (OdraTerminalEmulatorColor) {.r = color.r, .g = color.g, .b = color.b};
}

static OdraTerminalEmulatorStyleColor copy_style_color(GhosttyStyleColor color) {
    OdraTerminalEmulatorStyleColor copied = {.kind = (int32_t) color.tag};
    if (color.tag == GHOSTTY_STYLE_COLOR_PALETTE) {
        copied.palette = color.value.palette;
    } else if (color.tag == GHOSTTY_STYLE_COLOR_RGB) {
        copied.rgb = copy_color(color.value.rgb);
    }
    return copied;
}

static void copy_style(
    const GhosttyStyle* style,
    OdraTerminalEmulatorCellStyle* copied) {
    *copied = (OdraTerminalEmulatorCellStyle) {
        .foreground = copy_style_color(style->fg_color),
        .background = copy_style_color(style->bg_color),
        .underline_color = copy_style_color(style->underline_color),
        .bold = style->bold,
        .italic = style->italic,
        .faint = style->faint,
        .blink = style->blink,
        .inverse = style->inverse,
        .invisible = style->invisible,
        .strikethrough = style->strikethrough,
        .overline = style->overline,
        .underline = style->underline,
    };
}

OdraTerminalEmulatorResult odra_terminal_emulator_project(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorProjection* out_projection,
    OdraTerminalEmulatorRow* rows,
    size_t row_capacity,
    OdraTerminalEmulatorCell* cells,
    size_t cell_capacity) {
    if (out_projection == NULL || (rows == NULL && row_capacity != 0) ||
        (cells == NULL && cell_capacity != 0)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_projection = (OdraTerminalEmulatorProjection) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyResult foreign_result = ghostty_render_state_update(
        slot->render_state,
        slot->terminal);
    GhosttyRenderStateDirty damage = GHOSTTY_RENDER_STATE_DIRTY_FALSE;
    GhosttyRenderStateCursor cursor = GHOSTTY_INIT_SIZED(GhosttyRenderStateCursor);
    GhosttyRenderStateColors colors = GHOSTTY_INIT_SIZED(GhosttyRenderStateColors);
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state, GHOSTTY_RENDER_STATE_DATA_COLS, &out_projection->columns);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state, GHOSTTY_RENDER_STATE_DATA_ROWS, &out_projection->rows);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state, GHOSTTY_RENDER_STATE_DATA_DIRTY, &damage);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state, GHOSTTY_RENDER_STATE_DATA_CURSOR, &cursor);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_get(
            slot->render_state, GHOSTTY_RENDER_STATE_DATA_COLORS, &colors);
    }
    if (foreign_result != GHOSTTY_SUCCESS) {
        OdraTerminalEmulatorResult mapped = map_result(foreign_result);
        unlock_slots();
        return mapped;
    }

    out_projection->damage = (int32_t) damage;
    out_projection->cursor_in_viewport = cursor.viewport_has_value;
    out_projection->cursor_visible = cursor.visible;
    out_projection->cursor_blinking = cursor.blinking;
    out_projection->cursor_password_input = cursor.password_input;
    out_projection->cursor_wide_tail = cursor.wide_tail;
    out_projection->cursor_style = (int32_t) cursor.visual_style;
    if (cursor.viewport_has_value) {
        out_projection->cursor_column = cursor.viewport_x;
        out_projection->cursor_row = cursor.viewport_y;
    }
    out_projection->background = copy_color(colors.background);
    out_projection->foreground = copy_color(colors.foreground);
    out_projection->cursor_color_set = colors.cursor_has_value;
    if (colors.cursor_has_value) {
        out_projection->cursor = copy_color(colors.cursor);
    }
    for (size_t index = 0; index < 256; index += 1) {
        out_projection->palette[index] = copy_color(colors.palette[index]);
    }

    if ((size_t) out_projection->rows > row_capacity ||
        (size_t) out_projection->columns * out_projection->rows > cell_capacity) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_BUFFER_TOO_SMALL;
    }
    foreign_result = ghostty_render_state_get(
        slot->render_state,
        GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
        &slot->row_iterator);
    uint16_t y = 0;
    while (foreign_result == GHOSTTY_SUCCESS &&
           ghostty_render_state_row_iterator_next_dirty(slot->row_iterator, &y)) {
        OdraTerminalEmulatorRow* copied_row = &rows[y];
        *copied_row = (OdraTerminalEmulatorRow) {.row = y, .dirty = true};
        GhosttyRow row = 0;
        foreign_result = ghostty_render_state_row_get(
            slot->row_iterator, GHOSTTY_RENDER_STATE_ROW_DATA_RAW, &row);
        if (foreign_result == GHOSTTY_SUCCESS) {
            foreign_result = ghostty_row_get(row, GHOSTTY_ROW_DATA_WRAP, &copied_row->wrapped);
        }
        if (foreign_result == GHOSTTY_SUCCESS) {
            foreign_result = ghostty_row_get(
                row,
                GHOSTTY_ROW_DATA_WRAP_CONTINUATION,
                &copied_row->wrap_continuation);
        }
        if (foreign_result == GHOSTTY_SUCCESS) {
            foreign_result = ghostty_render_state_row_get(
                slot->row_iterator,
                GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                &slot->row_cells);
        }
        for (uint16_t x = 0; foreign_result == GHOSTTY_SUCCESS &&
             x < out_projection->columns; x += 1) {
            if (!ghostty_render_state_row_cells_next(slot->row_cells)) {
                foreign_result = GHOSTTY_INVALID_VALUE;
                break;
            }
            size_t cell_index = (size_t) y * out_projection->columns + x;
            OdraTerminalEmulatorCell* copied_cell = &cells[cell_index];
            *copied_cell = (OdraTerminalEmulatorCell) {.column = x, .row = y};
            GhosttyCell raw = 0;
            GhosttyStyle style = GHOSTTY_INIT_SIZED(GhosttyStyle);
            foreign_result = ghostty_render_state_row_cells_get(
                slot->row_cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &raw);
            if (foreign_result == GHOSTTY_SUCCESS) {
                foreign_result = ghostty_cell_get(
                    raw, GHOSTTY_CELL_DATA_WIDE, &copied_cell->width);
            }
            if (foreign_result == GHOSTTY_SUCCESS) {
                foreign_result = ghostty_cell_get(
                    raw, GHOSTTY_CELL_DATA_SEMANTIC_CONTENT, &copied_cell->semantic_content);
            }
            if (foreign_result == GHOSTTY_SUCCESS) {
                foreign_result = ghostty_cell_get(
                    raw, GHOSTTY_CELL_DATA_HAS_TEXT, &copied_cell->has_text);
            }
            if (foreign_result == GHOSTTY_SUCCESS) {
                foreign_result = ghostty_cell_get(
                    raw, GHOSTTY_CELL_DATA_PROTECTED, &copied_cell->protected_cell);
            }
            if (foreign_result == GHOSTTY_SUCCESS) {
                foreign_result = ghostty_cell_get(
                    raw, GHOSTTY_CELL_DATA_HAS_HYPERLINK, &copied_cell->hyperlink);
            }
            if (foreign_result == GHOSTTY_SUCCESS) {
                foreign_result = ghostty_render_state_row_cells_get(
                    slot->row_cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_SELECTED,
                    &copied_cell->selected);
            }
            if (foreign_result == GHOSTTY_SUCCESS) {
                foreign_result = ghostty_render_state_row_cells_get(
                    slot->row_cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style);
            }
            if (foreign_result == GHOSTTY_SUCCESS) {
                copy_style(&style, &copied_cell->style);
                GhosttyBuffer text = {
                    .ptr = copied_cell->text,
                    .cap = ODRA_TERMINAL_EMULATOR_CELL_TEXT_BYTES,
                };
                GhosttyResult text_result = ghostty_render_state_row_cells_get(
                    slot->row_cells,
                    GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8,
                    &text);
                if (text_result == GHOSTTY_OUT_OF_SPACE) {
                    copied_cell->text_clipped = true;
                    out_projection->clipped_cells += 1;
                    out_projection->clipped_text_bytes += text.len;
                } else if (text_result != GHOSTTY_SUCCESS) {
                    foreign_result = text_result;
                } else {
                    copied_cell->text_length = (uint16_t) text.len;
                }
            }
            out_projection->damaged_cells += 1;
        }
        if (out_projection->damaged_rows == 0) {
            out_projection->first_damaged_row = y;
        }
        out_projection->last_damaged_row = y;
        out_projection->damaged_rows += 1;
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_render_state_clean(slot->render_state);
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_scroll_state(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorScrollState* out_state) {
    if (out_state == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_state = (OdraTerminalEmulatorScrollState) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    size_t total_rows = 0;
    size_t scrollback_rows = 0;
    size_t scrollback_max_bytes = 0;
    size_t scrollback_max_lines = 0;
    GhosttyTerminalScrollbar scrollbar = {0};
    GhosttyResult foreign_result = ghostty_terminal_get(
        slot->terminal, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &total_rows);
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &scrollback_rows);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_SCROLLBAR, &scrollbar);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_VIEWPORT_ACTIVE,
            &out_state->viewport_active);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_MAX_BYTES,
            &scrollback_max_bytes);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_MAX_LINES,
            &scrollback_max_lines);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_compression_activity(
            slot->terminal, &out_state->compression_activity);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        out_state->total_rows = total_rows;
        out_state->scrollback_rows = scrollback_rows;
        out_state->viewport_offset = scrollbar.offset;
        out_state->viewport_rows = scrollbar.len;
        out_state->scrollback_max_bytes = scrollback_max_bytes;
        out_state->scrollback_max_lines = scrollback_max_lines;
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_semantic_state(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticState* out_state) {
    if (out_state == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_state = (OdraTerminalEmulatorSemanticState) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyTerminalScreen screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY;
    uint16_t cursor_y = 0;
    size_t scrollback_rows = 0;
    GhosttyResult foreign_result = ghostty_terminal_get(
        slot->terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen);
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_CURSOR_X, &out_state->cursor_column);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_CURSOR_Y, &cursor_y);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &scrollback_rows);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_terminal_get(
            slot->terminal,
            GHOSTTY_TERMINAL_DATA_CURSOR_AT_PROMPT,
            &out_state->cursor_at_prompt);
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        out_state->alternate_screen = screen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE;
        out_state->cursor_row = out_state->alternate_screen ? cursor_y : scrollback_rows + cursor_y;
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_mouse_state(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorMouseState* out_state) {
    if (out_state == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_state = (OdraTerminalEmulatorMouseState) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyResult result = ghostty_terminal_get(
        slot->terminal, GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &out_state->tracking);
    OdraTerminalEmulatorResult mapped = map_result(result);
    unlock_slots();
    return mapped;
}

OdraTerminalEmulatorResult odra_terminal_emulator_hyperlink_at(
    OdraTerminalEmulatorRef ref,
    uint16_t column,
    uint32_t row,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written) {
    if ((output == NULL && output_capacity != 0) || out_written == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyPoint point = {
        .tag = GHOSTTY_POINT_TAG_VIEWPORT,
        .value.coordinate = {.x = column, .y = row},
    };
    GhosttyGridRef grid_ref = GHOSTTY_INIT_SIZED(GhosttyGridRef);
    GhosttyResult result = ghostty_terminal_grid_ref(slot->terminal, point, &grid_ref);
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_grid_ref_hyperlink_uri(
            &grid_ref, output, output_capacity, out_written);
    }
    OdraTerminalEmulatorResult mapped = map_result(result);
    unlock_slots();
    return mapped;
}

OdraTerminalEmulatorResult odra_terminal_emulator_semantic_anchor_open(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticAnchor* out_anchor) {
    if (out_anchor == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_anchor = (OdraTerminalEmulatorSemanticAnchor) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyTerminalScreen screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY;
    uint16_t cursor_x = 0;
    uint16_t cursor_y = 0;
    GhosttyResult result = ghostty_terminal_get(
        slot->terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen);
    if (result == GHOSTTY_SUCCESS && screen != GHOSTTY_TERMINAL_SCREEN_PRIMARY) {
        result = GHOSTTY_NO_VALUE;
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_CURSOR_X, &cursor_x);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_CURSOR_Y, &cursor_y);
    }
    size_t anchor_index = ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY;
    if (result == GHOSTTY_SUCCESS) {
        for (size_t index = 0; index < ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY; index += 1) {
            if (slot->semantic_anchors[index] == NULL) {
                anchor_index = index;
                break;
            }
        }
        if (anchor_index == ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY) {
            result = GHOSTTY_OUT_OF_SPACE;
        }
    }
    if (result == GHOSTTY_SUCCESS) {
        GhosttyPoint point = {
            .tag = GHOSTTY_POINT_TAG_ACTIVE,
            .value.coordinate = {.x = cursor_x, .y = cursor_y},
        };
        result = ghostty_terminal_grid_ref_track(
            slot->terminal, point, &slot->semantic_anchors[anchor_index]);
    }
    if (result == GHOSTTY_SUCCESS) {
        uint32_t generation = slot->semantic_anchor_generations[anchor_index] + 1;
        if (generation == 0) {
            generation = 1;
        }
        slot->semantic_anchor_generations[anchor_index] = generation;
        out_anchor->slot = (uint32_t) anchor_index + 1;
        out_anchor->generation = generation;
    }
    OdraTerminalEmulatorResult mapped = map_result(result);
    unlock_slots();
    return mapped;
}

static GhosttyTrackedGridRef find_semantic_anchor(
    OdraTerminalEmulatorSlot* slot,
    OdraTerminalEmulatorSemanticAnchor anchor) {
    if (anchor.slot == 0 ||
        anchor.slot > ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY) {
        return NULL;
    }
    size_t index = anchor.slot - 1;
    if (slot->semantic_anchor_generations[index] != anchor.generation) {
        return NULL;
    }
    return slot->semantic_anchors[index];
}

OdraTerminalEmulatorResult odra_terminal_emulator_semantic_anchor_resolve(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticAnchor anchor,
    uint64_t* out_row,
    uint16_t* out_column) {
    if (out_row == NULL || out_column == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_row = 0;
    *out_column = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyTrackedGridRef tracked = find_semantic_anchor(slot, anchor);
    if (tracked == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyPointCoordinate point = {0};
    GhosttyResult result = ghostty_tracked_grid_ref_point(
        tracked, GHOSTTY_POINT_TAG_SCREEN, &point);
    if (result == GHOSTTY_SUCCESS) {
        *out_row = point.y;
        *out_column = point.x;
    }
    OdraTerminalEmulatorResult mapped = map_result(result);
    unlock_slots();
    return mapped;
}

OdraTerminalEmulatorResult odra_terminal_emulator_semantic_anchor_close(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticAnchor anchor) {
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyTrackedGridRef tracked = find_semantic_anchor(slot, anchor);
    if (tracked == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    ghostty_tracked_grid_ref_free(tracked);
    slot->semantic_anchors[anchor.slot - 1] = NULL;
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_scroll(
    OdraTerminalEmulatorRef ref,
    int32_t behavior,
    int64_t value) {
    GhosttyTerminalScrollViewport scroll = {0};
    switch ((OdraTerminalEmulatorScroll) behavior) {
    case ODRA_TERMINAL_EMULATOR_SCROLL_TOP:
        scroll.tag = GHOSTTY_SCROLL_VIEWPORT_TOP;
        break;
    case ODRA_TERMINAL_EMULATOR_SCROLL_BOTTOM:
        scroll.tag = GHOSTTY_SCROLL_VIEWPORT_BOTTOM;
        break;
    case ODRA_TERMINAL_EMULATOR_SCROLL_DELTA:
        scroll.tag = GHOSTTY_SCROLL_VIEWPORT_DELTA;
        scroll.value.delta = (intptr_t) value;
        if ((int64_t) scroll.value.delta != value) {
            return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
        }
        break;
    case ODRA_TERMINAL_EMULATOR_SCROLL_ROW:
        if (value < 0) {
            return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
        }
        scroll.tag = GHOSTTY_SCROLL_VIEWPORT_ROW;
        scroll.value.row = (size_t) value;
        if ((uint64_t) scroll.value.row != (uint64_t) value) {
            return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
        }
        break;
    default:
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    ghostty_terminal_scroll_viewport(slot->terminal, scroll);
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_compress(
    OdraTerminalEmulatorRef ref,
    bool* out_pending,
    bool* out_supported) {
    if (out_pending == NULL || out_supported == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_pending = false;
    *out_supported = false;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyTerminalCompressionResult compression =
        GHOSTTY_TERMINAL_COMPRESSION_RESULT_UNSUPPORTED;
    GhosttyResult foreign_result = ghostty_terminal_compress(
        slot->terminal,
        GHOSTTY_TERMINAL_COMPRESSION_MODE_INCREMENTAL,
        &compression);
    if (foreign_result == GHOSTTY_SUCCESS) {
        *out_supported = compression != GHOSTTY_TERMINAL_COMPRESSION_RESULT_UNSUPPORTED;
        *out_pending = compression == GHOSTTY_TERMINAL_COMPRESSION_RESULT_PENDING;
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

static GhosttyResult text_formatter_new(
    OdraTerminalEmulatorSlot* slot,
    const OdraTerminalEmulatorTextRequest* request,
    GhosttyFormatter* out_formatter) {
    GhosttySelection selection = GHOSTTY_INIT_SIZED(GhosttySelection);
    const GhosttySelection* selection_ptr = NULL;
    GhosttyPointTag tag = GHOSTTY_POINT_TAG_SCREEN;
    GhosttyPointCoordinate start = {0};
    GhosttyPointCoordinate end = {0};
    if (request->scope == ODRA_TERMINAL_EMULATOR_TEXT_VIEWPORT) {
        uint16_t columns = 0;
        uint16_t rows = 0;
        GhosttyResult geometry_result = ghostty_terminal_get(
            slot->terminal, GHOSTTY_TERMINAL_DATA_COLS, &columns);
        if (geometry_result == GHOSTTY_SUCCESS) {
            geometry_result = ghostty_terminal_get(
                slot->terminal, GHOSTTY_TERMINAL_DATA_ROWS, &rows);
        }
        if (geometry_result != GHOSTTY_SUCCESS || columns == 0 || rows == 0) {
            return geometry_result;
        }
        tag = GHOSTTY_POINT_TAG_VIEWPORT;
        end.x = columns - 1;
        end.y = rows - 1;
        selection_ptr = &selection;
    } else if (request->scope == ODRA_TERMINAL_EMULATOR_TEXT_SCREEN_RANGE ||
               request->scope == ODRA_TERMINAL_EMULATOR_TEXT_HISTORY_RANGE) {
        tag = request->scope == ODRA_TERMINAL_EMULATOR_TEXT_SCREEN_RANGE ?
            GHOSTTY_POINT_TAG_SCREEN : GHOSTTY_POINT_TAG_HISTORY;
        start.x = request->start_column;
        start.y = request->start_row;
        end.x = request->end_column;
        end.y = request->end_row;
        selection_ptr = &selection;
    } else if (request->scope != ODRA_TERMINAL_EMULATOR_TEXT_SCREEN) {
        return GHOSTTY_INVALID_VALUE;
    }
    GhosttyResult foreign_result = GHOSTTY_SUCCESS;
    if (selection_ptr != NULL) {
        GhosttyPoint start_point = {.tag = tag};
        GhosttyPoint end_point = {.tag = tag};
        start_point.value.coordinate = start;
        end_point.value.coordinate = end;
        selection.start = (GhosttyGridRef) GHOSTTY_INIT_SIZED(GhosttyGridRef);
        selection.end = (GhosttyGridRef) GHOSTTY_INIT_SIZED(GhosttyGridRef);
        selection.rectangle = request->rectangle;
        foreign_result = ghostty_terminal_grid_ref(
            slot->terminal, start_point, &selection.start);
        if (foreign_result == GHOSTTY_SUCCESS) {
            foreign_result = ghostty_terminal_grid_ref(
                slot->terminal, end_point, &selection.end);
        }
    }
    if (foreign_result == GHOSTTY_SUCCESS) {
        GhosttyFormatterTerminalOptions options =
            GHOSTTY_INIT_SIZED(GhosttyFormatterTerminalOptions);
        options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN;
        options.unwrap = request->unwrap;
        options.trim = request->trim;
        options.selection = selection_ptr;
        foreign_result = ghostty_formatter_terminal_new(
            &slot->allocator, out_formatter, slot->terminal, options);
    }
    return foreign_result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_format_text(
    OdraTerminalEmulatorRef ref,
    const OdraTerminalEmulatorTextRequest* request,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written) {
    if (request == NULL || out_written == NULL ||
        (output == NULL && output_capacity != 0)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyFormatter formatter = NULL;
    GhosttyResult foreign_result = text_formatter_new(slot, request, &formatter);
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_formatter_format_buf(
            formatter, output, output_capacity, out_written);
    }
    ghostty_formatter_free(formatter);
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

typedef struct {
    uint8_t* output;
    size_t capacity;
    size_t copied;
    size_t required;
} OdraTerminalEmulatorBoundedText;

static bool bounded_text_write(void* userdata, const uint8_t* data, size_t length) {
    OdraTerminalEmulatorBoundedText* bounded = userdata;
    if (bounded == NULL || data == NULL || SIZE_MAX - bounded->required < length) {
        return false;
    }
    bounded->required += length;
    size_t available = bounded->capacity - bounded->copied;
    size_t copied = length < available ? length : available;
    if (copied > 0) {
        memcpy(bounded->output + bounded->copied, data, copied);
        bounded->copied += copied;
    }
    return true;
}

OdraTerminalEmulatorResult odra_terminal_emulator_format_text_bounded(
    OdraTerminalEmulatorRef ref,
    const OdraTerminalEmulatorTextRequest* request,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_copied,
    size_t* out_required) {
    if (request == NULL || out_copied == NULL || out_required == NULL ||
        (output == NULL && output_capacity != 0)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_copied = 0;
    *out_required = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyFormatter formatter = NULL;
    GhosttyResult foreign_result = text_formatter_new(slot, request, &formatter);
    OdraTerminalEmulatorBoundedText bounded = {
        .output = output,
        .capacity = output_capacity,
    };
    if (foreign_result == GHOSTTY_SUCCESS) {
        GhosttyWriter writer = {
            .write = bounded_text_write,
            .userdata = &bounded,
        };
        foreign_result = ghostty_formatter_format(formatter, writer);
    }
    ghostty_formatter_free(formatter);
    *out_copied = bounded.copied;
    *out_required = bounded.required;
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_encode_key(
    OdraTerminalEmulatorRef ref,
    int32_t key,
    int32_t action,
    uint32_t modifiers,
    const uint8_t* text,
    size_t text_length,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written) {
    GhosttyKey translated_key;
    GhosttyMods translated_modifiers;
    if (out_written == NULL || (text == NULL && text_length != 0) ||
        (output == NULL && output_capacity != 0) ||
        (action != ODRA_TERMINAL_EMULATOR_KEY_PRESS &&
         action != ODRA_TERMINAL_EMULATOR_KEY_REPEAT) ||
        !translate_key(key, &translated_key) ||
        !translate_modifiers(modifiers, &translated_modifiers)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    ghostty_key_encoder_setopt_from_terminal(slot->key_encoder, slot->terminal);
    ghostty_key_event_set_action(
        slot->key_event,
        action == ODRA_TERMINAL_EMULATOR_KEY_REPEAT ?
            GHOSTTY_KEY_ACTION_REPEAT : GHOSTTY_KEY_ACTION_PRESS);
    ghostty_key_event_set_key(slot->key_event, translated_key);
    ghostty_key_event_set_mods(slot->key_event, translated_modifiers);
    ghostty_key_event_set_utf8(slot->key_event, (const char*) text, text_length);
    GhosttyResult foreign_result = ghostty_key_encoder_encode(
        slot->key_encoder,
        slot->key_event,
        (char*) output,
        output_capacity,
        out_written);
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_encode_focus(
    OdraTerminalEmulatorRef ref,
    int32_t event,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written,
    bool* out_enabled) {
    if (out_written == NULL || out_enabled == NULL ||
        (output == NULL && output_capacity != 0) ||
        (event != ODRA_TERMINAL_EMULATOR_FOCUS_GAINED &&
         event != ODRA_TERMINAL_EMULATOR_FOCUS_LOST)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    *out_enabled = false;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyTerminalModeConfig mode = {
        .mode = GHOSTTY_MODE_FOCUS_EVENT,
        .value = false,
    };
    GhosttyResult foreign_result = ghostty_terminal_get(
        slot->terminal,
        GHOSTTY_TERMINAL_DATA_MODE,
        &mode);
    if (foreign_result == GHOSTTY_SUCCESS && mode.value) {
        foreign_result = ghostty_focus_encode(
            event == ODRA_TERMINAL_EMULATOR_FOCUS_GAINED ?
                GHOSTTY_FOCUS_GAINED : GHOSTTY_FOCUS_LOST,
            (char*) output,
            output_capacity,
            out_written);
        if (foreign_result == GHOSTTY_SUCCESS) {
            *out_enabled = true;
        }
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

static bool paste_contains_unsafe_sequence(
    const uint8_t* text,
    size_t text_length,
    bool bracketed) {
    static const uint8_t bracketed_end[] = "\x1b[201~";
    if (!bracketed) {
        return text_length > 0 && memchr(text, '\n', text_length) != NULL;
    }
    if (text_length < sizeof(bracketed_end) - 1) {
        return false;
    }
    for (size_t index = 0; index <= text_length - (sizeof(bracketed_end) - 1); index += 1) {
        if (memcmp(text + index, bracketed_end, sizeof(bracketed_end) - 1) == 0) {
            return true;
        }
    }
    return false;
}

OdraTerminalEmulatorResult odra_terminal_emulator_encode_paste(
    OdraTerminalEmulatorRef ref,
    uint8_t* text,
    size_t text_length,
    bool allow_unsafe,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written,
    bool* out_bracketed) {
    if ((text == NULL && text_length != 0) ||
        (output == NULL && output_capacity != 0) ||
        out_written == NULL || out_bracketed == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    *out_bracketed = false;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyTerminalModeConfig mode = {
        .mode = GHOSTTY_MODE_BRACKETED_PASTE,
        .value = false,
    };
    GhosttyResult result = ghostty_terminal_get(
        slot->terminal,
        GHOSTTY_TERMINAL_DATA_MODE,
        &mode);
    if (result == GHOSTTY_SUCCESS && !allow_unsafe &&
        paste_contains_unsafe_sequence(text, text_length, mode.value)) {
        result = GHOSTTY_REJECTED;
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_paste_encode(
            (char*) text,
            text_length,
            mode.value,
            (char*) output,
            output_capacity,
            out_written);
    }
    if (result == GHOSTTY_SUCCESS) {
        *out_bracketed = mode.value;
    }
    OdraTerminalEmulatorResult mapped = map_result(result);
    unlock_slots();
    return mapped;
}

OdraTerminalEmulatorResult odra_terminal_emulator_encode_mouse(
    OdraTerminalEmulatorRef ref,
    int32_t action,
    int32_t button,
    uint32_t modifiers,
    float x,
    float y,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written) {
    GhosttyMouseAction translated_action;
    GhosttyMouseButton translated_button = GHOSTTY_MOUSE_BUTTON_UNKNOWN;
    GhosttyMods translated_modifiers;
    bool has_button = button != ODRA_TERMINAL_EMULATOR_MOUSE_NONE;
    if (out_written == NULL || (output == NULL && output_capacity != 0) ||
        !translate_mouse_action(action, &translated_action) ||
        (has_button && !translate_mouse_button(button, &translated_button)) ||
        !translate_modifiers(modifiers, &translated_modifiers) ||
        !isfinite(x) || !isfinite(y) || x < 0 || y < 0) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    ghostty_mouse_encoder_setopt_from_terminal(slot->mouse_encoder, slot->terminal);
    ghostty_mouse_event_set_action(slot->mouse_event, translated_action);
    if (!has_button) {
        ghostty_mouse_event_clear_button(slot->mouse_event);
    } else {
        ghostty_mouse_event_set_button(slot->mouse_event, translated_button);
    }
    ghostty_mouse_event_set_mods(slot->mouse_event, translated_modifiers);
    ghostty_mouse_event_set_position(slot->mouse_event, (GhosttyMousePosition) {.x = x, .y = y});
    GhosttyResult foreign_result = ghostty_mouse_encoder_encode(
        slot->mouse_encoder,
        slot->mouse_event,
        (char*) output,
        output_capacity,
        out_written);
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_select_all(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written) {
    if (out_written == NULL || (output == NULL && output_capacity != 0)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttySelection selection = {0};
    GhosttyResult foreign_result = ghostty_terminal_select_all(slot->terminal, &selection);
    if (foreign_result == GHOSTTY_SUCCESS) {
        GhosttyTerminalSelectionFormatOptions options =
            GHOSTTY_INIT_SIZED(GhosttyTerminalSelectionFormatOptions);
        options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN;
        options.unwrap = true;
        options.trim = true;
        options.selection = &selection;
        foreign_result = ghostty_terminal_selection_format_buf(
            slot->terminal, options, output, output_capacity, out_written);
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_snapshot(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written) {
    if (out_written == NULL || (output == NULL && output_capacity != 0)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    OdraTerminalEmulatorResult result = map_result(ghostty_snapshot_encode_buf(
        slot->terminal, output, output_capacity, out_written));
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_effects(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorEffects* out_effects) {
    if (out_effects == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_effects = (OdraTerminalEmulatorEffects) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    *out_effects = slot->effects;
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

static OdraTerminalEmulatorResult copy_terminal_string(
    OdraTerminalEmulatorRef ref,
    GhosttyTerminalData data,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_copied,
    size_t* out_required) {
    if (out_copied == NULL || out_required == NULL ||
        (output == NULL && output_capacity != 0)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_copied = 0;
    *out_required = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyString value = {0};
    GhosttyResult foreign_result = ghostty_terminal_get(slot->terminal, data, &value);
    if (foreign_result != GHOSTTY_SUCCESS) {
        OdraTerminalEmulatorResult result = map_result(foreign_result);
        unlock_slots();
        return result;
    }
    size_t copied = value.len < output_capacity ? value.len : output_capacity;
    if (copied > 0) memcpy(output, value.ptr, copied);
    *out_copied = copied;
    *out_required = value.len;
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_title_copy(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_copied,
    size_t* out_required) {
    return copy_terminal_string(
        ref,
        GHOSTTY_TERMINAL_DATA_TITLE,
        output,
        output_capacity,
        out_copied,
        out_required);
}

OdraTerminalEmulatorResult odra_terminal_emulator_pwd_copy(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_copied,
    size_t* out_required) {
    return copy_terminal_string(
        ref,
        GHOSTTY_TERMINAL_DATA_PWD,
        output,
        output_capacity,
        out_copied,
        out_required);
}

OdraTerminalEmulatorResult odra_terminal_emulator_writeback_copy(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written,
    size_t* out_pending) {
    if (out_written == NULL || out_pending == NULL ||
        (output == NULL && output_capacity != 0)) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_written = 0;
    *out_pending = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    size_t copied = slot->writeback_length < output_capacity ?
        slot->writeback_length : output_capacity;
    if (copied > 0) {
        memcpy(output, slot->writeback, copied);
    }
    *out_written = copied;
    *out_pending = slot->writeback_length;
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_writeback_consume(
    OdraTerminalEmulatorRef ref,
    size_t length) {
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    if (length > slot->writeback_length) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    size_t remaining = slot->writeback_length - length;
    if (remaining > 0) {
        memmove(slot->writeback, slot->writeback + length, remaining);
    }
    slot->writeback_length = remaining;
    slot->effects.writeback_pending_bytes = remaining;
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_image_generation(
    OdraTerminalEmulatorRef ref,
    uint64_t* out_generation) {
    if (out_generation == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_generation = 0;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyKittyGraphics graphics = NULL;
    GhosttyResult foreign_result = ghostty_terminal_get(
        slot->terminal, GHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS, &graphics);
    if (foreign_result == GHOSTTY_SUCCESS) {
        foreign_result = ghostty_kitty_graphics_get(
            graphics, GHOSTTY_KITTY_GRAPHICS_DATA_GENERATION, out_generation);
    }
    OdraTerminalEmulatorResult result = map_result(foreign_result);
    unlock_slots();
    return result;
}

OdraTerminalEmulatorResult odra_terminal_emulator_project_images(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorImagePlacement* output,
    size_t output_capacity,
    size_t* out_count,
    uint64_t* out_generation,
    uint64_t* out_decoded_bytes,
    bool* out_truncated) {
    if ((output == NULL && output_capacity != 0) || out_count == NULL ||
        out_generation == NULL || out_decoded_bytes == NULL || out_truncated == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_count = 0;
    *out_generation = 0;
    *out_decoded_bytes = 0;
    *out_truncated = false;
    lock_slots();
    OdraTerminalEmulatorSlot* slot = find_slot(ref);
    if (slot == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    GhosttyKittyGraphics graphics = NULL;
    GhosttyResult result = ghostty_terminal_get(
        slot->terminal, GHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS, &graphics);
    if (result == GHOSTTY_NO_VALUE || graphics == NULL) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_OK;
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_kitty_graphics_get(
            graphics, GHOSTTY_KITTY_GRAPHICS_DATA_GENERATION, out_generation);
    }
    if (result == GHOSTTY_SUCCESS) {
        result = ghostty_kitty_graphics_get(
            graphics,
            GHOSTTY_KITTY_GRAPHICS_DATA_PLACEMENT_ITERATOR,
            &slot->image_iterator);
    }
    size_t total_count = 0;
    while (result == GHOSTTY_SUCCESS &&
           ghostty_kitty_graphics_placement_next(slot->image_iterator)) {
        uint32_t image_id = 0;
        bool virtual_placement = false;
        result = ghostty_kitty_graphics_placement_get(
            slot->image_iterator,
            GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IMAGE_ID,
            &image_id);
        if (result == GHOSTTY_SUCCESS) {
            result = ghostty_kitty_graphics_placement_get(
                slot->image_iterator,
                GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IS_VIRTUAL,
                &virtual_placement);
        }
        if (result != GHOSTTY_SUCCESS) break;
        if (virtual_placement) continue;
        total_count += 1;
        if (total_count > output_capacity) continue;
        OdraTerminalEmulatorImagePlacement* copied = &output[total_count - 1];
        *copied = (OdraTerminalEmulatorImagePlacement) {.image_id = image_id};
        result = ghostty_kitty_graphics_placement_get(
            slot->image_iterator,
            GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_PLACEMENT_ID,
            &copied->placement_id);
        if (result == GHOSTTY_SUCCESS) {
            result = ghostty_kitty_graphics_placement_get(
                slot->image_iterator, GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Z, &copied->z);
        }
        GhosttyKittyGraphicsImage image = ghostty_kitty_graphics_image(graphics, image_id);
        if (result != GHOSTTY_SUCCESS || image == NULL) {
            copied->rejected = true;
            if (result == GHOSTTY_SUCCESS) continue;
            break;
        }
        size_t decoded_bytes = 0;
        result = ghostty_kitty_graphics_image_get(
            image, GHOSTTY_KITTY_IMAGE_DATA_GENERATION, &copied->generation);
        if (result == GHOSTTY_SUCCESS) result = ghostty_kitty_graphics_image_get(
            image, GHOSTTY_KITTY_IMAGE_DATA_WIDTH, &copied->image_width);
        if (result == GHOSTTY_SUCCESS) result = ghostty_kitty_graphics_image_get(
            image, GHOSTTY_KITTY_IMAGE_DATA_HEIGHT, &copied->image_height);
        if (result == GHOSTTY_SUCCESS) result = ghostty_kitty_graphics_image_get(
            image, GHOSTTY_KITTY_IMAGE_DATA_FORMAT, &copied->format);
        if (result == GHOSTTY_SUCCESS) result = ghostty_kitty_graphics_image_get(
            image, GHOSTTY_KITTY_IMAGE_DATA_DATA_LEN, &decoded_bytes);
        if (result != GHOSTTY_SUCCESS) break;
        copied->decoded_bytes = decoded_bytes > UINT64_MAX ?
            UINT64_MAX : (uint64_t) decoded_bytes;
        *out_decoded_bytes = saturated_add(*out_decoded_bytes, copied->decoded_bytes);
        const uint8_t* pixels = NULL;
        GhosttyResult pixel_result = ghostty_kitty_graphics_image_get(
            image, GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR, &pixels);
        copied->pending = pixel_result == GHOSTTY_NO_VALUE;
        if (pixel_result != GHOSTTY_SUCCESS && pixel_result != GHOSTTY_NO_VALUE) {
            result = pixel_result;
            break;
        }
        copied->rejected = copied->image_width == 0 || copied->image_height == 0 ||
            copied->decoded_bytes > ODRA_TERMINAL_EMULATOR_IMAGE_DECODED_BYTES;
        GhosttyKittyGraphicsPlacementRenderInfo info =
            GHOSTTY_INIT_SIZED(GhosttyKittyGraphicsPlacementRenderInfo);
        result = ghostty_kitty_graphics_placement_render_info(
            slot->image_iterator, image, slot->terminal, &info);
        if (result != GHOSTTY_SUCCESS) break;
        copied->visible = info.viewport_visible;
        copied->viewport_column = info.viewport_col;
        copied->viewport_row = info.viewport_row;
        copied->grid_columns = info.grid_cols;
        copied->grid_rows = info.grid_rows;
        copied->pixel_width = info.pixel_width;
        copied->pixel_height = info.pixel_height;
    }
    if (result != GHOSTTY_SUCCESS) {
        OdraTerminalEmulatorResult mapped = map_result(result);
        unlock_slots();
        return mapped;
    }
    *out_count = total_count < output_capacity ? total_count : output_capacity;
    *out_truncated = total_count > output_capacity;
    if (total_count > ODRA_TERMINAL_EMULATOR_IMAGE_PLACEMENTS) {
        uint64_t disabled = 0;
        uint64_t restored = ODRA_TERMINAL_EMULATOR_IMAGE_STORAGE_BYTES;
        (void) ghostty_terminal_set(
            slot->terminal, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT, &disabled);
        (void) ghostty_terminal_set(
            slot->terminal, GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT, &restored);
    }
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}

OdraTerminalEmulatorResult odra_terminal_emulator_feature(
    int32_t feature,
    bool* out_supported) {
    if (out_supported == NULL) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_supported = false;
    GhosttyResult result = GHOSTTY_SUCCESS;
    switch ((OdraTerminalEmulatorFeature) feature) {
    case ODRA_TERMINAL_EMULATOR_FEATURE_KEY_ENCODING:
    case ODRA_TERMINAL_EMULATOR_FEATURE_MOUSE_ENCODING:
    case ODRA_TERMINAL_EMULATOR_FEATURE_SELECTION:
    case ODRA_TERMINAL_EMULATOR_FEATURE_SNAPSHOT:
        *out_supported = true;
        break;
    case ODRA_TERMINAL_EMULATOR_FEATURE_KITTY_GRAPHICS:
        result = ghostty_build_info(GHOSTTY_BUILD_INFO_KITTY_GRAPHICS, out_supported);
        break;
    case ODRA_TERMINAL_EMULATOR_FEATURE_TMUX_CONTROL_MODE:
        result = ghostty_build_info(GHOSTTY_BUILD_INFO_TMUX_CONTROL_MODE, out_supported);
        break;
    case ODRA_TERMINAL_EMULATOR_FEATURE_SIMD:
        result = ghostty_build_info(GHOSTTY_BUILD_INFO_SIMD, out_supported);
        break;
    default:
        return ODRA_TERMINAL_EMULATOR_UNSUPPORTED;
    }
    return map_result(result);
}

OdraTerminalEmulatorResult odra_terminal_emulator_stats(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorStats* out_stats) {
    if (out_stats == NULL || ref.slot == 0 || ref.slot > ODRA_TERMINAL_EMULATOR_CAPACITY ||
        ref.generation == 0) {
        return ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT;
    }
    *out_stats = (OdraTerminalEmulatorStats) {0};
    lock_slots();
    OdraTerminalEmulatorSlot* slot = &slots[ref.slot - 1];
    if (slot->generation != ref.generation) {
        unlock_slots();
        return ODRA_TERMINAL_EMULATOR_STALE_HANDLE;
    }
    out_stats->generation = slot->generation;
    out_stats->live = slot->live;
    out_stats->allocation_attempts = slot->allocation_attempts;
    out_stats->allocations = slot->allocations;
    out_stats->frees = slot->frees;
    out_stats->live_bytes = slot->live_bytes;
    out_stats->peak_bytes = slot->peak_bytes;
    unlock_slots();
    return ODRA_TERMINAL_EMULATOR_OK;
}
