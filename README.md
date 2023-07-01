# Naersk

[![GitHub Actions](https://github.com/nix-community/naersk/workflows/test/badge.svg?branch=master)](https://github.com/nix-community/naersk/actions)

Build Rust projects with ease!

* [Introduction](#introduction)
* [Setup](#setup)
* [Usage](#usage)
* [Examples](#examples)
* [Tips & Tricks](#tips--tricks)

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

``` shell
$ nix flake init -t github:nix-community/naersk
$ nix flake lock
```

Alternatively, store this as `flake.nix` in your repository:

``` nix
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

``` nix
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

``` shell
$ niv init
$ niv add nix-community/naersk
```

... and then create `default.nix` with:

``` nix
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

``` shell
$ niv add mozilla/nixpkgs-mozilla
```

... and then:

``` nix
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
describing your application's directory, its dependencies etc.; in general, the
usage is:

``` nix
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

### `buildPackage`'s parameters

| Attribute | Description |
| - | - |
| `name` | The name of the derivation. |
| `version` | The version of the derivation. |
| `src` | Used by `naersk` as source input to the derivation. When `root` is not set, `src` is also used to discover the `Cargo.toml` and `Cargo.lock`. |
| `root` | Used by `naersk` to read the `Cargo.toml` and `Cargo.lock` files. May be different from `src`. When `src` is not set, `root` is (indirectly) used as `src`. |
| `gitAllRefs` | Whether to fetch all refs while fetching Git dependencies. Useful if the wanted revision isn't in the default branch. Requires Nix 2.4+. Default: `false` |
| `gitSubmodules` | Whether to fetch submodules while fetching Git dependencies. Requires Nix 2.4+. Default: `false` |
| `cratesDownloadUrl` | Url for downloading crates from an alternative source Default: `"https://crates.io"` |
| `cargoBuild` | The command to use for the build. The argument must be a function modifying the default value. <br/> Default: `''cargo $cargo_options build $cargo_build_options >> $cargo_build_output_json''` |
| `cargoBuildOptions` | Options passed to cargo build, i.e. `cargo build <OPTS>`. These options can be accessed during the build through the environment variable `cargo_build_options`. <br/> Note: naersk relies on the `--out-dir out` option and the `--message-format` option. The `$cargo_message_format` variable is set based on the cargo version.<br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' "--message-format=$cargo_message_format" ]` |
| `remapPathPrefix` | When `true`, rustc remaps the (`/nix/store`) source paths to `/sources` to reduce the number of dependencies in the closure. Default: `true` |
| `cargoTestCommands` | The commands to run in the `checkPhase`. Do not forget to set [`doCheck`](https://nixos.org/nixpkgs/manual/#ssec-check-phase). The argument must be a function modifying the default value. <br/> Default: `[ ''cargo $cargo_options test $cargo_test_options'' ]` |
| `cargoTestOptions` | Options passed to cargo test, i.e. `cargo test <OPTS>`. These options can be accessed during the build through the environment variable `cargo_test_options`. <br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' ]` |
| `cargoClippyOptions` | Options passed to cargo clippy, i.e. `cargo clippy -- <OPTS>`. These options can be accessed during the build through the environment variable `cargo_clippy_options`. <br /> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "-D warnings" ]` |
| `cargoFmtOptions` | Options passed to cargo fmt, i.e. `cargo fmt -- <OPTS>`. These options can be accessed during the build through the environment variable `cargo_fmt_options`. <br /> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "--check" ]` |
| `nativeBuildInputs` | Extra `nativeBuildInputs` to all derivations. Default: `[]` |
| `buildInputs` | Extra `buildInputs` to all derivations. Default: `[]` |
| `cargoOptions` | Options passed to all cargo commands, i.e. `cargo <OPTS> ...`. These options can be accessed during the build through the environment variable `cargo_options`. <br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ ]` |
| `doDoc` | When true, `cargo doc` is run and a new output `doc` is generated. Default: `false` |
| `cargoDocCommands` | The commands to run in the `docPhase`. Do not forget to set `doDoc`. The argument must be a function modifying the default value. <br/> Default: `[ ''cargo $cargo_options doc $cargo_doc_options'' ]` |
| `cargoDocOptions` | Options passed to cargo doc, i.e. `cargo doc <OPTS>`. These options can be accessed during the build through the environment variable `cargo_doc_options`. <br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "--offline" "$cargo_release" ''-j "$NIX_BUILD_CORES"'' ]` |
| `release` | When true, all cargo builds are run with `--release`. The environment variable `cargo_release` is set to `--release` iff this option is set. Default: `true` |
| `override` | An override for all derivations involved in the build. Default: `(x: x)` |
| `overrideMain` | An override for the top-level (last, main) derivation. If both `override` and `overrideMain` are specified, _both_ will be applied to the top-level derivation. Default: `(x: x)` |
| `singleStep` | When true, no intermediary (dependency-only) build is run. Enabling `singleStep` greatly reduces the incrementality of the builds. Default: `false` |
| `copyBins` | When true, the resulting binaries are copied to `$out/bin`. <br/> Note: this relies on cargo's `--message-format` argument, set in the default `cargoBuildOptions`. Default: `true` |
| `copyLibs` | When true, the resulting binaries are copied to `$out/lib`. <br/> Note: this relies on cargo's `--message-format` argument, set in the default `cargoBuildOptions`. Default: `false` |
| `copyBinsFilter` | A [`jq`](https://stedolan.github.io/jq) filter for selecting which build artifacts to release. This is run on cargo's [`--message-format`](https://doc.rust-lang.org/cargo/reference/external-tools.html#json-messages) JSON output. <br/> The value is written to the `cargo_bins_jq_filter` variable. Default: `''select(.reason == "compiler-artifact" and .executable != null and .profile.test == false)''` |
| `copyLibsFilter` | A [`jq`](https://stedolan.github.io/jq) filter for selecting which build artifacts to release. This is run on cargo's [`--message-format`](https://doc.rust-lang.org/cargo/reference/external-tools.html#json-messages) JSON output. <br/> The value is written to the `cargo_libs_jq_filter` variable. Default: `''select(.reason == "compiler-artifact" and ((.target.kind | contains(["staticlib"])) or (.target.kind | contains(["cdylib"]))) and .filenames != null and .profile.test == false)''` Default: `''select(.reason == "compiler-artifact" and ((.target.kind | contains(["staticlib"])) or (.target.kind | contains(["cdylib"]))) and .filenames != null and .profile.test == false)''` |
| `copyDocsToSeparateOutput` | When true, the documentation is generated in a different output, `doc`. Default: `true` |
| `doDocFail` | When true, the build fails if the documentation step fails; otherwise the failure is ignored. Default: `false` |
| `removeReferencesToSrcFromDocs` | When true, references to the nix store are removed from the generated documentation. Default: `true` |
| `compressTarget` | When true, the build output of intermediary builds is compressed with [`Zstandard`](https://facebook.github.io/zstd/). This reduces the size of closures. Default: `true` |
| `copyTarget` | When true, the `target/` directory is copied to `$out`. Default: `false` |
| `postInstall` | Optional hook to run after the compilation is done; inside this script, `$out/bin` contains compiled Rust binaries. Useful if your application needs e.g. custom environment variables, in which case you can simply run `wrapProgram $out/bin/your-app-name` in here. Default: `false` |
| `usePureFromTOML` | Whether to use the `fromTOML` built-in or not. When set to `false` the python package `remarshal` is used instead (in a derivation) and the JSON output is read with `builtins.fromJSON`. This is a workaround for old versions of Nix. May be used safely from Nix 2.3 onwards where all bugs in `builtins.fromTOML` seem to have been fixed. Default: `true` |
| `mode` | What to do when building the derivation. Either `build`, `check`, `test`, `fmt` or `clippy`. <br/> When set to something other than `build`, no binaries are generated. Default: `"build"` |


## Examples

See: [./examples](./examples).

## Tips & Tricks

### Building a particular example

If you want to build only a particular example, use:

``` nix
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

``` nix
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

### Using OpenSSL

If your application uses OpenSSL (making the build process fail), try:

``` nix
naersk.buildPackage {
  # ...
  
  nativeBuildInputs = with pkgs; [ pkg-config ];
  buildInputs = with pkgs; [ openssl ];
}
```
