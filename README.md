### Notices

#### Mirrors

Repository:
- [Codeberg](https://codeberg.org/paveloom-z/zig-gir-ffi)
- [GitHub](https://github.com/paveloom-z/zig-gir-ffi)
- [GitLab](https://gitlab.com/paveloom-g/zig/zig-gir-ffi)

#### Prerequisites

Make sure you have installed:

- Development libraries for
  - `gobject-introspection`
  - `libxml2`
- [Zig](https://ziglang.org) (`v0.10.1`)
- [Zigmod](https://github.com/nektro/zigmod)

Alternatively, you can use the [Nix flake](flake.nix) via `nix develop`.

#### Build

First, fetch the dependencies by running `zigmod fetch`.

To build the binary, run `zig build`. To run it, run `zig build run`.

See `zig build --help` for more build options.

#### Related

Similar projects:
- [DerryAlex/zig-gir-ffi](https://github.com/DerryAlex/zig-gir-ffi)
