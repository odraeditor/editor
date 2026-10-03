// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../ui"

/* UI_ROLE_CAPABILITY_SCHEMA_VERSION identifies the first programmable UI role ABI. */
UI_ROLE_CAPABILITY_SCHEMA_VERSION :: u64(1)
/* MAX_UI_ROLE_PROVIDERS bounds copied providers across one session. */
MAX_UI_ROLE_PROVIDERS :: u64(64)
/* MAX_UI_ROLE_CAPABILITY_REQUIREMENTS bounds one provider capability set. */
MAX_UI_ROLE_CAPABILITY_REQUIREMENTS :: u64(8)
/* MAX_UI_ROLE_PROPOSAL_BYTES bounds one copied package proposal. */
MAX_UI_ROLE_PROPOSAL_BYTES :: u64(ui.MAX_SNAPSHOT_BYTES)
/* MAX_UI_ROLE_PROVIDER_TEXT_BYTES bounds copied provider and package names. */
MAX_UI_ROLE_PROVIDER_TEXT_BYTES :: u64(ui.MAX_COMPACT_REGION_BYTES)
/* MAX_UI_ROLE_DIAGNOSTIC_BYTES mirrors the native UI diagnostic ceiling. */
MAX_UI_ROLE_DIAGNOSTIC_BYTES :: u64(ui.MAX_DIAGNOSTIC_BYTES)

/* UI_ROLE_SCOPE_RECORD_BYTES is one exact session and provider generation. */
UI_ROLE_SCOPE_RECORD_BYTES :: u64(96)
/* UI_ROLE_SNAPSHOT_HEADER_BYTES precedes copied UI and provider records. */
UI_ROLE_SNAPSHOT_HEADER_BYTES :: u64(336)
/* UI_ROLE_PROJECTION_RECORD_BYTES is one pointer-free model projection. */
UI_ROLE_PROJECTION_RECORD_BYTES :: u64(88)
/* UI_ROLE_VIEW_RECORD_BYTES is one pointer-free visual view descriptor. */
UI_ROLE_VIEW_RECORD_BYTES :: u64(96)
/* UI_ROLE_LIST_ITEM_RECORD_BYTES is one copied list item and checked action. */
UI_ROLE_LIST_ITEM_RECORD_BYTES :: u64(104)
/* UI_ROLE_INPUT_CHOICE_RECORD_BYTES is one copied input choice and checked action. */
UI_ROLE_INPUT_CHOICE_RECORD_BYTES :: u64(88)
/* UI_ROLE_SURFACE_RECORD_BYTES is one logical surface with bounded geometry. */
UI_ROLE_SURFACE_RECORD_BYTES :: u64(160)
/* UI_ROLE_COMPOSITION_RECORD_BYTES is one pointer-free composition node. */
UI_ROLE_COMPOSITION_RECORD_BYTES :: u64(200)
/* UI_ROLE_STATUS_RECORD_BYTES is one copied attached or root-edge status region. */
UI_ROLE_STATUS_RECORD_BYTES :: u64(168)
/* UI_ROLE_STYLE_RECORD_BYTES is one copied semantic style. */
UI_ROLE_STYLE_RECORD_BYTES :: u64(56)
/* UI_ROLE_DECORATION_RECORD_BYTES is one copied checked semantic decoration. */
UI_ROLE_DECORATION_RECORD_BYTES :: u64(120)
/* UI_ROLE_PROVIDER_RECORD_BYTES is one copied provider selection. */
UI_ROLE_PROVIDER_RECORD_BYTES :: u64(96)
/* UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES is one renderer requirement. */
UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES :: u64(16)
/* UI_ROLE_DIAGNOSTIC_RECORD_BYTES is one copied contained failure. */
UI_ROLE_DIAGNOSTIC_RECORD_BYTES :: u64(80)
/* UI_ROLE_REQUEST_HEADER_BYTES precedes one copied provider proposal. */
UI_ROLE_REQUEST_HEADER_BYTES :: u64(280)
/* UI_ROLE_OUTCOME_RECORD_BYTES is one copied activation result. */
UI_ROLE_OUTCOME_RECORD_BYTES :: u64(184)

