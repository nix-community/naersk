{
  description = "Build Rust projects with ease. No configuration, no code generation; IFD and sandbox friendly.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" "i686-linux" "aarch64-linux" "aarch64-darwin" ];

    in rec {
      lib = forAllSystems (system: nixpkgs.legacyPackages."${system}".callPackage ./default.nix { });

      packages = forAllSystems (system: {
          readme = nixpkgs.legacyPackages."${system}".callPackage ./readme.nix { };
      });

      # Useful when composing with other flakes:
      overlays.default = import ./overlay.nix;

      templates = rec {
        default = hello-world;

        hello-world = {
          description = "A simple and straight-forward 'hello world' Rust program.";
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/hello-world;
        };

        cross-windows = {
          description = "Pre-configured for cross-compiling to Windows.";
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/cross-windows;
        };

        static-musl = {
          description = "Pre-configured for statically linked binaries for Linux with musl.";
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/static-musl;
        };

        multi-target = {
          description = "A Rust project with multiple crates and build targets.";
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/multi-target;
        };
      };
    };
}
