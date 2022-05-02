{ naersk, pkgs, ... }:
let
  app = naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
  };

in
pkgs.runCommand "dummyfication-test" {
  buildInputs = [ app ];
} "my-bin > $out"
