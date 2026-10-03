// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery_command

import "../command"
import "../interaction"
import "../ksawery"
import "base:runtime"

/* Ksawery_Extension_Command_Admission borrows one family and attributable source. */
Ksawery_Extension_Command_Admission :: struct {
	family: ksawery.Extension_Command_Family_Generation,
	source: string,
}

/* Ksawery_Extension_Command_Route binds one generation-local route to stable identities. */
Ksawery_Extension_Command_Route :: struct {
	route:              interaction.Command_Route,
	contributor:        ksawery.Contributor_Handle,
	family:             ksawery.Extension_Command_Family_ID,
	family_generation:  ksawery.Extension_Command_Family_Generation_ID,
	action:             ksawery.Extension_Command_Action_ID,
}

/* Ksawery_Extension_Command_Catalog owns definitions until its registry generation retires. */
Ksawery_Extension_Command_Catalog :: struct {
	definitions: []interaction.Command_Definition,
	routes:      []Ksawery_Extension_Command_Route,
	entries:     []Ksawery_Extension_Command_Entry,
	generation:  interaction.Registry_Generation,
	allocator:   runtime.Allocator,
}

/* Ksawery_Extension_Command_Entry owns copied registry metadata for one action route. */
Ksawery_Extension_Command_Entry :: struct {
	name:               [interaction.MAX_COMMAND_NAME_BYTES]u8,
	name_length:        u8,
	description:        [interaction.MAX_COMMAND_DESCRIPTION_BYTES]u8,
	description_length: u16,
	provider:           [ksawery.MAX_EXTENSION_IDENTITY_BYTES]u8,
	provider_length:    u16,
	source:             [ksawery.MAX_EXTENSION_PROVENANCE_BYTES]u8,
	source_length:      u16,
	location:           [ksawery.MAX_EXTENSION_IDENTITY_BYTES]u8,
	location_length:    u16,
	contributor:        ksawery.Contributor_Handle,
	family:             ksawery.Extension_Command_Family_ID,
	family_generation:  ksawery.Extension_Command_Family_Generation_ID,
	action:             ksawery.Extension_Command_Action_ID,
}

/* ksawery_extension_command_catalog_build composes one deterministic shared-registry generation. */
ksawery_extension_command_catalog_build :: proc(
	catalog: ^Ksawery_Extension_Command_Catalog,
	generation: interaction.Registry_Generation,
	admissions: []Ksawery_Extension_Command_Admission,
	allocator: runtime.Allocator,
) -> (bool, interaction.Failure_Context) {
	if catalog == nil || catalog.allocator.procedure != nil || generation == 0 ||
	   allocator.procedure == nil {
		return false, {code = .Invalid_Registry, registry_generation = generation}
	}
	count := 0
	for admission in admissions {
		_, family_failure := ksawery.extension_command_family_validate(admission.family)
		if family_failure.code != .None || len(admission.source) == 0 ||
		   u64(len(admission.source)) > ksawery.MAX_EXTENSION_PROVENANCE_BYTES {
			return false, {code = .Invalid_Provenance, registry_generation = generation}
		}
		if len(admission.family.actions) > interaction.MAX_COMMANDS - count {
			return false, {code = .Command_Limit, registry_generation = generation,
				limit = interaction.MAX_COMMANDS, actual = u64(count + len(admission.family.actions))}
		}
		count += len(admission.family.actions)
	}
	if count == 0 {
		return false, {code = .Command_Limit, registry_generation = generation,
			limit = interaction.MAX_COMMANDS}
	}
	entries, entries_error := make([]Ksawery_Extension_Command_Entry, count, allocator)
	if entries_error != nil {
		return false, {code = .Persistent_Memory_Limit, registry_generation = generation,
			actual = u64(count * size_of(Ksawery_Extension_Command_Entry))}
	}
	definitions, definitions_error := make([]interaction.Command_Definition, count, allocator)
	if definitions_error != nil {
		delete(entries, allocator)
		return false, {code = .Persistent_Memory_Limit, registry_generation = generation,
			actual = u64(count * size_of(interaction.Command_Definition))}
	}
	routes, routes_error := make([]Ksawery_Extension_Command_Route, count, allocator)
	if routes_error != nil {
		delete(definitions, allocator)
		delete(entries, allocator)
		return false, {code = .Persistent_Memory_Limit, registry_generation = generation,
			actual = u64(count * size_of(Ksawery_Extension_Command_Route))}
	}
	index := 0
	for admission in admissions {
		for action in admission.family.actions {
			entry := &entries[index]
			if !ksawery_extension_command_entry_assign(entry, admission, action) {
				delete(routes, allocator)
				delete(definitions, allocator)
				delete(entries, allocator)
				return false, {code = .Invalid_Name, registry_generation = generation}
			}
			index += 1
		}
	}
	ksawery_extension_command_entries_sort(entries)
	for _, entry_index in entries {
		entry := &entries[entry_index]
		if entry_index > 0 && ksawery_extension_command_entry_name(&entries[entry_index - 1]) ==
		                      ksawery_extension_command_entry_name(entry) {
			delete(routes, allocator)
			delete(definitions, allocator)
			delete(entries, allocator)
			return false, {code = .Duplicate_Command, registry_generation = generation,
				actual = u64(entry_index)}
		}
		route := command.racket_route(.Ksawery_Extension, u16(entry_index + 1))
		definitions[entry_index] = {
			name = ksawery_extension_command_entry_name(entry),
			route = route,
			implementation = .Racket,
			invocation = .Ordinary,
			text_requirement = .Prohibited,
			effects = {.Lifecycle},
			description = string(entry.description[:entry.description_length]),
			interactive = true,
			requirements = {.Active_Buffer},
			provenance = {
				provider = string(entry.provider[:entry.provider_length]),
				source = string(entry.source[:entry.source_length]),
				location = string(entry.location[:entry.location_length]),
			},
		}
		routes[entry_index] = {
			route = route,
			contributor = entry.contributor,
			family = entry.family,
			family_generation = entry.family_generation,
			action = entry.action,
		}
	}
	catalog^ = {
		definitions = definitions,
		routes = routes,
		entries = entries,
		generation = generation,
		allocator = allocator,
	}
	return true, {}
}

