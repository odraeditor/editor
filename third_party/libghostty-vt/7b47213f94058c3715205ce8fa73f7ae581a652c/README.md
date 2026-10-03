# libghostty-vt 7b47213f

This directory contains the repository-controlled inputs for Odra's terminal
emulator boundary.

- Upstream: `ghostty-org/ghostty`
- Commit: `7b47213f94058c3715205ce8fa73f7ae581a652c`
- Library version: `0.1.0-dev`
- License: MIT
- C ABI manifest schema: `1`
- Build toolchain: Zig `0.16.0`
- Build profile: `ReleaseFast`, SIMD disabled

`MANIFEST` is the admission contract consumed by
`scripts/check-terminal-dependency.sh`. `SHA256SUMS` protects the admitted
license, public C headers, source distribution, package-cache inputs, and
toolchain archive. `scripts/build-terminal-vendor.sh` extracts those inputs
under `.build/` and disables network access through an intentionally invalid
proxy while Zig produces the static library.

The application never imports these headers directly. The repository-owned
terminal emulator adapter is the only consumer of this upstream C surface.
