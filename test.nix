{ system ? builtins.currentSystem, fast ? false, nixpkgs ? "nixpkgs" }:

import ./test {
  inherit system fast nixpkgs;
}
