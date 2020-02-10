# Naersk

[![CircleCI](https://circleci.com/gh/nmattia/naersk.svg?style=svg)](https://circleci.com/gh/nmattia/naersk)

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

| Attribute | Description |
| - | - |
| `name` | The name of the derivation. |
| `version` | The version of the derivation. |
| `src` | Used by `naersk` as source input to the derivation. When `root` is not set, `src` is also used to discover the `Cargo.toml` and `Cargo.lock`. |
| `root` | Used by `naersk` to read the `Cargo.toml` and `Cargo.lock` files. May be different from `src`. When `src` is not set, `root` is (indirectly) used as `src`. |
| `cargoBuild` | The command to use for the build. The argument must be a function modifying the default value. <br/> Default: `''cargo $cargo_options build $cargo_build_options''` |
| `cargoBuildOptions` | Options passed to cargo build, i.e. `cargo build <OPTS>`. These options can be accessed during the build through the environment variable `cargo_build_options`. <br/> Note: naersk relies on the `--out-dir out` option. <br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' "--out-dir" "out" ]` |
| `doCheck` | When true, `checkPhase` is run. Default: `true` |
| `cargoTestCommands` | The commands to run in the `checkPhase`. The argument must be a function modifying the default value. <br/> Default: `[ ''cargo $cargo_options test $cargo_test_options'' ]` |
| `cargoTestOptions` | Options passed to cargo test, i.e. `cargo test <OPTS>`. These options can be accessed during the build through the environment variable `cargo_test_options`. <br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' ]` |
| `buildInputs` | Extra `buildInputs` to all derivations. Default: `[]` |
| `cargoOptions` | Options passed to all cargo commands, i.e. `cargo <OPTS> ...`. These options can be accessed during the build through the environment variable `cargo_options`. <br/> Note: these values are not (shell) escaped, meaning that you can use environment variables but must be careful when introducing e.g. spaces. <br/> The argument must be a function modifying the default value. <br/> Default: `[ "-Z" "unstable-options" ]` |
| `doDoc` | When true, `cargo doc` is run and a new output `doc` is generated. Default: `false` |
| `release` | When true, all cargo builds are run with `--release`. The environment variable `cargo_release` is set to `--release` iff this option is set. Default: `true` |
| `override` | An override for all derivations involved in the build. Default: `(x: x)` |
| `singleStep` | When true, no intermediary (dependency-only) build is run. Enabling `singleStep` greatly reduces the incrementality of the builds. Default: `false` |
| `targets` | The targets to build if the `Cargo.toml` is a virtual manifest. |
| `copyBins` | When true, the resulting binaries are copied to `$out/bin`. Default: `true` |
| `copyDocsToSeparateOutput` | When true, the documentation is generated in a different output, `doc`. Default: `true` |
| `doDocFail` | When true, the build fails if the documentation step fails; otherwise the failure is ignored. Default: `false` |
| `removeReferencesToSrcFromDocs` | When true, references to the nix store are removed from the generated documentation. Default: `true` |
| `compressTarget` | When true, the build output of intermediary builds is compressed with [`Zstandard`](https://facebook.github.io/zstd/). This reduces the size of closures. Default: `true` |
| `copyTarget` | When true, the `target/` directory is copied to `$out`. Default: `false` |
| `usePureFromTOML` | Whether to use the `fromTOML` built-in or not. When set to `false` the python package `remarshal` is used instead (in a derivation) and the JSON output is read with `builtins.fromJSON`. This is a workaround for old versions of Nix. May be used safely from Nix 2.3 onwards where all bugs in `builtins.fromTOML` seem to have been fixed. Default: `true` |

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
