{ naersk, pkgs, ... }:
let
docparse = naersk.buildPackage {
  root = ../../../docparse;

  src = builtins.filterSource (
    p: t:
      let
        p' = pkgs.lib.removePrefix (toString ../../../docparse + "/") p;
      in
      p' == "Cargo.lock" || p' == "Cargo.toml" || p' == "src" || p' == "src/main.rs"
  ) ../../../docparse;
};

readme = pkgs.runCommand "readme-gen" {} ''
  cat ${../../../README.tpl.md} > $out
  ${docparse}/bin/docparse ${../../../config.nix} >> gen
  sed -e '/GEN_CONFIGURATION/{r gen' -e 'd}' -i $out
'';

in
pkgs.runCommand "readme-test" {} ''
  diff ${../../../README.md} ${readme}
  touch $out
''
