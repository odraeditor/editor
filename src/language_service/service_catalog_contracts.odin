// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import language "../language"

/* MAX_SERVICE_CATALOG_DEFINITIONS bounds records in one confirmed catalog. */
MAX_SERVICE_CATALOG_DEFINITIONS :: 64
/* MAX_SERVICE_CATALOG_SELECTIONS bounds explicit language selections. */
MAX_SERVICE_CATALOG_SELECTIONS :: 64
/* MAX_SERVICE_CATALOG_SOURCES bounds contributing source generations. */
MAX_SERVICE_CATALOG_SOURCES :: 64
/* MAX_SERVICE_CATALOG_CONFLICTS bounds retained catalog conflicts. */
MAX_SERVICE_CATALOG_CONFLICTS :: 64
/* MAX_SERVICE_CONFLICT_PARTICIPANTS bounds records named by conflicts. */
MAX_SERVICE_CONFLICT_PARTICIPANTS :: 64
/* MAX_SERVICE_IDENTITY_BYTES bounds one stable service identity. */
MAX_SERVICE_IDENTITY_BYTES :: 96
/* MAX_SERVICE_SCOPE_BYTES bounds one contribution-scope identity. */
MAX_SERVICE_SCOPE_BYTES :: 256
/* MAX_SERVICE_PROVENANCE_BYTES bounds one copied provenance description. */
MAX_SERVICE_PROVENANCE_BYTES :: 256
/* MAX_SERVICE_ROOT_TRACE_BYTES bounds one copied resolved-root trace. */
MAX_SERVICE_ROOT_TRACE_BYTES :: 16 * 1_024

/* Service_Catalog_ID identifies one native service-catalog owner. */
Service_Catalog_ID :: distinct u32
/* Service_Catalog_Generation identifies one immutable catalog snapshot. */
Service_Catalog_Generation :: distinct u64
/* Service_Source_Generation identifies one exact contribution publication. */
Service_Source_Generation :: distinct u64

/* Service_Contribution_Source defines deterministic contribution precedence. */
Service_Contribution_Source :: enum u8 {
	Invalid,
	Factory,
	Package,
	Personal,
	Project,
}

/* Service_Scope_Kind identifies the authority boundary of a contribution. */
Service_Scope_Kind :: enum u8 {
	Invalid,
	Global,
	Package,
	Project_Membership,
}

/* Service_Candidate_State explains one definition's effective disposition. */
Service_Candidate_State :: enum u8 {
	Invalid,
	Effective,
	Disabled,
	Shadowed,
	Conflicted,
}

/* Service_Selection_Kind explains how one effective definition was selected. */
Service_Selection_Kind :: enum u8 {
	None,
	Explicit_Project,
	Explicit_Personal,
	Unique_Default,
	Sole_Candidate,
	Factory_Restoration,
}

/* Service_Resolution_State reports one deterministic selection outcome. */
Service_Resolution_State :: enum u8 {
	Invalid,
	Selected,
	Absent,
	Ambiguous,
	Invalid_Explicit_Selection,
	Untrusted_Project,
}

/* Service_Conflict_Kind classifies one retained same-precedence conflict. */
Service_Conflict_Kind :: enum u8 {
	None,
	Duplicate_Identity,
	Package_Identity,
	Ambiguous_Default,
}

/* Service_Catalog_Failure_Code classifies one contained catalog rejection. */
Service_Catalog_Failure_Code :: enum u16 {
	None,
	Invalid_Catalog,
	Closed_Catalog,
	Invalid_Generation,
	Stale_Generation,
	Definition_Limit,
	Selection_Limit,
	Conflict_Limit,
	Identity_Limit,
	Scope_Limit,
	Provenance_Limit,
	Language_Limit,
	Invalid_Definition,
	Invalid_Language,
	Invalid_Source,
	Invalid_Scope,
	Duplicate_Identity,
	Package_Conflict,
	Ambiguous_Default,
	Invalid_Explicit_Selection,
	No_Selection,
	Generation_Limit,
	Allocation,
}

/* Service_Catalog_Field identifies the rejected bounded field. */
Service_Catalog_Field :: enum u8 {
	None,
	Catalog_Generation,
	Source_Generation,
	Definitions,
	Selections,
	Conflicts,
	Identity,
	Languages,
	Source,
	Scope,
	Provenance,
	Default_Policy,
}

/* Service_Identity_Text is one bounded copied stable service identity. */
Service_Identity_Text :: struct {
	bytes:  [MAX_SERVICE_IDENTITY_BYTES]u8,
	length: u16,
}

/* Service_Scope_Text is one bounded copied contribution-scope identity. */
Service_Scope_Text :: struct {
	bytes:  [MAX_SERVICE_SCOPE_BYTES]u8,
	length: u16,
}

/* Service_Provenance_Text is one bounded copied contribution description. */
Service_Provenance_Text :: struct {
	bytes:  [MAX_SERVICE_PROVENANCE_BYTES]u8,
	length: u16,
}

/* Service_Root_Text is one bounded copied resolved root. */
Service_Root_Text :: struct {
	bytes:  [MAX_SERVICE_ROOT_TRACE_BYTES]u8,
	length: u16,
}

/* Service_Source_Scope identifies one exact contribution authority. */
Service_Source_Scope :: struct {
	source: Service_Contribution_Source,
	kind:   Service_Scope_Kind,
	name:   Service_Scope_Text,
}

/* Service_Selection_Policy is one definition's explicit enabled/default policy. */
Service_Selection_Policy :: struct {
	enabled:           bool,
	default_selection: bool,
}

