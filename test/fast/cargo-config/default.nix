{
  sources,
  pkgs,
  ...
}: let
  fenix = import sources.fenix {};

  # Support for custom environmental variables was introduced in Cargo 1.56 and
  # our tests use nixpkgs-21.05 which contains an older version of Cargo, making
  # this test fail otherwise.
  toolchain = fenix.latest;

  naersk = pkgs.callPackage ../../../default.nix {
    cargo = toolchain.cargo;
    rustc = toolchain.rustc;
  };
in
  naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
  }
