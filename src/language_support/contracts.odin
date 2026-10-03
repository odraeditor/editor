// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_support

import "../language"
import "../language_service"
import json "core:encoding/json"
import "core:strings"
import "core:unicode/utf8"

/* CONFIGURATION_SCHEMA_VERSION identifies copied declarative support payloads. */
CONFIGURATION_SCHEMA_VERSION :: i64(1)
/* MAX_CONFIGURATION_BYTES bounds one copied contribution payload. */
MAX_CONFIGURATION_BYTES :: 128 * 1_024
/* MAX_ROOT_MARKERS bounds relative root selectors per service. */
MAX_ROOT_MARKERS :: language_service.MAX_ROOT_MARKERS
/* MAX_FEATURES bounds symbolic feature policy per service. */
MAX_FEATURES :: 16
/* MAX_JSON_VALUES bounds recursive options and settings values. */
MAX_JSON_VALUES :: 65_536

@(private)
Text_Kind :: enum {
	Ordinary,
	Filename,
	Suffix,
	Root_Marker,
	Feature,
}

/* configuration_valid admits one complete bounded language-support payload. */
configuration_valid :: proc(input: []u8) -> bool {
	if len(input) == 0 || len(input) > MAX_CONFIGURATION_BYTES ||
	   !utf8.valid_string(string(input)) {
		return false
	}
	value, parse_error := json.parse_bytes(input, .JSON, true, context.temp_allocator)
	if parse_error != .None {
		json.destroy_value(value, context.temp_allocator)
		return false
	}
	defer json.destroy_value(value, context.temp_allocator)
	return configuration_value_valid(value)
}

@(private)
configuration_value_valid :: proc(value: json.Value) -> bool {
	root, root_ok := value.(json.Object)
	if !root_ok do return false
	schema_value, schema_present := root["schema"]
	languages_value, languages_present := root["languages"]
	services_value, services_present := root["services"]
	selections_value, selections_present := root["selections"]
	schema, schema_ok := schema_value.(json.Integer)
	languages, languages_ok := languages_value.(json.Array)
	services, services_ok := services_value.(json.Array)
	selections, selections_ok := selections_value.(json.Array)
	if !schema_present || !languages_present || !services_present || !selections_present ||
	   !schema_ok || !languages_ok || !services_ok || !selections_ok ||
	   schema != CONFIGURATION_SCHEMA_VERSION || len(root) != 4 ||
	   len(languages) > language.MAX_LANGUAGES ||
	   len(services) > language_service.MAX_SERVICE_CATALOG_DEFINITIONS ||
	   len(selections) > language_service.MAX_SERVICE_CATALOG_SELECTIONS {
		return false
	}
	for candidate, index in languages {
		if !language_valid(candidate) do return false
		identity, _ := object_string(candidate, "id")
		for previous in 0 ..< index {
			previous_identity, _ := object_string(languages[previous], "id")
			if identity == previous_identity do return false
		}
	}
	for candidate, index in services {
		if !service_valid(candidate) do return false
		identity, _ := object_string(candidate, "id")
		for previous in 0 ..< index {
			previous_identity, _ := object_string(services[previous], "id")
			if identity == previous_identity do return false
		}
	}
	for candidate, index in selections {
		if !selection_valid(candidate) do return false
		identity, _ := object_string(candidate, "language")
		for previous in 0 ..< index {
			previous_identity, _ := object_string(selections[previous], "language")
			if identity == previous_identity do return false
		}
	}
	return true
}

