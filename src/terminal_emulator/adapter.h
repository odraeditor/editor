// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#ifndef ODRA_TERMINAL_EMULATOR_ADAPTER_H
#define ODRA_TERMINAL_EMULATOR_ADAPTER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    ODRA_TERMINAL_EMULATOR_OK = 0,
    ODRA_TERMINAL_EMULATOR_INVALID_ARGUMENT = 1,
    ODRA_TERMINAL_EMULATOR_UNAVAILABLE = 2,
    ODRA_TERMINAL_EMULATOR_STALE_HANDLE = 3,
    ODRA_TERMINAL_EMULATOR_ALLOCATION_FAILED = 4,
    ODRA_TERMINAL_EMULATOR_BUFFER_TOO_SMALL = 5,
    ODRA_TERMINAL_EMULATOR_UNSUPPORTED = 6,
    ODRA_TERMINAL_EMULATOR_FOREIGN_FAILURE = 7,
    ODRA_TERMINAL_EMULATOR_REJECTED = 8,
} OdraTerminalEmulatorResult;

typedef enum {
    ODRA_TERMINAL_EMULATOR_FEATURE_INVALID = 0,
    ODRA_TERMINAL_EMULATOR_FEATURE_KEY_ENCODING = 1,
    ODRA_TERMINAL_EMULATOR_FEATURE_MOUSE_ENCODING = 2,
    ODRA_TERMINAL_EMULATOR_FEATURE_SELECTION = 3,
    ODRA_TERMINAL_EMULATOR_FEATURE_SNAPSHOT = 4,
    ODRA_TERMINAL_EMULATOR_FEATURE_KITTY_GRAPHICS = 5,
    ODRA_TERMINAL_EMULATOR_FEATURE_TMUX_CONTROL_MODE = 6,
    ODRA_TERMINAL_EMULATOR_FEATURE_SIMD = 7,
} OdraTerminalEmulatorFeature;

typedef enum {
    ODRA_TERMINAL_EMULATOR_KEY_CHARACTER = 1,
    ODRA_TERMINAL_EMULATOR_KEY_ENTER = 2,
    ODRA_TERMINAL_EMULATOR_KEY_ARROW_UP = 3,
    ODRA_TERMINAL_EMULATOR_KEY_ARROW_DOWN = 4,
    ODRA_TERMINAL_EMULATOR_KEY_ARROW_LEFT = 5,
    ODRA_TERMINAL_EMULATOR_KEY_ARROW_RIGHT = 6,
    ODRA_TERMINAL_EMULATOR_KEY_TAB = 7,
    ODRA_TERMINAL_EMULATOR_KEY_BACKSPACE = 8,
    ODRA_TERMINAL_EMULATOR_KEY_DELETE = 9,
    ODRA_TERMINAL_EMULATOR_KEY_ESCAPE = 10,
    ODRA_TERMINAL_EMULATOR_KEY_HOME = 11,
    ODRA_TERMINAL_EMULATOR_KEY_END = 12,
    ODRA_TERMINAL_EMULATOR_KEY_PAGE_UP = 13,
    ODRA_TERMINAL_EMULATOR_KEY_PAGE_DOWN = 14,
    ODRA_TERMINAL_EMULATOR_KEY_SPACE = 15,
} OdraTerminalEmulatorKey;

typedef enum {
    ODRA_TERMINAL_EMULATOR_KEY_PRESS = 0,
    ODRA_TERMINAL_EMULATOR_KEY_REPEAT = 1,
} OdraTerminalEmulatorKeyAction;

typedef enum {
    ODRA_TERMINAL_EMULATOR_FOCUS_GAINED = 0,
    ODRA_TERMINAL_EMULATOR_FOCUS_LOST = 1,
} OdraTerminalEmulatorFocusEvent;

typedef enum {
    ODRA_TERMINAL_EMULATOR_MOUSE_PRESS = 0,
    ODRA_TERMINAL_EMULATOR_MOUSE_RELEASE = 1,
    ODRA_TERMINAL_EMULATOR_MOUSE_MOTION = 2,
} OdraTerminalEmulatorMouseAction;

typedef enum {
    ODRA_TERMINAL_EMULATOR_MOUSE_NONE = -1,
    ODRA_TERMINAL_EMULATOR_MOUSE_LEFT = 0,
    ODRA_TERMINAL_EMULATOR_MOUSE_RIGHT = 1,
    ODRA_TERMINAL_EMULATOR_MOUSE_MIDDLE = 2,
    ODRA_TERMINAL_EMULATOR_MOUSE_WHEEL_UP = 3,
    ODRA_TERMINAL_EMULATOR_MOUSE_WHEEL_DOWN = 4,
} OdraTerminalEmulatorMouseButton;

