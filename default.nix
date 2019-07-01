# TODO:
# cargo puts all built libs in 'target/(release|debug)/deps'. The format is
# something like 'libfoo-<some hash>.(rlib|rmeta)'. Would be straightforward to
# just copy these instead of rebuilding everything from scratch.
#
#
with rec
  { sources = import ./nix/sources.nix;
    gitignore = _pkgs.callPackage sources.gitignore {};
    _pkgs = import sources.nixpkgs {};
  };

{ lib ? _pkgs.lib
, runCommand ? _pkgs.runCommand
, symlinkJoin ? _pkgs.symlinkJoin
, stdenv ? _pkgs.stdenv
, writeText ? _pkgs.writeText
, llvmPackages ? _pkgs.llvmPackages
, jq ? _pkgs.jq
, rsync ? _pkgs.rsync
, darwin ? _pkgs.darwin
, remarshal ? _pkgs.remarshal
, rustPackages ?
    with sources;
    (_pkgs.callPackage rust-nightly {}).rust {inherit (rust-nightly) date; }
}:

with
  { libb = import ./lib.nix { inherit lib writeText runCommand remarshal; }; };

# Crate building
with rec
  {
      buildPackage = src: attrs:
        with
          { defaultAttrs =
              { inherit
                  llvmPackages
                  jq
                  runCommand
                  rustPackages
                  lib
                  darwin
                  writeText
                  stdenv
                  rsync
                  remarshal
                  symlinkJoin ;
              } ;
          };
        import ./build.nix src (defaultAttrs // attrs);

      buildPackageIncremental = cargolock: name: version: src: attrs:
        with rec
          { buildDependency = depName: depVersion:
              # Really this should be 'buildPackageIncremental' but that makes
              # Nix segfault
              buildPackage (libb.dummySrc depName depVersion)
                { cargoBuild = "cargo build --release -p ${depName}:${depVersion} -j $NIX_BUILD_CORES";
                  inherit (attrs) cargo;
                  cargotomlPath = libb.writeTOML (libb.cargotomlFor depName depVersion);
                  cargolockPath = libb.writeTOML (
                    libb.cargolockFor cargolock depName depVersion
                    );
                  doCheck = false;
                };
          };
        buildPackage src (attrs //
          {
            builtDependencies = map (x: buildDependency x.name x.version)
              (libb.directDependencies cargolock name version) ;
          }
          );

  };

with rec
  { # patched version of cargo that fixes
    #   https://github.com/rust-lang/cargo/issues/7078
    # which is needed for incremental builds
    patchedCargo =
      with rec
        { cargoSrc = sources.cargo ;
          cargoCargoToml = libb.readTOML "${cargoSrc}/Cargo.toml";
          cargoCargoToml' = cargoCargoToml //
            { dependencies = lib.filterAttrs (k: _:
                k != "rustc-workspace-hack")
                cargoCargoToml.dependencies;
            };

          cargoCargoLock = "${sources.rust}/Cargo.lock";
        };
      buildPackage cargoSrc
        { cargolockPath = cargoCargoLock;
          cargotomlPath = libb.writeTOML cargoCargoToml';

          # Tests fail, although cargo seems to operate normally
          doCheck = false;

          # cannot pass in --frozen because cargo fails (unsure why).
          # Nonetheless, cargo doesn't try to hit the network, so we're fine.
          cargoBuild = "cargo build --release -j $NIX_BUILD_CORES";

          override = oldAttrs:
            { buildInputs = oldAttrs.buildInputs ++
                [ _pkgs.pkgconfig
                  _pkgs.openssl
                  _pkgs.libgit2
                  _pkgs.libiconv
                  _pkgs.curl
                  _pkgs.git
                ];
              NIX_LDFLAGS="-F${_pkgs.darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks -framework CoreFoundation ";
              LIBGIT2_SYS_USE_PKG_CONFIG = 1;
            };
        };
  };

with rec
  { crates =
      { lorri = buildPackageIncremental (libb.readTOML "${sources.lorri}/Cargo.lock") "lorri" "0.1.0" sources.lorri
          { override = _oldAttrs:
              { BUILD_REV_COUNT = 1;
                RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
              };
            doCheck = false;
            cargo = patchedCargo;
          };

        ripgrep-all = buildPackage sources.ripgrep-all {};

        rustfmt = buildPackage sources.rustfmt {};

        simple-dep =
          buildPackageIncremental (libb.readTOML ./test/simple-dep/Cargo.lock)
            "simple-dep" "0.1.0" ./test/simple-dep
            { cargo = patchedCargo;
            };
      };
  };

{ inherit buildPackage crates;

  test_lorri = runCommand "lorri" { buildInputs = [ crates.lorri ]; }
    "lorri --help && touch $out";

  test_talent-plan-1 = buildPackage "${sources.talent-plan}/rust/projects/project-1" {};
  test_talent-plan-2 = buildPackage "${sources.talent-plan}/rust/projects/project-2" {};
  test_talent-plan-3 = buildPackage
    "${sources.talent-plan}/rust/projects/project-3"
    { doCheck = false; };

  # TODO: support for git deps
  #test_talent-plan-4 = buildPackage "${sources.talent-plan}/rust/projects/project-4" {};
  #test_talent-plan-5 = buildPackage "${sources.talent-plan}/rust/projects/project-5" {};

  # TODO: figure out executables from src/bin/*.rs
  test_ripgrep-all = runCommand "ripgrep-all"
    { buildInputs = [ crates.ripgrep-all ]; }
    "touch $out";

  # TODO: Nix error:
  # error: while parsing a TOML string at default.nix:80:25:
  #   Bare key 'cfg(all(target_env = "musl", target_pointer_width = "64"))'
  #   cannot contain whitespace at line 64
  # and this is the culprit:
  #  https://github.com/BurntSushi/ripgrep/blob/d1389db2e39802d5e04dc7b902fd2b1f9f615b01/Cargo.toml#L64
  # TODO: update Nix: https://github.com/NixOS/nix/pull/2902
  #test_ripgrep = buildPackage sources.ripgrep {};

  # TODO: (workspace)
  # error: while parsing a TOML string at ...:115:25:
  #   Bare key 'cfg(any(all(target_arch = "wasm32", not(target_os = "emscripten")), all(target_vendor = "fortanix", target_env = "sgx")))'
  #   cannot contain whitespace at line 53
  #test_rust = buildPackage sources.rust {};

  # Unable to update https://github.com/...
  #test_noria = buildPackage sources.noria {};

  # TODO: fix submodules
  test_lucet =
      with rec
        { lucetSpec =
            { inherit (sources.lucet) owner repo rev;
              fetchSubmodules = true;
              sha256 = "1vwz7gijq4pcs2dvaazmzcdyb8d64y5qss6s4j2wwigsgqmpfdvs";
            } ;
          lucetGit = _pkgs.fetchFromGitHub lucetSpec;
        };
      buildPackage lucetGit
        { nativeBuildInputs = [ _pkgs.cmake _pkgs.python3 ] ;
          doCheck = false;
          cargoBuild =
            lib.concatStringsSep " "
              [ "cargo build"
                "-p lucetc"
                "-p lucet-runtime"
                "-p lucet-runtime-internals"
                "-p lucet-module-data"
              ];
        };

  test_rustlings = buildPackage sources.rustlings {};

  # TODO: walk through bins
  test_rustfmt = runCommand "rust-fmt"
    { buildInputs = [ crates.rustfmt ]; }
    ''
      rustfmt --help
      cargo-fmt --help
      touch $out
    '';

    #test_git-dep = buildPackage (lib.cleanSource ./test/git-dep)
      #{ override = oldAttrs:
          #{};

      #};
}
