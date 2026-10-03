// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:unicode/utf8"

/* DEFAULT_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR is the initial owner-local section budget. */
DEFAULT_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR :: u16(4)
/* MAX_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR is the immutable owner-local section ceiling. */
MAX_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR :: u16(16)
/* DEFAULT_EXTENSION_STATUS_ITEMS_PER_SECTION is the initial section item budget. */
DEFAULT_EXTENSION_STATUS_ITEMS_PER_SECTION :: u16(32)
/* MAX_EXTENSION_STATUS_ITEMS_PER_SECTION is the immutable section item ceiling. */
MAX_EXTENSION_STATUS_ITEMS_PER_SECTION :: u16(256)
/* DEFAULT_EXTENSION_STATUS_ITEMS is the initial aggregate item budget. */
DEFAULT_EXTENSION_STATUS_ITEMS :: u32(128)
/* MAX_EXTENSION_STATUS_ITEMS is the immutable aggregate item ceiling. */
MAX_EXTENSION_STATUS_ITEMS :: u32(4_096)
/* DEFAULT_EXTENSION_STATUS_METADATA is the initial aggregate metadata budget. */
DEFAULT_EXTENSION_STATUS_METADATA :: u32(512)
/* MAX_EXTENSION_STATUS_METADATA is the immutable aggregate metadata ceiling. */
MAX_EXTENSION_STATUS_METADATA :: u32(16_384)
/* MAX_EXTENSION_STATUS_METADATA_PER_ITEM bounds metadata fanout on one item. */
MAX_EXTENSION_STATUS_METADATA_PER_ITEM :: u8(8)
/* MAX_EXTENSION_STATUS_TEXT_BYTES bounds one copied public text field. */
MAX_EXTENSION_STATUS_TEXT_BYTES :: 4 * KIBIBYTE
/* MAX_EXTENSION_STATUS_METADATA_VALUE_BYTES bounds one copied metadata value. */
MAX_EXTENSION_STATUS_METADATA_VALUE_BYTES :: 1 * KIBIBYTE
/* DEFAULT_EXTENSION_STATUS_COPY_BYTES is the initial complete generation budget. */
DEFAULT_EXTENSION_STATUS_COPY_BYTES :: u64(256 * KIBIBYTE)
/* MAX_EXTENSION_STATUS_COPY_BYTES is the immutable complete generation ceiling. */
MAX_EXTENSION_STATUS_COPY_BYTES :: u64(4 * MEBIBYTE)

/* Extension_Status_Section_Generation identifies one immutable section projection. */
Extension_Status_Section_Generation :: distinct u64
/* Extension_Status_Item_ID identifies one stable item within its contributor generation. */
Extension_Status_Item_ID :: distinct u64

/* Extension_Status_Text owns one bounded copied public text field. */
Extension_Status_Text :: struct {
	bytes:  [MAX_EXTENSION_STATUS_TEXT_BYTES]u8,
	length: u16,
}

/* Extension_Status_Metadata_Value owns one bounded copied public metadata value. */
Extension_Status_Metadata_Value :: struct {
	bytes:  [MAX_EXTENSION_STATUS_METADATA_VALUE_BYTES]u8,
	length: u16,
}

/* Extension_Status_Style names theme-backed semantics without carrying terminal styling. */
Extension_Status_Style :: enum u8 {
	Invalid,
	Normal,
	Muted,
	Identity,
	Active,
	Success,
	Warning,
	Alert,
	Information,
}

/* Extension_Status_Truncation records why one otherwise valid projection is incomplete. */
Extension_Status_Truncation :: enum u8 {
	Invalid,
	Complete,
	Item_Limit,
	Metadata_Limit,
	Text_Limit,
	Provider_Limit,
}

/* Extension_Status_Command_Reference identifies one admitted generation-owned command. */
Extension_Status_Command_Reference :: struct {
	present:      bool,
	contributor:  Contributor_Handle,
	contribution: Contribution_ID,
	identity:     Extension_Identity,
}