#define ODRA_TERMINAL_EMULATOR_MOD_SHIFT (1u << 0)
#define ODRA_TERMINAL_EMULATOR_MOD_CONTROL (1u << 1)
#define ODRA_TERMINAL_EMULATOR_MOD_ALT (1u << 2)
#define ODRA_TERMINAL_EMULATOR_MOD_SUPER (1u << 3)
#define ODRA_TERMINAL_EMULATOR_WRITEBACK_CAPACITY (64u * 1024u)
#define ODRA_TERMINAL_EMULATOR_CELL_TEXT_BYTES 64u
#define ODRA_TERMINAL_EMULATOR_SEMANTIC_ANCHOR_CAPACITY 128u
#define ODRA_TERMINAL_EMULATOR_METADATA_BYTES (16u * 1024u)
#define ODRA_TERMINAL_EMULATOR_UNKNOWN_CAPTURE_BYTES (4u * 1024u)
#define ODRA_TERMINAL_EMULATOR_CLIPBOARD_WRITE_BYTES (64u * 1024u)
#define ODRA_TERMINAL_EMULATOR_IMAGE_PLACEMENTS 8u
#define ODRA_TERMINAL_EMULATOR_IMAGE_ENCODED_BYTES (8u * 1024u * 1024u)
#define ODRA_TERMINAL_EMULATOR_IMAGE_DECODED_BYTES (16u * 1024u * 1024u)
#define ODRA_TERMINAL_EMULATOR_IMAGE_STORAGE_BYTES (32u * 1024u * 1024u)

typedef struct {
    uint32_t slot;
    uint32_t generation;
} OdraTerminalEmulatorRef;

typedef struct {
    uint32_t slot;
    uint32_t generation;
} OdraTerminalEmulatorSemanticAnchor;

typedef struct {
    uint16_t columns;
    uint16_t rows;
    uint32_t cell_width_pixels;
    uint32_t cell_height_pixels;
    uint64_t allocation_fail_after;
    uint64_t scrollback_max_bytes;
    uint64_t scrollback_max_lines;
} OdraTerminalEmulatorOptions;

typedef enum {
    ODRA_TERMINAL_EMULATOR_SCROLL_TOP = 0,
    ODRA_TERMINAL_EMULATOR_SCROLL_BOTTOM = 1,
    ODRA_TERMINAL_EMULATOR_SCROLL_DELTA = 2,
    ODRA_TERMINAL_EMULATOR_SCROLL_ROW = 3,
} OdraTerminalEmulatorScroll;

typedef enum {
    ODRA_TERMINAL_EMULATOR_TEXT_SCREEN = 0,
    ODRA_TERMINAL_EMULATOR_TEXT_VIEWPORT = 1,
    ODRA_TERMINAL_EMULATOR_TEXT_SCREEN_RANGE = 2,
    ODRA_TERMINAL_EMULATOR_TEXT_HISTORY_RANGE = 3,
} OdraTerminalEmulatorTextScope;

typedef struct {
    uint64_t total_rows;
    uint64_t scrollback_rows;
    uint64_t viewport_offset;
    uint64_t viewport_rows;
    uint64_t scrollback_max_bytes;
    uint64_t scrollback_max_lines;
    uint64_t compression_activity;
    bool viewport_active;
} OdraTerminalEmulatorScrollState;

typedef struct {
    uint16_t cursor_column;
    uint64_t cursor_row;
    bool alternate_screen;
    bool cursor_at_prompt;
} OdraTerminalEmulatorSemanticState;

typedef struct {
    bool tracking;
} OdraTerminalEmulatorMouseState;

typedef struct {
    int32_t scope;
    uint16_t start_column;
    uint32_t start_row;
    uint16_t end_column;
    uint32_t end_row;
    bool rectangle;
    bool unwrap;
    bool trim;
} OdraTerminalEmulatorTextRequest;

typedef struct {
    uint16_t columns;
    uint16_t rows;
    uint16_t cursor_column;
    uint16_t cursor_row;
    bool cursor_visible;
} OdraTerminalEmulatorRenderState;

