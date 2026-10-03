// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "base:runtime"
import "core:testing"

import "../editor"

/* Verifies Jan projects representative structural syntax into copied records. */
@(test)
jan_structural_analysis_projects_owned_nodes :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string(
		"#+title: Demo\r\n" +
		"* TODO Parent :tag:\n" +
		":PROPERTIES:\n" +
		":ID: alpha\n" +
		":END:\n" +
		"SCHEDULED: <2026-09-10>\n" +
		"- [ ] item\n" +
		"| a | b |\n" +
		"|---+---|\n" +
		"#+begin_src odin\n" +
		"main :: proc() {}\n" +
		"#+end_src\n",
	))
	analysis, analyzed, failure := jan_structural_owner_analyze(&owner, source, jan_structural_test_scope())
	testing.expect(t, analyzed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.None)
	defer jan_structural_analysis_close(&analysis)
	nodes := jan_structural_analysis_nodes(&analysis)
	testing.expect(t, len(nodes) > 0)
	testing.expect_value(t, nodes[0].kind, Jan_Node_Kind.Document_Root)
	testing.expect_value(t, nodes[0].range.start, editor.Byte_Offset(0))
	testing.expect_value(t, nodes[0].range.end, editor.Byte_Offset(len(source)))
	required_kinds := []Jan_Node_Kind{
		Jan_Node_Kind.Zeroth_Section, Jan_Node_Kind.Keyword, Jan_Node_Kind.Heading,
		Jan_Node_Kind.Section, Jan_Node_Kind.Property_Drawer,
		Jan_Node_Kind.Node_Property, Jan_Node_Kind.Planning_Line,
		Jan_Node_Kind.Plain_List, Jan_Node_Kind.List_Item, Jan_Node_Kind.Pipe_Table,
		Jan_Node_Kind.Table_Row, Jan_Node_Kind.Table_Separator_Row,
		Jan_Node_Kind.Source_Block, Jan_Node_Kind.Preserved_Whitespace,
	}
	for kind in required_kinds {
		testing.expect(t, jan_structural_test_contains_kind(nodes, kind))
	}
	for node in nodes do testing.expect(t, jan_node_record_is_valid(node, u64(len(source))))
	attributes := jan_structural_analysis_attributes(&analysis)
	testing.expect(t, len(attributes) >= 6)
	for attribute in attributes do testing.expect(t, jan_attribute_record_is_valid(attribute, u64(len(source))))
	usage, inspected := jan_structural_analysis_usage(&analysis)
	testing.expect(t, inspected)
	testing.expect_value(t, usage.source_bytes, u64(len(source)))
	testing.expect_value(t, usage.nodes, u32(len(nodes)))
}

/* Verifies confirmed syntax configuration controls copied inline classification. */
@(test)
jan_structural_analysis_classifies_configured_syntax :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	configuration := jan_factory_configuration(1)
	testing.expect(t, jan_configuration_list_clear(&configuration.task_keywords))
	testing.expect(t, jan_configuration_list_append(&configuration.task_keywords, "READY"))
	testing.expect(t, jan_configuration_list_append(&configuration.task_keywords, "DONE"))
	testing.expect(t, jan_configuration_list_append(&configuration.block_names, "custom"))
	testing.expect(t, jan_configuration_confirm(&configuration, 2))
	source := transmute([]u8)(string(
		"#+options: toc:nil\n" +
		"#+match_regexp: ^[A-Z]+$\n" +
		"* READY [#A] Work :Tag:local:\n" +
		":PROPERTIES:\n" +
		":Owner: Ada\n" +
		":END:\n" +
		"Entity \\alpha and registered https://example.test.\n" +
		"Markup *valid* and word/invalid/word.\n" +
		"<<<focus>>>\n" +
		"Return to focus.\n" +
		"#+begin_custom\n" +
		"body\n" +
		"#+end_custom\n",
	))
	scope := jan_structural_test_scope()
	scope.configuration = configuration.identity
	scope.analysis_generation = 23
	analysis, analyzed, failure := jan_structural_owner_analyze_configured(
		&owner,
		source,
		scope,
		configuration,
	)
	testing.expect(t, analyzed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.None)
	defer jan_structural_analysis_close(&analysis)
	nodes := jan_structural_analysis_nodes(&analysis)
	attributes := jan_structural_analysis_attributes(&analysis)
	required_inline_kinds := [6]Jan_Node_Kind{
		.Entity, .Plain_Link, .Radio_Target, .Radio_Link, .Bold_Markup, .Italic_Markup,
	}
	for kind in required_inline_kinds {
		testing.expect(t, jan_structural_test_contains_kind(nodes, kind))
	}
	testing.expect(t, jan_structural_test_has_attribute(attributes, "task-state", "READY"))
	testing.expect(t, jan_structural_test_has_attribute(attributes, "priority", "A"))
	testing.expect(t, jan_structural_test_has_attribute(attributes, "tag", "Tag"))
	testing.expect(t, jan_structural_test_has_attribute(attributes, "configured", "true"))
	testing.expect(t, jan_structural_test_has_attribute(attributes, "registered", "true"))
	testing.expect(t, jan_structural_test_has_attribute(attributes, "regular-expression-dialect", "org-compatible"))
	testing.expect(t, jan_structural_test_has_attribute(attributes, "boundary-valid", "false"))
	testing.expect(t, jan_structural_test_has_attribute(attributes, "file-local-setting", "true"))

	_, default_ok, default_failure := jan_structural_owner_analyze(
		&owner,
		source,
		scope,
	)
	testing.expect(t, !default_ok)
	testing.expect_value(t, default_failure.code, Jan_Failure_Code.Invalid_Configuration)
}