@(private)
language_valid :: proc(value: json.Value) -> bool {
	object, ok := value.(json.Object)
	if !ok || len(object) != 4 do return false
	identity, identity_ok := object_string(value, "id")
	display, display_ok := object_string(value, "display-name")
	filenames_value, filenames_present := object["filenames"]
	suffixes_value, suffixes_present := object["suffixes"]
	filenames, filenames_ok := filenames_value.(json.Array)
	suffixes, suffixes_ok := suffixes_value.(json.Array)
	return identity_ok && display_ok && filenames_present && suffixes_present &&
		filenames_ok && suffixes_ok &&
		text_valid(identity, language.MAX_LANGUAGE_NAME_BYTES, false) &&
		text_valid(display, language.MAX_LANGUAGE_DISPLAY_NAME_BYTES, false) &&
		string_array_valid(
			filenames, language.MAX_LANGUAGE_EXACT_FILENAMES,
			language.MAX_ASSOCIATION_BYTES, .Filename,
		) &&
		string_array_valid(
			suffixes, language.MAX_LANGUAGE_SUFFIXES,
			language.MAX_ASSOCIATION_BYTES, .Suffix,
		) &&
		len(filenames) + len(suffixes) <= language.MAX_LANGUAGE_SELECTORS
}

@(private)
service_valid :: proc(value: json.Value) -> bool {
	object, ok := value.(json.Object)
	if !ok || len(object) != 11 do return false
	identity, identity_ok := object_string(value, "id")
	display, display_ok := object_string(value, "display-name")
	languages_value, languages_present := object["languages"]
	command_value, command_present := object["command"]
	markers_value, markers_present := object["root-markers"]
	initialization, initialization_present := object["initialization-options"]
	settings, settings_present := object["settings"]
	environment_value, environment_present := object["environment"]
	features_value, features_present := object["features"]
	enabled_value, enabled_present := object["enabled"]
	default_value, default_present := object["default"]
	languages, languages_ok := languages_value.(json.Array)
	command, command_ok := command_value.(json.Array)
	markers, markers_ok := markers_value.(json.Array)
	environment, environment_ok := environment_value.(json.Array)
	features, features_ok := features_value.(json.Array)
	_, enabled_ok := enabled_value.(json.Boolean)
	_, default_ok := default_value.(json.Boolean)
	json_values := 0
	return identity_ok && display_ok && languages_present && command_present &&
		markers_present && initialization_present && settings_present &&
		environment_present && features_present && enabled_present && default_present &&
		languages_ok && command_ok && markers_ok && environment_ok && features_ok &&
		enabled_ok && default_ok &&
		text_valid(identity, language_service.MAX_SERVICE_IDENTITY_BYTES, false) &&
		text_valid(display, language_service.MAX_NAME_BYTES, false) &&
		string_array_valid(
			languages, language_service.MAX_LANGUAGE_IDENTITIES,
			language.MAX_LANGUAGE_NAME_BYTES, .Ordinary,
		) && len(languages) > 0 &&
		command_valid(command) &&
		string_array_valid(
			markers, MAX_ROOT_MARKERS,
			int(language_service.DEFAULT_LIMITS.root_bytes), .Root_Marker,
		) &&
		environment_valid(environment) &&
		string_array_valid(
			features, MAX_FEATURES,
			language_service.MAX_NAME_BYTES, .Feature,
		) &&
		json_value_valid(initialization, 1, &json_values) &&
		json_value_valid(settings, 1, &json_values)
}

@(private)
selection_valid :: proc(value: json.Value) -> bool {
	object, ok := value.(json.Object)
	if !ok || len(object) != 2 do return false
	language_identity, language_ok := object_string(value, "language")
	service_identity, service_ok := object_string(value, "service")
	return language_ok && service_ok &&
		text_valid(language_identity, language.MAX_LANGUAGE_NAME_BYTES, false) &&
		text_valid(service_identity, language_service.MAX_SERVICE_IDENTITY_BYTES, false)
}

@(private)
object_string :: proc(value: json.Value, name: string) -> (string, bool) {
	object, ok := value.(json.Object)
	if !ok do return "", false
	field, present := object[name]
	if !present do return "", false
	text, text_ok := field.(json.String)
	return string(text), text_ok
}

@(private)
string_array_valid :: proc(
	values: json.Array,
	maximum_count, maximum_bytes: int,
	kind: Text_Kind,
) -> bool {
	if len(values) > maximum_count do return false
	total_bytes := 0
	for value, index in values {
		text_value, ok := value.(json.String)
		if !ok do return false
		text := string(text_value)
		if !text_valid(text, maximum_bytes, false) || !text_kind_valid(text, kind) {
			return false
		}
		total_bytes += len(text)
		for previous in 0 ..< index {
			previous_text, previous_ok := values[previous].(json.String)
			if !previous_ok || text == string(previous_text) do return false
		}
	}
	if kind == .Root_Marker && total_bytes > int(language_service.DEFAULT_LIMITS.root_bytes) {
		return false
	}
	return true
}

