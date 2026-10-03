// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#include <stdalign.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "tree_sitter/api.h"

#define ODRA_TREE_SITTER_MEMORY_OWNERS 128u

extern const TSLanguage *tree_sitter_odin(void);
extern const TSLanguage *tree_sitter_jan(void);
extern const TSLanguage *tree_sitter_racket(void);
extern const TSLanguage *tree_sitter_go(void);
extern const TSLanguage *tree_sitter_rust(void);
extern const TSLanguage *tree_sitter_javascript(void);
extern const TSLanguage *tree_sitter_typescript(void);
extern const TSLanguage *tree_sitter_tsx(void);
extern const TSLanguage *tree_sitter_html(void);
extern const TSLanguage *tree_sitter_css(void);

const TSLanguage *odra_tree_sitter_factory_language(
    const uint8_t *identity, size_t length) {
  static const char odin_identity[] = "org.odra.odin";
  static const char jan_identity[] = "org.odra.jan";
  static const char racket_identity[] = "org.odra.racket";
  static const char go_identity[] = "org.odra.go";
  static const char rust_identity[] = "org.odra.rust";
  static const char javascript_identity[] = "org.odra.javascript";
  static const char javascript_jsx_identity[] = "org.odra.javascript.jsx";
  static const char typescript_identity[] = "org.odra.typescript";
  static const char typescript_tsx_identity[] = "org.odra.typescript.tsx";
  static const char html_identity[] = "org.odra.html";
  static const char css_identity[] = "org.odra.css";
  if (identity == NULL) {
    return NULL;
  }
  if (length == sizeof(odin_identity) - 1u &&
      memcmp(identity, odin_identity, length) == 0) {
    return tree_sitter_odin();
  }
  if (length == sizeof(jan_identity) - 1u &&
      memcmp(identity, jan_identity, length) == 0) {
    return tree_sitter_jan();
  }
  if (length == sizeof(racket_identity) - 1u &&
      memcmp(identity, racket_identity, length) == 0) {
    return tree_sitter_racket();
  }
  if (length == sizeof(go_identity) - 1u &&
      memcmp(identity, go_identity, length) == 0) {
    return tree_sitter_go();
  }
  if (length == sizeof(rust_identity) - 1u &&
      memcmp(identity, rust_identity, length) == 0) {
    return tree_sitter_rust();
  }
  if ((length == sizeof(javascript_identity) - 1u &&
       memcmp(identity, javascript_identity, length) == 0) ||
      (length == sizeof(javascript_jsx_identity) - 1u &&
       memcmp(identity, javascript_jsx_identity, length) == 0)) {
    return tree_sitter_javascript();
  }
  if (length == sizeof(typescript_identity) - 1u &&
      memcmp(identity, typescript_identity, length) == 0) {
    return tree_sitter_typescript();
  }
  if (length == sizeof(typescript_tsx_identity) - 1u &&
      memcmp(identity, typescript_tsx_identity, length) == 0) {
    return tree_sitter_tsx();
  }
  if (length == sizeof(html_identity) - 1u &&
      memcmp(identity, html_identity, length) == 0) {
    return tree_sitter_html();
  }
  if (length == sizeof(css_identity) - 1u &&
      memcmp(identity, css_identity, length) == 0) {
    return tree_sitter_css();
  }
  return NULL;
}

typedef union {
  max_align_t alignment;
  struct {
    size_t size;
    uint32_t owner;
  } allocation;
} OdraTreeSitterAllocation;

typedef struct {
  atomic_bool used;
  atomic_uint_fast64_t live_bytes;
  atomic_uint_fast64_t peak_bytes;
  atomic_uint_fast64_t allocations;
  atomic_uint_fast64_t frees;
} OdraTreeSitterMemoryOwner;

static atomic_int odra_tree_sitter_install_state;
static OdraTreeSitterMemoryOwner
    odra_tree_sitter_owners[ODRA_TREE_SITTER_MEMORY_OWNERS + 1u];
static _Thread_local uint32_t odra_tree_sitter_current_owner;

static OdraTreeSitterMemoryOwner *odra_tree_sitter_memory_owner(uint32_t owner) {
  if (owner > ODRA_TREE_SITTER_MEMORY_OWNERS) {
    return NULL;
  }
  return &odra_tree_sitter_owners[owner];
}

static void odra_tree_sitter_memory_record_allocation(
    OdraTreeSitterMemoryOwner *owner, size_t size) {
  if (owner == NULL) {
    return;
  }
  atomic_fetch_add_explicit(&owner->allocations, 1u, memory_order_relaxed);
  uint64_t live = atomic_fetch_add_explicit(
                      &owner->live_bytes, (uint64_t)size,
                      memory_order_relaxed) +
                  (uint64_t)size;
  uint64_t peak = atomic_load_explicit(&owner->peak_bytes, memory_order_relaxed);
  while (live > peak &&
         !atomic_compare_exchange_weak_explicit(
             &owner->peak_bytes, &peak, live, memory_order_relaxed,
             memory_order_relaxed)) {
  }
}

static void *odra_tree_sitter_malloc(size_t size) {
  uint32_t owner_id = odra_tree_sitter_current_owner;
  OdraTreeSitterMemoryOwner *owner = odra_tree_sitter_memory_owner(owner_id);
  if (size > SIZE_MAX - sizeof(OdraTreeSitterAllocation)) {
    return NULL;
  }
  OdraTreeSitterAllocation *allocation =
      malloc(sizeof(OdraTreeSitterAllocation) + size);
  if (allocation == NULL) {
    return NULL;
  }
  allocation->allocation.size = size;
  allocation->allocation.owner = owner_id;
  odra_tree_sitter_memory_record_allocation(owner, size);
  return allocation + 1;
}

