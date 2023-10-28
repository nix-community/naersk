{
  system ? builtins.currentSystem,
  nixpkgs ? "nixpkgs",
  inNixShell ? null,
}: let
  sources = import ./sources.nix;
  sources_nixpkgs =
    if builtins.hasAttr nixpkgs sources
    then sources."${nixpkgs}"
    else abort "No entry ${nixpkgs} in sources.json";
in
  import sources_nixpkgs {inherit system;}
