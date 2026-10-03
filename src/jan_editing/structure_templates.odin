// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../editor"
import "../language"
import "core:unicode/utf8"

/* Template_Resolution identifies one factory or configured source-only expansion. */
Template_Resolution :: struct {
	key:                      string,
	template_context:         Template_Context,
	source:                   string,
	provider:                 string,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
	factory:                  bool,
}

/* Template_Expansion_Request binds one key and insertion point to exact state. */
Template_Expansion_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	key:                string,
	point:              editor.Byte_Offset,
	rewrite_generation: language.Jan_Rewrite_Generation,
}

/* template_resolve selects factory definitions before conflicting configured values. */
template_resolve :: proc(
	configuration: ^Editing_Configuration,
	scope: Scope,
	key: string,
) -> (Template_Resolution, bool, Failure) {
	if configuration == nil || !scope_is_valid(scope) || !editing_configuration_text_is_valid(key, 96) {
		return {}, false, editing_failure(.Expand_Template, .Invalid_Scope, scope)
	}
	descriptor, inspected := editing_configuration_inspect(configuration)
	if !inspected || descriptor.generation != scope.configuration_generation ||
	   descriptor.provider_generation != scope.provider_generation {
		return {}, false, editing_failure(.Expand_Template, .Stale, scope)
	}
	if source, template_context, found := template_factory_lookup(key); found {
		return {
			key = key,
			template_context = template_context,
			source = source,
			provider = "odra-factory",
			configuration_generation = descriptor.generation,
			provider_generation = descriptor.provider_generation,
			factory = true,
		}, true, {}
	}
	for index in 0 ..< int(descriptor.template_count) {
		template, found := editing_configuration_template(configuration, index)
		if found && template.key == key {
			return {
				key = template.key,
				template_context = template.template_context,
				source = template.source,
				provider = "racket-configuration",
				configuration_generation = descriptor.generation,
				provider_generation = descriptor.provider_generation,
			}, true, {}
		}
	}
	return {}, false, editing_failure(.Expand_Template, .Unavailable, scope)
}

/* template_expansion_plan_prepare creates one checked insertion transaction. */
template_expansion_plan_prepare :: proc(
	plan: ^language.Jan_Rewrite_Plan,
	analysis: ^language.Jan_Structural_Analysis,
	source: []u8,
	configuration: ^Editing_Configuration,
	request: Template_Expansion_Request,
	allocator := context.allocator,
) -> (resolution: Template_Resolution, ok: bool, failure: Failure) {
	if plan == nil || analysis == nil || request.operation_id == Operation_ID(0) ||
	   request.rewrite_generation == language.Jan_Rewrite_Generation(0) ||
	   u64(request.point) > u64(len(source)) || !utf8.valid_string(string(source)) ||
	   allocator.procedure == nil {
		return {}, false, editing_failure(.Expand_Template, .Invalid_Scope, request.scope)
	}
	resolved: bool
	resolution, resolved, failure = template_resolve(configuration, request.scope, request.key)
	if !resolved do return {}, false, failure
	nodes := language.jan_structural_analysis_nodes(analysis)
	usage, inspected := language.jan_structural_analysis_usage(analysis)
	if !inspected || usage.source_bytes != u64(len(source)) || len(nodes) == 0 ||
	   nodes[0].range.scope != request.scope.analysis {
		return {}, false, editing_failure(.Expand_Template, .Stale, request.scope)
	}
	owner, found := contextual_completion_owner(nodes, request.point)
	if !found || !template_context_admitted(resolution.template_context, owner.kind) {
		return {}, false, editing_failure(.Expand_Template, .Unavailable, request.scope)
	}
	root := nodes[0]
	if root.kind != .Document_Root || root.range.start != 0 || u64(root.range.end) != u64(len(source)) {
		return {}, false, editing_failure(.Expand_Template, .Stale, request.scope)
	}
	replacement, allocation_error := make([]u8, len(source) + len(resolution.source), allocator)
	if allocation_error != nil {
		return {}, false, editing_failure(.Expand_Template, .Allocation_Failed, request.scope)
	}
	defer delete(replacement, allocator)
	point := int(request.point)
	copy(replacement[:point], source[:point])
	copy(replacement[point:point + len(resolution.source)], transmute([]u8)resolution.source)
	copy(replacement[point + len(resolution.source):], source[point:])
	requests := []language.Jan_Rewrite_Request{{
		node_id = root.id,
		range = root.range,
		replacement = string(replacement),
	}}
	planned, jan_failure := language.jan_rewrite_plan_prepare(
		plan,
		analysis,
		source,
		request.rewrite_generation,
		requests,
		allocator = allocator,
	)
	if !planned do return {}, false, template_failure_from_language(jan_failure, request.scope)
	return resolution, true, {}
}

@(private)
template_factory_lookup :: proc(key: string) -> (string, Template_Context, bool) {
	switch key {
	case "h1":     return "* Heading\n", .Document, true
	case "ul":     return "- Item\n", .Document, true
	case "drawer": return ":NOTES:\n\n:END:\n", .Heading, true
	case "src":    return "#+begin_src \n\n#+end_src\n", .Document, true
	case "quote":  return "#+begin_quote\n\n#+end_quote\n", .Document, true
	case "table":  return "| column |\n|--------|\n|        |\n", .Document, true
	}
	return "", .Invalid, false
}

@(private)
template_context_admitted :: proc(template_context: Template_Context, kind: language.Jan_Node_Kind) -> bool {
	switch template_context {
	case .Document:  return kind == .Document_Root || kind == .Zeroth_Section || kind == .Section || kind == .Paragraph
	case .Heading:   return kind == .Heading || kind == .Section || kind == .Paragraph
	case .List:      return kind == .Plain_List || kind == .List_Item
	case .Drawer:    return kind == .Drawer || kind == .Property_Drawer
	case .Block:     return navigation_kind_is_block(kind)
	case .Table:     return kind == .Pipe_Table || kind == .Table_Row || kind == .Table_Cell
	case .Paragraph: return kind == .Paragraph || kind == .Plain_Text
	case .Invalid:
	}
	return false
}

@(private)
template_failure_from_language :: proc(jan: language.Jan_Failure, scope: Scope) -> Failure {
	code := Failure_Code.Invalid_Target
	#partial switch jan.code {
	case .Stale, .Incomplete: code = .Stale
	case .Limited: code = .Limited
	case .Allocation_Failed: code = .Allocation_Failed
	case .Malformed: code = .Malformed
	case .Cancelled: code = .Cancelled
	}
	return {
		operation = .Expand_Template,
		code = code,
		scope = scope,
		limit = jan.limit,
		actual = jan.actual,
	}
}
