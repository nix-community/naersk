let
  pkgs = import ../nix {};
in pkgs.mkShell
  { nativeBuildInputs = [ pkgs.cargo pkgs.rustfmt ]; }
