// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package theme owns bounded theme identities, complete immutable style
// definitions, session selection, resource policy, and stable failures.
package theme

import "../ui"
import "core:unicode/utf8"

/* KIBIBYTE is the binary byte unit used by theme resource policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_PROVIDERS bounds factory and admitted Racket providers per session. */
MAX_PROVIDERS :: 64
/* MAX_DEFINITIONS bounds live immutable definition generations per session. */
MAX_DEFINITIONS :: 64
/* MAX_THEME_IDENTITY_BYTES bounds one stable machine-readable identity. */
MAX_THEME_IDENTITY_BYTES :: 96
/* MAX_DISPLAY_NAME_BYTES bounds one copied human-readable theme name. */
MAX_DISPLAY_NAME_BYTES :: 96
/* MAX_PROVIDER_NAME_BYTES bounds one copied provider name. */
MAX_PROVIDER_NAME_BYTES :: 96
/* MAX_PROVENANCE_BYTES bounds one copied package or source description. */
MAX_PROVENANCE_BYTES :: 256
/* MAX_STYLES bounds one complete semantic role mapping. */
MAX_STYLES :: 66
/* CURRENT_STYLE_ROLE_COUNT is the complete delivered semantic role vocabulary. */
CURRENT_STYLE_ROLE_COUNT :: 66
/* MAX_RETAINED_DEFINITION_BYTES bounds aggregate logical definition data. */
MAX_RETAINED_DEFINITION_BYTES :: 1 * MEBIBYTE
/* MAX_PROPOSAL_BYTES bounds one complete Racket definition proposal. */
MAX_PROPOSAL_BYTES :: 64 * KIBIBYTE
/* MAX_OPERATIONS_PER_TURN bounds one hosted theme capability turn. */
MAX_OPERATIONS_PER_TURN :: 64
/* MAX_INSPECTION_BYTES bounds one complete copied inspection. */
MAX_INSPECTION_BYTES :: 1 * MEBIBYTE
/* MAX_PREPARATION_BYTES bounds one validation or publication preparation. */
MAX_PREPARATION_BYTES :: 8 * MEBIBYTE
/* MAX_DIAGNOSTIC_BYTES bounds one copied failure explanation. */
MAX_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
/* MAX_CONCURRENT_HOSTED_TURNS admits only one owner-thread theme turn. */
MAX_CONCURRENT_HOSTED_TURNS :: 1
/* FACTORY_DEFINITION_COUNT includes four Wrocław themes and the safe baseline. */
FACTORY_DEFINITION_COUNT :: 5

/* Registry_ID identifies one session theme registry; zero is invalid. */
Registry_ID :: distinct u64
/* Registry_Generation identifies one exact registry state. */
Registry_Generation :: distinct u64
/* Selection_Generation identifies one exact active selection. */
Selection_Generation :: distinct u64
/* Provider_ID identifies one provider for a registry lifetime. */
Provider_ID :: distinct u64
/* Provider_Generation identifies one exact provider lifecycle state. */
Provider_Generation :: distinct u64
/* Definition_ID identifies one theme identity for a registry lifetime. */
Definition_ID :: distinct u64
/* Definition_Generation identifies one exact immutable definition generation. */
Definition_Generation :: distinct u64

/* Theme_Name is one bounded copied stable machine identity. */
Theme_Name :: struct {
	bytes:  [MAX_THEME_IDENTITY_BYTES]u8,
	length: u16,
}

/* Display_Name is one bounded copied human-readable theme name. */
Display_Name :: struct {
	bytes:  [MAX_DISPLAY_NAME_BYTES]u8,
	length: u16,
}

/* Provider_Name is one bounded copied provider identity. */
Provider_Name :: struct {
	bytes:  [MAX_PROVIDER_NAME_BYTES]u8,
	length: u16,
}

/* Provenance_Text is one bounded copied package or source description. */
Provenance_Text :: struct {
	bytes:  [MAX_PROVENANCE_BYTES]u8,
	length: u16,
}

/* Diagnostic_Text is one bounded copied contained failure explanation. */
Diagnostic_Text :: struct {
	bytes:  [MAX_DIAGNOSTIC_BYTES]u8,
	length: u16,
}

