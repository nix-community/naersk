# Naersk

[![GitHub Actions](https://github.com/nmattia/naersk/workflows/.github/workflows/test.yml/badge.svg)](https://github.com/nmattia/naersk/actions)

Nix support for building [cargo] crates.

* [Install](#install)
* [Configuration](#configuration)
* [Comparison](#install)

## Install

Use [niv]:

``` shell
$ niv add nmattia/naersk
```

And then

``` nix
let
    pkgs = import <nixpkgs> {};
    sources = import ./nix/sources.nix;
    naersk = pkgs.callPackage sources.naersk {};
in naersk.buildPackage ./path/to/rust
```

_NOTE_: `./path/to/rust/` should contain a `Cargo.lock`.

## Configuration

The `buildPackage` function also accepts an attribute set. The attributes are
described below. When the argument passed in _not_ an attribute set, e.g.

``` nix
naersk.buildPackage theArg
```

it is converted to an attribute set equivalent to `{ root = theArg; }`.

GEN_CONFIGURATION

## Comparison

There are two other notable Rust frameworks in Nix: `rustPlatform` and
`carnix`.

`naersk` uses `cargo` directly, as opposed to `carnix` which emulates `cargo`'s
build logic. Moreover `naersk` sources build information directly from the
project's `Cargo.lock` which makes any code generation unnecessary.

For the same reason, `naersk` does not need anything like `rustPlatform`'s
`cargoSha256`. All crates are downloaded using the `sha256` checksums provided
in the project's `Cargo.lock`.

Finally `naersk` supports incremental builds by first performing a
dependency-only build, and _then_ a build that depends on the top-level crate's
code and configuration.

[cargo]: https://crates.io/
[niv]: https://github.com/nmattia/niv
