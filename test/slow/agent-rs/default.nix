{ sources, naersk, pkgs, ... }:

naersk.buildPackage {
  src = sources.agent-rs;

  buildInputs = [
    pkgs.openssl
    pkgs.pkg-config
    pkgs.perl
  ] ++ pkgs.lib.optional pkgs.stdenv.isDarwin pkgs.libiconv;
}
