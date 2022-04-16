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

      # Tests that the builtDependencies derivation can successfully be unpacked
      # and that it actually contains cargo's output artifacts. If the result is
      # ever empty, cargo will still succeed in building the top level crate, except
      # it will need to rebuild all dependencies from scratch, which is wasteful.
      # See https://github.com/nix-community/naersk/issues/202
      depsTargetNotEmpty = pkgs.runCommand "depsTargetNotEmpty"
        { inherit (simple-dep) builtDependencies; }
        ''
          for dep in $builtDependencies; do
            # Make destination directory for unarchiving
            mkdir dst
            ${pkgs.zstd}/bin/zstd -d "$dep/target.tar.zst" --stdout | tar -x -C ./dst

            if [ -z "$(ls -A ./dst)" ]; then
              echo target directory is empty: "$dep"
              return 1
            fi

            rm -rf ./dst
          done

          # Success
          touch $out
        '';

      # Same as the test above except checks when the builtDependencies
      # derivation is not compressed.
      depsUncompressedTargetNotEmpty = pkgs.runCommand "depsUncompressedTargetNotEmpty"
        { inherit (simple-dep-no-compress) builtDependencies; }
        ''
          for dep in $builtDependencies; do
            if [ -z "$(ls -A "$dep"/target)" ]; then
              echo target directory is empty: "$dep"
              return 1
            fi
          done

          # Success
          touch $out
        '';

      simple-dep = naersk.buildPackage {
        src = ./test/simple-dep;
        doCheck = true;
      };

      simple-dep-no-compress = naersk.buildPackage {
        src = ./test/simple-dep;
        doCheck = true;
        compressTarget = false;
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

      git-symlink =
        let
          dep = pkgs.runCommand "dep" {
            buildInputs = [ pkgs.git ];
          } ''
            mkdir $out
            cd $out
            cp -ar ${./test/git-symlink/dep-workspace}/* .

            git init
            git add .
            git config user.email 'someone'
            git config user.name 'someone'
            git commit -am 'Initial commit'
          '';

          app = pkgs.runCommand "app" {
            buildInputs = [ pkgs.git ];
          } ''
            mkdir $out
            cd $out
            cp -ar ${./test/git-symlink/app}/* .

            depPath="${dep}"
            depRev=$(cd ${dep} && git rev-parse HEAD)

            sed "s:\$depPath:$depPath:" -is Cargo.*
            sed "s:\$depRev:$depRev:" -is Cargo.*
          '';

        in
        naersk.buildPackage {
          doCheck = true;
          src = app;
          cargoOptions = (opts: opts ++ [ "--locked" ]);
        };

      git-dep = naersk.buildPackage {
        doCheck = true;
        src = ./test/git-dep;
      };

      git-dep-by-branch = naersk.buildPackage {
        doCheck = true;
        src = ./test/git-dep-by-branch;
        cargoOptions = (opts: opts ++ [ "--locked" ]);
      };

      git-dep-by-branch-with-slash =
        let
          dep = pkgs.runCommand "dep" {
            buildInputs = [ pkgs.git ];
          } ''
            mkdir $out
            cd $out
            cp -ar ${./test/git-dep-by-branch-with-slash/dep}/* .

            git init --initial-branch=with/slash
            git add .
            git config user.email 'someone'
            git config user.name 'someone'
            git commit -am 'Initial commit'
          '';

          app = pkgs.runCommand "app" {
            buildInputs = [ pkgs.git ];
          } ''
            mkdir $out
            cd $out
            cp -ar ${./test/git-dep-by-branch-with-slash/app}/* .

            depPath="${dep}"
            depRev=$(cd ${dep} && git rev-parse HEAD)

            sed "s:\$depPath:$depPath:" -is Cargo.*
            sed "s:\$depRev:$depRev:" -is Cargo.*
          '';

        in
        naersk.buildPackage {
          doCheck = true;
          src = app;
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

      workspace-doc = naersk.buildPackage {
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

    agent-rs = naersk.buildPackage {
      doCheck = true;
      src = sources.agent-rs;
      buildInputs =
        [
          pkgs.openssl
          pkgs.pkg-config
          pkgs.perl
        ] ++ pkgs.lib.optional pkgs.stdenv.isDarwin pkgs.libiconv;
    };

  };
in
fastTests
// pkgs.lib.optionalAttrs (! fast) heavyTests
// pkgs.lib.optionalAttrs (nixpkgs == "nixpkgs-20.03" && pkgs.stdenv.isLinux) muslTests
