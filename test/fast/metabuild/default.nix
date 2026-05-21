{
  naersk,
  fenix,
  system,
  ...
}:
let
  toolchain =
    with fenix.packages.${system};
    combine [
      latest.rustc
      latest.cargo
    ];

  naersk' = naersk.override {
    cargo = toolchain;
    rustc = toolchain;
  };
in

naersk'.buildPackage {
  src = ./fixtures;
}
