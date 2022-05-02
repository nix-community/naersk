{ sources, naersk, pkgs, ... }:
let
  app = naersk.buildPackage {
    src = sources.lorri;
    BUILD_REV_COUNT = 1;
    RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
  };

in
pkgs.runCommand "lorri-test" {
  buildInputs = [ app ];
} "lorri --help && touch $out"