/* UI_Role identifies one accepted current visible-consumer replacement boundary. */
UI_Role :: enum u64 {
	Startup = 1,
	Buffer_Menu = 2,
	Candidate_Navigation = 3,
	Project_Inventory = 4,
	Keymap_Inspection = 5,
	Transient_Input = 6,
	Status = 7,
}

/* UI_Role_Provider_Kind distinguishes the confirmed native fallback from packages. */
UI_Role_Provider_Kind :: enum u64 {
	Built_In = 1,
	Package = 2,
}

/* UI_Role_Provider_State is the copied lifecycle state of one provider. */
UI_Role_Provider_State :: enum u64 {
	Registered = 1,
	Confirmed = 2,
	Rejected = 3,
	Failed = 4,
	Closed = 5,
}

/* UI_Role_Operation identifies one admitted synchronous role request. */
UI_Role_Operation :: enum i32 {
	Scope = 1,
	Snapshot = 2,
	Inspect_Provider = 3,
	Propose = 4,
	Activate = 5,
	Replace = 6,
	Rollback = 7,
	Teardown = 8,
	Invoke_Command = 9,
}

/* UI_Role_Access names checked authority without exposing native ownership. */
UI_Role_Access :: enum u64 {
	Inspect = 1,
	Propose = 2,
	Activate = 3,
	Replace = 4,
	Rollback = 5,
	Teardown = 6,
	Invoke_Command = 7,
}

/* UI_Role_Scope_Record binds one capability to exact session and UI generations. */
UI_Role_Scope_Record :: struct {
	schema_version:           u64,
	access:                   u64,
	session_id:               u64,
	session_generation:       u64,
	ui_registry_id:           u64,
	root_generation:          u64,
	role_registry_generation: u64,
	role:                     u64,
	provider_id:              u64,
	provider_generation:      u64,
	renderer_profile_id:      u64,
	capability_generation:    u64,
}

/* UI_Role_Snapshot_Header_Record describes one complete bounded copied snapshot. */
UI_Role_Snapshot_Header_Record :: struct {
	scope:                        UI_Role_Scope_Record,
	root_node_registry_id:        u64,
	root_node_object_id:          u64,
	root_node_root_generation:    u64,
	root_node_slot:               u64,
	root_node_slot_generation:    u64,
	focus_registry_id:            u64,
	focus_object_id:              u64,
	focus_root_generation:        u64,
	focus_slot:                   u64,
	focus_slot_generation:        u64,
	focus_captured:               u64,
	return_registry_id:           u64,
	return_object_id:             u64,
	return_root_generation:       u64,
	return_slot:                  u64,
	return_slot_generation:       u64,
	projection_count:             u64,
	view_count:                   u64,
	list_item_count:              u64,
	input_choice_count:           u64,
	surface_count:                u64,
	composition_count:            u64,
	status_region_count:          u64,
	style_count:                  u64,
	decoration_count:             u64,
	provider_count:               u64,
	capability_requirement_count: u64,
	content_bytes:                u64,
	retained_bytes:               u64,
	temporary_peak_bytes:         u64,
}

/* UI_Role_View_Record copies one exact visual view and projection relationship. */
UI_Role_View_Record :: struct {
	registry_id:               u64,
	object_id:                 u64,
	root_generation:           u64,
	slot:                      u64,
	slot_generation:           u64,
	kind:                      u64,
	projection_registry_id:    u64,
	projection_object_id:      u64,
	projection_root_generation: u64,
	projection_slot:           u64,
	projection_slot_generation: u64,
	read_only:                 u64,
}

/* UI_Role_List_Item_Record copies one list item and its checked semantic action. */
UI_Role_List_Item_Record :: struct {
	projection_registry_id:     u64,
	projection_object_id:       u64,
	projection_root_generation: u64,
	projection_slot:            u64,
	projection_slot_generation: u64,
	item_id:                    u64,
	text_offset:                u64,
	text_bytes:                 u64,
	action_owner_id:            u64,
	action_id:                  u64,
	action_generation:          u64,
	mark:                       u64,
	reserved:                   u64,
}

/* UI_Role_Input_Choice_Record copies one choice and its checked semantic action. */
UI_Role_Input_Choice_Record :: struct {
	projection_registry_id:     u64,
	projection_object_id:       u64,
	projection_root_generation: u64,
	projection_slot:            u64,
	projection_slot_generation: u64,
	choice_id:                  u64,
	name_offset:                u64,
	name_bytes:                 u64,
	action_owner_id:            u64,
	action_id:                  u64,
	action_generation:          u64,
}

