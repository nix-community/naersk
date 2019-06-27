# TODO:
# cargo puts all built libs in 'target/(release|debug)/deps'. The format is
# something like 'libfoo-<some hash>.(rlib|rmeta)'. Would be straightforward to
# just copy these instead of rebuilding everything from scratch.
#
#
with rec
  { sources = import ./nix/sources.nix;
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
, rustPackages ?
    with sources;
    (_pkgs.callPackage rust-nightly {}).rust {inherit (rust-nightly) date; }
}:

with
  { libb = import ./lib.nix { inherit lib; }; };

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
                  symlinkJoin ;
              } ;
          };
        import ./build.nix src (defaultAttrs // attrs);
  };

with
  { crates =
      { lorri = buildPackage sources.lorri
          { override = _oldAttrs:
              { BUILD_REV_COUNT = 1;
                RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
              };
            doCheck = false;
          };

        ripgrep-all = buildPackage sources.ripgrep-all {};

        rustfmt = buildPackage sources.rustfmt {};

        simple-dep =
          with rec
          { rand = buildPackage ./test/simple-dep
              { cargoBuild = "cargo build --release --frozen -p rand -j $NIX_BUILD_CORES";
                doCheck = false;
                #override = _oldAttrs:
                  #{ installPhase = "echo no install"; };
              };

          };
          buildPackage ./test/simple-dep
            { builtDependencies = [ rand ];
              cargoBuild = "cargo build --release --frozen -j $NIX_BUILD_CORES";
              #override = _oldAttrs:
                #{ preBuild =
                    #''
                    #echo $PWD
                    #sleep infinity


                    #'';
                #};
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
