{ sources, naersk, pkgs, ... }:
let
  app = naersk.buildPackage {
    src = sources.nushell;

    nativeBuildInputs = with pkgs; [ pkg-config ];

    buildInputs = with pkgs; [ openssl ]
      ++ lib.optionals stdenv.isDarwin [ zlib libiconv darwin.Libsystem darwin.Security darwin.apple_sdk.frameworks.Foundation ];

    LIBCLANG_PATH = "${pkgs.clang.cc.lib}/lib";
  };

in
pkgs.runCommand "nushell-test"
{
  buildInputs = [ app ];
} "nu -c 'echo yes!' && touch $out"