/* UI_Role_Surface_Record copies one logical surface without physical frontend state. */
UI_Role_Surface_Record :: struct {
	registry_id:          u64,
	object_id:            u64,
	root_generation:      u64,
	slot:                 u64,
	slot_generation:      u64,
	owner_id:             u64,
	view_registry_id:     u64,
	view_object_id:       u64,
	view_root_generation: u64,
	view_slot:            u64,
	view_slot_generation: u64,
	focusable:            u64,
	visible:              u64,
	input_context:        u64,
	keymap_context:       u64,
	required_profile_id:  u64,
	row:                  u64,
	column:               u64,
	height:               u64,
	width:                u64,
}

/* UI_Role_Projection_Record copies one exact model-to-view projection identity. */
UI_Role_Projection_Record :: struct {
	registry_id:         u64,
	object_id:           u64,
	root_generation:     u64,
	slot:                u64,
	slot_generation:     u64,
	owner_id:            u64,
	model_id:            u64,
	model_generation:    u64,
	byte_count:          u64,
	item_count:          u64,
	read_only:           u64,
}

/* UI_Role_Composition_Record copies one exact surface leaf or split node. */
UI_Role_Composition_Record :: struct {
	registry_id:            u64,
	object_id:              u64,
	root_generation:        u64,
	slot:                   u64,
	slot_generation:        u64,
	kind:                   u64,
	surface_registry_id:    u64,
	surface_object_id:      u64,
	surface_root_generation: u64,
	surface_slot:           u64,
	surface_slot_generation: u64,
	first_registry_id:      u64,
	first_object_id:        u64,
	first_root_generation:  u64,
	first_slot:             u64,
	first_slot_generation:  u64,
	second_registry_id:     u64,
	second_object_id:       u64,
	second_root_generation: u64,
	second_slot:            u64,
	second_slot_generation: u64,
	orientation:            u64,
	first_weight:           u64,
	second_weight:          u64,
	depth:                  u64,
}

/* UI_Role_Status_Record copies one status region and its compact-content range. */
UI_Role_Status_Record :: struct {
	registry_id:             u64,
	object_id:               u64,
	root_generation:         u64,
	slot:                    u64,
	slot_generation:         u64,
	owner_id:                u64,
	placement:               u64,
	surface_registry_id:     u64,
	surface_object_id:       u64,
	surface_root_generation: u64,
	surface_slot:            u64,
	surface_slot_generation: u64,
	rows:                    u64,
	row:                     u64,
	column:                  u64,
	height:                  u64,
	width:                   u64,
	content_offset:          u64,
	content_bytes:           u64,
	style_role:              u64,
	active:                  u64,
}

/* UI_Role_Style_Record copies one exact semantic role and admitted attributes. */
UI_Role_Style_Record :: struct {
	registry_id:     u64,
	object_id:       u64,
	root_generation: u64,
	slot:            u64,
	slot_generation: u64,
	role:            u64,
	attributes:      u64,
}

/* UI_Role_Decoration_Record copies one checked semantic decoration. */
UI_Role_Decoration_Record :: struct {
	registry_id:               u64,
	object_id:                 u64,
	root_generation:           u64,
	slot:                      u64,
	slot_generation:           u64,
	owner_id:                  u64,
	kind:                      u64,
	projection_registry_id:    u64,
	projection_object_id:      u64,
	projection_root_generation: u64,
	projection_slot:           u64,
	projection_slot_generation: u64,
	start:                     u64,
	end:                       u64,
	style_role:                u64,
}

/* UI_Role_Provider_Record copies one provider without native pointers. */
UI_Role_Provider_Record :: struct {
	role:                         u64,
	provider_id:                  u64,
	provider_generation:          u64,
	kind:                         u64,
	state:                        u64,
	capability_requirement_offset: u64,
	capability_requirement_count: u64,
	name_offset:                  u64,
	name_bytes:                   u64,
	package_offset:               u64,
	package_bytes:                u64,
	confirmed_root_generation:    u64,
}

/* UI_Role_Capability_Requirement_Record declares one physical frontend need. */
UI_Role_Capability_Requirement_Record :: struct {
	capability: u64,
	required:   u64,
}

