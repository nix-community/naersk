{ lib
, runCommand
, symlinkJoin
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
      symlinkJoin
      cargo
      rustc
      zstd
      fetchurl
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
        libb.findGitDependencies { inherit (config) cargotomls; };
    in
      import ./build.nix
        (
          defaultBuildAttrs // {
            pname = config.packageName;
            version = config.packageVersion;
            preBuild = lib.optionalString (!config.isSingleStep) ''
              # Cargo uses mtime, and we write `src/lib.rs`, `src/main.rs` and
              # `./build.rs` in the dep build step, so make sure cargo
              # rebuilds stuff
              for file in src/lib.rs src/main.rs build.rs; do
                if [ -f "$file" ]; then touch "$file"; fi
              done
            '';
            inherit (config) src cargoTestCommands copyTarget copyBins copyBinsFilter copyDocsToSeparateOutput;
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