/* Extension_Status_Metadata is one provider-owned copied key and value. */
Extension_Status_Metadata :: struct {
	key:   Extension_Identity,
	value: Extension_Status_Metadata_Value,
}

/* Extension_Status_Item is one semantic row inside an extension-owned section. */
Extension_Status_Item :: struct {
	id:       Extension_Status_Item_ID,
	identity: Extension_Identity,
	text:     Extension_Status_Text,
	detail:   Extension_Status_Text,
	style:    Extension_Status_Style,
	command:  Extension_Status_Command_Reference,
	metadata: []Extension_Status_Metadata,
}

/* Extension_Status_Order_Key fixes contributor-then-section ordering. */
Extension_Status_Order_Key :: struct {
	contributor: Contributor_Identity,
	section:     Extension_Identity,
}

/* Extension_Status_Section is one immutable proposal bound to exact Status truth. */
Extension_Status_Section :: struct {
	contributor:            Contributor_Handle,
	contributor_identity:   Contributor_Identity,
	contribution:           Contribution_ID,
	identity:               Extension_Identity,
	generation:             Extension_Status_Section_Generation,
	repository:             Repository_Context,
	observation_generation: Observation_Generation,
	label:                  Extension_Label,
	items:                  []Extension_Status_Item,
	truncation:             Extension_Status_Truncation,
}

/* Extension_Status_Generation is one complete immutable contributor projection. */
Extension_Status_Generation :: struct {
	contributor:            Contributor_Handle,
	contributor_identity:   Contributor_Identity,
	generation:             Extension_Status_Section_Generation,
	repository:             Repository_Context,
	observation_generation: Observation_Generation,
	sections:               []Extension_Status_Section,
}

/* Extension_Status_Limits bounds one complete provider-owned projection generation. */
Extension_Status_Limits :: struct {
	sections_per_contributor: u16,
	items_per_section:        u16,
	total_items:              u32,
	total_metadata:           u32,
	copy_bytes:               u64,
}

/* DEFAULT_EXTENSION_STATUS_LIMITS selects the initial bounded projection envelope. */
DEFAULT_EXTENSION_STATUS_LIMITS :: Extension_Status_Limits {
	sections_per_contributor = DEFAULT_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR,
	items_per_section = DEFAULT_EXTENSION_STATUS_ITEMS_PER_SECTION,
	total_items = DEFAULT_EXTENSION_STATUS_ITEMS,
	total_metadata = DEFAULT_EXTENSION_STATUS_METADATA,
	copy_bytes = DEFAULT_EXTENSION_STATUS_COPY_BYTES,
}

/* MAX_EXTENSION_STATUS_LIMITS records every immutable section ceiling. */
MAX_EXTENSION_STATUS_LIMITS :: Extension_Status_Limits {
	sections_per_contributor = MAX_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR,
	items_per_section = MAX_EXTENSION_STATUS_ITEMS_PER_SECTION,
	total_items = MAX_EXTENSION_STATUS_ITEMS,
	total_metadata = MAX_EXTENSION_STATUS_METADATA,
	copy_bytes = MAX_EXTENSION_STATUS_COPY_BYTES,
}

/* Extension_Status_Usage reports exact copied content in one section generation. */
Extension_Status_Usage :: struct {
	sections:       u16,
	items:          u32,
	metadata:       u32,
	text_bytes:     u64,
	copy_bytes:     u64,
	command_references: u32,
	truncated:      bool,
}

/* Extension_Status_Failure_Code classifies expected projection rejection. */
Extension_Status_Failure_Code :: enum u16 {
	None,
	Invalid_Section,
	Invalid_Item,
	Invalid_Text,
	Invalid_Metadata,
	Invalid_Style,
	Invalid_Command,
	Duplicate_Section,
	Duplicate_Item,
	Duplicate_Metadata,
	Stale_Contributor,
	Stale_Observation,
	Section_Limit,
	Item_Limit,
	Metadata_Limit,
	Copy_Limit,
}