/* UI_Role_Diagnostic_Record reports one contained rejection with copied text. */
UI_Role_Diagnostic_Record :: struct {
	operation:          u64,
	code:               u64,
	role:               u64,
	provider_id:        u64,
	provider_generation: u64,
	root_generation:    u64,
	limit:              u64,
	actual:             u64,
	message_offset:     u64,
	message_bytes:      u64,
}

/* UI_Role_Request_Header_Record describes one generation-checked copied proposal. */
UI_Role_Request_Header_Record :: struct {
	expected_scope:               UI_Role_Scope_Record,
	operation:                    u64,
	role:                         u64,
	expected_provider_id:         u64,
	expected_provider_generation: u64,
	provider_id:                  u64,
	provider_generation:          u64,
	provider_kind:                u64,
	proposal_root_generation:     u64,
	projection_count:             u64,
	view_count:                   u64,
	list_item_count:              u64,
	input_choice_count:           u64,
	surface_count:                u64,
	composition_count:            u64,
	status_region_count:          u64,
	style_count:                  u64,
	decoration_count:             u64,
	capability_requirement_count: u64,
	name_bytes:                   u64,
	package_bytes:                u64,
	content_bytes:                u64,
	command_bytes:                u64,
	callback_budget:              u64,
}

/* UI_Role_Outcome_Record copies one activation, rollback, or teardown result. */
UI_Role_Outcome_Record :: struct {
	scope:                        UI_Role_Scope_Record,
	previous_provider_id:         u64,
	previous_provider_generation: u64,
	provider_id:                  u64,
	provider_generation:          u64,
	confirmed_root_generation:    u64,
	changed:                      u64,
	fallback_selected:            u64,
	diagnostic_code:              u64,
	diagnostic_bytes:             u64,
	retained_bytes:               u64,
	callback_count:               u64,
}

/* ui_role_snapshot_record_bytes checks every copied snapshot quota. */
ui_role_snapshot_record_bytes :: proc(
	projection_count, view_count, list_item_count, input_choice_count, surface_count,
	composition_count, status_region_count, style_count, decoration_count, provider_count,
	capability_requirement_count, content_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if projection_count > ui.MAX_LIVE_VIEWS ||
	   view_count > ui.MAX_LIVE_VIEWS ||
	   list_item_count > ui.MAX_LIST_ITEMS ||
	   input_choice_count > ui.MAX_FIXED_CHOICES ||
	   surface_count > ui.MAX_LIVE_SURFACES ||
	   composition_count > ui.MAX_COMPOSITION_NODES ||
	   status_region_count > ui.MAX_STATUS_REGIONS ||
	   style_count > ui.MAX_STYLES ||
	   decoration_count > ui.MAX_DECORATIONS ||
	   provider_count > MAX_UI_ROLE_PROVIDERS ||
	   capability_requirement_count >
	       MAX_UI_ROLE_PROVIDERS * MAX_UI_ROLE_CAPABILITY_REQUIREMENTS ||
	   content_bytes > MAX_UI_ROLE_PROPOSAL_BYTES {
		return 0, false
	}
	bytes = UI_ROLE_SNAPSHOT_HEADER_BYTES +
	        projection_count * UI_ROLE_PROJECTION_RECORD_BYTES +
	        view_count * UI_ROLE_VIEW_RECORD_BYTES +
	        list_item_count * UI_ROLE_LIST_ITEM_RECORD_BYTES +
	        input_choice_count * UI_ROLE_INPUT_CHOICE_RECORD_BYTES +
	        surface_count * UI_ROLE_SURFACE_RECORD_BYTES +
	        composition_count * UI_ROLE_COMPOSITION_RECORD_BYTES +
	        status_region_count * UI_ROLE_STATUS_RECORD_BYTES +
	        style_count * UI_ROLE_STYLE_RECORD_BYTES +
	        decoration_count * UI_ROLE_DECORATION_RECORD_BYTES +
	        provider_count * UI_ROLE_PROVIDER_RECORD_BYTES +
	        capability_requirement_count * UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES +
	        content_bytes
	return bytes, bytes <= MAX_UI_ROLE_PROPOSAL_BYTES
}

