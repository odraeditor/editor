// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#include <stdint.h>

#include "tree_sitter/api.h"
#include "tree-sitter-odin.h"

int main(void) {
  const TSLanguage *language = tree_sitter_odin();
  if (language == NULL || ts_language_abi_version(language) != 14) {
    return 1;
  }

  TSParser *parser = ts_parser_new();
  if (parser == NULL) {
    return 2;
  }

  const bool accepted = ts_parser_set_language(parser, language);
  ts_parser_delete(parser);
  return accepted ? 0 : 3;
}
