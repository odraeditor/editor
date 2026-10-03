<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Package Catalogs

Use these procedures to inspect, enroll, refresh, disable, replace, or remove a
catalog without changing installed packages.

## Inspect Registrations

Run `M-x package-catalog-list`, copy the exact registration identifier from the
result, then run `M-x package-catalog-describe` and enter that identifier.
Verify its catalog identity, designation, enabled state, refresh state, and
confirmed snapshot.

## Enroll an Independent Catalog

1. Obtain a publication directory containing `catalog.rktd`, `snapshot.rktd`,
   and `assertions.rktd` from one KASPER-compatible publication.
2. Run `M-x package-catalog-add` and enter the publication directory.
3. Review the decoded identity, generated registration identifier, snapshot,
   and assertion count, then confirm the proposal.
4. The confirmed addition performs its first verified refresh. Run
   `M-x package-catalog-describe` with the generated registration identifier.

Explicit command enrollment currently accepts a local publication path.
Checked personal configuration remains the path for HTTPS registrations and
opaque credential references; credential values do not belong in catalog
configuration or diagnostics.

## Configure with Racket

Personal configuration may export one complete checked configuration:

```racket
#lang racket/base
(require odra/package-catalogs)
(provide odra-package-catalogs)

(define catalog-id "<64 lowercase hexadecimal characters>")
(define trust
  (package-catalog-trust-reference
   #:id "<64 lowercase hexadecimal characters>"
   #:catalog-id catalog-id))
(define endpoint
  (package-catalog-endpoint
   #:id "independent-origin"
   #:catalog-id catalog-id
   #:uri "https://catalog.example/snapshots/current.rktd"
   #:credential-reference "ODRA_CATALOG_AUTHORIZATION"))
(define registration
  (package-catalog-registration
   #:id "independent"
   #:kind 'independent
   #:trust trust
   #:endpoints (list endpoint)
   #:precedence 20))
(define odra-package-catalogs
  (package-catalog-configuration
   #:registrations (list registration)))
```

This value replaces the complete registration set. Export an empty checked
configuration to disable all defaults deliberately. Omitting the export leaves
the factory configuration in effect.

For a private endpoint, arrange for the process that launches Odra to inherit
the referenced environment variable. Its value is the complete HTTP
`Authorization` value expected by the server, such as a bearer scheme and
token. Keep the value in a local secret manager or launcher environment; do not
write it into the Racket configuration, repository, shell command history, or
catalog publication. Public endpoints omit `#:credential-reference`.

Odra resolves this value only while refreshing the configured endpoint and its
content-addressed assertion artifact. Missing or rejected credentials leave
the last confirmed catalog snapshot available for offline resolution.

## Disable, Replace, or Remove

- Run `M-x package-catalog-disable` to stop refresh and resolution while
  retaining registration history. Enter the exact registration identifier and
  confirm.
- Replace an endpoint only after confirming the same catalog identity at the
  new location. A hostname change does not rotate trust.
- Run `M-x package-catalog-remove` to remove the registration and its active
  resolution input. Enter the exact registration identifier and confirm.
  Installed packages remain installed.

## Recover Failures

Run `M-x package-catalog-doctor`. Correct the reported identity, endpoint,
credential reference, signature, history, expiry, mirror divergence, or
resource failure. Odra retains the last confirmed state on refresh failure and
quarantines corrupt local records instead of accepting partial state.

See the [Package Catalog Reference](../../reference/package-catalogs/index.md)
for exact records, limits, states, and failure behavior.
