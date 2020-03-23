{ lib
, runCommand
, stdenv
, writeText
, jq
, rsync
, darwin
, remarshal
, cargo
, rustc
, zstd
, fetchurl
, lndir
}:

let
  libb = import ./lib.nix { inherit lib writeText runCommand remarshal; };

  defaultBuildAttrs = {
    inherit
      jq
      runCommand
      lib
      darwin
      writeText
      stdenv
      rsync
      remarshal
      cargo
      rustc
      zstd
      fetchurl
      lndir
      ;
  };

  builtinz = builtins // import ./builtins
    { inherit lib writeText remarshal runCommand; };
in
  # Crate building
let
  mkConfig = arg:
    import ./config.nix { inherit lib arg libb builtinz; };

  buildPackage = arg:
    let
      config = mkConfig arg;
      gitDependencies =
        libb.findGitDependencies { inherit (config) cargotomls cargolock; };
    in
      import ./build.nix
        (
          defaultBuildAttrs // {
            pname = config.packageName;
            version = config.packageVersion;
            preBuild = "";
            inherit (config) userAttrs src cargoTestCommands copyTarget copyBins copyBinsFilter copyDocsToSeparateOutput;
            inherit gitDependencies;
          } // config.buildConfig // {
            builtDependencies = lib.optional (! config.isSingleStep)
              (
                import ./build.nix
                  (
                    {
                      inherit gitDependencies;
                      src = libb.dummySrc {
                        cargoconfig =
                          if builtinz.pathExists (toString config.root + "/.cargo/config")
                          then builtins.readFile (config.root + "/.cargo/config")
                          else null;
                        cargolock = config.cargolock;
                        cargotomls = config.cargotomls;
                        inherit (config) patchedSources;
                      };
                    } // (
                      defaultBuildAttrs // {
                        pname = "${config.packageName}-deps";
                        version = config.packageVersion;
                      } // config.buildConfig // {
                        inherit (config) userAttrs;
                        preBuild = "";
                        # TODO: custom cargoTestCommands should not be needed here
                        cargoTestCommands = map (cmd: "${cmd} || true") config.buildConfig.cargoTestCommands;
                        copyTarget = true;
                        copyBins = false;
                        copyBinsFilter = ".";
                        copyDocsToSeparateOutput = false;
                        builtDependencies = [];
                      }
                    )
                  )
              );
          }
        );
in
  { inherit buildPackage; }