/* Provider_Kind distinguishes maintained factory data from Racket proposals. */
Provider_Kind :: enum u8 {Invalid, Factory, Racket}
/* Provider_State reports one provider lifecycle state. */
Provider_State :: enum u8 {Invalid, Confirmed, Failed, Closed}
/* Definition_State reports one immutable definition lifecycle state. */
Definition_State :: enum u8 {Invalid, Proposed, Confirmed, Failed, Closed}

/* Selection_State reports why the current complete definition is active. */
Selection_State :: enum u8 {
	Invalid,
	Factory,
	Selected,
	Replaced,
	Restored,
	Safe_Baseline,
	Fallback_After_Failure,
}

/* Provider_Handle is one checked pointer-free provider identity. */
Provider_Handle :: struct {
	registry_id:         Registry_ID,
	provider_id:         Provider_ID,
	provider_generation: Provider_Generation,
}

/* Definition_Handle is one checked pointer-free immutable generation. */
Definition_Handle :: struct {
	registry_id:            Registry_ID,
	provider_id:            Provider_ID,
	provider_generation:    Provider_Generation,
	definition_id:          Definition_ID,
	definition_generation: Definition_Generation,
}

/* Provider_Descriptor is one copied bounded provider inspection record. */
Provider_Descriptor :: struct {
	handle: Provider_Handle,
	kind:   Provider_Kind,
	state:  Provider_State,
	name:   Provider_Name,
}

/* Definition_Descriptor is one copied immutable generation inspection record. */
Definition_Descriptor :: struct {
	handle:         Definition_Handle,
	identity:       Theme_Name,
	display_name:   Display_Name,
	provider:       Provider_Handle,
	state:          Definition_State,
	provenance:     Provenance_Text,
	style_count:    u16,
	retained_bytes: u64,
}

/* Definition_View borrows immutable styles until the next registry mutation. */
Definition_View :: struct {
	descriptor: Definition_Descriptor,
	styles:     []ui.Style_Definition,
}

/* Definition_Proposal borrows one complete definition during validation. */
Definition_Proposal :: struct {
	identity:      string,
	display_name:  string,
	provider_name: string,
	provenance:    string,
	styles:        []ui.Style_Definition,
}

/* Selection copies the one exact active, fallback, and safe-baseline state. */
Selection :: struct {
	registry_id:          Registry_ID,
	registry_generation:  Registry_Generation,
	selection_generation: Selection_Generation,
	state:                Selection_State,
	active:               Definition_Handle,
	fallback:             Definition_Handle,
	baseline:             Definition_Handle,
}

/* Resource_Limits contains every selected initial native and hosted bound. */
Resource_Limits :: struct {
	providers:                 u16,
	definitions:               u16,
	theme_identity_bytes:      u16,
	display_name_bytes:        u16,
	provider_name_bytes:       u16,
	provenance_bytes:          u16,
	styles:                    u16,
	retained_definition_bytes: u64,
	proposal_bytes:            u64,
	operations_per_turn:       u16,
	inspection_bytes:          u64,
	preparation_bytes:         u64,
	diagnostic_bytes:          u64,
	concurrent_hosted_turns:   u16,
}

/* DEFAULT_RESOURCE_LIMITS is the accepted initial Theme MVP policy. */
DEFAULT_RESOURCE_LIMITS :: Resource_Limits {
	providers = MAX_PROVIDERS,
	definitions = MAX_DEFINITIONS,
	theme_identity_bytes = MAX_THEME_IDENTITY_BYTES,
	display_name_bytes = MAX_DISPLAY_NAME_BYTES,
	provider_name_bytes = MAX_PROVIDER_NAME_BYTES,
	provenance_bytes = MAX_PROVENANCE_BYTES,
	styles = MAX_STYLES,
	retained_definition_bytes = MAX_RETAINED_DEFINITION_BYTES,
	proposal_bytes = MAX_PROPOSAL_BYTES,
	operations_per_turn = MAX_OPERATIONS_PER_TURN,
	inspection_bytes = MAX_INSPECTION_BYTES,
	preparation_bytes = MAX_PREPARATION_BYTES,
	diagnostic_bytes = MAX_DIAGNOSTIC_BYTES,
	concurrent_hosted_turns = MAX_CONCURRENT_HOSTED_TURNS,
}

