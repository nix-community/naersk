{
  description = "Build rust crates in Nix. No configuration, no code generation. IFD and sandbox friendly.";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" "i686-linux" "aarch64-linux" "aarch64-darwin" ];
    in
    rec {
      # Naersk is not a package, not an app, not a module... It's just a Library
      lib = forAllSystems (system: nixpkgs.legacyPackages."${system}".callPackage ./default.nix { });
      # Useful when composing with other flakes
      overlay = import ./overlay.nix;

      # Expose the examples as templates.
      defaultTemplate = templates.hello-world;
      templates = {
        hello-world = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/hello-world;
          description = "Build a rust project with naersk.";
        };
        cross-windows = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/cross-windows;
          description = "Cross compile a rust project for use on Windows.";
        };
        static-musl = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/static-musl;
          description = "Compile a rust project statically using musl.";
        };
        multi-target = {
          path =
            builtins.filterSource (path: type: baseNameOf path == "flake.nix")
              ./examples/multi-target;
          description = "Compile a rust project to multiple targets.";
        };
      };
    };
}
