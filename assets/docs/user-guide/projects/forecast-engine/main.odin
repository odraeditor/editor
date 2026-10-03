// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:fmt"

import "./src/forecast"

main :: proc() {
	observations := forecast.sample_observations()
	summary := forecast.summarize(observations[:])

	fmt.printf("Station: %s\n", summary.station)
	fmt.printf("Samples: %d\n", summary.sample_count)
	fmt.printf("Average: %.1f C\n", summary.average_temperature_c)
}