/* Resource_Usage reports exact current logical occupancy and peak preparation. */
Resource_Usage :: struct {
	providers:                 u16,
	definitions:               u16,
	retained_definition_bytes: u64,
	inspection_bytes:          u64,
	preparation_peak_bytes:    u64,
	operations_in_turn:        u16,
	hosted_turns:              u16,
}

/* Operation identifies the theme lifecycle action that produced a failure. */
Operation :: enum u8 {
	None,
	Initialize,
	Propose,
	Confirm,
	Select,
	Replace,
	Restore,
	Select_Baseline,
	Fail,
	Inspect,
	Close_Provider,
	Close,
}

/* Failure_Code classifies every expected theme rejection. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Wrong_Registry,
	Invalid_Provider,
	Stale_Provider,
	Duplicate_Provider,
	Provider_Limit,
	Provider_Name_Limit,
	Provider_Not_Confirmed,
	Factory_Provider_Required,
	Invalid_Definition,
	Stale_Definition,
	Duplicate_Definition,
	Definition_Limit,
	Definition_Not_Proposed,
	Definition_Not_Confirmed,
	Factory_Definition_Immutable,
	Invalid_Identity,
	Identity_Limit,
	Display_Name_Limit,
	Provenance_Limit,
	Invalid_Style,
	Unknown_Style_Role,
	Duplicate_Style_Role,
	Incomplete_Style_Roles,
	Monochrome_Indistinguishable,
	Stale_Registry,
	Stale_Selection,
	Retained_Definition_Limit,
	Proposal_Limit,
	Operation_Limit,
	Inspection_Limit,
	Preparation_Limit,
	Diagnostic_Limit,
	Generation_Limit,
	Allocation,
	Busy,
}

/* Failure reports one rejected operation without native pointers. */
Failure :: struct {
	operation:  Operation,
	code:       Failure_Code,
	provider:   Provider_Handle,
	definition: Definition_Handle,
	limit:      u64,
	actual:     u64,
}

/* Registry_Inspection copies exact session selection, occupancy, and policy. */
Registry_Inspection :: struct {
	selection:      Selection,
	usage:          Resource_Usage,
	limits:         Resource_Limits,
	latest_failure: Failure,
}

/* Registry is a non-copyable owner of one session theme registry. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* resource_limits_are_valid checks the complete selected policy relationship. */
resource_limits_are_valid :: proc(limits: Resource_Limits) -> bool {
	return limits.providers > 0 && limits.providers <= MAX_PROVIDERS &&
		limits.definitions >= FACTORY_DEFINITION_COUNT && limits.definitions <= MAX_DEFINITIONS &&
		limits.theme_identity_bytes > 0 && limits.theme_identity_bytes <= MAX_THEME_IDENTITY_BYTES &&
		limits.display_name_bytes > 0 && limits.display_name_bytes <= MAX_DISPLAY_NAME_BYTES &&
		limits.provider_name_bytes > 0 && limits.provider_name_bytes <= MAX_PROVIDER_NAME_BYTES &&
		limits.provenance_bytes > 0 && limits.provenance_bytes <= MAX_PROVENANCE_BYTES &&
		limits.styles >= CURRENT_STYLE_ROLE_COUNT && limits.styles <= MAX_STYLES &&
		limits.retained_definition_bytes > 0 &&
		limits.retained_definition_bytes <= MAX_RETAINED_DEFINITION_BYTES &&
		limits.proposal_bytes > 0 && limits.proposal_bytes <= MAX_PROPOSAL_BYTES &&
		limits.operations_per_turn > 0 && limits.operations_per_turn <= MAX_OPERATIONS_PER_TURN &&
		limits.inspection_bytes > 0 && limits.inspection_bytes <= MAX_INSPECTION_BYTES &&
		limits.preparation_bytes > 0 && limits.preparation_bytes <= MAX_PREPARATION_BYTES &&
		limits.diagnostic_bytes > 0 && limits.diagnostic_bytes <= MAX_DIAGNOSTIC_BYTES &&
		limits.concurrent_hosted_turns == MAX_CONCURRENT_HOSTED_TURNS
}

