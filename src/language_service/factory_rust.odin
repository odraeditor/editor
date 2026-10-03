// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

/* FACTORY_RUST_ANALYZER_IDENTITY is the maintained Rust service identity. */
FACTORY_RUST_ANALYZER_IDENTITY :: "rust-analyzer"
/* FACTORY_RUST_ANALYZER_EXECUTABLE is the controlled executable lookup name. */
FACTORY_RUST_ANALYZER_EXECUTABLE :: "rust-analyzer"
/* FACTORY_RUST_ANALYZER_RELEASE is the validated maintained acceptance release. */
FACTORY_RUST_ANALYZER_RELEASE :: "2026-09-14"
/* FACTORY_RUST_ANALYZER_RELEASE_DIGEST pins the Linux x86-64 acceptance asset. */
FACTORY_RUST_ANALYZER_RELEASE_DIGEST :: "7609ba53f85cd80a3bde77a4b2e94e304d0f94650e4f4cffc061b9bca454ba75"
/* FACTORY_RUST_ANALYZER_ROOT_MARKERS select the nearest Cargo package root. */
FACTORY_RUST_ANALYZER_ROOT_MARKERS := [1]string{"Cargo.toml"}
