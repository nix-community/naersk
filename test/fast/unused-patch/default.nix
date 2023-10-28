{
  naersk,
  pkgs,
  ...
}: let
  app = naersk.buildPackage {
    src = ./fixtures;
  };
in
  if builtins.compareVersions pkgs.lib.version "22.11" <= 0
  then
    # Executing this test requires nixpkgs > 22.11 due to changes to the TOML
    # serialization function.
    #
    # See `writeTOML` in this repository for more details.
    true
  else app
