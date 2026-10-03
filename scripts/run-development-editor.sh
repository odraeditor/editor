#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.


set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
development_binary="${repository_root}/.build/odra-development"
development_configuration_home="${ODRA_DEVELOPMENT_XDG_CONFIG_HOME:-}"

if [[ ! -x "${development_binary}" ]]; then
  echo "Development executable is missing; run make development-build." >&2
  exit 1
fi

if [[ -n "${development_configuration_home}" ]]; then
  export XDG_CONFIG_HOME="${development_configuration_home}"
fi
unset development_configuration_home ODRA_DEVELOPMENT_XDG_CONFIG_HOME

exec "${development_binary}" "$@"