/* Extension_Status_Failure identifies one attributable bounded rejection. */
Extension_Status_Failure :: struct {
	code:    Extension_Status_Failure_Code,
	section: Extension_Identity,
	item:    Extension_Status_Item_ID,
	index:   u32,
	limit:   u64,
	actual:  u64,
}

/* extension_status_text_assign copies one checked public text field. */
extension_status_text_assign :: proc(text: ^Extension_Status_Text, value: string, allow_empty := false) -> bool {
	if text == nil do return false
	text^ = {}
	if (!allow_empty && len(value) == 0) || len(value) > len(text.bytes) || !utf8.valid_string(value) {
		return false
	}
	copy(text.bytes[:len(value)], transmute([]u8)value)
	text.length = u16(len(value))
	return true
}

/* extension_status_metadata_value_assign copies one checked public metadata value. */
extension_status_metadata_value_assign :: proc(
	value: ^Extension_Status_Metadata_Value,
	text: string,
) -> bool {
	if value == nil do return false
	value^ = {}
	if len(text) == 0 || len(text) > len(value.bytes) || !utf8.valid_string(text) do return false
	copy(value.bytes[:len(text)], transmute([]u8)text)
	value.length = u16(len(text))
	return true
}

/* extension_status_limits_are_valid checks one policy against immutable ceilings. */
extension_status_limits_are_valid :: proc(limits: Extension_Status_Limits) -> bool {
	return limits.sections_per_contributor > 0 &&
		limits.sections_per_contributor <= MAX_EXTENSION_STATUS_SECTIONS_PER_CONTRIBUTOR &&
		limits.items_per_section > 0 && limits.items_per_section <= MAX_EXTENSION_STATUS_ITEMS_PER_SECTION &&
		limits.total_items > 0 && limits.total_items <= MAX_EXTENSION_STATUS_ITEMS &&
		u32(limits.sections_per_contributor) * u32(limits.items_per_section) >= limits.total_items &&
		limits.total_metadata > 0 && limits.total_metadata <= MAX_EXTENSION_STATUS_METADATA &&
		limits.copy_bytes > 0 && limits.copy_bytes <= MAX_EXTENSION_STATUS_COPY_BYTES
}

/* extension_status_section_validate checks one complete immutable section proposal. */
extension_status_section_validate :: proc(
	section: Extension_Status_Section,
	limits := DEFAULT_EXTENSION_STATUS_LIMITS,
) -> (usage: Extension_Status_Usage, failure: Extension_Status_Failure) {
	if !extension_status_limits_are_valid(limits) ||
	   !contributor_handle_is_valid(section.contributor) ||
	   !contributor_identity_is_valid(section.contributor_identity) ||
	   section.contribution == Contribution_ID(0) || !extension_identity_is_valid(section.identity) ||
	   section.generation == Extension_Status_Section_Generation(0) ||
	   !repository_context_is_valid(section.repository) ||
	   section.observation_generation == Observation_Generation(0) ||
	   !extension_label_is_valid(section.label) || section.truncation == .Invalid {
		return {}, {code = .Invalid_Section, section = section.identity}
	}
	if len(section.items) > int(limits.items_per_section) {
		return {}, {code = .Item_Limit, section = section.identity, limit = u64(limits.items_per_section), actual = u64(len(section.items))}
	}
	usage.sections = 1
	usage.items = u32(len(section.items))
	usage.text_bytes = u64(section.label.length)
	usage.copy_bytes = u64(size_of(Extension_Status_Section))
	usage.truncated = section.truncation != .Complete
	for item, item_index in section.items {
		item_failure := extension_status_item_validate(item, section.contributor)
		if item_failure.code != .None {
			item_failure.section = section.identity
			item_failure.index = u32(item_index)
			return {}, item_failure
		}
		for prior in 0 ..< item_index {
			if section.items[prior].id == item.id || section.items[prior].identity == item.identity {
				return {}, {code = .Duplicate_Item, section = section.identity, item = item.id, index = u32(item_index)}
			}
		}
		usage.metadata += u32(len(item.metadata))
		usage.text_bytes += u64(item.text.length) + u64(item.detail.length)
		usage.copy_bytes += u64(size_of(Extension_Status_Item) + len(item.metadata) * size_of(Extension_Status_Metadata))
		if item.command.present do usage.command_references += 1
		for metadata in item.metadata do usage.text_bytes += u64(metadata.key.length) + u64(metadata.value.length)
	}
	if usage.items > limits.total_items {
		return {}, {code = .Item_Limit, section = section.identity, limit = u64(limits.total_items), actual = u64(usage.items)}
	}
	if usage.metadata > limits.total_metadata {
		return {}, {code = .Metadata_Limit, section = section.identity, limit = u64(limits.total_metadata), actual = u64(usage.metadata)}
	}
	if usage.copy_bytes > limits.copy_bytes {
		return {}, {code = .Copy_Limit, section = section.identity, limit = limits.copy_bytes, actual = usage.copy_bytes}
	}
	return usage, {}
}