/* Verifies every Stage 1 index family is derived from the exact copied tree. */
@(test)
jan_structural_analysis_indexes_document_facts :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string(
		"#+bibliography: references.bib\n" +
		"#+options: toc:nil\n" +
		"* TODO [#A] Indexed :tag:\n" +
		":PROPERTIES:\n" +
		":ID: alpha\n" +
		":END:\n" +
		"SCHEDULED: <2026-09-10 Wed>\n" +
		"CLOCK: [2026-09-10 Wed]\n" +
		"[fn:note] definition\n" +
		"#+name: sample\n" +
		"| a | b |\n" +
		"#+tblfm: $1=$2\n" +
		"#+results: sample\n" +
		"#+call: total()\n" +
		"<<target>> <<<focus>>> focus https://example.test [cite:@doe]\n" +
		"<2026-09-11>\n" +
		"call_total(1)\n" +
		"word/invalid/word\n" +
		"#+begin_src odin\n" +
		"value := 1\n" +
		"#+end_src\n" +
		"#+begin_unterminated\n" +
		"body\n",
	))
	analysis, analyzed, failure := jan_structural_owner_analyze(
		&owner,
		source,
		jan_structural_test_scope(),
	)
	testing.expect(t, analyzed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.None)
	defer jan_structural_analysis_close(&analysis)
	facts := jan_structural_analysis_indexes(&analysis)
	required := [26]Jan_Index_Kind{
		.Heading, .Task_State, .Priority, .Tag, .Property, .Identifier, .Name,
		.Target, .Radio_Target, .Link, .Timestamp, .Planning, .Clock, .Footnote,
		.Citation, .Bibliography, .Table, .Formula, .Block, .Call, .Result,
		.Code_Reference, .Affiliated_Keyword, .File_Local_Setting, .Lint_Fact,
		.Recovery_Region,
	}
	for kind in required do testing.expect(t, jan_structural_test_contains_index(facts, kind))
	for fact in facts do testing.expect(t, jan_index_fact_is_valid(fact, u64(len(source))))
	usage, inspected := jan_structural_analysis_usage(&analysis)
	testing.expect(t, inspected)
	testing.expect_value(t, usage.index_facts, u32(len(facts)))

	limits := DEFAULT_JAN_RESOURCE_LIMITS
	limits.index_facts = 1
	_, limited, limited_failure := jan_structural_owner_analyze(
		&owner,
		source,
		jan_structural_test_scope(),
		limits,
	)
	testing.expect(t, !limited)
	testing.expect_value(t, limited_failure.code, Jan_Failure_Code.Limited)
}

/* Verifies inline normalization is deterministic across context and malformed input. */
@(test)
jan_structural_analysis_normalizes_inline_contexts :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string(
		"Unicode λ and \\alpha with $x+y$.\n" +
		"[cite:@doe] call_total(1) src_odin{value}\\\\\n" +
		"[[target][description]] <https://example.test>\n" +
		"<<<focus>>>\n" +
		"focus and \\focus\n" +
		"<2026-09-10>--<2026-09-11>\n" +
		"word/invalid/word and *valid*\n",
	))
	scope := jan_structural_test_scope()
	first, first_ok, _ := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, first_ok)
	defer jan_structural_analysis_close(&first)
	second, second_ok, _ := jan_structural_owner_analyze(&owner, source, scope)
	testing.expect(t, second_ok)
	defer jan_structural_analysis_close(&second)
	first_nodes := jan_structural_analysis_nodes(&first)
	second_nodes := jan_structural_analysis_nodes(&second)
	testing.expect(t, jan_structural_test_nodes_equivalent(first_nodes, second_nodes))
	testing.expect_value(t, jan_structural_test_count_kind(first_nodes, .Radio_Link), 1)
	testing.expect(t, jan_structural_test_contains_kind(first_nodes, .Timestamp_Range))
	testing.expect(t, jan_structural_test_contains_kind(first_nodes, .Citation_Reference))
	for node in first_nodes do testing.expect(t, jan_node_record_is_valid(node, u64(len(source))))

	malformed_source := transmute([]u8)(string("[cite:@missing\n"))
	malformed, malformed_ok, _ := jan_structural_owner_analyze(
		&owner,
		malformed_source,
		scope,
	)
	testing.expect(t, malformed_ok)
	defer jan_structural_analysis_close(&malformed)
	malformed_nodes := jan_structural_analysis_nodes(&malformed)
	testing.expect(t, jan_structural_test_contains_kind(malformed_nodes, .Citation))
	testing.expect(t, len(jan_structural_analysis_recoveries(&malformed)) > 0)
}

