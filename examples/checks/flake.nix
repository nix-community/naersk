{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    flake-utils,
    naersk,
    nixpkgs,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = (import nixpkgs) {
          inherit system;
        };

        naersk' = pkgs.callPackage naersk {};
      in rec {
        packages = {
          # For `nix build` & `nix run`:
          default = naersk'.buildPackage {
            src = ./.;
          };
          # Run `nix build .#check` to check code
          check = naersk'.buildPackage {
            src = ./.;
            mode = "check";
          };
          # Run `nix build .#test` to run tests
          test = naersk'.buildPackage {
            src = ./.;
            mode = "test";
          };
          # Run `nix build .#clippy` to lint code
          clippy = naersk'.buildPackage {
            src = ./.;
            mode = "clippy";
          };
        };

        # For `nix develop`:
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [rustc cargo];
        };
      }
    );
}
