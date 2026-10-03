// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package forecast

Observation :: struct {
	station:       string,
	temperature_c: f64,
}

Summary :: struct {
	station:               string,
	sample_count:          int,
	average_temperature_c: f64,
}

sample_observations :: proc() -> [3]Observation {
	return [3]Observation {
		{station = "Market Square", temperature_c = 18.5},
		{station = "Market Square", temperature_c = 20.0},
		{station = "Market Square", temperature_c = 21.5},
	}
}
