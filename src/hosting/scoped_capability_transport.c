// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

enum odra_scoped_capability_kind {
    ODRA_SCOPED_CAPABILITY_TRANSACTION = 1,
    ODRA_SCOPED_CAPABILITY_TRANSFER = 2,
    ODRA_SCOPED_CAPABILITY_SEARCH = 3,
    ODRA_SCOPED_CAPABILITY_BUFFER_SESSION = 4,
    ODRA_SCOPED_CAPABILITY_RESERVED_5 = 5,
    ODRA_SCOPED_CAPABILITY_LAYOUT = 6,
    ODRA_SCOPED_CAPABILITY_UI_ROLE = 7,
    ODRA_SCOPED_CAPABILITY_THEME = 8,
    ODRA_SCOPED_CAPABILITY_STRUCTURAL = 9,
    ODRA_SCOPED_CAPABILITY_LANGUAGE_SERVICE = 10,
    ODRA_SCOPED_CAPABILITY_RESULT = 11,
    ODRA_SCOPED_CAPABILITY_STATUS_BAR = 12,
    ODRA_SCOPED_CAPABILITY_TERMINAL = 13,
};

typedef int32_t (*odra_scoped_capability_callback)(
    void *, int32_t, uint64_t, uint64_t, uint64_t, int32_t, uint64_t, uint64_t,
    const uint8_t *, uint64_t, uint8_t *, uint64_t, uint64_t *, uint64_t *,
    uint32_t *, uint64_t *, uint64_t *
);

struct odra_scoped_capability_context {
    odra_scoped_capability_callback callback;
    void *user_data;
    int32_t kind;
    uint64_t generation;
    uint64_t token;
    uint64_t domain_context;
    thrd_t owner_thread;
    atomic_int active;
    atomic_int callback_active;
};

static struct odra_scoped_capability_context odra_scoped_capability_context = {0};
static uint64_t odra_scoped_capability_next_generation = 1;

static int odra_scoped_capability_kind_is_valid(int32_t kind) {
    return kind >= ODRA_SCOPED_CAPABILITY_TRANSACTION &&
        kind <= ODRA_SCOPED_CAPABILITY_TERMINAL &&
        kind != ODRA_SCOPED_CAPABILITY_RESERVED_5;
}

static int odra_scoped_capability_begin(
    int32_t kind,
    uint64_t token,
    uint64_t domain_context,
    odra_scoped_capability_callback callback,
    void *user_data,
    uint64_t *generation
) {
    if (!odra_scoped_capability_kind_is_valid(kind) || token == 0 ||
        callback == NULL || generation == NULL ||
        atomic_load_explicit(&odra_scoped_capability_context.active, memory_order_acquire)) {
        return 0;
    }
    uint64_t next = odra_scoped_capability_next_generation;
    if (next == 0) {
        return 0;
    }
    odra_scoped_capability_next_generation = next == UINT64_MAX ? 0 : next + 1;
    odra_scoped_capability_context.callback = callback;
    odra_scoped_capability_context.user_data = user_data;
    odra_scoped_capability_context.kind = kind;
    odra_scoped_capability_context.generation = next;
    odra_scoped_capability_context.token = token;
    odra_scoped_capability_context.domain_context = domain_context;
    odra_scoped_capability_context.owner_thread = thrd_current();
    atomic_store_explicit(
        &odra_scoped_capability_context.active, 1, memory_order_release);
    *generation = next;
    return 1;
}

static void odra_scoped_capability_end(void) {
    atomic_store_explicit(
        &odra_scoped_capability_context.active, 0, memory_order_release);
    while (atomic_load_explicit(
               &odra_scoped_capability_context.callback_active, memory_order_acquire)) {
        thrd_yield();
    }
    odra_scoped_capability_context.callback = NULL;
    odra_scoped_capability_context.user_data = NULL;
    odra_scoped_capability_context.kind = 0;
    odra_scoped_capability_context.generation = 0;
    odra_scoped_capability_context.token = 0;
    odra_scoped_capability_context.domain_context = 0;
    memset(&odra_scoped_capability_context.owner_thread, 0, sizeof(thrd_t));
}

// odra_racket_scoped_capability_call dispatches one bounded domain operation.
int32_t odra_racket_scoped_capability_call(
    int32_t kind,
    uint64_t generation,
    uint64_t token,
    int32_t operation,
    uint64_t arg0,
    uint64_t arg1,
    const uint8_t *input,
    uint64_t input_length,
    uint8_t *output,
    uint64_t output_capacity,
    uint64_t *output_length,
    uint64_t *value,
    uint32_t *failure_code,
    uint64_t *limit,
    uint64_t *actual
) {
    if ((input == NULL && input_length != 0) ||
        (output == NULL && output_capacity != 0) || output_length == NULL ||
        value == NULL || failure_code == NULL || limit == NULL || actual == NULL) {
        return 2;
    }
    *output_length = 0;
    *value = 0;
    *failure_code = 0;
    *limit = 0;
    *actual = 0;
    if (atomic_exchange_explicit(
            &odra_scoped_capability_context.callback_active, 1, memory_order_acq_rel)) {
        return 2;
    }
    if (!atomic_load_explicit(
            &odra_scoped_capability_context.active, memory_order_acquire) ||
        odra_scoped_capability_context.callback == NULL ||
        kind != odra_scoped_capability_context.kind ||
        generation != odra_scoped_capability_context.generation ||
        token != odra_scoped_capability_context.token ||
        !thrd_equal(thrd_current(), odra_scoped_capability_context.owner_thread)) {
        atomic_store_explicit(
            &odra_scoped_capability_context.callback_active, 0, memory_order_release);
        return 2;
    }
    int32_t result = odra_scoped_capability_context.callback(
        odra_scoped_capability_context.user_data,
        kind,
        generation,
        token,
        odra_scoped_capability_context.domain_context,
        operation,
        arg0,
        arg1,
        input,
        input_length,
        output,
        output_capacity,
        output_length,
        value,
        failure_code,
        limit,
        actual);
    if (*output_length > output_capacity) {
        result = 2;
        *output_length = 0;
    }
    atomic_store_explicit(
        &odra_scoped_capability_context.callback_active, 0, memory_order_release);
    return result;
}
