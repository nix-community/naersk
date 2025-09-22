{ naersk, ... }:

naersk.buildPackage {
  src = ./.;
  # add `-vv` which can lead to issues with JSON output parsing
  cargoBuildOptions = (def: def ++ [ "-vv" ]);
}
