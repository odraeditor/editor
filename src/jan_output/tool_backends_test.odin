// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:strings"
import "core:testing"

/* Verifies PDF, ODT, and Info plans remain ordered, bounded, and non-effectful. */
@(test)
tool_backend_plans_are_complete_before_process_handoff :: proc(t: ^testing.T) {
	scope := output_test_scope()
	tools := tool_backend_test_tools(scope.provider_generation)
	request := Tool_Backend_Request {operation_id = 51, scope = scope, backend = .Pdf,
		input_resource_id = 101, output_resource_id = 103, provider_generation = scope.provider_generation,
		explicit = true, validate_output = true, limits = DEFAULT_LIMITS}
	steps: [4]Tool_Step
	temporaries: [5]Temporary_Resource
	plan, ok, _ := prepare_tool_backend_plan(request, tools[:], steps[:], temporaries[:])
	testing.expect(t, ok)
	testing.expect(t, plan.complete)
	testing.expect_value(t, plan.step_count, u16(3))
	testing.expect_value(t, plan.temporary_count, u16(4))
	testing.expect_value(t, steps[0].kind, Tool_Step_Kind.Compile)
	testing.expect_value(t, steps[1].sequence, u16(2))
	testing.expect_value(t, steps[2].kind, Tool_Step_Kind.Validate)
	testing.expect_value(t, temporaries[0].kind, Temporary_Resource_Kind.Directory)
	testing.expect_value(t, temporaries[3].kind, Temporary_Resource_Kind.Log)

	request.backend = .Odt
	plan, ok, _ = prepare_tool_backend_plan(request, tools[:], steps[:], temporaries[:])
	testing.expect(t, ok)
	testing.expect_value(t, steps[0].kind, Tool_Step_Kind.Package)
	request.backend = .Info
	plan, ok, _ = prepare_tool_backend_plan(request, tools[:], steps[:], temporaries[:])
	testing.expect(t, ok)
	testing.expect_value(t, steps[0].kind, Tool_Step_Kind.Compile)
}

