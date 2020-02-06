{ system ? builtins.currentSystem }:
let
  sources = import ./nix/sources.nix;
  pkgs = import ./nix { inherit system; };
  naersk = pkgs.callPackage ./default.nix
    { inherit (pkgs.rustPackages) cargo rustc; };
  builtinz = builtins // pkgs.callPackage ./builtins {};
in
rec
{
  readme = pkgs.runCommand "readme-gen" {}
    ''
    cat ${./README.tpl.md} > $out
    ${docparse}/bin/docparse ${./config.nix} >> gen
    sed -e '/GEN_CONFIGURATION/{r gen' -e 'd}' -i $out
    '';

  docparse = naersk.buildPackage {
    doCheck = false;
    root = ./docparse;
    src = builtins.filterSource (
      p: t:
        let
          p' = pkgs.lib.removePrefix (toString ./docparse + "/") p;
        in
        p' == "Cargo.lock" ||
        p' == "Cargo.toml" ||
        p' == "src" ||
        p' == "src/main.rs"
      ) ./docparse;
    };

  readme_test = pkgs.runCommand "readme-test" {}
    ''
    diff ${./README.md} ${readme}
    touch $out
    '';

  # error[E0554]: `#![feature]` may not be used on the stable release channel
  # rustfmt = naersk.buildPackage sources.rustfmt { doDocFail = false; };
  # rustfmt_test = pkgs.runCommand "rustfmt-test"
  #   { buildInputs = [ rustfmt ]; }
  #   "rustfmt --help && cargo-fmt --help && touch $out";

  # error: evaluation aborted with the following error message: 'Not implemented: type int'
  # ripgrep = naersk.buildPackage sources.ripgrep { usePureFromTOML = false; };
  # XXX: the `rg` executable is missing because we don't do `cargo install
  # --path .`.
  # ripgrep_test = pkgs.runCommand "ripgrep-test"
  #   { buildInputs = [ ripgrep ]; }
  #   "rg --help && touch $out";

  ripgrep-all = naersk.buildPackage sources.ripgrep-all;
  ripgrep-all_test = pkgs.runCommand "ripgrep-all-test"
    { buildInputs = [ ripgrep-all ]; }
    "rga --help && touch $out";

  lorri = naersk.buildPackage {
    src = sources.lorri;
    override = _oldAttrs: {
      BUILD_REV_COUNT = 1;
      RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
    };
    doCheck = false;
  };

  lorri_test = pkgs.runCommand "lorri-test" { buildInputs = [ lorri ]; }
    "lorri --help && touch $out";

  talent-plan-1 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-1";
  talent-plan-2 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-2";
  talent-plan-3 = naersk.buildPackage {
    src = "${sources.talent-plan}/rust/projects/project-3";
    doCheck = false;
  };

  # TODO: support for git deps
  #test_talent-plan-4 = buildPackage "${sources.talent-plan}/rust/projects/project-4" {};
  #test_talent-plan-5 = buildPackage "${sources.talent-plan}/rust/projects/project-5" {};

  # TODO: change this when niv finally supports submodules
  # lucetSrc = pkgs.fetchFromGitHub
  #   { inherit (sources.lucet) owner repo rev;
  #     fetchSubmodules = true;
  #     sha256 = "1vwz7gijq4pcs2dvaazmzcdyb8d64y5qss6s4j2wwigsgqmpfdvs";
  #   } ;

  # "targets" is broken
  #lucet = naersk.buildPackage lucetSrc
  #{ nativeBuildInputs = [ pkgs.cmake pkgs.python3 ] ;
  #doCheck = false;
  #targets =
  #[ "lucetc"
  #"lucet-runtime"
  #"lucet-runtime-internals"
  #"lucet-module-data"
  #];
  #};

  # error in readTOML (remarshal):
  #   Error: Cannot parse as TOML (<string>(92, 14): msg)
  #rust = naersk.buildPackage sources.rust {};

  rustlings = naersk.buildPackage sources.rustlings;

  simple-dep = naersk.buildPackage ./test/simple-dep;

  simple-dep-doc = naersk.buildPackage
    { src = ./test/simple-dep;
      doDoc = true;
    };

  simple-dep-patched = naersk.buildPackage
    { root = ./test/simple-dep-patched;
      # TODO: the lockfile needs to be regenerated
      cargoOptions = builtins.filter (x: x != "--locked");
    };

  dummyfication = naersk.buildPackage ./test/dummyfication;
  dummyfication_test = pkgs.runCommand
    "dummyfication-test"
    { buildInputs = [ dummyfication ]; }
    "my-bin > $out";

  git-dep = naersk.buildPackage {
    root = ./test/git-dep;
    cargoOptions = [ "--locked" ];
  };

  git-dep-dup = naersk.buildPackage {
    root = ./test/git-dep-dup;
    cargoOptions = [ "--locked" ];
  };

  cargo-wildcard = naersk.buildPackage ./test/cargo-wildcard;

  workspace = naersk.buildPackage ./test/workspace;

  workspace-patched = naersk.buildPackage ./test/workspace-patched;

  workspace-doc = naersk.buildPackage
    { src = ./test/workspace;
      doDoc = true;
    };

  # Fails with some remarshal error
  #servo = naersk.buildPackage
  #sources.servo
  #{ inherit cargo; };

  # TODO: error: no matching package named `rustc-workspace-hack` found
  # cargo =
  #   with rec
  #     # error: no matching package named `rustc-workspace-hack` found
  #     { cargoSrc = pkgs.runCommand "cargo-src"
  #         {}
  #         ''
  #         mkdir -p $out
  #         cp -r ${sources.cargo}/* $out
  #         chmod -R +w $out
  #         cp ${builtinz.writeTOML "Cargo.toml" cargoCargoToml} $out/Cargo.toml
  #         cp ${builtinz.writeTOML "Cargo.lock" cargoCargoLock} $out/Cargo.lock
  #         '';
  #       #sources.cargo;
  #       # cannot use the pure readTOML
  #       cargoCargoToml = builtinz.readTOML false "${sources.cargo}/Cargo.toml";

  #       # XXX: this works around some hack that breaks the build. For more info
  #       # on the hack, see
  #       # https://github.com/rust-lang/rust/blob/b43eb4235ac43c822d903ad26ed806f34cc1a14a/Cargo.toml#L63-L65
  #       cargoCargoToml' = cargoCargoToml //
  #         { dependencies = pkgs.lib.filterAttrs (k: _:
  #             k != "rustc-workspace-hack")
  #             cargoCargoToml.dependencies;
  #         };

  #       cargoCargoLock = builtinz.readTOML true "${sources.rust}/Cargo.lock";
  #     };
  #   naersk.buildPackage cargoSrc
  #     {
  #       # Tests fail, although cargo seems to operate normally
  #       doCheck = false;

  #       override = oldAttrs:
  #         { buildInputs = oldAttrs.buildInputs ++
  #             [ pkgs.pkgconfig
  #               pkgs.openssl
  #               pkgs.libgit2
  #               pkgs.libiconv
  #               pkgs.curl
  #               pkgs.git
  #             ];
  #           LIBGIT2_SYS_USE_PKG_CONFIG = 1;
  #         } // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin
  #         {
  #           NIX_LDFLAGS="-F${pkgs.darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks -framework CoreFoundation ";

  #         };
  #     };
}
