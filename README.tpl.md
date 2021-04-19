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

## Using with Nix Flakes

Initialize flakes within your repo by running:

``` bash
nix flake init -t github:nmattia/naersk
nix flake lock
```

Alternatively, copy this `flake.nix` into your repo.

``` nix
{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nmattia/naersk";
  };

  outputs = { self, nixpkgs, utils, naersk }:
    utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages."${system}";
      naersk-lib = naersk.lib."${system}";
    in rec {
      # `nix build`
      packages.my-project = naersk-lib.buildPackage {
        pname = "my-project";
        root = ./.;
      };
      defaultPackage = packages.my-project;

      # `nix run`
      apps.my-project = utils.lib.mkApp {
        drv = packages.my-project;
      };
      defaultApp = apps.my-project;

      # `nix develop`
      devShell = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [ rustc cargo ];
      };
    });
}
```

If you want to use a specific toolchain version instead of the latest stable
available in nixpkgs, you can use mozilla's nixpkgs overlay in your flake.

``` nix
{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nmattia/naersk";
    mozillapkgs = {
      url = "github:mozilla/nixpkgs-mozilla";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, naersk, mozillapkgs }:
    utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages."${system}";

      # Get a specific rust version
      mozilla = pkgs.callPackage (mozillapkgs + "/package-set.nix") {};
      rust = (mozilla.rustChannelOf {
        date = "2020-01-01"; # get the current date with `date -I`
        channel = "nightly";
        sha256 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      }).rust;

      # Override the version used in naersk
      naersk-lib = naersk.lib."${system}".override {
        cargo = rust;
        rustc = rust;
      };
    in rec {
      # `nix build`
      packages.my-project = naersk-lib.buildPackage {
        pname = "my-project";
        root = ./.;
      };
      defaultPackage = packages.my-project;

      # `nix run`
      apps.my-project = utils.lib.mkApp {
        drv = packages.my-project;
      };
      defaultApp = apps.my-project;

      # `nix develop`
      devShell = pkgs.mkShell {
        # supply the specific rust version
        nativeBuildInputs = [ rust ];
      };
    });
}
```
