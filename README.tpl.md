# Naersk

[![GitHub Actions](https://github.com/nmattia/naersk/workflows/test/badge.svg?branch=master)](https://github.com/nmattia/naersk/actions)

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
described below. Any attribute that is _not_ listed below will be forwarded _as
is_ to `stdenv.mkDerivation`. When the argument passed in _not_ an attribute
set, e.g.

``` nix
naersk.buildPackage theArg
```

it is converted to an attribute set equivalent to `{ root = theArg; }`.

GEN_CONFIGURATION

## Using naersk with nixpkgs-mozilla

The [nixpkgs-mozilla](https://github.com/mozilla/nixpkgs-mozilla) overlay
provides nightly versions of `rustc` and `cargo`. Below is an example setup for
using it with naersk:

``` nix
let
  sources = import ./nix/sources.nix;
  nixpkgs-mozilla = import sources.nixpkgs-mozilla;
  pkgs = import sources.nixpkgs {
    overlays =
      [
        nixpkgs-mozilla
        (self: super:
            {
              rustc = self.latest.rustChannels.nightly.rust;
              cargo = self.latest.rustChannels.nightly.rust;
            }
        )
      ];
  };
  naersk = pkgs.callPackage sources.naersk {};
in
naersk.buildPackage ./my-package
```

[cargo]: https://crates.io/
[niv]: https://github.com/nmattia/niv