/* definition_proposal_validate checks a complete immutable role mapping. */
definition_proposal_validate :: proc(
	proposal: Definition_Proposal,
	limits := DEFAULT_RESOURCE_LIMITS,
) -> (ok: bool, failure: Failure) {
	if !resource_limits_are_valid(limits) {
		return false, theme_failure(.Propose, .Invalid_Registry)
	}
	if !theme_identity_is_valid(proposal.identity) {
		code := Failure_Code.Invalid_Identity
		if len(proposal.identity) > int(limits.theme_identity_bytes) {
			code = .Identity_Limit
		}
		return false, theme_failure_with_limit(
			.Propose, code, u64(limits.theme_identity_bytes), u64(len(proposal.identity)),
		)
	}
	text_checks := [?]struct {text: string, limit: u16, code: Failure_Code} {
		{proposal.display_name, limits.display_name_bytes, .Display_Name_Limit},
		{proposal.provider_name, limits.provider_name_bytes, .Provider_Name_Limit},
		{proposal.provenance, limits.provenance_bytes, .Provenance_Limit},
	}
	for check in text_checks {
		if len(check.text) == 0 || len(check.text) > int(check.limit) || !utf8.valid_string(check.text) {
			return false, theme_failure_with_limit(
				.Propose, check.code, u64(check.limit), u64(len(check.text)),
			)
		}
	}
	if len(proposal.styles) != CURRENT_STYLE_ROLE_COUNT || len(proposal.styles) > int(limits.styles) {
		return false, theme_failure_with_limit(
			.Propose, .Incomplete_Style_Roles, CURRENT_STYLE_ROLE_COUNT, u64(len(proposal.styles)),
		)
	}
	seen: [MAX_STYLES + 1]bool
	for style in proposal.styles {
		if !ui.style_role_is_valid(style.role) {
			return false, theme_failure(.Propose, .Unknown_Style_Role)
		}
		if !ui.style_definition_is_valid(style) {
			return false, theme_failure(.Propose, .Invalid_Style)
		}
		index := int(style.role)
		if seen[index] {
			return false, theme_failure(.Propose, .Duplicate_Style_Role)
		}
		seen[index] = true
	}
	if !monochrome_distinctions_are_valid(proposal.styles) {
		return false, theme_failure(.Propose, .Monochrome_Indistinguishable)
	}
	proposal_bytes := definition_proposal_bytes(proposal)
	if proposal_bytes > limits.proposal_bytes {
		return false, theme_failure_with_limit(
			.Propose, .Proposal_Limit, limits.proposal_bytes, proposal_bytes,
		)
	}
	return true, {}
}

/* definition_proposal_bytes reports exact copied logical proposal data. */
definition_proposal_bytes :: proc(proposal: Definition_Proposal) -> u64 {
	return u64(len(proposal.identity) + len(proposal.display_name) +
		len(proposal.provider_name) + len(proposal.provenance)) +
		u64(len(proposal.styles)) * u64(size_of(ui.Style_Definition))
}

/* theme_identity_is_valid checks the canonical lowercase machine-name form. */
theme_identity_is_valid :: proc(identity: string) -> bool {
	if len(identity) == 0 || len(identity) > MAX_THEME_IDENTITY_BYTES ||
	   identity[0] == '-' || identity[len(identity) - 1] == '-' {
		return false
	}
	for byte in transmute([]u8)identity {
		if (byte < 'a' || byte > 'z') && (byte < '0' || byte > '9') && byte != '-' {
			return false
		}
	}
	return true
}

/* theme_name_string borrows one copied identity as a string. */
theme_name_string :: proc(name: ^Theme_Name) -> string {
	if name == nil || name.length > MAX_THEME_IDENTITY_BYTES do return ""
	return string(name.bytes[:name.length])
}

/* display_name_string borrows one copied display name as a string. */
display_name_string :: proc(name: ^Display_Name) -> string {
	if name == nil || name.length > MAX_DISPLAY_NAME_BYTES do return ""
	return string(name.bytes[:name.length])
}

/* provider_name_string borrows one copied provider name as a string. */
provider_name_string :: proc(name: ^Provider_Name) -> string {
	if name == nil || name.length > MAX_PROVIDER_NAME_BYTES do return ""
	return string(name.bytes[:name.length])
}

/* provenance_text_string borrows one copied provenance description. */
provenance_text_string :: proc(text: ^Provenance_Text) -> string {
	if text == nil || text.length > MAX_PROVENANCE_BYTES do return ""
	return string(text.bytes[:text.length])
}

