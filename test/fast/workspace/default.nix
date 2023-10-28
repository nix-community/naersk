{naersk, ...}: {
  default = naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
  };

  withDoc = naersk.buildPackage {
    src = ./fixtures;
    doDoc = true;
    doCheck = true;
  };
}
