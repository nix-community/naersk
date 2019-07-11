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

with
  { defaultBuildAttrs =
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
      };
  };

with
  { builtinz =
      builtins //
      import ./builtins.nix
        { inherit writeText remarshal runCommand ; };
  };

# Crate building
with rec
  {
      commonAttrs = src: attrs: rec
        { cargolockPath = attrs.cargolockPath or null;
          cargotomlPath = attrs.cargotomlPath or null;
          cargolock =
            if isNull cargolockPath then
              builtinz.readTOML "${src}/Cargo.lock"
            else
              builtinz.readTOML cargolockPath;
          rootCargotoml =
            if isNull cargotomlPath then
              builtinz.readTOML "${src}/Cargo.toml"
            else
              builtinz.readTOML cargotomlPath;

          # All the Cargo.tomls, including the top-level one
          cargotomls =
            if builtins.hasAttr "package" rootCargotoml then
              [rootCargotoml]
            else
              with { members = rootCargotoml.workspace.members or []; };
              lib.filter (cargotoml:
                if builtins.hasAttr "targets" attrs then
                  lib.elem cargotoml.package.name attrs.targets
                else true
              ) ( map
                (member: (builtinz.readTOML "${src}/${member}/Cargo.toml"))
                members );

          # The list of paths to Cargo.tomls. If this is a workspace, the paths
          # are the members. Otherwise, there is a single path, ".".
          cratePaths =
            with rec
              { workspaceMembers = rootCargotoml.workspace.members or null;
              };

            if isNull workspaceMembers then "."
            else lib.concatStringsSep "\n" workspaceMembers;
          crateDependencies = libb.mkVersions cargolock;
          targetInstructions =
            if builtins.hasAttr "targets" attrs then
              lib.concatMapStringsSep " " (target: "-p ${target}") attrs.targets
            else "";
          cargoBuild = attrs.cargoBuild or
            "cargo build ${targetInstructions} --$CARGO_BUILD_PROFILE -j $NIX_BUILD_CORES";
        };
      buildPackage = src: attrs:
        with (commonAttrs src attrs);
        import ./build.nix src
          ( defaultBuildAttrs //
            { name =
                if lib.length cargotomls == 0 then
                  abort "Found no cargotomls"
                else if lib.length cargotomls == 1 then
                  (lib.head cargotomls).package.name
                else
                  "${(lib.head cargotomls).package.name}-and-others";
              version = (lib.head cargotomls).package.version;
              inherit cratePaths crateDependencies cargoBuild;
            } //
            (removeAttrs attrs [ "targets"])
          );

      buildPackageIncremental = src: attrs:
        with (commonAttrs src attrs);
        with rec
          # FIXME: directDependencies should be built on a per-cargotoml basis.
          # All dependencies are not available in every member.
          # Also, if a dependency is shared between two cargotomls, there's
          # (most of the time) no point recompiling it
          { buildDepsScript = writeText "prebuild-script"
              ''
                cat ${builtinz.writeJSON "crates" ((directDependenciesList))} |\
                  jq -r \
                    --arg cbp $CARGO_BUILD_PROFILE \
                    --arg nbc $NIX_BUILD_CORES \
                    '.[] | "cargo build --\($cbp) -j \($nbc) -p \(.name):\(.version)"' |\
                    while IFS= read -r c
                    do
                      echo "Running build command '$c'"
                      $c || echo "WARNING: one some dependencies failed to build: $c"
                    done
              '';
            isMember = name:
              lib.elem name (map (ctoml: ctoml.package.name) cargotomls);

            isLocal = v:
              ! builtins.hasAttr "path" v;

            versions =
              lib.listToAttrs (
              map (v: { name = v.name; value = v.version; })
                crateDependencies);

            directDependenciesList =
              lib.filter (c:
                builtins.hasAttr c.name directDependencies) crateDependencies;

            directDependencies =
              lib.filterAttrs (_: v:
                lib.isString v ||
                (! builtins.hasAttr "path" v)
                ) (
              lib.foldr (x: y: x // y) {}
              (map (cargotoml:
                (lib.optionalAttrs (builtins.hasAttr "dependencies" cargotoml)
                  cargotoml.dependencies) //
                (lib.optionalAttrs (builtins.hasAttr "dev-dependencies" cargotoml)
                  cargotoml.dev-dependencies)
                ) cargotomls
              ));
          };
        buildPackage src
          ((attrs) //
          { builtDependencies =
              [(
              buildPackage libb.dummySrc
                (attrs //
                { cargoBuild = "source ${buildDepsScript}";
                  doCheck = false;
                  cargolockPath = builtinz.writeTOML cargolock;
                  cargotomlPath = builtinz.writeTOML
                    (
                    { package = { name = "dummy"; version = "0.0.0"; }; } //
                        { dependencies = directDependencies; }
                    )
                    ;
                name =
                if lib.length cargotomls == 0 then
                  abort "Found no cargotomls"
                else if lib.length cargotomls == 1 then
                  "${(lib.head cargotomls).package.name}-deps"
                else
                  "${(lib.head cargotomls).package.name}-and-others-deps";
                })
              )];
          });
  };

{ inherit buildPackage buildPackageIncremental crates;
}
