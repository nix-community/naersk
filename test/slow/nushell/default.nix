{
  sources,
  pkgs,
  ...
}: let
  fenix = import sources.fenix {};

  toolchain = fenix.fromToolchainFile {
    file = "${sources.nushell}/rust-toolchain.toml";
    sha256 = "sha256-Zk2rxv6vwKFkTTidgjPm6gDsseVmmljVt201H7zuDkk=";
  };

  naersk = pkgs.callPackage ../../../default.nix {
    cargo = toolchain;
    rustc = toolchain;
  };

  app = naersk.buildPackage {
    src = sources.nushell;

    nativeBuildInputs = with pkgs; [pkg-config];

    buildInputs = with pkgs;
      [openssl]
      ++ lib.optionals stdenv.isDarwin [zlib libiconv darwin.Libsystem darwin.Security darwin.apple_sdk.frameworks.Foundation];

    LIBCLANG_PATH = "${pkgs.clang.cc.lib}/lib";
  };
in
  pkgs.runCommand "nushell-test"
  {
    buildInputs = [app];
  } "nu -c 'echo yes!' && touch $out"
