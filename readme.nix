# This script is used to test & generate `README.md`.

let
  sources = import ./nix/sources.nix;

  pkgs = import ./nix {
    system = builtins.currentSystem;
    nixpkgs = "nixpkgs";
  };

  naersk = pkgs.callPackage ./default.nix {
    inherit (pkgs.rustPackages) cargo rustc;
  };

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

in rec {
  body = pkgs.runCommand "readme-body" {
    buildInputs = [ docparse ];
  } ''
    cat ${./README.tpl.md} > $out
    docparse ${./config.nix} >> gen
    sed -e '/GEN_CONFIGURATION/{r gen' -e 'd}' -i $out
  '';

  test = pkgs.runCommand "readme-test" {} ''
    diff ${./README.md} ${body}
    touch $out
  '';
}