/* failure_code_diagnostic returns one stable human-readable theme rejection. */
failure_code_diagnostic :: proc(code: Failure_Code) -> string {
	switch code {
	case .None: return "no failure"
	case .Invalid_Registry: return "theme registry is invalid"
	case .Closed_Registry: return "theme registry is closed"
	case .Wrong_Registry: return "theme handle belongs to another registry"
	case .Invalid_Provider: return "theme provider is invalid"
	case .Stale_Provider: return "theme provider generation is stale"
	case .Duplicate_Provider: return "theme provider already exists"
	case .Provider_Limit: return "theme provider limit exceeded"
	case .Provider_Name_Limit: return "theme provider name is invalid or too large"
	case .Provider_Not_Confirmed: return "theme provider is not confirmed"
	case .Factory_Provider_Required: return "maintained factory provider is required"
	case .Invalid_Definition: return "theme definition is invalid"
	case .Stale_Definition: return "theme definition generation is stale"
	case .Duplicate_Definition: return "theme identity already exists"
	case .Definition_Limit: return "theme definition limit exceeded"
	case .Definition_Not_Proposed: return "theme definition is not proposed"
	case .Definition_Not_Confirmed: return "theme definition is not confirmed"
	case .Factory_Definition_Immutable: return "factory theme definition is immutable"
	case .Invalid_Identity: return "theme identity is invalid"
	case .Identity_Limit: return "theme identity is too large"
	case .Display_Name_Limit: return "theme display name is invalid or too large"
	case .Provenance_Limit: return "theme provenance is invalid or too large"
	case .Invalid_Style: return "theme style is invalid"
	case .Unknown_Style_Role: return "theme style role is unknown"
	case .Duplicate_Style_Role: return "theme style role is duplicated"
	case .Incomplete_Style_Roles: return "theme style mapping is incomplete"
	case .Monochrome_Indistinguishable: return "theme loses required monochrome distinctions"
	case .Stale_Registry: return "theme registry generation is stale"
	case .Stale_Selection: return "theme selection generation is stale"
	case .Retained_Definition_Limit: return "retained theme definition limit exceeded"
	case .Proposal_Limit: return "theme proposal limit exceeded"
	case .Operation_Limit: return "theme operation limit exceeded"
	case .Inspection_Limit: return "theme inspection limit exceeded"
	case .Preparation_Limit: return "theme preparation limit exceeded"
	case .Diagnostic_Limit: return "theme diagnostic limit exceeded"
	case .Generation_Limit: return "theme generation is exhausted"
	case .Allocation: return "theme allocation failed"
	case .Busy: return "theme registry is busy"
	}
	return "unknown theme failure"
}

@(private)
monochrome_distinctions_are_valid :: proc(styles: []ui.Style_Definition) -> bool {
	normal, normal_ok := style_for_role(styles, .Text_Normal)
	region, region_ok := style_for_role(styles, .Text_Region)
	rejected, rejected_ok := style_for_role(styles, .Diagnostic_Rejected)
	error_style, error_ok := style_for_role(styles, .Diagnostic_Error)
	warning, warning_ok := style_for_role(styles, .Diagnostic_Warning)
	information, information_ok := style_for_role(styles, .Diagnostic_Information)
	hint, hint_ok := style_for_role(styles, .Diagnostic_Hint)
	return normal_ok && region_ok && rejected_ok && error_ok && warning_ok &&
		information_ok && hint_ok && region.attributes != normal.attributes &&
		rejected.attributes != normal.attributes && error_style.attributes != normal.attributes &&
		warning.attributes != normal.attributes && information.attributes != normal.attributes &&
		hint.attributes != normal.attributes && error_style.attributes != warning.attributes &&
		error_style.attributes != information.attributes && error_style.attributes != hint.attributes &&
		warning.attributes != information.attributes && warning.attributes != hint.attributes &&
		information.attributes != hint.attributes
}

@(private)
style_for_role :: proc(styles: []ui.Style_Definition, role: ui.Style_Role) -> (ui.Style_Definition, bool) {
	for style in styles {
		if style.role == role do return style, true
	}
	return {}, false
}

@(private)
theme_failure :: proc(operation: Operation, code: Failure_Code) -> Failure {
	return Failure{operation = operation, code = code}
}

@(private)
theme_failure_with_limit :: proc(
	operation: Operation,
	code: Failure_Code,
	limit, actual: u64,
) -> Failure {
	return Failure{operation = operation, code = code, limit = limit, actual = actual}
}
