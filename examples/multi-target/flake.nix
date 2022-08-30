{
  inputs = {
    fenix.url = "github:nix-community/fenix";
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, fenix, flake-utils, naersk, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = (import nixpkgs) {
          inherit system;
        };

        toolchain = with fenix.packages.${system};
          combine [
            minimal.rustc
            minimal.cargo
            targets.x86_64-unknown-linux-musl.latest.rust-std
            targets.x86_64-pc-windows-gnu.latest.rust-std
            targets.i686-pc-windows-gnu.latest.rust-std
          ];

        naersk' = naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        };

        naerskBuildPackage = target: args:
          naersk'.buildPackage (
            args
              // { CARGO_BUILD_TARGET = target; }
              // cargoConfig
          );

        # All of the CARGO_* configurations which should be used for all
        # targets.
        #
        # Only use this for options which should be universally applied or which
        # can be applied to a specific target triple.
        #
        # This is also merged into the devShell.
        cargoConfig = {
          # Tells Cargo to enable static compilation.
          # (https://doc.rust-lang.org/cargo/reference/config.html#targettriplerustflags)
          #
          # Note that the resulting binary might still be considered dynamically
          # linked by ldd, but that's just because the binary might have
          # position-independent-execution enabled.
          # (see: https://github.com/rust-lang/rust/issues/79624#issuecomment-737415388)
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_RUSTFLAGS = "-C target-feature=+crt-static";

          # Tells Cargo that it should use Wine to run tests.
          # (https://doc.rust-lang.org/cargo/reference/config.html#targettriplerunner)
          CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUNNER = pkgs.writeScript "wine-wrapper" ''
            export WINEPREFIX="$(mktemp -d)"
            exec wine64 $@
          '';
        };

      in rec {
        defaultPackage = packages.x86_64-unknown-linux-musl;

        # For `nix build .#x86_64-unknown-linux-musl`:
        packages.x86_64-unknown-linux-musl = naerskBuildPackage "x86_64-unknown-linux-musl" {
          src = ./.;
          doCheck = true;
          nativeBuildInputs = with pkgs; [ pkgsStatic.stdenv.cc ];
        };

        # For `nix build .#x86_64-pc-windows-gnu`:
        packages.x86_64-pc-windows-gnu = naerskBuildPackage "x86_64-pc-windows-gnu" {
          src = ./.;
          doCheck = true;
          strictDeps = true;

          depsBuildBuild = with pkgs; [
            pkgsCross.mingwW64.stdenv.cc
            pkgsCross.mingwW64.windows.pthreads
          ];

          nativeBuildInputs = with pkgs; [
            # We need Wine to run tests:
            wineWowPackages.stable
          ];
        };

        # For `nix build .#i686-pc-windows-gnu`:
        packages.i686-pc-windows-gnu = 
          let
            # GCC supports 2 types of exception handling: SJLJ and DWARF-2
            # (https://gcc.gnu.org/wiki/WindowsGCCImprovements)
            #
            # Rust uses libgcc_eh for exception handling and it does not support SJLJ
            # (https://github.com/rust-lang/rust/pull/55444#issuecomment-434044002)
            #
            # Solution for this are either: 
            # 1. Rebuilding MinGW32 with DWARF-2 enabled instead of SJLJ (Which is provided in this example)
            # 2. Using "panic = abort" for i686-pc-windows-gnu target and rebuilding rust-std to exclude any linking to libgcc_eh
            cc' = pkgs.pkgsCross.mingw32.buildPackages.wrapCC (
              pkgs.pkgsCross.mingw32.buildPackages.gcc.cc.overrideAttrs (oldAttr: rec{
                configureFlags = oldAttr.configureFlags ++ [
                  # Taken from Fedora mingw32 rpm spec
                  # (https://src.fedoraproject.org/rpms/mingw-gcc/blob/rawhide/f/mingw-gcc.spec)
                  "--disable-sjlj-exceptions --with-dwarf2"
                ];
              })
            );

          in naerskBuildPackage "i686-pc-windows-gnu" {
            src = ./.;
            doCheck = true;
            strictDeps = true;

            # libgcc_eh implicitly requires libmcfgthread to be linked.
            depsBuildBuild = [cc'] ++ (with pkgs.pkgsCross.mingw32.windows; [ pthreads mcfgthreads ]);
            # It's currently not possible to statically link mcfgtread, so instead just add a symlink so it's easier to transfer to target machine
            postInstall = ''
              ln -s ${pkgs.pkgsCross.mingw32.windows.mcfgthreads}/bin/mcfgthread-12.dll $out/bin/mcfgthread-12.dll
            '';
            CARGO_TARGET_I686_PC_WINDOWS_GNU_RUSTFLAGS = "-Clink-args=-lmcfgthread";
            CARGO_TARGET_I686_PC_WINDOWS_GNU_RUNNER = pkgs.writeScript "wine-wrapper" ''
              export WINEPREFIX="$(mktemp -d)"
              ln -s \
                ${pkgs.pkgsCross.mingw32.windows.mcfgthreads}/bin/mcfgthread-12.dll \
                mcfgthread-12.dll
              exec wine64 $@
            '';

            nativeBuildInputs = with pkgs; [
              # We need Wine to run tests:
              wineWowPackages.stable
            ];
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
