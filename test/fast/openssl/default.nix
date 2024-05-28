# OpenSSL needs `pkg-config` and `openssl` buildInputs. This tests whether we correctly supply them automatically.

{ naersk, pkgs, ... }:

let
  # Whether the nixpkgs is version 23 or newer, because in older nixpkgs, rustc is too old to build openssl.
  buildIt = with pkgs.lib;
    (strings.toInt ((builtins.elemAt (splitString "." trivial.version) 0)) >= 23);
in

if buildIt then
  naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
  }
else
  builtins.trace ''
      Not building OpenSSL test, because Rust from nixpkgs under major version 23 cannot build OpenSSL
      Current nixpkgs version: ${pkgs.lib.trivial.version}
    ''

    pkgs.stdenv.mkDerivation {
      name = "not-building-openssl-test";

      dontUnpack = true;

      buildPhase = ''
        echo Not building OpenSSL test, because Rust from nixpkgs under major version 23 cannot build OpenSSL
        echo Current nixpkgs version: ${pkgs.lib.trivial.version}
      '';

      installPhase = "mkdir $out";
    }
