{ naersk, pkgs, ... }:
let
  app = naersk.buildPackage {
    src = ./fixtures;
    nativeBuildInputs = with pkgs; [ makeWrapper ];
    postInstall = ''
      wrapProgram $out/bin/app --set FAVORITE_SHOW 'The Office'
    '';
  };

in
pkgs.runCommand "post-install-hook-test" { buildInputs = [ app ]; } ''
  app && touch $out
''
