// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

/* FACTORY_TYPESCRIPT_LANGUAGE_SERVER_IDENTITY is the shared JS/TS service identity. */
FACTORY_TYPESCRIPT_LANGUAGE_SERVER_IDENTITY :: "typescript-language-server"
/* FACTORY_TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE is the controlled executable lookup name. */
FACTORY_TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE :: "typescript-language-server"
/* FACTORY_TYPESCRIPT_LANGUAGE_SERVER_VERSION pins maintained acceptance. */
FACTORY_TYPESCRIPT_LANGUAGE_SERVER_VERSION :: "6.0.0"
/* FACTORY_TYPESCRIPT_VERSION pins the compiler service used by maintained acceptance. */
FACTORY_TYPESCRIPT_VERSION :: "6.0.3"
/* FACTORY_TYPESCRIPT_LANGUAGE_SERVER_ARGUMENTS is the shell-free launch vector tail. */
FACTORY_TYPESCRIPT_LANGUAGE_SERVER_ARGUMENTS := [1]string{"--stdio"}
/* FACTORY_TYPESCRIPT_ROOT_MARKERS select the nearest configured web project. */
FACTORY_TYPESCRIPT_ROOT_MARKERS := [3]string{"tsconfig.json", "jsconfig.json", "package.json"}

/* FACTORY_HTML_LANGUAGE_SERVER_IDENTITY is the maintained HTML service identity. */
FACTORY_HTML_LANGUAGE_SERVER_IDENTITY :: "vscode-html-language-server"
/* FACTORY_HTML_LANGUAGE_SERVER_EXECUTABLE is the controlled executable lookup name. */
FACTORY_HTML_LANGUAGE_SERVER_EXECUTABLE :: "vscode-html-language-server"
/* FACTORY_CSS_LANGUAGE_SERVER_IDENTITY is the maintained CSS service identity. */
FACTORY_CSS_LANGUAGE_SERVER_IDENTITY :: "vscode-css-language-server"
/* FACTORY_CSS_LANGUAGE_SERVER_EXECUTABLE is the controlled executable lookup name. */
FACTORY_CSS_LANGUAGE_SERVER_EXECUTABLE :: "vscode-css-language-server"
/* FACTORY_VSCODE_LANGSERVERS_VERSION pins maintained HTML/CSS acceptance. */
FACTORY_VSCODE_LANGSERVERS_VERSION :: "4.10.0"
/* FACTORY_VSCODE_LANGSERVER_ARGUMENTS is the shared shell-free launch vector tail. */
FACTORY_VSCODE_LANGSERVER_ARGUMENTS := [1]string{"--stdio"}
/* FACTORY_WEB_ROOT_MARKERS select the nearest package root. */
FACTORY_WEB_ROOT_MARKERS := [1]string{"package.json"}
