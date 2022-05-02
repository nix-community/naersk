{ sources, naersk, pkgs, ... }:
let
  app = naersk.buildPackage {
    src = sources.ripgrep-all;
    doCheck = true;
  };

in
pkgs.runCommand "ripgrep-all-test" {
  buildInputs = [ app ];
} "rga --help && touch $out"
