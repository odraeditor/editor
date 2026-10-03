// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import language "../language"

/* FACTORY_OLS_IDENTITY is the maintained factory service identity. */
FACTORY_OLS_IDENTITY :: "ols"
/* FACTORY_OLS_EXECUTABLE is the controlled executable lookup name. */
FACTORY_OLS_EXECUTABLE :: "ols"
/* FACTORY_OLS_SOURCE_GENERATION identifies the maintained catalog record. */
FACTORY_OLS_SOURCE_GENERATION :: Service_Source_Generation(1)

@(private)
FACTORY_OLS_LANGUAGES := [1]string{"odin"}

/* factory_ols_definition returns the maintained data-only OLS definition. */
factory_ols_definition :: proc() -> Definition_Proposal {
	return Definition_Proposal{
		kind = .Factory,
		name = FACTORY_OLS_IDENTITY,
		executable = FACTORY_OLS_EXECUTABLE,
		root_policy = .Project_Membership,
		languages = FACTORY_OLS_LANGUAGES[:],
		initialization_options = `{}`,
		client_settings = `{}`,
		feature_policy = {.Diagnostics, .Completion},
		requested_capabilities = {
			.Initialize,
			.Shutdown,
			.Cancellation,
			.Full_Synchronization,
			.Incremental_Synchronization,
			.Save_Notification,
			.Push_Diagnostics,
			.Log_Message,
			.Completion,
		},
		preferred_encoding = .UTF_16,
		preferred_sync = .Incremental,
		limits = DEFAULT_LIMITS,
		deadlines = DEFAULT_DEADLINES,
		restart = DEFAULT_RESTART_POLICY,
	}
}

/* factory_ols_catalog_confirm publishes OLS through generic service resolution. */
factory_ols_catalog_confirm :: proc(
	catalog: ^Service_Catalog,
	factory: Definition_Handle,
	odin: language.Language_Identity,
) -> (bool, Service_Catalog_Failure) {
	languages := [?]language.Language_Identity{odin}
	definitions := [?]Service_Catalog_Definition_Candidate {{
		definition = factory,
		identity = FACTORY_OLS_IDENTITY,
		languages = languages[:],
		source = .Factory,
		scope_kind = .Global,
		source_generation = FACTORY_OLS_SOURCE_GENERATION,
		policy = {enabled = true, default_selection = true},
		provenance = "Odra factory OLS",
	}}
	return service_catalog_confirm(
		catalog,
		0,
		{
			generation = 1,
			language_catalog_generation = language.Language_Catalog_Generation(odin.generation),
			definitions = definitions[:],
		},
	)
}

/* provider_registry_register_factory_ols admits, confirms, and selects factory OLS. */
provider_registry_register_factory_ols :: proc(
	registry: ^Provider_Registry,
) -> (Definition_Handle, bool, Failure_Context) {
	state := provider_registry_state(registry)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	if state.factory.id != Definition_ID(0) {
		return {}, false, Failure_Context{code = .Invalid_Definition, definition = state.factory}
	}
	handle, proposed, failure := provider_registry_propose(registry, factory_ols_definition())
	if !proposed do return {}, false, failure
	confirmed, confirm_failure := provider_registry_confirm(registry, handle)
	if !confirmed {
		owner, _ := provider_registry_resolve(state, handle)
		provider_registry_discard(state, owner)
		return {}, false, confirm_failure
	}
	state.factory = handle
	selected, select_failure := provider_registry_select(registry, handle)
	if !selected {
		state.factory = {}
		owner, _ := provider_registry_resolve(state, handle)
		provider_registry_discard(state, owner)
		return {}, false, select_failure
	}
	return handle, true, {}
}
