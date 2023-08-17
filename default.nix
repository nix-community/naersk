{ cargo
, darwin
, fetchurl
, jq
, lib
, lndir
, remarshal
, formats
, rsync
, runCommandLocal
, rustc
, stdenv
, writeText
, zstd
, clippy
}@defaultBuildAttrs:

let
  libb = import ./lib.nix { inherit lib writeText runCommandLocal remarshal formats; };

  builtinz = builtins // import ./builtins
    { inherit lib writeText remarshal runCommandLocal formats; };

  mkConfig = arg:
    import ./config.nix { inherit lib arg libb builtinz; };

  buildPackage = arg:
    let
      config = mkConfig arg;
      gitDependencies =
        libb.findGitDependencies { inherit (config) cargolock gitAllRefs gitSubmodules; };
      cargoconfig =
        if builtinz.pathExists (toString config.root + "/.cargo/config")
        then (config.root + "/.cargo/config")
        else null;
      build = args: import ./build.nix (
        {
          inherit gitDependencies;
          version = config.packageVersion;
        } // config.buildConfig // defaultBuildAttrs // args
      );

      # the dependencies from crates.io
      buildDeps =
        build
          {
            pname = "${config.packageName}-deps";
            src = libb.dummySrc {
              inherit cargoconfig;
              inherit (config) cargolock cargotomls copySources copySourcesFrom;
            };
            inherit (config) userAttrs;
            # TODO: custom cargoTestCommands should not be needed here
            cargoTestCommands = map (cmd: "${cmd} || true") config.buildConfig.cargoTestCommands;
            copyTarget = true;
            copyBins = false;
            copyBinsFilter = ".";
            copyDocsToSeparateOutput = false;
            postInstall = false;
            builtDependencies = [];
          };

      # the top-level build
      buildTopLevel =
        let
          drv =
            build
              {
                pname = config.packageName;
                inherit (config) userAttrs src;
                builtDependencies = lib.optional (! config.isSingleStep) buildDeps;
              };
        in
          drv.overrideAttrs config.overrideMain;
    in
      buildTopLevel;
in
{ inherit buildPackage; }