/* extension_status_generation_validate checks complete contributor publication atomicity. */
extension_status_generation_validate :: proc(
	generation: Extension_Status_Generation,
	limits := DEFAULT_EXTENSION_STATUS_LIMITS,
) -> (usage: Extension_Status_Usage, failure: Extension_Status_Failure) {
	if !extension_status_limits_are_valid(limits) ||
	   !contributor_handle_is_valid(generation.contributor) ||
	   !contributor_identity_is_valid(generation.contributor_identity) ||
	   generation.generation == Extension_Status_Section_Generation(0) ||
	   !repository_context_is_valid(generation.repository) ||
	   generation.observation_generation == Observation_Generation(0) {
		return {}, {code = .Invalid_Section}
	}
	if len(generation.sections) > int(limits.sections_per_contributor) {
		return {}, {code = .Section_Limit, limit = u64(limits.sections_per_contributor), actual = u64(len(generation.sections))}
	}
	for section, section_index in generation.sections {
		if section.contributor != generation.contributor ||
		   section.contributor_identity != generation.contributor_identity ||
		   section.generation != generation.generation {
			return {}, {code = .Stale_Contributor, section = section.identity, index = u32(section_index)}
		}
		if section.repository != generation.repository ||
		   section.observation_generation != generation.observation_generation {
			return {}, {code = .Stale_Observation, section = section.identity, index = u32(section_index)}
		}
		for prior in 0 ..< section_index {
			if generation.sections[prior].identity == section.identity {
				return {}, {code = .Duplicate_Section, section = section.identity, index = u32(section_index)}
			}
		}
		section_usage, section_failure := extension_status_section_validate(section, limits)
		if section_failure.code != .None {
			section_failure.index = u32(section_index)
			return {}, section_failure
		}
		usage.sections += section_usage.sections
		usage.items += section_usage.items
		usage.metadata += section_usage.metadata
		usage.text_bytes += section_usage.text_bytes
		usage.copy_bytes += section_usage.copy_bytes
		usage.command_references += section_usage.command_references
		usage.truncated = usage.truncated || section_usage.truncated
	}
	if usage.items > limits.total_items {
		return {}, {code = .Item_Limit, limit = u64(limits.total_items), actual = u64(usage.items)}
	}
	if usage.metadata > limits.total_metadata {
		return {}, {code = .Metadata_Limit, limit = u64(limits.total_metadata), actual = u64(usage.metadata)}
	}
	if usage.copy_bytes > limits.copy_bytes {
		return {}, {code = .Copy_Limit, limit = limits.copy_bytes, actual = usage.copy_bytes}
	}
	return usage, {}
}

/* extension_status_section_matches_observation rejects stale or cross-repository projections. */
extension_status_section_matches_observation :: proc(
	section: Extension_Status_Section,
	observation: Observation_Descriptor,
) -> (bool, Extension_Status_Failure) {
	if section.repository != observation.repository ||
	   section.observation_generation != observation.generation {
		return false, {code = .Stale_Observation, section = section.identity}
	}
	return true, {}
}

