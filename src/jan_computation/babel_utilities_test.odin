// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:testing"

@(test)
/* Verifies source blocks, adjacent results, names, and hashes are resolved without adapters. */
babel_utilities_inspect_source_and_results :: proc(t: ^testing.T) {
	source := "#+name: first\n#+begin_src racket :results value\n(displayln 1)\n#+end_src\n\n#+RESULTS: first\n: 1\n"
	point := len("#+name: first\n#+begin_src racket :results value\n")
	block, found, failure := babel_source_block_at(source, point)
	testing.expect(t, found)
	testing.expect_value(t, failure, Babel_Utility_Failure.None)
	testing.expect_value(t, source[block.language_start:block.language_end], "racket")
	testing.expect_value(t, source[block.body_start:block.body_end], "(displayln 1)\n")
	result, result_found := babel_result_after_block(source, block)
	testing.expect(t, result_found)
	testing.expect_value(t, source[result:result + len("#+RESULTS:")], "#+RESULTS:")
	named_source, named_source_found := babel_named_source_at(source, 0)
	testing.expect(t, named_source_found)
	testing.expect_value(t, source[named_source.name_start:named_source.name_end], "first")
	named_result, named_result_found := babel_named_result_at(source, 0)
	testing.expect(t, named_result_found)
	testing.expect_value(t, source[named_result.name_start:named_result.name_end], "first")
	first_hash, hashed := babel_source_hash(source, block)
	second_hash, second_hashed := babel_source_hash(source, block)
	testing.expect(t, hashed && second_hashed)
	testing.expect(t, first_hash != 0)
	testing.expect_value(t, first_hash, second_hash)
}

@(test)
/* Verifies demarcation and explicit header insertion reject ambiguous mutations. */
babel_utilities_prepare_checked_edits :: proc(t: ^testing.T) {
	source := "#+begin_src odin :results output\nfirst()\nsecond()\n#+end_src\n"
	point := len("#+begin_src odin :results output\nfirst()\n")
	block, found, _ := babel_source_block_at(source, point)
	testing.expect(t, found)
	storage: [128]u8
	split, split_ok, split_failure := babel_demarcation_text(source, block, point, storage[:])
	testing.expect(t, split_ok)
	testing.expect_value(t, split_failure, Babel_Utility_Failure.None)
	testing.expect_value(t, split, "#+end_src\n#+begin_src odin :results output\n")
	_, midline_ok, midline_failure := babel_demarcation_text(source, block, point + 2, storage[:])
	testing.expect(t, !midline_ok)
	testing.expect_value(t, midline_failure, Babel_Utility_Failure.Invalid_Point)
	argument, argument_ok, _ := babel_header_argument_insertion(":cache yes", storage[:])
	testing.expect(t, argument_ok)
	testing.expect_value(t, argument, " :cache yes")
	_, invalid_ok, invalid_failure := babel_header_argument_insertion("cache yes", storage[:])
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure, Babel_Utility_Failure.Invalid_Argument)
}

@(test)
/* Verifies malformed or unrelated text cannot be treated as executable source. */
babel_utilities_reject_malformed_source :: proc(t: ^testing.T) {
	_, found, failure := babel_source_block_at("#+begin_src racket\n1\n", 20)
	testing.expect(t, !found)
	testing.expect_value(t, failure, Babel_Utility_Failure.Malformed_Source)
	_, found, failure = babel_source_block_at("plain text\n", 2)
	testing.expect(t, !found)
	testing.expect_value(t, failure, Babel_Utility_Failure.No_Source_Block)
}
