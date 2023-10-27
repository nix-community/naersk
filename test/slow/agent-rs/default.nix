{
  sources,
  pkgs,
  ...
}: let
  fenix = import sources.fenix {};

  toolchain = fenix.fromToolchainFile {
    file = "${sources.agent-rs}/rust-toolchain.toml";
    sha256 = "sha256-DzNEaW724O8/B8844tt5AVHmSjSQ3cmzlU4BP90oRlY=";
  };

  naersk = pkgs.callPackage ../../../default.nix {
    cargo = toolchain;
    rustc = toolchain;
  };
in
  naersk.buildPackage {
    src = sources.agent-rs;

    buildInputs =
      [
        pkgs.openssl
        pkgs.pkg-config
        pkgs.perl
      ]
      ++ pkgs.lib.optional pkgs.stdenv.isDarwin pkgs.libiconv;
  }