/* ui_role_request_record_bytes checks one complete provider request quota. */
ui_role_request_record_bytes :: proc(
	projection_count, view_count, list_item_count, input_choice_count, surface_count,
	composition_count, status_region_count, style_count, decoration_count,
	capability_requirement_count,
	name_bytes, package_bytes, content_bytes, command_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if projection_count > ui.MAX_LIVE_VIEWS ||
	   view_count > ui.MAX_LIVE_VIEWS ||
	   list_item_count > ui.MAX_LIST_ITEMS ||
	   input_choice_count > ui.MAX_FIXED_CHOICES ||
	   surface_count > ui.MAX_LIVE_SURFACES ||
	   composition_count > ui.MAX_COMPOSITION_NODES ||
	   status_region_count > ui.MAX_STATUS_REGIONS ||
	   style_count > ui.MAX_STYLES ||
	   decoration_count > ui.MAX_DECORATIONS ||
	   capability_requirement_count > MAX_UI_ROLE_CAPABILITY_REQUIREMENTS ||
	   name_bytes + package_bytes > MAX_UI_ROLE_PROVIDER_TEXT_BYTES ||
	   content_bytes > MAX_UI_ROLE_PROPOSAL_BYTES ||
	   command_bytes > MAX_UI_ROLE_PROVIDER_TEXT_BYTES {
		return 0, false
	}
	bytes = UI_ROLE_REQUEST_HEADER_BYTES +
	        projection_count * UI_ROLE_PROJECTION_RECORD_BYTES +
	        view_count * UI_ROLE_VIEW_RECORD_BYTES +
	        list_item_count * UI_ROLE_LIST_ITEM_RECORD_BYTES +
	        input_choice_count * UI_ROLE_INPUT_CHOICE_RECORD_BYTES +
	        surface_count * UI_ROLE_SURFACE_RECORD_BYTES +
	        composition_count * UI_ROLE_COMPOSITION_RECORD_BYTES +
	        status_region_count * UI_ROLE_STATUS_RECORD_BYTES +
	        style_count * UI_ROLE_STYLE_RECORD_BYTES +
	        decoration_count * UI_ROLE_DECORATION_RECORD_BYTES +
	        capability_requirement_count * UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES +
	        name_bytes + package_bytes + content_bytes + command_bytes
	return bytes, bytes <= MAX_UI_ROLE_PROPOSAL_BYTES
}

/* ui_role_record_layout_is_valid verifies every C and Racket ABI width. */
ui_role_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(UI_Role_Scope_Record)) == UI_ROLE_SCOPE_RECORD_BYTES &&
	       u64(size_of(UI_Role_Snapshot_Header_Record)) == UI_ROLE_SNAPSHOT_HEADER_BYTES &&
	       u64(size_of(UI_Role_Projection_Record)) == UI_ROLE_PROJECTION_RECORD_BYTES &&
	       u64(size_of(UI_Role_View_Record)) == UI_ROLE_VIEW_RECORD_BYTES &&
	       u64(size_of(UI_Role_List_Item_Record)) == UI_ROLE_LIST_ITEM_RECORD_BYTES &&
	       u64(size_of(UI_Role_Input_Choice_Record)) == UI_ROLE_INPUT_CHOICE_RECORD_BYTES &&
	       u64(size_of(UI_Role_Surface_Record)) == UI_ROLE_SURFACE_RECORD_BYTES &&
	       u64(size_of(UI_Role_Composition_Record)) == UI_ROLE_COMPOSITION_RECORD_BYTES &&
	       u64(size_of(UI_Role_Status_Record)) == UI_ROLE_STATUS_RECORD_BYTES &&
	       u64(size_of(UI_Role_Style_Record)) == UI_ROLE_STYLE_RECORD_BYTES &&
	       u64(size_of(UI_Role_Decoration_Record)) == UI_ROLE_DECORATION_RECORD_BYTES &&
	       u64(size_of(UI_Role_Provider_Record)) == UI_ROLE_PROVIDER_RECORD_BYTES &&
	       u64(size_of(UI_Role_Capability_Requirement_Record)) ==
	           UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES &&
	       u64(size_of(UI_Role_Diagnostic_Record)) == UI_ROLE_DIAGNOSTIC_RECORD_BYTES &&
	       u64(size_of(UI_Role_Request_Header_Record)) == UI_ROLE_REQUEST_HEADER_BYTES &&
	       u64(size_of(UI_Role_Outcome_Record)) == UI_ROLE_OUTCOME_RECORD_BYTES
}
