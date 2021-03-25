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
          ];
        naersk-lib = naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
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
          packages.x86_64-unknown-linux-musl = naersk-lib.buildPackage {
            src = ./.;

            nativeBuildInputs = with pkgs; [ pkgsStatic.stdenv.cc ];

            # Configures the target which will be built.
            # ref: https://doc.rust-lang.org/cargo/reference/config.html#buildtarget
            CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";

            # Enables static compilation.
            #
            # If the resulting executable is still considered dynamically
            # linked by ldd but doesn't have anything actually linked to it,
            # don't worry. It's still statically linked. It just has static
            # position independent execution enabled.
            # ref: https://github.com/rust-lang/rust/issues/79624#issuecomment-737415388
            CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";

            # Configures the linker which will be used. cc.targetPrefix is
            # sometimes different than the targets used by rust. i.e.: the
            # mingw-w64 linker is "x86_64-w64-mingw32-gcc" whereas the rust
            # target is "x86_64-pc-windows-gnu".
            #
            # This is only necessary if rustc doesn't already know the correct linker to use.
            #
            # ref: https://doc.rust-lang.org/cargo/reference/config.html#targettriplelinker
            # CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER = with pkgs.pkgsStatic.stdenv;
            #   "${cc}/bin/${cc.targetPrefix}gcc";

            doCheck = true;
          };
        }
    );
}
