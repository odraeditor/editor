// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

/* FACTORY_RACKET_LANGUAGE_SERVER_IDENTITY is the maintained Racket service identity. */
FACTORY_RACKET_LANGUAGE_SERVER_IDENTITY :: "racket-langserver"

/* FACTORY_RACKET_LANGUAGE_SERVER_PACKAGE is the external Racket package identity. */
FACTORY_RACKET_LANGUAGE_SERVER_PACKAGE :: "racket-langserver"

/* FACTORY_RACKET_LANGUAGE_SERVER_CATALOG_CHECKSUM pins interoperability evidence. */
FACTORY_RACKET_LANGUAGE_SERVER_CATALOG_CHECKSUM :: "93efe35dcc07a7cc86c958f00497280744f0e75c"

/* FACTORY_RACKET_LANGUAGE_SERVER_ARGUMENTS is the shell-free launch vector tail. */
FACTORY_RACKET_LANGUAGE_SERVER_ARGUMENTS := [2]string{"-l", "racket-langserver"}
/* FACTORY_RACKET_ROOT_MARKERS select the nearest package root. */
FACTORY_RACKET_ROOT_MARKERS := [1]string{"info.rkt"}

/* FACTORY_GOPLS_IDENTITY is the maintained Go language-service identity. */
FACTORY_GOPLS_IDENTITY :: "gopls"
/* FACTORY_GOPLS_EXECUTABLE is the controlled executable lookup name. */
FACTORY_GOPLS_EXECUTABLE :: "gopls"
/* FACTORY_GOPLS_VERSION is the validated maintained acceptance version. */
FACTORY_GOPLS_VERSION :: "v0.23.0"
/* FACTORY_GOPLS_ARGUMENTS is the shell-free launch vector tail. */
FACTORY_GOPLS_ARGUMENTS := [1]string{"serve"}
/* FACTORY_GOPLS_ROOT_MARKERS select the nearest workspace or module root. */
FACTORY_GOPLS_ROOT_MARKERS := [2]string{"go.work", "go.mod"}
