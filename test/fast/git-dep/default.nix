{ naersk, ... }:

naersk.buildPackage {
  src = ./fixtures;
  doCheck = true;
}