typedef struct {
    uint64_t bell_count;
    uint64_t writeback_count;
    uint64_t writeback_bytes;
    uint64_t writeback_pending_bytes;
    uint64_t writeback_dropped_bytes;
    uint64_t title_change_count;
    uint64_t pwd_change_count;
    uint64_t clipboard_read_denied_count;
    uint64_t clipboard_write_denied_count;
    uint64_t notification_denied_count;
    uint64_t notification_bytes;
    uint64_t progress_count;
    uint64_t progress_state;
    int64_t progress_percent;
    uint64_t unknown_sequence_count;
    uint64_t unknown_sequence_bytes;
    uint64_t unknown_truncated_count;
} OdraTerminalEmulatorEffects;

typedef struct {
    uint32_t image_id;
    uint32_t placement_id;
    uint64_t generation;
    uint64_t decoded_bytes;
    uint32_t image_width;
    uint32_t image_height;
    int32_t format;
    int32_t viewport_column;
    int32_t viewport_row;
    uint32_t grid_columns;
    uint32_t grid_rows;
    uint32_t pixel_width;
    uint32_t pixel_height;
    int32_t z;
    bool visible;
    bool pending;
    bool rejected;
} OdraTerminalEmulatorImagePlacement;

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} OdraTerminalEmulatorColor;

typedef struct {
    int32_t kind;
    uint8_t palette;
    OdraTerminalEmulatorColor rgb;
} OdraTerminalEmulatorStyleColor;

typedef struct {
    OdraTerminalEmulatorStyleColor foreground;
    OdraTerminalEmulatorStyleColor background;
    OdraTerminalEmulatorStyleColor underline_color;
    bool bold;
    bool italic;
    bool faint;
    bool blink;
    bool inverse;
    bool invisible;
    bool strikethrough;
    bool overline;
    int32_t underline;
} OdraTerminalEmulatorCellStyle;

typedef struct {
    uint16_t column;
    uint16_t row;
    uint8_t text[ODRA_TERMINAL_EMULATOR_CELL_TEXT_BYTES];
    uint16_t text_length;
    int32_t width;
    int32_t semantic_content;
    bool has_text;
    bool selected;
    bool protected_cell;
    bool hyperlink;
    bool text_clipped;
    OdraTerminalEmulatorCellStyle style;
} OdraTerminalEmulatorCell;

typedef struct {
    uint16_t row;
    bool dirty;
    bool wrapped;
    bool wrap_continuation;
} OdraTerminalEmulatorRow;

typedef struct {
    int32_t damage;
    uint16_t columns;
    uint16_t rows;
    uint16_t damaged_rows;
    uint16_t first_damaged_row;
    uint16_t last_damaged_row;
    uint64_t damaged_cells;
    uint64_t clipped_cells;
    uint64_t clipped_text_bytes;
    uint16_t cursor_column;
    uint16_t cursor_row;
    int32_t cursor_style;
    bool cursor_in_viewport;
    bool cursor_visible;
    bool cursor_blinking;
    bool cursor_password_input;
    bool cursor_wide_tail;
    OdraTerminalEmulatorColor background;
    OdraTerminalEmulatorColor foreground;
    OdraTerminalEmulatorColor cursor;
    bool cursor_color_set;
    OdraTerminalEmulatorColor palette[256];
} OdraTerminalEmulatorProjection;

typedef struct {
    uint32_t generation;
    bool live;
    uint64_t allocation_attempts;
    uint64_t allocations;
    uint64_t frees;
    uint64_t live_bytes;
    uint64_t peak_bytes;
} OdraTerminalEmulatorStats;

OdraTerminalEmulatorResult odra_terminal_emulator_open(
    const OdraTerminalEmulatorOptions* options,
    OdraTerminalEmulatorRef* out_ref);
OdraTerminalEmulatorResult odra_terminal_emulator_close(
    OdraTerminalEmulatorRef ref);
OdraTerminalEmulatorResult odra_terminal_emulator_write(
    OdraTerminalEmulatorRef ref,
    const uint8_t* bytes,
    size_t length);
OdraTerminalEmulatorResult odra_terminal_emulator_resize(
    OdraTerminalEmulatorRef ref,
    uint16_t columns,
    uint16_t rows,
    uint32_t cell_width_pixels,
    uint32_t cell_height_pixels);
