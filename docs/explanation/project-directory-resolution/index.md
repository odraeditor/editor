<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Opening a Dir Checks Local Project Authority

Opening a filesystem root should always succeed as a Dir when path policy
admits it. Project recognition is an additional exact check, not a prerequisite
for editing and not an invitation to create metadata.

Odra checks `<dir>/.odra/project.rkt` because that record is colocated with the
root it identifies. The stored normalized root, identity, and generation must
all validate before the session publishes a Project projection. Missing or
invalid metadata leaves the root as an ordinary Dir.

This avoids filesystem-wide discovery, repository-marker inference, and
ambiguous global matches. The global discovery catalog can accelerate listing
and Workspace resolution, but it cannot override a valid local record or make
an invalid local record authoritative.

The same rule makes failure containment straightforward. A stale discovery
reference, unavailable root, malformed record, or generation mismatch is
reported without replacing the active session composition. Explicit promotion
or migration is required before new local identity can appear.
