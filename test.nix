{ system ? builtins.currentSystem
, fast ? false
, nixpkgs ? "nixpkgs"
}:
let
  sources = import ./nix/sources.nix;
  pkgs = import ./nix { inherit system nixpkgs; };
  naersk = pkgs.callPackage ./default.nix
    { inherit (pkgs.rustPackages) cargo rustc; };

  # very temporary musl tests, just to make sure 1_41_0 builds on 20.03
  # (okay, it's actually a wasm test)
  muslTests =
    {
      wasm_rust_1_41_0 =
        let
          pkgs' = pkgs.appendOverlays
            [
              (
                self: super: rec {
                  rust_1_41_0 = (
                    self.callPackage ./rust/1_41_0.nix {
                      inherit (self.darwin.apple_sdk.frameworks) CoreFoundation Security;
                      inherit (self) path;
                    }
                  );
                  rust = rust_1_41_0;
                  rustPackages = self.rust.packages.stable;
                  inherit (self.rustPackages) rustPlatform;
                }
              )
            ];
          naersk' = pkgs'.callPackage ./default.nix {};
        in
          naersk'.buildPackage
            {
              src = ./test/simple-dep;
              CARGO_BUILD_TARGET = "wasm32-unknown-unknown";
              CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_LINKER = "${pkgs'.llvmPackages_9.lld}/bin/lld";

            };

      musl_rust_1_41_0 =
        let
          pkgs' = pkgs.appendOverlays
            [
              (
                self: super: rec {
                  rust_1_41_0 = (
                    self.callPackage ./rust/1_41_0.nix {
                      inherit (self.darwin.apple_sdk.frameworks) CoreFoundation Security;
                      inherit (self) path;
                    }
                  );
                  rust = rust_1_41_0;
                  rustPackages = self.rust.packages.stable;
                  inherit (self.rustPackages) rustPlatform;
                }
              )
            ];
          naersk' = pkgs'.callPackage ./default.nix {};
        in
          naersk'.buildPackage
            {
              src = ./test/simple-dep;
              CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";

            };
    };

  # local tests, that run pretty fast
  fastTests =
    rec
    {

      readme = pkgs.runCommand "readme-gen" {}
        ''
          cat ${./README.tpl.md} > $out
          ${docparse}/bin/docparse ${./config.nix} >> gen
          sed -e '/GEN_CONFIGURATION/{r gen' -e 'd}' -i $out
        '';

      docparse = naersk.buildPackage {
        root = ./docparse;
        src = builtins.filterSource (
          p: t:
            let
              p' = pkgs.lib.removePrefix (toString ./docparse + "/") p;
            in
              p' == "Cargo.lock" || p' == "Cargo.toml" || p' == "src" || p' == "src/main.rs"
        ) ./docparse;
      };

      readme_test = pkgs.runCommand "readme-test" {}
        ''
          diff ${./README.md} ${readme}
          touch $out
        '';

      simple-dep = naersk.buildPackage {
        src = ./test/simple-dep;
        doCheck = true;
      };

      simple-dep-doc = naersk.buildPackage
        {
          src = ./test/simple-dep;
          doDoc = true;
          doCheck = true;
        };

      simple-dep-patched = naersk.buildPackage {
        src = ./test/simple-dep-patched;
        doCheck = true;
      };

      dummyfication = naersk.buildPackage {
        src = ./test/dummyfication;
        doCheck = true;
      };

      dummyfication_test = pkgs.runCommand
        "dummyfication-test"
        { buildInputs = [ dummyfication ]; }
        "my-bin > $out";

      git-dep = naersk.buildPackage {
        doCheck = true;
        src = ./test/git-dep;
        cargoOptions = (opts: opts ++ [ "--locked" ]);
      };

      git-dep-by-tag = naersk.buildPackage {
        doCheck = true;
        src = ./test/git-dep-by-tag;
        cargoOptions = (opts: opts ++ [ "--locked" ]);
      };

      git-dep-dup = naersk.buildPackage {
        doCheck = true;
        src = ./test/git-dep-dup;
        cargoOptions = (opts: opts ++ [ "--locked" ]);
      };

      cargo-wildcard = naersk.buildPackage {
        src = ./test/cargo-wildcard;
        doCheck = true;
      };

      workspace = naersk.buildPackage {
        src = ./test/workspace;
        doCheck = true;
      };

      workspace-patched = naersk.buildPackage {
        src = ./test/workspace-patched;
        doCheck = true;
      };

      workspace-doc = naersk.buildPackage
        {
          src = ./test/workspace;
          doDoc = true;
          doCheck = true;
        };

      workspace-build-rs = naersk.buildPackage {
        src = ./test/workspace-build-rs;
        doCheck = true;
      };

      default-run = naersk.buildPackage {
        src = ./test/default-run;
        doCheck = true;
      };
    };

  # extra crates, that are kinda slow to build
  heavyTests = rec {

    ripgrep-all = naersk.buildPackage
      {
        src = sources.ripgrep-all;
        doCheck = true;
      };

    ripgrep-all_test = pkgs.runCommand "ripgrep-all-test"
      { buildInputs = [ ripgrep-all ]; }
      "rga --help && touch $out";

    lorri = naersk.buildPackage {
      src = sources.lorri;
      BUILD_REV_COUNT = 1;
      RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
    };

    lorri_test = pkgs.runCommand "lorri-test" { buildInputs = [ lorri ]; }
      "lorri --help && touch $out";

    talent-plan-1 = naersk.buildPackage {
      src = "${sources.talent-plan}/rust/projects/project-1";
      doCheck = true;
    };

    talent-plan-2 = naersk.buildPackage {
      doCheck = true;
      src = "${sources.talent-plan}/rust/projects/project-2";
    };

    talent-plan-3 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-3";

    rustlings = naersk.buildPackage sources.rustlings;
  };
in
fastTests
// pkgs.lib.optionalAttrs (! fast) heavyTests
// pkgs.lib.optionalAttrs (nixpkgs == "nixpkgs-20.03" && pkgs.stdenv.isLinux) muslTests
