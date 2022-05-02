{ sources, naersk, pkgs, ... }: {
  talent-plan-1 = naersk.buildPackage {
    src = "${sources.talent-plan}/rust/projects/project-1";
    doCheck = true;
  };

  talent-plan-2 = naersk.buildPackage {
    src = "${sources.talent-plan}/rust/projects/project-2";
    doCheck = true;
  };

  talent-plan-3 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-3";
}
