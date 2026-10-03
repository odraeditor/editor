// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "tree_sitter/api.h"
#include "tree-sitter-jan.h"

static bool contains_type(TSNode node, const char *type) {
  if (strcmp(ts_node_type(node), type) == 0) return true;
  uint32_t count = ts_node_named_child_count(node);
  for (uint32_t index = 0; index < count; index++) {
    if (contains_type(ts_node_named_child(node, index), type)) return true;
  }
  return false;
}

int main(void) {
  static const char source[] =
      "#+title: Demo\r\n"
      "* TODO Heading :tag:\n"
      ":PROPERTIES:\n"
      ":ID: alpha\n"
      ":END:\n"
      "SCHEDULED: <2026-09-10>\n"
      "- [ ] item\n"
      "| a | b |\n"
      "|---+---|\n"
      "#+begin_src odin\n"
      "main :: proc() {}\n"
      "#+end_src\n"
      "Entity \\alpha and math $x+y$ with @@html:<b>x</b>@@.\n"
      "Footnotes [fn:n] [fn:n:body] [fn::anonymous] and [cite:@doe; @roe].\n"
      "call_total(1,2)\n"
      "src_odin{value}\n"
      "https://example.test <https://example.test> [[target][description]]\n"
      "<<ordinary>> <<<radio>>> {{{name(arg)}}}\n"
      "[50%] [1/2] x_1 x^{2} --- ...\n"
      "<2026-09-10 Wed> [2026-09-10 Wed] <2026-09-10 +1w> <2026-09-10 -2d>\n"
      "<2026-09-10>--<2026-09-11> <%%(diary-float t 1)>\n"
      "*bold* /italic/ _underlined_ =verbatim= ~code~ +struck+\\\\\n";
  TSParser *parser = ts_parser_new();
  if (parser == NULL) return 1;
  if (!ts_parser_set_language(parser, tree_sitter_jan())) {
    ts_parser_delete(parser);
    return 2;
  }
  TSTree *tree = ts_parser_parse_string(parser, NULL, source, (uint32_t)strlen(source));
  if (tree == NULL) {
    ts_parser_delete(parser);
    return 3;
  }
  TSNode root = ts_tree_root_node(tree);
  int result = 0;
  if (strcmp(ts_node_type(root), "document") != 0) result = 4;
  if (ts_node_start_byte(root) != 0 || ts_node_end_byte(root) != strlen(source)) result = 5;
  if (ts_node_has_error(root)) result = 6;
  if (ts_node_named_child_count(root) != 2) result = 7;
  static const char *required[] = {
      "zeroth_section", "keyword", "heading", "section", "property_drawer",
      "node_property", "planning_line", "plain_list", "list_item",
      "pipe_table", "table_row", "table_separator_row", "source_block",
      "table_cell", "entity", "latex_fragment", "export_snippet",
      "named_footnote_reference", "inline_footnote_reference",
      "anonymous_footnote_reference", "citation", "citation_reference",
      "inline_call", "inline_source", "plain_link", "angle_link",
      "regular_link", "target", "radio_target", "macro",
      "percentage_cookie", "fraction_cookie", "subscript", "superscript",
      "point_timestamp", "active_timestamp", "inactive_timestamp",
      "diary_timestamp", "timestamp_range", "repeating_timestamp",
      "delayed_timestamp", "special_symbol", "plain_text",
      "bold_markup", "italic_markup", "underline_markup", "verbatim_markup",
      "code_markup", "strike_through_markup", "explicit_line_break",
  };
  for (size_t index = 0; index < sizeof(required) / sizeof(required[0]); index++) {
    if (!contains_type(root, required[index])) {
      fprintf(stderr, "missing node type: %s\n", required[index]);
      result = 8;
    }
  }
  ts_tree_delete(tree);
  ts_parser_delete(parser);
  return result;
}
