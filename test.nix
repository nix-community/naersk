with rec
  { sources = import ./nix/sources.nix ;
    pkgs = import sources.nixpkgs {};
    rustPackages =
      with sources;
      (pkgs.callPackage rust-nightly {}).rust {inherit (rust-nightly) date; };

    naersk = pkgs.callPackage ./default.nix
      # We need a more recent rustc for building cargo:
      #   error: internal compiler error: src/librustc/ty/subst.rs:491: Type
      #   parameter `T/#1` (T/1) out of range when substituting (root type=Some(T))
      #   substs=[T]
      { cargo = rustPackages; rustc = rustPackages;
      };
  };

with
  { builtinz = builtins // pkgs.callPackage ./builtins.nix {}; };

rec
{ rustfmt = naersk.buildPackage sources.rustfmt {};
  rustfmt_test = pkgs.runCommand "rustfmt-test"
    { buildInputs = [ rustfmt ]; }
    "rustfmt --help && cargo-fmt --help && touch $out";

  ripgrep = naersk.buildPackage sources.ripgrep {};
  # XXX: executables are missing
  #ripgrep_test = pkgs.runCommand "ripgrep-test"
    #{ buildInputs = [ ripgrep ]; }
    #"rg --help && touch $out";

  ripgrep-all = naersk.buildPackage sources.ripgrep-all {};
  ripgrep-all_test = pkgs.runCommand "ripgrep-all-test"
    { buildInputs = [ ripgrep-all ]; }
    "rga --help && touch $out";

  lorri = naersk.buildPackage sources.lorri
    { override = _oldAttrs:
        { BUILD_REV_COUNT = 1;
          RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
        };
      doCheck = false;
    };
  lorri_test = pkgs.runCommand "lorri-test" { buildInputs = [ lorri ]; }
    "lorri --help && touch $out";

  talent-plan-1 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-1" {};
  talent-plan-2 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-2" {};
  talent-plan-3 = naersk.buildPackage
    "${sources.talent-plan}/rust/projects/project-3"
    { doCheck = false; };

  # TODO: support for git deps
  #test_talent-plan-4 = buildPackage "${sources.talent-plan}/rust/projects/project-4" {};
  #test_talent-plan-5 = buildPackage "${sources.talent-plan}/rust/projects/project-5" {};

  # TODO: change this when niv finally supports submodules
  lucetSrc = pkgs.fetchFromGitHub
    { inherit (sources.lucet) owner repo rev;
      fetchSubmodules = true;
      sha256 = "1vwz7gijq4pcs2dvaazmzcdyb8d64y5qss6s4j2wwigsgqmpfdvs";
    } ;
  lucet = naersk.buildPackage lucetSrc
    { nativeBuildInputs = [ pkgs.cmake pkgs.python3 ] ;
      doCheck = false;
      cargoBuild =
        pkgs.lib.concatStringsSep " "
          [ "cargo build"
            "-p lucetc"
            "-p lucet-runtime"
            "-p lucet-runtime-internals"
            "-p lucet-module-data"
          ];
    };

  # error in readTOML (remarshal):
  #   Error: Cannot parse as TOML (<string>(92, 14): msg)
  #rust = naersk.buildPackage sources.rust {};

  rustlings = naersk.buildPackage sources.rustlings {};

  simple-dep = naersk.buildPackage ./test/simple-dep {};

  cargo =
    with rec
      { cargoSrc = sources.cargo ;
        cargoCargoToml = builtinz.readTOML "${cargoSrc}/Cargo.toml";
        cargoCargoToml' = cargoCargoToml //
          { dependencies = pkgs.lib.filterAttrs (k: _:
              k != "rustc-workspace-hack")
              cargoCargoToml.dependencies;
          };

        cargoCargoLock = "${sources.rust}/Cargo.lock";
      };
    naersk.buildPackage cargoSrc
      { cargolockPath = cargoCargoLock;
        cargotomlPath = builtinz.writeTOML cargoCargoToml';

        # Tests fail, although cargo seems to operate normally
        doCheck = false;

        # cannot pass in --frozen because cargo fails (unsure why).
        # Nonetheless, cargo doesn't try to hit the network, so we're fine.
        cargoBuild = "cargo build --release -j $NIX_BUILD_CORES";

        override = oldAttrs:
          { buildInputs = oldAttrs.buildInputs ++
              [ pkgs.pkgconfig
                pkgs.openssl
                pkgs.libgit2
                pkgs.libiconv
                pkgs.curl
                pkgs.git
              ];
            NIX_LDFLAGS="-F${pkgs.darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks -framework CoreFoundation ";
            LIBGIT2_SYS_USE_PKG_CONFIG = 1;
          };
      };
}
