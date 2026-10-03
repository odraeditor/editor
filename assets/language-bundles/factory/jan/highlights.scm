; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

[
  (heading)
  (target)
  (radio_target)
] @label

[
  (keyword)
  (affiliated_keyword)
  (planning_line)
  (dynamic_block)
  (center_block)
  (quote_block)
  (special_block)
] @keyword

[
  (node_property)
  (property_drawer)
  (drawer)
] @attribute

[
  (line_comment)
  (comment_block)
] @comment

[
  (source_block)
  (example_block)
  (export_block)
  (lesser_block)
  (latex_environment)
  (latex_fragment)
  (export_snippet)
  (inline_call)
  (inline_source)
  (verbatim_markup)
  (code_markup)
  (named_footnote_reference)
  (inline_footnote_reference)
  (anonymous_footnote_reference)
  (citation)
  (citation_reference)
  (plain_link)
  (angle_link)
  (regular_link)
  (bold_markup)
  (italic_markup)
  (underline_markup)
  (strike_through_markup)
] @string

[
  (entity)
  (special_symbol)
  (macro)
  (active_timestamp)
  (inactive_timestamp)
  (diary_timestamp)
  (point_timestamp)
  (timestamp_range)
  (repeating_timestamp)
  (delayed_timestamp)
] @constant

[
  (percentage_cookie)
  (fraction_cookie)
] @number

[
  (list_item)
  (plain_list)
  (pipe_table)
  (table_provider_form)
  (table_row)
  (table_separator_row)
  (table_cell)
  (horizontal_rule)
  (explicit_line_break)
] @punctuation

(recovery) @comment.error
