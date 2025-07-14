{ pkgs, sources, naersk, fenix, ... }: {
  lorri = pkgs.callPackage ./lorri { inherit sources naersk fenix; };
  probe-rs = pkgs.callPackage ./probe-rs { inherit sources naersk fenix; };
  ripgrep-all = pkgs.callPackage ./ripgrep-all { inherit sources naersk fenix; };
  rustlings = pkgs.callPackage ./rustlings { inherit sources naersk fenix; };
  talent-plan = pkgs.callPackage ./talent-plan { inherit sources naersk fenix; };
} //

  /* nushell doesn't build on Darwin */
pkgs.lib.optionalAttrs pkgs.stdenv.isLinux { nushell = pkgs.callPackage ./nushell { inherit sources naersk fenix; }; }
