{ sources, ... }:
let
  pkgs = import sources.nixpkgs {
    overlays = [
      (import sources.nixpkgs-mozilla)
    ];
  };

  toolchain = (pkgs.rustChannelOf {
    rustToolchain = "${sources.nushell}/rust-toolchain.toml";
    sha256 = "sha256-Zk2rxv6vwKFkTTidgjPm6gDsseVmmljVt201H7zuDkk=";
  }).rust;

  naersk = pkgs.callPackage ../../../default.nix {
    cargo = toolchain;
    rustc = toolchain;
  };

  app = naersk.buildPackage {
    src = sources.nushell;
    nativeBuildInputs = with pkgs; [ pkg-config ];
    buildInputs = with pkgs; [ openssl ];
  };

in
pkgs.runCommand "nushell-test"
{
  buildInputs = [ app ];
} "nu -c 'echo yes!' && touch $out"