static void *odra_tree_sitter_calloc(size_t count, size_t size) {
  if (count != 0u && size > SIZE_MAX / count) {
    return NULL;
  }
  size_t bytes = count * size;
  void *memory = odra_tree_sitter_malloc(bytes);
  if (memory != NULL) {
    for (size_t index = 0; index < bytes; ++index) {
      ((unsigned char *)memory)[index] = 0u;
    }
  }
  return memory;
}

static void odra_tree_sitter_free(void *memory) {
  if (memory == NULL) {
    return;
  }
  OdraTreeSitterAllocation *allocation =
      ((OdraTreeSitterAllocation *)memory) - 1;
  OdraTreeSitterMemoryOwner *owner =
      odra_tree_sitter_memory_owner(allocation->allocation.owner);
  if (owner != NULL) {
    atomic_fetch_sub_explicit(
        &owner->live_bytes, (uint64_t)allocation->allocation.size,
        memory_order_relaxed);
    atomic_fetch_add_explicit(&owner->frees, 1u, memory_order_relaxed);
  }
  free(allocation);
}

static void *odra_tree_sitter_realloc(void *memory, size_t size) {
  if (memory == NULL) {
    return odra_tree_sitter_malloc(size);
  }
  if (size == 0u) {
    odra_tree_sitter_free(memory);
    return NULL;
  }
  OdraTreeSitterAllocation *old_allocation =
      ((OdraTreeSitterAllocation *)memory) - 1;
  uint32_t owner_id = old_allocation->allocation.owner;
  size_t old_size = old_allocation->allocation.size;
  OdraTreeSitterMemoryOwner *owner = odra_tree_sitter_memory_owner(owner_id);
  if (size > SIZE_MAX - sizeof(OdraTreeSitterAllocation)) {
    return NULL;
  }
  OdraTreeSitterAllocation *allocation =
      realloc(old_allocation, sizeof(OdraTreeSitterAllocation) + size);
  if (allocation == NULL) {
    return NULL;
  }
  allocation->allocation.size = size;
  allocation->allocation.owner = owner_id;
  if (owner != NULL) {
    if (size >= old_size) {
      odra_tree_sitter_memory_record_allocation(owner, size - old_size);
    } else {
      atomic_fetch_sub_explicit(
          &owner->live_bytes, (uint64_t)(old_size - size),
          memory_order_relaxed);
    }
  }
  return allocation + 1;
}

void odra_tree_sitter_memory_install(void) {
  int expected = 0;
  if (atomic_compare_exchange_strong_explicit(
          &odra_tree_sitter_install_state, &expected, 1,
          memory_order_acq_rel, memory_order_acquire)) {
    ts_set_allocator(
        odra_tree_sitter_malloc, odra_tree_sitter_calloc,
        odra_tree_sitter_realloc, odra_tree_sitter_free);
    atomic_store_explicit(
        &odra_tree_sitter_install_state, 2, memory_order_release);
    return;
  }
  while (atomic_load_explicit(
             &odra_tree_sitter_install_state, memory_order_acquire) != 2) {
  }
}

uint32_t odra_tree_sitter_memory_owner_open(void) {
  for (uint32_t index = 1u; index <= ODRA_TREE_SITTER_MEMORY_OWNERS; ++index) {
    bool expected = false;
    if (atomic_compare_exchange_strong_explicit(
            &odra_tree_sitter_owners[index].used, &expected, true,
            memory_order_acq_rel, memory_order_acquire)) {
      atomic_store(&odra_tree_sitter_owners[index].live_bytes, 0u);
      atomic_store(&odra_tree_sitter_owners[index].peak_bytes, 0u);
      atomic_store(&odra_tree_sitter_owners[index].allocations, 0u);
      atomic_store(&odra_tree_sitter_owners[index].frees, 0u);
      return index;
    }
  }
  return 0u;
}

void odra_tree_sitter_memory_owner_begin(uint32_t owner) {
  odra_tree_sitter_current_owner = owner;
}

void odra_tree_sitter_memory_owner_end(void) {
  odra_tree_sitter_current_owner = 0u;
}

uint64_t odra_tree_sitter_memory_owner_live_bytes(uint32_t owner) {
  OdraTreeSitterMemoryOwner *entry = odra_tree_sitter_memory_owner(owner);
  return entry == NULL ? 0u : atomic_load(&entry->live_bytes);
}

uint64_t odra_tree_sitter_memory_owner_peak_bytes(uint32_t owner) {
  OdraTreeSitterMemoryOwner *entry = odra_tree_sitter_memory_owner(owner);
  return entry == NULL ? 0u : atomic_load(&entry->peak_bytes);
}

uint64_t odra_tree_sitter_memory_owner_allocations(uint32_t owner) {
  OdraTreeSitterMemoryOwner *entry = odra_tree_sitter_memory_owner(owner);
  return entry == NULL ? 0u : atomic_load(&entry->allocations);
}

uint64_t odra_tree_sitter_memory_owner_frees(uint32_t owner) {
  OdraTreeSitterMemoryOwner *entry = odra_tree_sitter_memory_owner(owner);
  return entry == NULL ? 0u : atomic_load(&entry->frees);
}

bool odra_tree_sitter_memory_owner_close(uint32_t owner) {
  OdraTreeSitterMemoryOwner *entry = odra_tree_sitter_memory_owner(owner);
  if (entry == NULL || atomic_load(&entry->live_bytes) != 0u) {
    return false;
  }
  atomic_store_explicit(&entry->used, false, memory_order_release);
  return true;
}
