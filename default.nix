{ cargo
, darwin
, fetchurl
, jq
, lib
, lndir
, remarshal
, rsync
, runCommand
, rustc
, stdenv
, writeText
, zstd
}@defaultBuildAttrs:

let
  libb = import ./lib.nix { inherit lib writeText runCommand remarshal; };

  builtinz = builtins // import ./builtins
    { inherit lib writeText remarshal runCommand; };

  mkConfig = { arg, cargoConfig }:
    import ./config.nix { inherit lib arg libb builtinz cargoConfig; };

  buildPackage = arg:
    let
      # Config for cargo itself
      source = libb.resolveSource arg;
      configFile = source.root + "/.cargo/config.toml";
      cargoConfigText =
        if builtinz.pathExists configFile
        then builtins.readFile configFile
        else "";
      usePureFromTOML = arg.usePureFromTOML or true;
      readTOML = builtinz.readTOML usePureFromTOML;
      cargoConfig = readTOML cargoConfigText;
      # The project config
      config = mkConfig { inherit arg cargoConfig; };
      gitDependencies =
        libb.findGitDependencies { inherit (config) cargotomls cargolock; };
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
              inherit cargoConfigText;
              inherit (config) cargolock cargotomls copySources copySourcesFrom;
            };
            inherit (config) userAttrs;
            # TODO: custom cargoTestCommands should not be needed here
            cargoTestCommands = map (cmd: "${cmd} || true") config.buildConfig.cargoTestCommands;
            copyTarget = true;
            copyBins = false;
            copyBinsFilter = ".";
            copyDocsToSeparateOutput = false;
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
