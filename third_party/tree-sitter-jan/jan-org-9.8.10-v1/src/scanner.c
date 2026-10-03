#include "tree_sitter/parser.h"

#include <stdbool.h>
#include <stddef.h>

enum TokenType {
  BLANK_LINE,
  LINE_ENDING,
  END_OF_FILE,
};

static void advance(TSLexer *lexer) { lexer->advance(lexer, false); }

static void skip(TSLexer *lexer) { lexer->advance(lexer, true); }

static bool scan_line_ending(TSLexer *lexer, enum TokenType symbol) {
  if (lexer->lookahead == '\r') {
    advance(lexer);
    if (lexer->lookahead == '\n') advance(lexer);
  } else if (lexer->lookahead == '\n') {
    advance(lexer);
  } else {
    return false;
  }
  lexer->mark_end(lexer);
  lexer->result_symbol = symbol;
  return true;
}

void *tree_sitter_jan_external_scanner_create(void) { return NULL; }

void tree_sitter_jan_external_scanner_destroy(void *payload) { (void)payload; }

unsigned tree_sitter_jan_external_scanner_serialize(void *payload, char *buffer) {
  (void)payload;
  (void)buffer;
  return 0;
}

void tree_sitter_jan_external_scanner_deserialize(
    void *payload, const char *buffer, unsigned length) {
  (void)payload;
  (void)buffer;
  (void)length;
}

bool tree_sitter_jan_external_scanner_scan(
    void *payload, TSLexer *lexer, const bool *valid_symbols) {
  (void)payload;
  if (valid_symbols[LINE_ENDING]) {
    return scan_line_ending(lexer, LINE_ENDING);
  }
  if (valid_symbols[END_OF_FILE] && lexer->lookahead == 0) {
    lexer->mark_end(lexer);
    lexer->result_symbol = END_OF_FILE;
    return true;
  }
  if (valid_symbols[BLANK_LINE]) {
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') skip(lexer);
    if (scan_line_ending(lexer, BLANK_LINE)) return true;
    return false;
  }
  return false;
}
