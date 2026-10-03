#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../src/report.rkt")

;; The rendered report keeps the station, sample count, and average together so
;; a regression in any public field produces a meaningful failure.
(check-equal?
 (render-report "Market Square" 3 20.0)
 "Station: Market Square\nSamples: 3\nAverage: 20.0 C"
 "renders one complete forecast report")