/* Verifies heading levels become a deterministic parent forest with owned subtrees. */
@(test)
jan_structural_analysis_projects_heading_forest :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string("* A\n** B\n*** C\n** D\n* E\n"))
	analysis, analyzed, _ := jan_structural_owner_analyze(&owner, source, jan_structural_test_scope())
	testing.expect(t, analyzed)
	defer jan_structural_analysis_close(&analysis)
	headings: [5]Jan_Node_Record
	count: int
	for node in jan_structural_analysis_nodes(&analysis) {
		if node.kind == .Heading {
			headings[count] = node
			count += 1
		}
	}
	testing.expect_value(t, count, 5)
	testing.expect_value(t, headings[0].structural_depth, u16(1))
	testing.expect_value(t, headings[1].structural_depth, u16(2))
	testing.expect_value(t, headings[2].structural_depth, u16(3))
	testing.expect_value(t, headings[3].parent_id, headings[0].id)
	testing.expect_value(t, headings[4].parent_id, Jan_Node_ID(1))
	testing.expect_value(t, headings[0].range.end, headings[4].range.start)
	testing.expect_value(t, headings[4].range.end, editor.Byte_Offset(len(source)))
}

/* Verifies malformed delimiters remain source-owned recovery rather than parser failure. */
@(test)
jan_structural_analysis_contains_malformed_source :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string("#+begin_unterminated\nbody\n"))
	analysis, analyzed, _ := jan_structural_owner_analyze(&owner, source, jan_structural_test_scope())
	testing.expect(t, analyzed)
	defer jan_structural_analysis_close(&analysis)
	recoveries := jan_structural_analysis_recoveries(&analysis)
	testing.expect(t, len(recoveries) > 0)
	for recovery in recoveries do testing.expect(t, jan_recovery_record_is_valid(recovery, u64(len(source))))
}

/* Verifies heading-local planning syntax is not admitted in the zeroth section. */
@(test)
jan_structural_analysis_enforces_planning_context :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	outside := transmute([]u8)(string("SCHEDULED: <2026-09-10>\n"))
	outside_analysis, outside_ok, _ := jan_structural_owner_analyze(
		&owner,
		outside,
		jan_structural_test_scope(),
	)
	testing.expect(t, outside_ok)
	testing.expect(
		t,
		!jan_structural_test_contains_kind(
			jan_structural_analysis_nodes(&outside_analysis),
			.Planning_Line,
		),
	)
	jan_structural_analysis_close(&outside_analysis)

	inside := transmute([]u8)(string("* Heading\nSCHEDULED: <2026-09-10>\n"))
	inside_analysis, inside_ok, _ := jan_structural_owner_analyze(
		&owner,
		inside,
		jan_structural_test_scope(),
	)
	testing.expect(t, inside_ok)
	defer jan_structural_analysis_close(&inside_analysis)
	testing.expect(
		t,
		jan_structural_test_contains_kind(
			jan_structural_analysis_nodes(&inside_analysis),
			.Planning_Line,
		),
	)
}

