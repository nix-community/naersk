{ naersk, pkgs, ... }: {
  default = naersk.buildPackage {
    src = pkgs.symlinkJoin {
      name = "src";
      paths = [ ./fixtures ];
    };
  };
}
