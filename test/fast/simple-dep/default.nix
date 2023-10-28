{
  naersk,
  pkgs,
  ...
}: rec {
  default = naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
  };

  withCompressTarget = naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
    compressTarget = true;
  };

  withoutCompressTarget = naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
    compressTarget = false;
  };

  withDoc = naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
    doDoc = true;
  };

  withoutDoc = naersk.buildPackage {
    src = ./fixtures;
    doCheck = true;
    doDoc = false;
  };

  # Tests that the builtDependencies derivation can successfully be unpacked and
  # that it actually contains Cargo's output artifacts.
  #
  # If the result is ever empty, Cargo will still succeed in building the top
  # level crate, except it will need to rebuild all dependencies from scratch,
  # which is wasteful.
  #
  # See: https://github.com/nix-community/naersk/issues/202.
  depsTargetNotEmptyWhenCompressed =
    pkgs.runCommand "test" {
      inherit (withCompressTarget) builtDependencies;
    } ''
      for dep in $builtDependencies; do
        mkdir dst
        ${pkgs.zstd}/bin/zstd -d "$dep/target.tar.zst" --stdout | tar -x -C ./dst

        if [ -z "$(ls -A ./dst)" ]; then
          echo target directory is empty: "$dep"
          return 1
        fi

        rm -rf ./dst
      done

      # Success
      touch $out
    '';

  # Same as the one above, just for `withoutCompressTarget`
  depsTargetNotEmptyWhenNotCompressed =
    pkgs.runCommand "test" {
      inherit (withoutCompressTarget) builtDependencies;
    } ''
      for dep in $builtDependencies; do
        if [ -z "$(ls -A "$dep"/target)" ]; then
          echo target directory is empty: "$dep"
          return 1
        fi
      done

      # Success
      touch $out
    '';
}
