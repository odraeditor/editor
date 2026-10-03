<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Package Catalog Federation Uses Explicit Trust Roots

Git and modern forges make package publication naturally distributed. They do
not determine which curator a client should trust. Odra therefore federates
catalogs through explicit local enrollment rather than a single global
registration authority or automatic discovery graph.

Each catalog has an identity derived from initial root public material. Its
policy, human curators, publisher authorizations, endpoints, signed snapshots,
and advisories remain separate records. A repository, domain, display name, or
copied catalog cannot inherit another catalog's identity. Moving governance to
a different forge or organization grants no new authority by itself.

Origins and mirrors separate authority from availability. An origin publishes
signed bytes; a mirror serves those exact bytes through another endpoint.
Clients verify identity, history, publisher threshold, digest, sequence,
policy, validity, and exact mirror agreement locally. A mirror may improve
availability but cannot curate or rewrite content.

Forks are equally explicit. Copying package selections and policy creates a
new catalog when root material changes. Both catalogs can remain configured,
and resolution preserves their attribution. Precedence selects among
compatible candidates; it does not suppress a conflict where the same release
identity names different immutable content.

Confirmed snapshots support bounded offline operation. Network failure keeps
the last confirmed unexpired state. Invalid or divergent new data is rejected
without destroying that state. Users can disable or remove a catalog without
uninstalling packages, and installed content does not become untrusted merely
because an endpoint is temporarily unavailable.

This design is indifferent to how many independent curation spaces exist. Odra
restricts only which identity it labels official. Technical validity comes
from the common protocol; enrollment and effective trust remain explicit local
choices.
