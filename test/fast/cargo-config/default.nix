{ naersk, pkgs, ... }:

naersk.buildPackage {
  src = ./fixtures;
  doCheck = true;
}
