<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Package Catalog Curator Kit

This kit is a neutral starting point for an independent Odra package catalog.
It uses the same public records and validation contracts as the catalog bundled
with Odra. Creating an independent catalog requires no official designation or
approval from the Odra maintainer.

Copy `template/catalog.rkt` and the `policy/` directory into the catalog's own
governance repository. Replace every `catalog.example` coordinate, placeholder
digest, public verification key, identity, timestamp, and policy statement
before publishing anything.

The template constructs checked examples of:

- catalog identity, root and publisher authorization;
- origin and exact mirror endpoints;
- human curator authority and policy references;
- package release, submission, attributable assessment, and human decision;
- curation assertion, draft security advisory, and unsigned snapshot.

The unsigned values are authoring inputs. Signing is an external custody
operation: use the offline exchange workflow and add only resulting public
signatures to publication records. Never place signing material or deployment
credentials in the catalog repository.

The examples deliberately use `org.example` identities and placeholder public
keys. A copied display name, hostname, repository, or template never grants the
official designation, which is pinned locally to one compiled catalog identity.