/* extension_status_order_key returns the only admitted section ordering input. */
extension_status_order_key :: proc(section: Extension_Status_Section) -> Extension_Status_Order_Key {
	return {contributor = section.contributor_identity, section = section.identity}
}

/* extension_status_order_key_is_less orders contributor identity before section identity. */
extension_status_order_key_is_less :: proc(a, b: Extension_Status_Order_Key) -> bool {
	a_copy, b_copy := a, b
	contributor_order := extension_status_bytes_compare(
		a_copy.contributor.bytes[:a_copy.contributor.length],
		b_copy.contributor.bytes[:b_copy.contributor.length],
	)
	if contributor_order != 0 do return contributor_order < 0
	return extension_status_bytes_compare(
		a_copy.section.bytes[:a_copy.section.length],
		b_copy.section.bytes[:b_copy.section.length],
	) < 0
}

/* extension_status_section_is_visible omits empty or truncated-away additive projections. */
extension_status_section_is_visible :: proc(section: Extension_Status_Section) -> bool {
	return len(section.items) > 0
}

@(private)
extension_status_item_validate :: proc(
	item: Extension_Status_Item,
	owner: Contributor_Handle,
) -> Extension_Status_Failure {
	if item.id == Extension_Status_Item_ID(0) || !extension_identity_is_valid(item.identity) {
		return {code = .Invalid_Item, item = item.id}
	}
	if !extension_status_text_is_valid(item.text, false) || !extension_status_text_is_valid(item.detail, true) {
		return {code = .Invalid_Text, item = item.id}
	}
	if item.style == .Invalid {
		return {code = .Invalid_Style, item = item.id}
	}
	if item.command.present && (!contributor_handle_is_valid(item.command.contributor) ||
	   item.command.contributor != owner || item.command.contribution == Contribution_ID(0) ||
	   !extension_identity_is_valid(item.command.identity)) {
		return {code = .Invalid_Command, item = item.id}
	}
	if !item.command.present && item.command != (Extension_Status_Command_Reference{}) {
		return {code = .Invalid_Command, item = item.id}
	}
	if len(item.metadata) > int(MAX_EXTENSION_STATUS_METADATA_PER_ITEM) {
		return {code = .Metadata_Limit, item = item.id, limit = u64(MAX_EXTENSION_STATUS_METADATA_PER_ITEM), actual = u64(len(item.metadata))}
	}
	for metadata, metadata_index in item.metadata {
		if !extension_identity_is_valid(metadata.key) || !extension_status_metadata_value_is_valid(metadata.value) {
			return {code = .Invalid_Metadata, item = item.id, index = u32(metadata_index)}
		}
		for prior in 0 ..< metadata_index {
			if item.metadata[prior].key == metadata.key {
				return {code = .Duplicate_Metadata, item = item.id, index = u32(metadata_index)}
			}
		}
	}
	return {}
}

@(private)
extension_status_text_is_valid :: proc(text: Extension_Status_Text, allow_empty: bool) -> bool {
	if (!allow_empty && text.length == 0) || int(text.length) > len(text.bytes) do return false
	copy_value := text
	return utf8.valid_string(string(copy_value.bytes[:copy_value.length]))
}

@(private)
extension_status_metadata_value_is_valid :: proc(value: Extension_Status_Metadata_Value) -> bool {
	copy_value := value
	return copy_value.length > 0 && int(copy_value.length) <= len(copy_value.bytes) &&
		utf8.valid_string(string(copy_value.bytes[:copy_value.length]))
}

@(private)
extension_status_bytes_compare :: proc(a, b: []u8) -> int {
	count := min(len(a), len(b))
	for index in 0 ..< count {
		if a[index] < b[index] do return -1
		if a[index] > b[index] do return 1
	}
	if len(a) < len(b) do return -1
	if len(a) > len(b) do return 1
	return 0
}
