# Naersk

[![GitHub Actions](https://img.shields.io/github/checks-status/nix-community/naersk/master)](https://github.com/nix-community/naersk/actions)

Build Rust projects with ease!

- [Introduction](#introduction)
- [Setup](#setup)
- [Usage](#usage)
- [Examples](#examples)
- [Tips & Tricks](#tips--tricks)

Status: project's working!

## Introduction

Naersk is a [Nix](https://nixos.org/explore.html) library for building Rust
projects - basically, you write:

```
naersk.buildPackage {
  src = ./.; # Wherever your Cargo.lock and the rest of your source code are
}
```

... and that turns your code into a Nix derivation which you can, for instance,
include in your system:

```
environment.systemPackages = [
  (naersk.buildPackage {
    src = ./my-cool-app;
  })
];

# (see below for more complete examples)
```

Under the hood, `buildPackage` parses `Cargo.lock`, downloads all dependencies,
and compiles your application, fully utilizing Nix's sandboxing and caching
abilities; so, with a pinch of salt, Naersk is `cargo build`, but inside Nix!

If you're using Hydra, you can rely on Naersk as well because it doesn't use
IFD - all the parsing happens directly inside Nix code.

## Setup

### Using Flakes

```shell
$ nix flake init -t github:nix-community/naersk
$ nix flake lock
```

Alternatively, store this as `flake.nix` in your repository:

```nix
{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, flake-utils, naersk, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = (import nixpkgs) {
          inherit system;
        };

        naersk' = pkgs.callPackage naersk {};

      in rec {
        # For `nix build` & `nix run`:
        defaultPackage = naersk'.buildPackage {
          src = ./.;
        };

        # For `nix develop` (optional, can be skipped):
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ rustc cargo ];
        };
      }
    );
}
```

This assumes `flake.nix` is created next to `Cargo.toml` & `Cargo.lock` - if
that's not the case for you, adjust `./.` in `naersk'.buildPackage`.

Note that Naersk by default ignores the `rust-toolchain` file, using whatever
Rust compiler version is present in `nixpkgs`.

If you have a custom `rust-toolchain` file, you can make Naersk use it this way:

```nix
{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";

    nixpkgs-mozilla = {
      url = "github:mozilla/nixpkgs-mozilla";
      flake = false;
    };
  };

  outputs = { self, flake-utils, naersk, nixpkgs, nixpkgs-mozilla }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = (import nixpkgs) {
          inherit system;

          overlays = [
            (import nixpkgs-mozilla)
          ];
        };

        toolchain = (pkgs.rustChannelOf {
          rustToolchain = ./rust-toolchain;
          sha256 = "";
          #        ^ After you run `nix build`, replace this with the actual
          #          hash from the error message
        }).rust;

        naersk' = pkgs.callPackage naersk {
          cargo = toolchain;
          rustc = toolchain;
        };

      in rec {
        # For `nix build` & `nix run`:
        defaultPackage = naersk'.buildPackage {
          src = ./.;
        };

        # For `nix develop` (optional, can be skipped):
        devShell = pkgs.mkShell {
          nativeBuildInputs = [ toolchain ];
        };
      }
    );
}
```

### Using Niv

```shell
$ niv init
$ niv add nix-community/naersk
```

... and then create `default.nix` with:

```nix
let
  pkgs = import <nixpkgs> {};
  sources = import ./nix/sources.nix;
  naersk = pkgs.callPackage sources.naersk {};

in
  naersk.buildPackage ./.
```

This assumes `default.nix` is created next to `Cargo.toml` & `Cargo.lock` - if
that's not the case for you, adjust `./.` in `naersk.buildPackage`.

Note that Naersk by default ignores the `rust-toolchain` file, using whatever
Rust compiler version is present in `nixpkgs`.

If you have a custom `rust-toolchain` file, you can make Naersk use it this way:

```shell
$ niv add mozilla/nixpkgs-mozilla
```

... and then:

```nix
let
  sources = import ./nix/sources.nix;
  nixpkgs-mozilla = import sources.nixpkgs-mozilla;

  pkgs = import sources.nixpkgs {
    overlays = [
      nixpkgs-mozilla
    ];
  };

  toolchain = (pkgs.rustChannelOf {
    rustToolchain = ./rust-toolchain;
    sha256 = "";
    #        ^ After you run `nix-build`, replace this with the actual
    #          hash from the error message
  }).rust;

  naersk = pkgs.callPackage sources.naersk {
    cargo = toolchain;
    rustc = toolchain;
  };

in
  naersk.buildPackage ./.
```

## Usage

Naersk provides a function called `buildPackage` that takes an attribute set
describing your application's directory, its dependencies etc. - in general, the
usage is:

```nix
naersk.buildPackage {
  # Assuming there's `Cargo.toml` right in this directory:
  src = ./.;

  someOption = "yass";
  someOtherOption = false;
  CARGO_ENVIRONMENTAL_VARIABLE = "test";
}
```

Some of the options (described below) are used by Naersk to affect the building
process, rest is passed-through into `mkDerivation`.

Note that you shouldn't call `overrideAttrs` on a derivation built by Naersk
(see the [note on `overrideAttrs`](#note-on-overrideattrs) below).

### `buildPackage`'s parameters

GEN_CONFIGURATION

### Note on `overrideAttrs`

When you call `buildPackage`, Naersk internally builds two derivations: one that
compiles all of your application's dependencies and then another one that
compiles just your application.

It's done this way to improve compilation speed when you build your program for
the second time etc., because then if only your application's code has changed
(and `Cargo.toml` & `Cargo.lock` stayed the same), Naersk doesn't have to
rebuild your dependencies.

This mechanism has a shortcoming, though - in particular, you shouldn't use
`overrideAttrs` to inject something into the build environment:

```nix
{ pkgs, naersk, ... }:

let
  app = naersk.buildPackage {
    src = ./.;
  };

in
app.overrideAttrs (p: {
  buildInputs = p.buildInputs + [ pkgs.cmake ];
  SOME_ENV_VAR = "yes";
})
```

... because that will inject it only into the app-derivation, leaving it
inaccessible for your dependencies to use.

Instead, you should pass the parameters directly into the `buildPackage`
invocation:

```nix
{ pkgs, naersk, ... }:

naersk.buildPackage {
  src = ./.;
  buildInputs = [ pkgs.cmake ];
  SOME_ENV_VAR = "yes";
}
```

... or use `override`, if the names conflict with something already reserved by
Naersk:

```nix
{ pkgs, naersk, ... }:

naersk.buildPackage {
  src = ./.;

  override = p: {
    # ...
  };
}
```

... or, if you really have to call `overrideAttrs` on the final derivation, you
should disable the incremental-compilation mechanism:

```nix
{ pkgs, naersk, ... }:

let
  app = naersk.buildPackage {
    src = ./.;
    singleStep = true; # here
  };

in
app.overrideAttrs (p: {
  buildInputs = p.buildInputs + [ pkgs.cmake ];
})
```

(it's just an optimization so there's no harm in disabling it, Naersk should
produce the same binary anyway.)

## Examples

See: [./examples](./examples).

## Tips & Tricks

### Building a particular example

If you want to build only a particular example, use:

```nix
naersk.buildPackage {
  pname = "your-example-name";
  src = ./.;

  overrideMain = old: {
    preConfigure = ''
      cargo_build_options="$cargo_build_options --example your-example-name"
    '';
  };
}
```

### Using CMake

If your application uses CMake, the build process might fail, saying:

```
CMake Error: The current CMakeCache.txt directory ... is different than the directory ... where CMakeCache.txt was created.
```

You can fix this problem by removing stale `CMakeCache.txt` files before the
build:

```nix
naersk.buildPackage {
  # ...

  preBuild = ''
    find \
        -name CMakeCache.txt \
        -exec rm {} \;
  '';
}
```

([context](https://github.com/nix-community/naersk/pull/288))
