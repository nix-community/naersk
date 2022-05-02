{ naersk, ... }:

naersk.buildPackage {
  src = ./fixtures;
  doCheck = true;
  cargoOptions = (opts: opts ++ [ "--locked" ]);
}
