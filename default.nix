{ lib
, runCommand
, symlinkJoin
, stdenv
, writeText
, llvmPackages
, jq
, rsync
, darwin
, remarshal
, cargo
, rustc
}:

with
  { libb = import ./lib.nix { inherit lib writeText runCommand remarshal; }; };

let
  defaultBuildAttrs =
      { inherit
          llvmPackages
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
          rustc;
      }; in

let
  builtinz =
      builtins //
      import ./builtins
        { inherit lib writeText remarshal runCommand ; }; in

# Crate building
with rec
  {
      commonAttrs = src: attrs: rec
        { usePureFromTOML = attrs.usePureFromTOML or true;
          readTOML = builtinz.readTOML usePureFromTOML;

          # The members we want to build
          wantedMembers =
            lib.mapAttrsToList (member: _cargotoml: member) wantedMemberCargotomls;

          # Member path to cargotoml
          wantedMemberCargotomls =
            let pred =
              if ! isWorkspace
              then (_member: _cargotoml: true)
              else
                if builtins.hasAttr "targets" attrs
                then (_member: cargotoml: lib.elem cargotoml.package.name attrs.targets)
                else (member: _cargotoml: member != "."); in
            lib.filterAttrs pred cargotomls;

          # All cargotoml, from path to nix object
          cargotomls =
            let readTOML = builtinz.readTOML usePureFromTOML; in

            { "." = toplevelCargotoml; } //
            lib.optionalAttrs isWorkspace
            (lib.listToAttrs
              (map
                (member:
                  { name = member;
                    value = readTOML (src + "/${member}/Cargo.toml");
                  }
                )
                (toplevelCargotoml.workspace.members or [])
              )
            );

          # Are we building a workspace (or is this a simple crate) ?
          isWorkspace = builtins.hasAttr "workspace" toplevelCargotoml;

          # The top level Cargo.toml, either a workspace or package
          toplevelCargotoml = readTOML (src + "/Cargo.toml");

          # The cargo lock
          cargolock = readTOML (src + "/Cargo.lock");

          # The list of paths to Cargo.tomls. If this is a workspace, the paths
          # are the members. Otherwise, there is a single path, ".".
          cratePaths = lib.concatStringsSep "\n" wantedMembers;
          crateDependencies = libb.mkVersions cargolock;
          preBuild = ''
            # Cargo uses mtime, and we write `src/main.rs` in the dep build
            # step, so make sure cargo rebuilds stuff
            find . -type f -name '*.rs' -exec touch {} +
          '';
          cargoBuild = attrs.cargoBuild or ''
            cargo build "''${cargo_release}" \
              --frozen \
              -j $NIX_BUILD_CORES \
              -Z unstable-options \
              --out-dir out
          '';
          cargoTestCommands = attrs.cargoTestCommands or [
            ''cargo test "''${cargo_release}" --frozen -j $NIX_BUILD_CORES''
          ];
        };
      buildPackageSingleStep = src: attrs:
        with (commonAttrs src attrs);
        import ./build.nix src
          ( defaultBuildAttrs //
            { name = "some-name";
              version = "some-version";
              inherit cratePaths crateDependencies cargoBuild cargoTestCommands;
            } //
            (removeAttrs attrs [ "targets" "usePureFromTOML" "cargotomls" ])
          );

      buildPackageIncremental = src: attrs:
        with (commonAttrs src attrs);
        import ./build.nix src
          (defaultBuildAttrs //
            { name = "foo";
              version = "bar";
              inherit cratePaths crateDependencies preBuild cargoBuild cargoTestCommands;
            } //
            (removeAttrs attrs [ "targets" "usePureFromTOML" "cargotomls" ]) //
            { builtDependencies =
                [(
                  import ./build.nix
                  (libb.dummySrc
                    { cargoconfig =
                        if builtinz.pathExists (src + "/.cargo/config")
                        then builtins.readFile (src + "/.cargo/config")
                        else "";
                      cargolock = cargolock;
                      cargotomls = cargotomls;
                    }
                  )
                  (defaultBuildAttrs //
                    { name = "foo-deps";
                      version = "bar";
                      inherit cratePaths crateDependencies cargoBuild;
                    } //
                  (removeAttrs attrs [ "targets" "usePureFromTOML" "cargotomls" ]) //
                  { preBuild = "";
                    cargoTestCommands = map (cmd: "${cmd} || true") cargoTestCommands;
                    copyTarget = true;
                    copyBins = false;
                    copyDocsToSeparateOutput = false;
                    name = "some-name";
                  }
                  )
                )];
            });
  };

{ inherit buildPackageSingleStep buildPackageIncremental crates;
  buildPackage = buildPackageIncremental;
}
