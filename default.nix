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
}:

with
  { libb = import ./lib.nix { inherit lib writeText runCommand remarshal; }; };

let
  defaultBuildAttrs =
      { inherit
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

          override = attrs.override or (_oldAttrs: {});

          packageName = attrs.name or (if isWorkspace then "rust-workspace" else "rust-package");

          # The members we want to build
          # (list of directory names)
          wantedMembers =
            lib.mapAttrsToList (member: _cargotoml: member) wantedMemberCargotomls;

          # Member path to cargotoml
          # (attrset from directory name to Nix object)
          wantedMemberCargotomls =
            let pred =
              if ! isWorkspace
              then (_member: _cargotoml: true)
              else
                if builtins.hasAttr "targets" attrs
                then (_member: cargotoml: lib.elem cargotoml.package.name attrs.targets)
                else (member: _cargotoml: member != "."); in
            lib.filterAttrs pred cargotomls;

          # All cargotomls, from path to nix object
          # (attrset from directory name to Nix object)
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


          # The list of _all_ crates (incl. transitive dependencies) with name,
          # version and sha256 of the crate
          # Example:
          #   [ { name = "wabt", version = "2.0.6", sha256 = "..." } ]
          crateDependencies = libb.mkVersions cargolock;

          preBuild = ''
            # Cargo uses mtime, and we write `src/lib.rs` and `src/main.rs`in
            # the dep build step, so make sure cargo rebuilds stuff
            if [ -f src/lib.rs ] ; then touch src/lib.rs; fi
            if [ -f src/main.rs ] ; then touch src/main.rs; fi
          '';

          cargoTestCommands = attrs.cargoTestCommands or [
            ''cargo test "''${cargo_release}" -j $NIX_BUILD_CORES''
          ];
        };
      buildPackageSingleStep = src: attrs:
        with (commonAttrs src attrs);
        let finalDrv = import ./build.nix src
          ( defaultBuildAttrs //
            { name = packageName;
              inherit crateDependencies cargoTestCommands;
            } //
            (removeAttrs attrs [ "targets" "usePureFromTOML" "cargotomls" "override"])
          );
        in finalDrv.overrideAttrs override;

      buildPackageIncremental = src: attrs:
        with (commonAttrs src attrs);
        let
          someNameDrv =
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
              { name = "${packageName}-deps";
                inherit crateDependencies ;
              } //
            (removeAttrs attrs [ "targets" "usePureFromTOML" "cargotomls" "override"]) //
            { preBuild = "";
              cargoTestCommands = map (cmd: "${cmd} || true") cargoTestCommands;
              copyTarget = true;
              copyBins = false;
              copyDocsToSeparateOutput = false;
            }
            );
          finalDrv =
            import ./build.nix src
              (defaultBuildAttrs //
                { name = packageName;
                  inherit crateDependencies preBuild cargoTestCommands;
                } //
                (removeAttrs attrs [ "targets" "usePureFromTOML" "cargotomls" "override" ]) //
                { builtDependencies = [ (someNameDrv.overrideAttrs override) ]; }
                );
        in finalDrv.overrideAttrs override;
  };

{ inherit buildPackageSingleStep buildPackageIncremental;
  buildPackage = buildPackageIncremental;
}
