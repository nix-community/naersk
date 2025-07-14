{ pkgs, ... }:
let
  readme = pkgs.callPackage ../../../readme.nix { };
in
pkgs.runCommand "readme-test" { } ''
  diff ${../../../README.md} ${readme}
  touch $out
''
