{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    naersk = {
      url = github:nmattia/naersk;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = github:nix-community/fenix;
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = github:numtide/flake-utils;
  };

  outputs = { self, nixpkgs, naersk, fenix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        toolchain = with fenix.packages.${system};
          combine [
            minimal.rustc
            minimal.cargo
            targets.x86_64-unknown-linux-musl.latest.rust-std
            targets.x86_64-pc-windows-gnu.latest.rust-std
          ];
        # Make naersk aware of the tool chain which is to be used.
        naersk-lib = naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        };
        # Utility for merging the common cargo configuration with the target
        # specific configuration.
        naerskBuildPackage = target: args: naersk-lib.buildPackage
          (args // { CARGO_BUILD_TARGET = target; } // cargoConfig);
        # All of the CARGO_* configurations which should be used for all
        # targets. Only use this for options which should be universally
        # applied or which can be applied to a specific target triple.
        # This is also merged into the devShell.
        cargoConfig = {
          # Enables static compilation.
          #
          # If the resulting executable is still considered dynamically
          # linked by ldd but doesn't have anything actually linked to it,
          # don't worry. It's still statically linked. It just has static
          # position independent execution enabled.
          # ref: https://doc.rust-lang.org/cargo/reference/config.html#targettriplerustflags
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_RUSTFLAGS = "-C target-feature=+crt-static";

          # Configures the script which should be used to run tests. Since
          # this is compiled for 64-bit Windows, use wine64 to run the tests.
          # ref: https://doc.rust-lang.org/cargo/reference/config.html#targettriplerunner
          CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUNNER = pkgs.writeScript "wine-wrapper" ''
            # Without this, wine will error out when attempting to create the
            # prefix in the build's homeless shelter.
            export WINEPREFIX="$(mktemp -d)"
            exec wine64 $@
          '';

          # Configures the linker which will be used. cc.targetPrefix is
          # sometimes different than the targets used by rust. i.e.: the
          # mingw-w64 linker is "x86_64-w64-mingw32-gcc" whereas the rust
          # target is "x86_64-pc-windows-gnu".
          #
          # This is only necessary if rustc doesn't already know the correct linker to use.
          #
          # ref: https://doc.rust-lang.org/cargo/reference/config.html#targettriplelinker
          # CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = with pkgs.pkgsCross.mingwW64.stdenv;
          #   "${cc}/bin/${cc.targetPrefix}gcc";
          # CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER = with pkgs.pkgsStatic.stdenv;
          #   "${cc}/bin/${cc.targetPrefix}gcc";
        };
      in
        rec {
          defaultPackage = packages.x86_64-unknown-linux-musl;

          # The rust compiler is internally a cross compiler, so a single
          # toolchain can be used to compile multiple targets. In a hermetic
          # build system like nix flakes, there's effectively one package for
          # every permutation of the supported hosts and targets.
          # i.e.: nix build .#packages.x86_64-linux.x86_64-pc-windows-gnu
          # where x86_64-linux is the host and x86_64-pc-windows-gnu is the
          # target
          packages.x86_64-unknown-linux-musl = naerskBuildPackage "x86_64-unknown-linux-musl" {
            src = ./.;
            nativeBuildInputs = with pkgs; [ pkgsStatic.stdenv.cc ];
            doCheck = true;
          };

          packages.x86_64-pc-windows-gnu = naerskBuildPackage "x86_64-pc-windows-gnu" {
            src = ./.;

            nativeBuildInputs = with pkgs; [
              pkgsCross.mingwW64.stdenv.cc
              # Used for running tests.
              wineWowPackages.stable
              # wineWowPackages is overkill, but it's built in CI for nixpkgs,
              # so it doesn't need to be built from source. It needs to provide
              # wine64 not just wine. An alternative would be this:
              # (wineMinimal.override { wineBuild = "wine64"; })
            ];

            buildInputs = with pkgs.pkgsCross.mingwW64.windows; [ mingw_w64_pthreads pthreads ];

            doCheck = true;

            # Multi-stage builds currently fail for mingwW64.
            singleStep = true;
          };

          devShell = pkgs.mkShell (
            {
              inputsFrom = with packages; [ x86_64-unknown-linux-musl x86_64-pc-windows-gnu ];
              CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
            } // cargoConfig
          );
        }
    );
}
