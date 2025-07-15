{ naersk, pkgs, ... }:
naersk.buildPackage {
  src = ./fixtures/app;
  doCheck = true;
  cargoOptions = (opts: opts ++ [ "--locked" ]);
}
