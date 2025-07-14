{ sources, system, fenix, pkgs }:
let
  naersk = pkgs.callPackage ../default.nix {
    inherit (pkgs.rustPackages) cargo rustc;
  };

  # aggregate all derivations found (recursively) in the input attribute set.
  flatten = attrs:
    pkgs.lib.collect pkgs.lib.isDerivation attrs;

  fastTests = flatten (pkgs.callPackage ./fast { inherit naersk fenix; });
  slowTests = flatten (pkgs.callPackage ./slow { inherit sources naersk fenix; });

  collectResults = name: tests: pkgs.runCommand name { TESTS = tests; } ''
    echo tests successful
    touch $out
  '';

in
(collectResults "all-tests" (fastTests ++ slowTests)) //
  /* bit of a hack but super useful to the fast tests only */
{ fast = collectResults "fast-tests" fastTests; }