OdraTerminalEmulatorResult odra_terminal_emulator_render(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorRenderState* out_state);
OdraTerminalEmulatorResult odra_terminal_emulator_project(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorProjection* out_projection,
    OdraTerminalEmulatorRow* rows,
    size_t row_capacity,
    OdraTerminalEmulatorCell* cells,
    size_t cell_capacity);
OdraTerminalEmulatorResult odra_terminal_emulator_scroll_state(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorScrollState* out_state);
OdraTerminalEmulatorResult odra_terminal_emulator_semantic_state(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticState* out_state);
OdraTerminalEmulatorResult odra_terminal_emulator_mouse_state(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorMouseState* out_state);
OdraTerminalEmulatorResult odra_terminal_emulator_hyperlink_at(
    OdraTerminalEmulatorRef ref,
    uint16_t column,
    uint32_t row,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written);
OdraTerminalEmulatorResult odra_terminal_emulator_semantic_anchor_open(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticAnchor* out_anchor);
OdraTerminalEmulatorResult odra_terminal_emulator_semantic_anchor_resolve(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticAnchor anchor,
    uint64_t* out_row,
    uint16_t* out_column);
OdraTerminalEmulatorResult odra_terminal_emulator_semantic_anchor_close(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorSemanticAnchor anchor);
OdraTerminalEmulatorResult odra_terminal_emulator_scroll(
    OdraTerminalEmulatorRef ref,
    int32_t behavior,
    int64_t value);
OdraTerminalEmulatorResult odra_terminal_emulator_compress(
    OdraTerminalEmulatorRef ref,
    bool* out_pending,
    bool* out_supported);
OdraTerminalEmulatorResult odra_terminal_emulator_format_text(
    OdraTerminalEmulatorRef ref,
    const OdraTerminalEmulatorTextRequest* request,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written);
OdraTerminalEmulatorResult odra_terminal_emulator_format_text_bounded(
    OdraTerminalEmulatorRef ref,
    const OdraTerminalEmulatorTextRequest* request,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_copied,
    size_t* out_required);
OdraTerminalEmulatorResult odra_terminal_emulator_encode_key(
    OdraTerminalEmulatorRef ref,
    int32_t key,
    int32_t action,
    uint32_t modifiers,
    const uint8_t* text,
    size_t text_length,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written);
OdraTerminalEmulatorResult odra_terminal_emulator_encode_focus(
    OdraTerminalEmulatorRef ref,
    int32_t event,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written,
    bool* out_enabled);
OdraTerminalEmulatorResult odra_terminal_emulator_encode_paste(
    OdraTerminalEmulatorRef ref,
    uint8_t* text,
    size_t text_length,
    bool allow_unsafe,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written,
    bool* out_bracketed);
OdraTerminalEmulatorResult odra_terminal_emulator_encode_mouse(
    OdraTerminalEmulatorRef ref,
    int32_t action,
    int32_t button,
    uint32_t modifiers,
    float x,
    float y,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written);
OdraTerminalEmulatorResult odra_terminal_emulator_select_all(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written);
OdraTerminalEmulatorResult odra_terminal_emulator_snapshot(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written);
OdraTerminalEmulatorResult odra_terminal_emulator_effects(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorEffects* out_effects);
OdraTerminalEmulatorResult odra_terminal_emulator_title_copy(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_copied,
    size_t* out_required);
OdraTerminalEmulatorResult odra_terminal_emulator_pwd_copy(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_copied,
    size_t* out_required);
OdraTerminalEmulatorResult odra_terminal_emulator_writeback_copy(
    OdraTerminalEmulatorRef ref,
    uint8_t* output,
    size_t output_capacity,
    size_t* out_written,
    size_t* out_pending);
OdraTerminalEmulatorResult odra_terminal_emulator_writeback_consume(
    OdraTerminalEmulatorRef ref,
    size_t length);
OdraTerminalEmulatorResult odra_terminal_emulator_image_generation(
    OdraTerminalEmulatorRef ref,
    uint64_t* out_generation);
OdraTerminalEmulatorResult odra_terminal_emulator_project_images(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorImagePlacement* output,
    size_t output_capacity,
    size_t* out_count,
    uint64_t* out_generation,
    uint64_t* out_decoded_bytes,
    bool* out_truncated);
OdraTerminalEmulatorResult odra_terminal_emulator_feature(
    int32_t feature,
    bool* out_supported);
OdraTerminalEmulatorResult odra_terminal_emulator_stats(
    OdraTerminalEmulatorRef ref,
    OdraTerminalEmulatorStats* out_stats);

#endif
