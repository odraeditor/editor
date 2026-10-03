// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "core:testing"

when ODIN_OS == .Windows {
	@(private)
	PRESENTATION_TEST_ROOT :: "C:/work"
	@(private)
	PRESENTATION_TEST_VOLUME :: "C:/"
} else {
	@(private)
	PRESENTATION_TEST_ROOT :: "/work"
	@(private)
	PRESENTATION_TEST_VOLUME :: "/"
}

// Launch relevance must not mistake a neighboring path prefix or an unrelated file for the selected context.
@(test)
startup_scope :: proc(t: ^testing.T) {
	root :: PRESENTATION_TEST_ROOT
	cases := []struct {
		name: string,
		source: string,
		exact_file: string,
		roots: []string,
		matches: bool,
	}{
		{"same file", root + "/a/one.txt", root + "/a/one.txt", nil, true},
		{"different file", root + "/a/two.txt", root + "/a/one.txt", {root + "/a"}, false},
		{"nested source", root + "/a/notes/one.txt", "", {root + "/a"}, true},
		{"unrelated project", root + "/c/one.txt", "", {root + "/a", root + "/b"}, false},
		{"neighboring prefix", root + "/ab/one.txt", "", {root + "/a"}, false},
		{"second workspace root", root + "/b/one.txt", "", {root + "/a", root + "/b"}, true},
		{"trailing separator", root + "/a/one.txt", "", {root + "/a/"}, true},
		{"no launch context", root + "/a/one.txt", "", nil, false},
		{"untitled candidate", "", "", {root}, false},
		{"relative candidate", "a/one.txt", "", {root}, false},
		{"relative root", root + "/a/one.txt", "", {"a"}, false},
		{"selected root", root + "/a", "", {root + "/a"}, true},
		{"filesystem root", root + "/a/one.txt", "", {PRESENTATION_TEST_VOLUME}, true},
	}
	for scenario in cases {
		testing.expectf(t, startup_source_matches(scenario.source, scenario.exact_file, scenario.roots) == scenario.matches, "%s", scenario.name)
	}
	when ODIN_OS != .Windows {
		testing.expect(t, !startup_source_matches(root + "/a\\sibling.txt", "", {root + "/a"}))
	}
}
