{ system, fast, nixpkgs }:
let
  sources = import ../nix/sources.nix;

  pkgs = import ../nix {
    inherit system nixpkgs;
  };

  naersk = pkgs.callPackage ../default.nix {
    inherit (pkgs.rustPackages) cargo rustc;
  };

  args = {
    inherit sources pkgs naersk;
  };

  fastTests = import ./fast args;
  slowTests = import ./slow args;

  # Because `nix-build` doesn't recurse into attribute sets, some of our more
  # nested tests (e.g. `fastTests.foo.bar`) normally wouldn't be executed.
  #
  # To avoid that, we're recursively flattening all tests into a list, which
  # `nix-build` then evaluates in its entirety.
  runTests = tests:
    pkgs.lib.collect pkgs.lib.isDerivation tests;

in
runTests (
  fastTests // pkgs.lib.optionalAttrs (!fast) slowTests
)
