/**
 * @file Lossless structural grammar for the Jan document language
 * @license Repository-owned Odra source
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

const line = ($, rule) => seq(rule, optional($.line_ending));
const literalLine = ($, pattern, precedence = 10) =>
  line($, token(prec(precedence, pattern)));

module.exports = grammar({
  name: 'jan',

  extras: _ => [],

  externals: $ => [
    $.blank_line,
    $.line_ending,
    $._end_of_file,
  ],

  rules: {
    document: $ => seq(
      optional($.zeroth_section),
      repeat($.heading),
    ),

    zeroth_section: $ => repeat1($._section_element),

    heading: $ => seq(
      $.heading_line,
      optional($.section),
    ),

    heading_line: $ => literalLine($, /\*+[ \t]+[^\r\n]*/, 30),

    section: $ => repeat1(choice($.planning_line, $.inline_task, $._section_element)),

    _section_element: $ => choice(
      $.property_drawer,
      $.drawer,
      $.center_block,
      $.quote_block,
      $.special_block,
      $.dynamic_block,
      $.footnote_definition,
      $.plain_list,
      $.pipe_table,
      $.table_provider_form,
      $.source_block,
      $.example_block,
      $.export_block,
      $.comment_block,
      $.lesser_block,
      $.clock,
      $.diary_expression,
      $.line_comment,
      $.fixed_width_area,
      $.horizontal_rule,
      $.affiliated_keyword,
      $.keyword,
      $.latex_environment,
      $.paragraph,
      $.blank_line,
      $.recovery,
    ),

    center_block: $ => seq(
      $._begin_center,
      repeat($._block_element),
      $._end_center,
    ),
    _begin_center: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[Cc][Ee][Nn][Tt][Ee][Rr](?:[ \t]+[^\r\n]*)?/, 30),
    _end_center: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[Cc][Ee][Nn][Tt][Ee][Rr][ \t]*/, 30),

    quote_block: $ => seq(
      $._begin_quote,
      repeat($._block_element),
      $._end_quote,
    ),
    _begin_quote: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[Qq][Uu][Oo][Tt][Ee](?:[ \t]+[^\r\n]*)?/, 30),
    _end_quote: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[Qq][Uu][Oo][Tt][Ee][ \t]*/, 30),

    special_block: $ => seq(
      field('begin', $._begin_special),
      repeat($._block_element),
      field('end', $._end_special),
    ),
    _begin_special: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[A-Za-z][A-Za-z0-9_-]*(?:[ \t]+[^\r\n]*)?/, 15),
    _end_special: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[A-Za-z][A-Za-z0-9_-]*[ \t]*/, 15),

    dynamic_block: $ => seq(
      $._begin_dynamic,
      repeat($._block_element),
      $._end_dynamic,
    ),
    _begin_dynamic: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]:[ \t]+[A-Za-z][A-Za-z0-9_-]*(?:[ \t]+[^\r\n]*)?/, 30),
    _end_dynamic: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]:[ \t]*/, 30),

    drawer: $ => seq(
      field('begin', $._drawer_begin),
      repeat($._drawer_element),
      field('end', $._drawer_end),
    ),
    _drawer_begin: $ => literalLine($, /[ \t]*:[A-Za-z][A-Za-z0-9_@#%]*:[ \t]*/, 20),
    _drawer_end: $ => literalLine($, /[ \t]*:[Ee][Nn][Dd]:[ \t]*/, 30),

    property_drawer: $ => seq(
      $._property_drawer_begin,
      repeat(choice($.node_property, $.blank_line)),
      $._drawer_end,
    ),
    _property_drawer_begin: $ => literalLine($, /[ \t]*:[Pp][Rr][Oo][Pp][Ee][Rr][Tt][Ii][Ee][Ss]:[ \t]*/, 35),
    node_property: $ => literalLine($, /[ \t]*:[A-Za-z_][A-Za-z0-9_-]*\+?:[ \t]*[^\r\n]*/, 25),

    footnote_definition: $ => seq(
      $._footnote_definition_line,
      repeat($._indented_continuation),
    ),
    _footnote_definition_line: $ => literalLine($, /\[fn:[A-Za-z0-9_-]+\][ \t]*[^\r\n]*/, 40),

    inline_task: $ => $._inline_task_begin,
    _inline_task_begin: $ => literalLine($, /\*{15,}[ \t]+[^\r\n]*/, 35),
    _inline_task_end: $ => literalLine($, /\*{15,}[ \t]+[Ee][Nn][Dd][ \t]*/, 36),

    plain_list: $ => prec.right(repeat1($.list_item)),
    list_item: $ => $._list_item_line,
    _list_item_line: $ => literalLine($, /[ \t]*(?:[-+*]|(?:[0-9]+|[A-Za-z])[.)])[ \t]+[^\r\n]*/, 25),
    _indented_continuation: $ => literalLine($, /[ \t]+[^\r\n]+/, 12),

    pipe_table: $ => prec.right(repeat1(choice($.table_separator_row, $.table_row))),
    table_row: $ => prec.right(seq(
      optional(token(/[ \t]+/)),
      '|',
      repeat1($.table_cell),
      optional($.line_ending),
    )),
    table_separator_row: $ => literalLine($, /[ \t]*\|[-+|: \t]*[-+][-+|: \t]*\|?[ \t]*/, 30),
    table_cell: $ => seq(
      optional(alias(token(prec(-5, /[^|\r\n]+/)), $.plain_text)),
      '|',
    ),

    table_provider_form: $ => seq(
      $._begin_table_provider,
      repeat($._verbatim_line),
      $._end_table_provider,
    ),
    _begin_table_provider: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[Tt][Aa][Bb][Ll][Ee](?:[ \t]+[^\r\n]*)?/, 32),
    _end_table_provider: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[Tt][Aa][Bb][Ll][Ee][ \t]*/, 32),

    source_block: $ => seq($._begin_source, repeat($._verbatim_line), $._end_source),
    _begin_source: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[Ss][Rr][Cc](?:[ \t]+[^\r\n]*)?/, 35),
    _end_source: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[Ss][Rr][Cc][ \t]*/, 35),

    example_block: $ => seq($._begin_example, repeat($._verbatim_line), $._end_example),
    _begin_example: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[Ee][Xx][Aa][Mm][Pp][Ll][Ee](?:[ \t]+[^\r\n]*)?/, 35),
    _end_example: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[Ee][Xx][Aa][Mm][Pp][Ll][Ee][ \t]*/, 35),

    export_block: $ => seq($._begin_export, repeat($._verbatim_line), $._end_export),
    _begin_export: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[Ee][Xx][Pp][Oo][Rr][Tt](?:[ \t]+[^\r\n]*)?/, 35),
    _end_export: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[Ee][Xx][Pp][Oo][Rr][Tt][ \t]*/, 35),

    comment_block: $ => seq($._begin_comment, repeat($._verbatim_line), $._end_comment),
    _begin_comment: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_[Cc][Oo][Mm][Mm][Ee][Nn][Tt](?:[ \t]+[^\r\n]*)?/, 35),
    _end_comment: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_[Cc][Oo][Mm][Mm][Ee][Nn][Tt][ \t]*/, 35),

    lesser_block: $ => seq(
      field('begin', $._begin_lesser),
      repeat($._verbatim_line),
      field('end', $._end_lesser),
    ),
    _begin_lesser: $ => literalLine($, /[ \t]*#\+[Bb][Ee][Gg][Ii][Nn]_(?:[Vv][Ee][Rr][Ss][Ee]|[Aa][Ss][Cc][Ii][Ii]|[Hh][Tt][Mm][Ll]|[Ll][Aa][Tt][Ee][Xx])(?:[ \t]+[^\r\n]*)?/, 34),
    _end_lesser: $ => literalLine($, /[ \t]*#\+[Ee][Nn][Dd]_(?:[Vv][Ee][Rr][Ss][Ee]|[Aa][Ss][Cc][Ii][Ii]|[Hh][Tt][Mm][Ll]|[Ll][Aa][Tt][Ee][Xx])[ \t]*/, 34),

    clock: $ => literalLine($, /[ \t]*[Cc][Ll][Oo][Cc][Kk]:[ \t]+[^\r\n]+/, 25),
    diary_expression: $ => literalLine($, /%%\([^\r\n]*\)/, 25),
    planning_line: $ => literalLine($, /[ \t]*(?:(?:[Ss][Cc][Hh][Ee][Dd][Uu][Ll][Ee][Dd])|(?:[Dd][Ee][Aa][Dd][Ll][Ii][Nn][Ee])|(?:[Cc][Ll][Oo][Ss][Ee][Dd])):[ \t]+[^\r\n]+/, 25),
    line_comment: $ => literalLine($, /[ \t]*#[ \t][^\r\n]*/, 24),
    fixed_width_area: $ => prec.right(repeat1($._fixed_width_line)),
    _fixed_width_line: $ => literalLine($, /[ \t]*:[ \t][^\r\n]*/, 23),
    horizontal_rule: $ => literalLine($, /[ \t]*-----+[- \t]*/, 24),

    affiliated_keyword: $ => literalLine($, /[ \t]*#\+(?:[Cc][Aa][Pp][Tt][Ii][Oo][Nn]|[Nn][Aa][Mm][Ee]|[Hh][Ee][Aa][Dd][Ee][Rr]|[Rr][Ee][Ss][Uu][Ll][Tt][Ss]|[Pp][Ll][Oo][Tt]|[Aa][Tt][Tt][Rr]_[A-Za-z0-9_-]+):[ \t]*[^\r\n]*/, 25),
    keyword: $ => literalLine($, /[ \t]*#\+[A-Za-z][A-Za-z0-9_-]*\+?:[ \t]*[^\r\n]*/, 20),

    latex_environment: $ => seq(
      $._latex_begin,
      repeat($._verbatim_line),
      $._latex_end,
    ),
    _latex_begin: $ => literalLine($, /[ \t]*\\begin\{[A-Za-z*]+\}[ \t]*/, 25),
    _latex_end: $ => literalLine($, /[ \t]*\\end\{[A-Za-z*]+\}[ \t]*/, 25),

    paragraph: $ => prec.right(repeat1($.inline_line)),
    inline_line: $ => prec.right(seq(
      repeat1($._standard_object),
      choice($.line_ending, $._end_of_file),
    )),

    _standard_object: $ => choice(
      $.timestamp_range,
      $.diary_timestamp,
      $.repeating_timestamp,
      $.delayed_timestamp,
      $.point_timestamp,
      $.export_snippet,
      $.inline_footnote_reference,
      $.anonymous_footnote_reference,
      $.named_footnote_reference,
      $.citation,
      $.inline_call,
      $.inline_source,
      $.explicit_line_break,
      $.radio_target,
      $.target,
      $.regular_link,
      $.angle_link,
      $.plain_link,
      $.macro,
      $.percentage_cookie,
      $.fraction_cookie,
      $.latex_fragment,
      $.entity,
      $.special_symbol,
      $.bold_markup,
      $.italic_markup,
      $.underline_markup,
      $.verbatim_markup,
      $.code_markup,
      $.strike_through_markup,
      $.subscript,
      $.superscript,
      $.plain_text,
    ),

    entity: _ => token(prec(30, /\\[A-Za-z][A-Za-z0-9]*(?:\{\})?/)),
    special_symbol: _ => token(prec(20, /(?:---|--|\.\.\.)/)),
    latex_fragment: _ => token(prec(31, /(?:\$[^$\r\n]+\$|\\\([^\r\n]+\\\)|\\\[[^\r\n]+\\\])/)),
    export_snippet: _ => token(prec(35, /@@[A-Za-z0-9_-]+:[^@\r\n]*@@/)),
    named_footnote_reference: _ => token(prec(35, /\[fn:[A-Za-z0-9_-]+\]/)),
    inline_footnote_reference: _ => token(prec(37, /\[fn:[A-Za-z0-9_-]+:[^\]\r\n]+\]/)),
    anonymous_footnote_reference: _ => token(prec(38, /\[fn::[^\]\r\n]+\]/)),

    citation: $ => seq(
      token(prec(40, /\[cite(?:\/[A-Za-z0-9_-]+)?(?::[A-Za-z0-9_-]+)?/)),
      repeat(choice($.citation_reference, $._citation_text)),
      ']',
    ),
    citation_reference: _ => token(prec(30, /@[A-Za-z0-9][A-Za-z0-9_:.+-]*/)),
    _citation_text: _ => token(prec(-20, /[^@\]\r\n]+|./)),

    inline_call: _ => token(prec(35, /call_[A-Za-z0-9_-]+(?:\[[^\]\r\n]*\])?\([^\)\r\n]*\)(?:\[[^\]\r\n]*\])?/)),
    inline_source: _ => token(prec(35, /src_[A-Za-z0-9_-]+(?:\[[^\]\r\n]*\])?\{[^\}\r\n]*\}/)),
    explicit_line_break: _ => token(prec(40, /\\\\[ \t]*/)),

    plain_link: _ => token(prec(25, /[A-Za-z][A-Za-z0-9+.-]*:[^ \t\r\n<>\[\]]+/)),
    angle_link: _ => token(prec(35, /<[A-Za-z][A-Za-z0-9+.-]*:[^>\r\n]+>/)),
    regular_link: _ => token(prec(40, /\[\[[^\]\r\n]+\](?:\[[^\]\r\n]*\])?\]/)),
    macro: _ => token(prec(35, /\{\{\{[A-Za-z][A-Za-z0-9_-]*(?:\([^\)\r\n]*\))?\}\}\}/)),
    target: _ => token(prec(35, /<<[^<>\r\n]+>>/)),
    radio_target: _ => token(prec(40, /<<<[^<>\r\n]+>>>/)),
    percentage_cookie: _ => token(prec(30, /\[[0-9]{1,3}%\]/)),
    fraction_cookie: _ => token(prec(30, /\[[0-9]+\/[0-9]+\]/)),
    subscript: _ => token(prec(15, /_(?:[A-Za-z0-9+-]+|\{[^\}\r\n]+\})/)),
    superscript: _ => token(prec(15, /\^(?:[A-Za-z0-9+-]+|\{[^\}\r\n]+\})/)),

    point_timestamp: $ => choice($.active_timestamp, $.inactive_timestamp),
    active_timestamp: _ => token(prec(30, /<[0-9]{4}-[0-9]{2}-[0-9]{2}[^>\r\n]*>/)),
    inactive_timestamp: _ => token(prec(30, /\[[0-9]{4}-[0-9]{2}-[0-9]{2}[^\]\r\n]*\]/)),
    diary_timestamp: _ => token(prec(40, /<%%\([^>\r\n]*\)(?:[ \t]+[^>\r\n]*)?>/)),
    timestamp_range: _ => token(prec(45, /(?:<[0-9]{4}-[0-9]{2}-[0-9]{2}[^>\r\n]*>|\[[0-9]{4}-[0-9]{2}-[0-9]{2}[^\]\r\n]*\])--(?:<[0-9]{4}-[0-9]{2}-[0-9]{2}[^>\r\n]*>|\[[0-9]{4}-[0-9]{2}-[0-9]{2}[^\]\r\n]*\])/)),
    repeating_timestamp: _ => token(prec(42, /<[0-9]{4}-[0-9]{2}-[0-9]{2}[^>\r\n]*\+[0-9]+[hdwmy][^>\r\n]*>/)),
    delayed_timestamp: _ => token(prec(42, /<[0-9]{4}-[0-9]{2}-[0-9]{2}[^>\r\n]*-[0-9]+[hdwmy][^>\r\n]*>/)),

    bold_markup: _ => token(prec(25, /\*[^*\r\n]+\*/)),
    italic_markup: _ => token(prec(25, /\/[^\/\r\n]+\//)),
    underline_markup: _ => token(prec(25, /_[^_\r\n]+_/)),
    verbatim_markup: _ => token(prec(25, /=[^=\r\n]+=/)),
    code_markup: _ => token(prec(25, /~[^~\r\n]+~/)),
    strike_through_markup: _ => token(prec(25, /\+[^+\r\n]+\+/)),
    plain_text: _ => token(prec(-100, /[^\\@$\[\]\{\}<>*\/_=~+^|\-\r\n]+|[^\r\n]/)),

    _verbatim_line: $ => literalLine($, /[^\r\n]+/, -20),

    recovery: $ => literalLine($, /[ \t]*(?:#\+(?:[Bb][Ee][Gg][Ii][Nn]|[Ee][Nn][Dd])[_:]?[^\r\n]*|:[A-Za-z0-9_@#%+-]*[^:\r\n][^\r\n]*)/, 5),

    _block_element: $ => choice($._section_element, $.heading_line),
    _drawer_element: $ => choice(
      $.blank_line,
      $.fixed_width_area,
      $.line_comment,
      $.keyword,
      $.paragraph,
      $.recovery,
    ),
  },
});
