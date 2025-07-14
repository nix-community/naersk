{ sources, naersk, pkgs, fenix, ... }:
let
  app = naersk.buildPackage {
    src = sources.probe-rs;

    buildInputs = with pkgs; [
      pkg-config
      libusb1
      openssl
    ] ++ lib.optionals stdenv.isDarwin [
      darwin.DarwinTools
      darwin.apple_sdk.frameworks.AppKit
    ];
  };

in
if builtins.compareVersions pkgs.lib.version "22.11" <= 0 then
  # Executing this test requires nixpkgs > 22.11 due to changes to the TOML
  # serialization function.
  #
  # See `writeTOML` in this repository for more details.
  true
else
  pkgs.runCommand "probe-rs-test"
  {
    buildInputs = [ app ];
  } "rtthost --help && touch $out"
