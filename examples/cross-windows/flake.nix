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
            targets.x86_64-pc-windows-gnu.latest.rust-std
          ];
        naersk-lib = naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        };
      in
        rec {
          defaultPackage = packages.x86_64-pc-windows-gnu;

          # The rust compiler is internally a cross compiler, so a single
          # toolchain can be used to compile multiple targets. In a hermetic
          # build system like nix flakes, there's effectively one package for
          # every permutation of the supported hosts and targets.
          # i.e.: nix build .#packages.x86_64-linux.x86_64-pc-windows-gnu
          # where x86_64-linux is the host and x86_64-pc-windows-gnu is the
          # target
          packages.x86_64-pc-windows-gnu = naersk-lib.buildPackage {
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

            # Configures the target which will be built.
            # ref: https://doc.rust-lang.org/cargo/reference/config.html#buildtarget
            CARGO_BUILD_TARGET = "x86_64-pc-windows-gnu";

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

            # Configures the script which should be used to run tests. Since
            # this is compiled for 64-bit Windows, use wine64 to run the tests.
            # ref: https://doc.rust-lang.org/cargo/reference/config.html#targettriplerunner
            CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUNNER = pkgs.writeScript "wine-wrapper" ''
              # Without this, wine will error out when attempting to create the
              # prefix in the build's homeless shelter.
              export WINEPREFIX="$(mktemp -d)"
              exec wine64 $@
            '';

            doCheck = true;

            # Multi-stage builds currently fail for mingwW64.
            singleStep = true;
          };
        }
    );
}
