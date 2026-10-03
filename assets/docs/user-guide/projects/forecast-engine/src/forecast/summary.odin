// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package forecast

summarize :: proc(observations: []Observation) -> Summary {
	if len(observations) == 0 {
		return {}
	}

	total := 0.0
	for observation in observations {
		total += observation.temperature_c
	}

	return {
		station = observations[0].station,
		sample_count = len(observations),
		average_temperature_c = total / f64(len(observations)),
	}
}