/* Verifies unavailable, stale, and untrusted tools cannot form executable plans. */
@(test)
tool_backend_plans_require_exact_trusted_availability :: proc(t: ^testing.T) {
	scope := output_test_scope()
	tools := tool_backend_test_tools(scope.provider_generation)
	request := Tool_Backend_Request {operation_id = 53, scope = scope, backend = .Pdf,
		input_resource_id = 101, output_resource_id = 103, provider_generation = scope.provider_generation,
		explicit = true, limits = DEFAULT_LIMITS}
	steps: [3]Tool_Step
	temporaries: [4]Temporary_Resource
	tools[0].state = .Unavailable
	_, ok, failure := prepare_tool_backend_plan(request, tools[:], steps[:], temporaries[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	tools[0].state = .Available
	tools[0].generation -= 1
	_, ok, failure = prepare_tool_backend_plan(request, tools[:], steps[:], temporaries[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	tools[0].generation = scope.provider_generation
	tools[0].trusted = false
	_, ok, failure = prepare_tool_backend_plan(request, tools[:], steps[:], temporaries[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
}

/* Verifies ODT structure and cleanup obligations reject partial states. */
@(test)
odt_and_cleanup_contracts_are_exact :: proc(t: ^testing.T) {
	request := Odt_Package_Request {operation_id = 55, style_resource_id = 7, style_revision = 11,
		template_resource_id = 13, template_revision = 17, media_count = 2, math_count = 1,
		link_count = 3, content_bytes = 4096, converter_required = true}
	testing.expect(t, odt_package_request_is_valid(request))
	request.template_revision = 0
	testing.expect(t, !odt_package_request_is_valid(request))
	plan := Tool_Backend_Plan {operation_id = 55, backend = .Odt, provider_generation = 3,
		step_count = 2, temporary_count = 2, cleanup_count = 2, complete = true}
	temporaries := []Temporary_Resource {
		{resource_id = 1, kind = .Directory, created = true, cleaned = true},
		{resource_id = 2, kind = .Log, created = true},
	}
	testing.expect(t, !tool_backend_cleanup_complete(plan, temporaries))
	temporaries[1].cleaned = true
	testing.expect(t, tool_backend_cleanup_complete(plan, temporaries))
}

/* Verifies LaTeX, Beamer, Texinfo, and man source is deterministic and escaped. */
@(test)
tool_source_backends_render_deterministic_text :: proc(t: ^testing.T) {
	fragments := [4]Native_Fragment {
		{kind = .Text, text = "Usage & Safety"},
		{kind = .Text, text = "Read "},
		{kind = .Strong, text = "carefully"},
		{kind = .Link, text = "Odra", target = "https://example.test/a_b"},
	}
	blocks := [2]Native_Block {
		{kind = .Heading, level = 1, fragment_count = 1},
		{kind = .Paragraph, fragment_start = 1, fragment_count = 3},
	}
	document := Native_Document {title = "Tool & Backends", language = "en", blocks = blocks[:], fragments = fragments[:]}
	destination: [8_192]u8
	latex, ok, _ := render_tool_source_backend(57, .Latex, document, destination[:])
	testing.expect(t, ok)
	testing.expect_value(t, latex.backend, Tool_Backend.Latex)
	latex_text := string(destination[:int(latex.byte_count)])
	testing.expect(t, strings.contains(latex_text, "\\title{Tool \\& Backends}"))
	testing.expect(t, strings.contains(latex_text, "\\href{https://example.test/a\\_b}{Odra}"))
	beamer, beamer_ok, _ := render_tool_source_backend(58, .Beamer, document, destination[:])
	testing.expect(t, beamer_ok)
	testing.expect(t, strings.contains(string(destination[:int(beamer.byte_count)]), "\\begin{frame}[fragile]{Usage \\& Safety}"))
	texinfo, texinfo_ok, _ := render_tool_source_backend(59, .Texinfo, document, destination[:])
	testing.expect(t, texinfo_ok)
	testing.expect(t, strings.contains(string(destination[:int(texinfo.byte_count)]), "@strong{carefully}"))
	man, man_ok, _ := render_tool_source_backend(60, .Man_Page, document, destination[:])
	testing.expect(t, man_ok)
	testing.expect(t, strings.contains(string(destination[:int(man.byte_count)]), ".SH \"Usage & Safety\""))
}

/* Verifies iCalendar escaping, task state, privacy, and bounds. */
@(test)
tool_calendar_output_is_stable_and_restrictive :: proc(t: ^testing.T) {
	events := []Calendar_Event {
		{uid = "task-1@example.test", summary = "Review, ship", description = "Line 1\nLine 2",
		 location = "Room; 2", start_utc = "20260917T080000Z", categories = "JAN,ODRA",
		 task = true, completed = true, private = true},
	}
	destination: [2_048]u8
	result, ok, _ := render_icalendar(61, events, destination[:])
	testing.expect(t, ok)
	testing.expect_value(t, result.backend, Tool_Backend.ICalendar)
	text := string(destination[:int(result.byte_count)])
	testing.expect(t, strings.contains(text, "BEGIN:VTODO\r\n"))
	testing.expect(t, strings.contains(text, "SUMMARY:Review\\, ship\r\n"))
	testing.expect(t, strings.contains(text, "DESCRIPTION:Line 1\\nLine 2\r\n"))
	testing.expect(t, strings.contains(text, "STATUS:COMPLETED\r\nCLASS:PRIVATE\r\n"))
	events[0].completed = true
	events[0].task = false
	_, invalid_ok, failure := render_icalendar(62, events, destination[:])
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
	events[0].task = true
	events[0].start_utc = "2026-09-17T08:00Z"
	_, invalid_ok, failure = render_icalendar(63, events, destination[:])
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, failure.code, Failure_Code.Malformed)
}

/* Verifies source blocks cannot terminate adapter-owned containers or inject roff commands. */
@(test)
tool_source_blocks_neutralize_adapter_commands :: proc(t: ^testing.T) {
	fragments := [1]Native_Fragment {{kind = .Text, text = "\\end{verbatim}"}}
	blocks := [1]Native_Block {{kind = .Source, fragment_count = 1}}
	document := Native_Document {title = "Safety", language = "en", blocks = blocks[:], fragments = fragments[:]}
	destination: [2_048]u8
	_, ok, failure := render_tool_source_backend(64, .Latex, document, destination[:])
	testing.expect(t, !ok)
	testing.expect_value(t, failure.code, Failure_Code.Unsupported)

	fragments[0].text = "@bye"
	texinfo, texinfo_ok, _ := render_tool_source_backend(65, .Texinfo, document, destination[:])
	testing.expect(t, texinfo_ok)
	testing.expect(t, strings.contains(string(destination[:int(texinfo.byte_count)]), "@@bye"))

	fragments[0].text = ".danger\n'next"
	man, man_ok, _ := render_tool_source_backend(66, .Man_Page, document, destination[:])
	testing.expect(t, man_ok)
	testing.expect(t, strings.contains(string(destination[:int(man.byte_count)]), "\\&.danger\n\\&'next"))
}

/* Verifies source availability remains independent from optional final tools. */
@(test)
tool_backend_availability_is_inspectable :: proc(t: ^testing.T) {
	tools := tool_backend_test_tools(71)
	tools[0].state = .Unavailable
	records := tool_backend_inspection(tools[:], 71)
	for record in records {
		if record.backend == .Beamer || record.backend == .Latex {
			testing.expect_value(t, record.state, Availability_State.Available)
			testing.expect(t, record.source_available)
		}
		if record.backend == .Pdf {
			testing.expect_value(t, record.state, Availability_State.Unavailable)
			testing.expect(t, !record.source_available)
		}
	}
}

@(private = "file")
tool_backend_test_tools :: proc(generation: Provider_Generation) -> [5]Tool_Descriptor {
	return {
		{identity = "pdflatex", version = "test-1", generation = generation, state = .Available, trusted = true},
		{identity = "odra-odt-packager", version = "test-1", generation = generation, state = .Available, trusted = true},
		{identity = "makeinfo", version = "test-1", generation = generation, state = .Available, trusted = true},
		{identity = "groff", version = "test-1", generation = generation, state = .Available, trusted = true},
		{identity = "icalendar-validator", version = "test-1", generation = generation, state = .Available, trusted = true},
	}
}