/* ksawery_extension_command_catalog_route resolves one admitted generation-local route. */
ksawery_extension_command_catalog_route :: proc(
	catalog: ^Ksawery_Extension_Command_Catalog,
	route: interaction.Command_Route,
) -> (Ksawery_Extension_Command_Route, bool) {
	if catalog == nil || catalog.allocator.procedure == nil ||
	   route.provider != command.RACKET_KSAWERY_ROUTE_PROVIDER || route.operation == 0 ||
	   int(route.operation) > len(catalog.routes) {
		return {}, false
	}
	entry := catalog.routes[int(route.operation) - 1]
	return entry, entry.route == route
}

/* ksawery_extension_command_catalog_close releases one retired registry contribution. */
ksawery_extension_command_catalog_close :: proc(catalog: ^Ksawery_Extension_Command_Catalog) {
	if catalog == nil do return
	if catalog.allocator.procedure != nil {
		delete(catalog.routes, catalog.allocator)
		delete(catalog.definitions, catalog.allocator)
		delete(catalog.entries, catalog.allocator)
	}
	catalog^ = {}
}

@(private)
ksawery_extension_command_entry_assign :: proc(
	entry: ^Ksawery_Extension_Command_Entry,
	admission: Ksawery_Extension_Command_Admission,
	action: ksawery.Extension_Command_Action_Definition,
) -> bool {
	contributor_value := admission.family.contributor_identity
	family_value := admission.family.identity
	action_identity_value := action.identity
	action_label := action.label
	contributor := string(contributor_value.bytes[:int(contributor_value.length)])
	family := string(family_value.bytes[:int(family_value.length)])
	action_identity := string(action_identity_value.bytes[:int(action_identity_value.length)])
	name_length := len(contributor) + len(family) + len(action_identity) + 2
	if name_length > len(entry.name) || len(admission.source) > len(entry.source) do return false
	offset := copy(entry.name[:], contributor)
	entry.name[offset] = '/'
	offset += 1
	offset += copy(entry.name[offset:], family)
	entry.name[offset] = '/'
	offset += 1
	offset += copy(entry.name[offset:], action_identity)
	entry.name_length = u8(offset)
	entry.description_length = action_label.length
	copy(entry.description[:], string(action_label.bytes[:int(action_label.length)]))
	entry.provider_length = contributor_value.length
	copy(entry.provider[:], contributor)
	entry.source_length = u16(len(admission.source))
	copy(entry.source[:], admission.source)
	entry.location_length = family_value.length
	copy(entry.location[:], family)
	entry.contributor = admission.family.contributor
	entry.family = admission.family.family
	entry.family_generation = admission.family.generation
	entry.action = action.id
	return true
}

@(private)
ksawery_extension_command_entries_sort :: proc(entries: []Ksawery_Extension_Command_Entry) {
	for index in 1 ..< len(entries) {
		cursor := index
		for cursor > 0 && ksawery_extension_command_entry_name(&entries[cursor]) <
		                  ksawery_extension_command_entry_name(&entries[cursor - 1]) {
			entries[cursor], entries[cursor - 1] = entries[cursor - 1], entries[cursor]
			cursor -= 1
		}
	}
}

@(private)
ksawery_extension_command_entry_name :: proc(entry: ^Ksawery_Extension_Command_Entry) -> string {
	return string(entry.name[:entry.name_length])
}
