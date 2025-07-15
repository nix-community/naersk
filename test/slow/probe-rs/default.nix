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
pkgs.runCommand "probe-rs-test"
{
  buildInputs = [ app ];
} "rtthost --help && touch $out"
