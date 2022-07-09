{
  description = "Build Rust projects with ease. No configuration, no code generation; IFD and sandbox friendly.";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" "i686-linux" "aarch64-linux" "aarch64-darwin" ];

    in rec {
      lib = forAllSystems (system: nixpkgs.legacyPackages."${system}".callPackage ./default.nix { });

      # Useful when composing with other flakes:
      overlay = import ./overlay.nix;

      defaultTemplate = templates.hello-world;

      templates = {
        hello-world = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/hello-world;
        };

        cross-windows = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/cross-windows;
        };

        static-musl = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/static-musl;
        };

        multi-target = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/multi-target;
        };
      };
    };
}
