// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package indentation owns bounded indentation configuration and resolution.
package indentation

/* MAX_WIDTH bounds logical indentation and literal-tab display widths. */
MAX_WIDTH :: u16(64)
/* MAX_RULES bounds one confirmed indentation configuration generation. */
MAX_RULES :: 128
/* MAX_MATCHER_BYTES bounds copied Project, language, and filename matchers. */
MAX_MATCHER_BYTES :: 128

/* DEFAULT_INDENT_WIDTH is the initial logical indentation width. */
DEFAULT_INDENT_WIDTH :: u16(4)
/* DEFAULT_DISPLAY_TAB_WIDTH is the initial literal-tab display width. */
DEFAULT_DISPLAY_TAB_WIDTH :: u16(4)

/* Generation identifies one complete confirmed indentation configuration. */
Generation :: distinct u64
/* Profile_ID isolates configuration belonging to one interaction profile. */
Profile_ID :: distinct u64

/* Representation selects the bytes inserted for one indentation unit. */
Representation :: enum u8 {
	Invalid,
	Tabs,
	Spaces,
}

/* Scope defines deterministic indentation-policy precedence. */
Scope :: enum u8 {
	Invalid,
	Factory,
	User_Global,
	Project,
	File_Type,
	Language,
	Buffer_Local,
}

/* Matcher_Kind identifies the bounded evidence required by one scoped rule. */
Matcher_Kind :: enum u8 {
	Invalid,
	None,
	Project,
	Exact_Filename,
	Filename_Suffix,
	Language,
	Buffer,
}

/* Policy contains independent indentation and display values. */
Policy :: struct {
	representation:    Representation,
	indent_width:      u16,
	display_tab_width: u16,
}

/* DEFAULT_POLICY is the factory indentation policy. */
DEFAULT_POLICY :: Policy {
	representation = .Spaces,
	indent_width = DEFAULT_INDENT_WIDTH,
	display_tab_width = DEFAULT_DISPLAY_TAB_WIDTH,
}

/* Matcher_Text owns one bounded copied matcher. */
Matcher_Text :: struct {
	bytes:  [MAX_MATCHER_BYTES]u8,
	length: u16,
}

/* Rule_Candidate is borrowed only while replacing one complete generation. */
Rule_Candidate :: struct {
	profile_id:        Profile_ID,
	scope:             Scope,
	matcher_kind:      Matcher_Kind,
	matcher:           string,
	buffer_id:         u64,
	policy:            Policy,
	source_generation: u64,
}

/* Rule is one copied confirmed scoped policy. */
Rule :: struct {
	profile_id:        Profile_ID,
	scope:             Scope,
	matcher_kind:      Matcher_Kind,
	matcher:           Matcher_Text,
	buffer_id:         u64,
	policy:            Policy,
	source_generation: u64,
}

/* Replacement proposes one complete atomic configuration generation. */
Replacement :: struct {
	expected_generation:       Generation,
	proposed_generation:       Generation,
	factory_policy:            Policy,
	factory_source_generation: u64,
	rules:                     []Rule_Candidate,
}

/* Resolution_Context supplies copied semantic evidence without package coupling. */
Resolution_Context :: struct {
	profile_id: Profile_ID,
	buffer_id:  u64,
	project:    string,
	language:   string,
	path:       string,
}

/* Effective_Policy is the copied policy consumed by one active buffer. */
Effective_Policy :: struct {
	policy:                   Policy,
	scope:                    Scope,
	matcher_kind:             Matcher_Kind,
	matcher:                  Matcher_Text,
	source_generation:        u64,
	configuration_generation: Generation,
	profile_id:               Profile_ID,
}

/* DEFAULT_EFFECTIVE_POLICY is the inspectable initial factory resolution. */
DEFAULT_EFFECTIVE_POLICY :: Effective_Policy {
	policy = DEFAULT_POLICY,
	scope = .Factory,
	matcher_kind = .None,
	source_generation = 1,
	configuration_generation = Generation(1),
	profile_id = Profile_ID(1),
}

/* Failure_Code classifies contained configuration and resolution failures. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Invalid_Encoding,
	Invalid_Generation,
	Stale_Generation,
	Generation_Limit,
	Rule_Limit,
	Invalid_Profile,
	Invalid_Scope,
	Invalid_Matcher,
	Invalid_Policy,
	Invalid_Source_Generation,
	Duplicate_Rule,
	Invalid_Context,
}

/* Failure_Field identifies the rejected configuration field. */
Failure_Field :: enum u8 {
	None,
	Configuration_Generation,
	Configuration_Encoding,
	Rules,
	Profile,
	Scope,
	Matcher,
	Representation,
	Indent_Width,
	Display_Tab_Width,
	Source_Generation,
	Context,
}

/* Failure is copied and never retains candidate or caller storage. */
Failure :: struct {
	code:       Failure_Code,
	field:      Failure_Field,
	rule_index: u16,
	limit:      u64,
	actual:     u64,
}

/* Inspection is one copied complete confirmed generation. */
Inspection :: struct {
	generation:                Generation,
	factory_policy:            Policy,
	factory_source_generation: u64,
	rule_count:                u16,
	rules:                     [MAX_RULES]Rule,
	latest_rejection:          Failure,
}

/* Registry owns one atomically replaceable bounded configuration. */
Registry :: struct {
	initialized:               bool,
	generation:                Generation,
	factory_policy:            Policy,
	factory_source_generation: u64,
	rule_count:                u16,
	rules:                     [MAX_RULES]Rule,
	latest_rejection:          Failure,
}
