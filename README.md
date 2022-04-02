# Naersk

[![GitHub Actions](https://github.com/nix-community/naersk/workflows/test/badge.svg?branch=master)](https://github.com/nix-community/naersk/actions)

Nix support for building [cargo] crates.

* [Install](#install)
* [Configuration](#configuration)

## Install

Use [niv]:

``` shell
$ niv add nix-community/naersk
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

| Attribute | Description |
| - | - |
| `name` | The name of the derivation. |
| `version` | The version of the derivation. |
| `src` | Used by `naersk` as source input to the derivation. When `root` is not set, `src` is also used to discover the `Cargo.toml` and `Cargo.lock`. |
| `root` | Used by `naersk` to read the `Cargo.toml` and `Cargo.lock` files. May be different from `src`. When `src` is not set, `root` is (indirectly) used as `src`. |
| `allRefs` | Whether to fetch all refs while fetching Git dependencies. Useful if the wanted revision isn't in the default branch. |
| `cargoBuild` | The command to use for the build. The argument must be a function modifying the default value. <br/> Default: `''cargo $cargo_options build $cargo_build_options >> $cargo_build_output_json''` |
| `cargoBuildOptions` | Options passed to cargo build, i.e. `cargo build <OPTS>`. These options can be accessed during the build through the environment variable `cargo_build_options`. <br/> Note: naersk relies on the `--out-dir out` option and the `--message-format` option. The `$cargo_message_format` variable is set based on the cargo version.<br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' "--message-format=$cargo_message_format" ]` |
| `remapPathPrefix` | When `true`, rustc remaps the (`/nix/store`) source paths to `/sources` to reduce the number of dependencies in the closure. Default: `true` |
| `cargoTestCommands` | The commands to run in the `checkPhase`. Do not forget to set [`doCheck`](https://nixos.org/nixpkgs/manual/#ssec-check-phase). The argument must be a function modifying the default value. <br/> Default: `[ ''cargo $cargo_options test $cargo_test_options'' ]` |
| `cargoTestOptions` | Options passed to cargo test, i.e. `cargo test <OPTS>`. These options can be accessed during the build through the environment variable `cargo_test_options`. <br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' ]` |
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
| `targets` | The targets to build if the `Cargo.toml` is a virtual manifest. |
| `copyBins` | When true, the resulting binaries are copied to `$out/bin`. <br/> Note: this relies on cargo's `--message-format` argument, set in the default `cargoBuildOptions`. Default: `true` |
| `copyLibs` | When true, the resulting binaries are copied to `$out/lib`. <br/> Note: this relies on cargo's `--message-format` argument, set in the default `cargoBuildOptions`. Default: `false` |
| `copyBinsFilter` | A [`jq`](https://stedolan.github.io/jq) filter for selecting which build artifacts to release. This is run on cargo's [`--message-format`](https://doc.rust-lang.org/cargo/reference/external-tools.html#json-messages) JSON output. <br/> The value is written to the `cargo_bins_jq_filter` variable. Default: `''select(.reason == "compiler-artifact" and .executable != null and .profile.test == false)''` |
| `copyLibsFilter` | A [`jq`](https://stedolan.github.io/jq) filter for selecting which build artifacts to release. This is run on cargo's [`--message-format`](https://doc.rust-lang.org/cargo/reference/external-tools.html#json-messages) JSON output. <br/> The value is written to the `cargo_libs_jq_filter` variable. Default: `''select(.reason == "compiler-artifact" and ((.target.kind | contains(["staticlib"])) or (.target.kind | contains(["cdylib"]))) and .filenames != null and .profile.test == false)''` Default: `''select(.reason == "compiler-artifact" and ((.target.kind | contains(["staticlib"])) or (.target.kind | contains(["cdylib"]))) and .filenames != null and .profile.test == false)''` |
| `copyDocsToSeparateOutput` | When true, the documentation is generated in a different output, `doc`. Default: `true` |
| `doDocFail` | When true, the build fails if the documentation step fails; otherwise the failure is ignored. Default: `false` |
| `removeReferencesToSrcFromDocs` | When true, references to the nix store are removed from the generated documentation. Default: `true` |
| `compressTarget` | When true, the build output of intermediary builds is compressed with [`Zstandard`](https://facebook.github.io/zstd/). This reduces the size of closures. Default: `true` |
| `copyTarget` | When true, the `target/` directory is copied to `$out`. Default: `false` |
| `usePureFromTOML` | Whether to use the `fromTOML` built-in or not. When set to `false` the python package `remarshal` is used instead (in a derivation) and the JSON output is read with `builtins.fromJSON`. This is a workaround for old versions of Nix. May be used safely from Nix 2.3 onwards where all bugs in `builtins.fromTOML` seem to have been fixed. Default: `true` |

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
nix flake init -t github:nix-community/naersk
nix flake lock
```

Alternatively, copy this `flake.nix` into your repo.

``` nix
{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
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
    naersk.url = "github:nix-community/naersk";
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