@(private)
command_valid :: proc(values: json.Array) -> bool {
	if len(values) == 0 || len(values) > int(language_service.DEFAULT_LIMITS.arguments) {
		return false
	}
	total_bytes := 0
	for value, index in values {
		text_value, ok := value.(json.String)
		if !ok do return false
		text := string(text_value)
		if !text_valid(
			text,
			int(language_service.DEFAULT_LIMITS.argument_bytes),
			index > 0,
		) ||
		   (index == 0 && len(text) > int(language_service.DEFAULT_LIMITS.executable_bytes)) {
			return false
		}
		total_bytes += len(text)
	}
	return total_bytes <= int(language_service.DEFAULT_LIMITS.argument_bytes)
}

@(private)
environment_valid :: proc(values: json.Array) -> bool {
	if len(values) > int(language_service.DEFAULT_LIMITS.environment_entries) do return false
	total_bytes := 0
	for value, index in values {
		object, ok := value.(json.Object)
		if !ok || len(object) != 2 do return false
		key, key_ok := object_string(value, "key")
		entry, entry_ok := object_string(value, "value")
		if !key_ok || !entry_ok ||
		   !text_valid(key, int(language_service.DEFAULT_LIMITS.environment_bytes), false) ||
		   strings.index_byte(key, '=') >= 0 ||
		   !text_valid(entry, int(language_service.DEFAULT_LIMITS.environment_bytes), true) {
			return false
		}
		total_bytes += len(key) + 1 + len(entry)
		for previous in 0 ..< index {
			previous_key, previous_ok := object_string(values[previous], "key")
			if !previous_ok || key == previous_key do return false
		}
	}
	return total_bytes <= int(language_service.DEFAULT_LIMITS.environment_bytes)
}

@(private)
json_value_valid :: proc(value: json.Value, depth: int, values: ^int) -> bool {
	if values == nil || depth > int(language_service.DEFAULT_LIMITS.json_depth) ||
	   values^ >= MAX_JSON_VALUES {
		return false
	}
	values^ += 1
	#partial switch current in value {
	case json.Null, json.Integer, json.Float, json.Boolean, json.String:
		return true
	case json.Array:
		for entry in current {
			if !json_value_valid(entry, depth + 1, values) do return false
		}
		return true
	case json.Object:
		for key, entry in current {
			if !text_valid(key, language_service.MAX_NAME_BYTES, true) ||
			   !json_value_valid(entry, depth + 1, values) {
				return false
			}
		}
		return true
	case:
		return false
	}
}

@(private)
text_kind_valid :: proc(value: string, kind: Text_Kind) -> bool {
	switch kind {
	case .Filename:
		return value != "." && value != ".." &&
			strings.index_byte(value, '/') < 0 && strings.index_byte(value, '\\') < 0
	case .Suffix:
		return len(value) > 1 && value[0] == '.' &&
			strings.index_byte(value, '/') < 0 && strings.index_byte(value, '\\') < 0
	case .Root_Marker:
		if value[0] == '/' || value[0] == '\\' ||
		   (len(value) > 1 && value[1] == ':') || strings.contains_any(value, "*?[]{}") {
			return false
		}
		parts := strings.split(value, "/")
		defer delete(parts)
		for part in parts do if len(part) == 0 || part == ".." do return false
		return strings.index_byte(value, '\\') < 0
	case .Feature:
		_, ok := feature_from_string(value)
		return ok
	case .Ordinary:
		return true
	}
	return false
}

@(private)
text_valid :: proc(value: string, maximum: int, empty_ok: bool) -> bool {
	return (empty_ok || len(value) > 0) && len(value) <= maximum &&
		utf8.valid_string(value) && strings.index_byte(value, 0) < 0
}
