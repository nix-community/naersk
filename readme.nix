# This script is used to test & generate `README.md`.
{ pkgs }:

let

  naersk = pkgs.callPackage ./default.nix {
    inherit (pkgs.rustPackages) cargo rustc;
  };

  docparse = naersk.buildPackage {
    root = ./docparse;

    src = builtins.filterSource
      (
        p: t:
          let
            p' = pkgs.lib.removePrefix (toString ./docparse + "/") p;
          in
          p' == "Cargo.lock" || p' == "Cargo.toml" || p' == "src" || p' == "src/main.rs"
      ) ./docparse;
  };

in
pkgs.runCommand "readme"
{
  buildInputs = [ docparse ];
} ''
  docparse ${./config.nix} >> gen
  sed <${./README.tpl.md}  -e '/GEN_CONFIGURATION/{r gen' -e 'd}' > $out
''