/* Verifies source, node, cancellation, UTF-8, and allocation failures are contained. */
@(test)
jan_structural_analysis_contains_limits_and_faults :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 13)
	testing.expect(t, initialized)
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string("* Heading\nBody\n"))

	limits := DEFAULT_JAN_RESOURCE_LIMITS
	limits.nodes = 1
	_, analyzed, failure := jan_structural_owner_analyze(&owner, source, jan_structural_test_scope(), limits)
	testing.expect(t, !analyzed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Limited)

	testing.expect(t, jan_structural_owner_request_cancel(&owner))
	_, analyzed, failure = jan_structural_owner_analyze(&owner, source, jan_structural_test_scope())
	testing.expect(t, !analyzed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Cancelled)
	testing.expect(t, jan_structural_owner_clear_cancel(&owner))

	invalid_utf8 := []u8{0xff, '\n'}
	_, analyzed, failure = jan_structural_owner_analyze(&owner, invalid_utf8, jan_structural_test_scope())
	testing.expect(t, !analyzed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Malformed)

	failing := Jan_Structural_Failing_Allocator{backing = context.allocator}
	_, analyzed, failure = jan_structural_owner_analyze(
		&owner,
		source,
		jan_structural_test_scope(),
		DEFAULT_JAN_RESOURCE_LIMITS,
		jan_structural_failing_allocator(&failing),
	)
	testing.expect(t, !analyzed)
	testing.expect_value(t, failure.code, Jan_Failure_Code.Allocation_Failed)
}

/* Verifies line definitions outrank inline references while embedded references remain inline. */
@(test)
jan_structural_analysis_distinguishes_footnote_definitions :: proc(t: ^testing.T) {
	owner: Jan_Structural_Owner
	initialized, _ := jan_structural_owner_init(&owner, 34)
	testing.expect(t, initialized)
	if !initialized do return
	defer jan_structural_owner_close(&owner)
	source := transmute([]u8)(string(
		"See [fn:note].\n\n" +
		"[fn:note] Definition\n\n" +
		"[fn:other] Other\n",
	))
	scope := jan_structural_test_scope()
	scope.parser_generation = 34
	analysis, analyzed, failure := jan_structural_owner_analyze(&owner, source, scope)
	testing.expectf(t, analyzed, "footnote analysis failed with %v", failure.code)
	if !analyzed do return
	defer jan_structural_analysis_close(&analysis)
	nodes := jan_structural_analysis_nodes(&analysis)
	testing.expect_value(t, jan_structural_test_count_kind(nodes, .Footnote_Definition), 2)
	testing.expect_value(t, jan_structural_test_count_kind(nodes, .Named_Footnote_Reference), 1)
}

@(private = "file")
jan_structural_test_scope :: proc() -> Jan_Analysis_Scope {
	language_name: Language_Name
	language_name.length = u16(copy(language_name.bytes[:], "jan"))
	configuration := jan_factory_configuration(1).identity
	return {
		buffer_id = 3,
		document_id = 5,
		has_document = true,
		source_revision = 7,
		language = {id = 2, generation = 1, name = language_name},
		provider = {registry_id = 2, language_id = 2, provider_id = 1, provider_generation = 1},
		selection_generation = 11,
		parser_generation = 13,
		grammar_generation = 17,
		configuration = configuration,
		baseline = jan_factory_baseline(),
		analysis_generation = 19,
	}
}

@(private = "file")
jan_structural_test_contains_kind :: proc(nodes: []Jan_Node_Record, kind: Jan_Node_Kind) -> bool {
	for node in nodes do if node.kind == kind do return true
	return false
}

@(private = "file")
jan_structural_test_has_attribute :: proc(
	attributes: []Jan_Attribute_Record,
	name, value: string,
) -> bool {
	for attribute in attributes {
		if jan_bounded_text_matches(attribute.name.bytes, attribute.name.length, name) &&
		   jan_bounded_text_matches(attribute.value.bytes, attribute.value.length, value) {
			return true
		}
	}
	return false
}

@(private = "file")
jan_structural_test_contains_index :: proc(
	facts: []Jan_Index_Fact,
	kind: Jan_Index_Kind,
) -> bool {
	for fact in facts do if fact.kind == kind do return true
	return false
}

@(private = "file")
jan_structural_test_count_kind :: proc(nodes: []Jan_Node_Record, kind: Jan_Node_Kind) -> int {
	count: int
	for node in nodes do if node.kind == kind do count += 1
	return count
}

@(private = "file")
jan_structural_test_nodes_equivalent :: proc(
	left, right: []Jan_Node_Record,
) -> bool {
	if len(left) != len(right) do return false
	for node, index in left {
		other := right[index]
		if node.id != other.id || node.parent_id != other.parent_id ||
		   node.layer != other.layer || node.kind != other.kind ||
		   node.kind_text != other.kind_text ||
		   node.structural_depth != other.structural_depth ||
		   node.inline_depth != other.inline_depth ||
		   node.range != other.range || node.attribute_count != other.attribute_count {
			return false
		}
	}
	return true
}

@(private = "file")
Jan_Structural_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private = "file")
jan_structural_failing_allocator :: proc(data: ^Jan_Structural_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = jan_structural_failing_allocator_proc, data = data}
}

@(private = "file")
jan_structural_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	allocator := cast(^Jan_Structural_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after do return nil, .Out_Of_Memory
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