/* Service_Language_Reference is one compact confirmed language identity. */
Service_Language_Reference :: struct {
	id:         language.Language_ID,
	generation: language.Language_Generation,
}

/* Service_Catalog_Definition_Candidate borrows one complete resolution record. */
Service_Catalog_Definition_Candidate :: struct {
	definition:        Definition_Handle,
	identity:          string,
	languages:         []language.Language_Identity,
	source:            Service_Contribution_Source,
	scope_kind:        Service_Scope_Kind,
	scope:             string,
	source_generation: Service_Source_Generation,
	policy:            Service_Selection_Policy,
	provenance:        string,
}

/* Service_Explicit_Selection_Candidate borrows one authority-scoped choice. */
Service_Explicit_Selection_Candidate :: struct {
	language:          language.Language_Identity,
	service_identity: string,
	source:            Service_Contribution_Source,
	scope_kind:        Service_Scope_Kind,
	scope:             string,
	source_generation: Service_Source_Generation,
}

/* Service_Catalog_Candidate is one complete proposed immutable generation. */
Service_Catalog_Candidate :: struct {
	generation:                  Service_Catalog_Generation,
	language_catalog_generation: language.Language_Catalog_Generation,
	definitions:                 []Service_Catalog_Definition_Candidate,
	selections:                  []Service_Explicit_Selection_Candidate,
}

/* Service_Definition_Descriptor is one copied confirmed resolution record. */
Service_Definition_Descriptor :: struct {
	definition:        Definition_Handle,
	identity:          Service_Identity_Text,
	languages:         [MAX_LANGUAGE_IDENTITIES]Service_Language_Reference,
	language_count:    u16,
	scope:             Service_Source_Scope,
	source_generation: Service_Source_Generation,
	policy:            Service_Selection_Policy,
	provenance:        Service_Provenance_Text,
}

/* Service_Explicit_Selection is one copied authority-scoped choice. */
Service_Explicit_Selection :: struct {
	language:          Service_Language_Reference,
	service_identity: Service_Identity_Text,
	scope:             Service_Source_Scope,
	source_generation: Service_Source_Generation,
}

/* Service_Effective_Candidate records one definition-language disposition. */
Service_Effective_Candidate :: struct {
	definition:     Definition_Handle,
	language:       language.Language_Identity,
	state:          Service_Candidate_State,
	shadowed_by:    Definition_Handle,
	conflict_index: u16,
}

/* Service_Conflict_Participant identifies one record in a retained conflict. */
Service_Conflict_Participant :: struct {
	definition:        Definition_Handle,
	scope:             Service_Source_Scope,
	source_generation: Service_Source_Generation,
}

/* Service_Conflict_Record describes one bounded symmetric catalog conflict. */
Service_Conflict_Record :: struct {
	kind:         Service_Conflict_Kind,
	identity:     Service_Identity_Text,
	language:     Service_Language_Reference,
	participants: Record_Range,
	fallback:     Definition_Handle,
}

/* Service_Source_Record copies one contributing source generation. */
Service_Source_Record :: struct {
	scope:      Service_Source_Scope,
	generation: Service_Source_Generation,
	accepted:   bool,
}

/* Service_Catalog_Failure is copied and never retains candidate storage. */
Service_Catalog_Failure :: struct {
	code:              Service_Catalog_Failure_Code,
	field:             Service_Catalog_Field,
	source:            Service_Contribution_Source,
	source_generation: Service_Source_Generation,
	definition_index:  u16,
	selection_index:   u16,
	limit:             u64,
	actual:            u64,
}

/* Service_Resolution_Query borrows one trusted language/root selection scope. */
Service_Resolution_Query :: struct {
	language:           language.Language_Identity,
	project_membership: string,
	resolved_root:      string,
	project_trusted:    bool,
}

/* Service_Resolution_Trace is one copied deterministic selection explanation. */
Service_Resolution_Trace :: struct {
	catalog_id:         Service_Catalog_ID,
	catalog_generation: Service_Catalog_Generation,
	language:           language.Language_Identity,
	project_scope:      Service_Scope_Text,
	resolved_root:      Service_Root_Text,
	selected:           Definition_Handle,
	selected_identity:  Service_Identity_Text,
	kind:               Service_Selection_Kind,
	state:              Service_Resolution_State,
	considered:         u16,
	enabled:            u16,
	shadowed:           u16,
	conflicted:         u16,
	explicit_selection: Service_Explicit_Selection,
}

/* Service_Catalog_Inspection is one complete copied bounded snapshot. */
Service_Catalog_Inspection :: struct {
	catalog_id:          Service_Catalog_ID,
	catalog_generation:  Service_Catalog_Generation,
	language_generation: language.Language_Catalog_Generation,
	definition_count:    u16,
	selection_count:     u16,
	source_count:        u16,
	conflict_count:      u16,
	participant_count:   u16,
	definitions:         [MAX_SERVICE_CATALOG_DEFINITIONS]Service_Definition_Descriptor,
	selections:          [MAX_SERVICE_CATALOG_SELECTIONS]Service_Explicit_Selection,
	sources:             [MAX_SERVICE_CATALOG_SOURCES]Service_Source_Record,
	conflicts:           [MAX_SERVICE_CATALOG_CONFLICTS]Service_Conflict_Record,
	participants:        [MAX_SERVICE_CONFLICT_PARTICIPANTS]Service_Conflict_Participant,
	latest_rejection:    Service_Catalog_Failure,
}
