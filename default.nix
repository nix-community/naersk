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
          cargotoml =
            if isNull cargotomlPath then
              builtinz.readTOML "${src}/Cargo.toml"
            else
              builtinz.readTOML cargotomlPath;
          # The list of paths to Cargo.tomls. If this is a workspace, the paths
          # are the members. Otherwise, there is a single path, ".".
          cratePaths =
            with rec
              { workspaceMembers = cargotoml.workspace.members or null;
              };

            if isNull workspaceMembers then "."
            else lib.concatStringsSep "\n" workspaceMembers;
          crateDependencies = libb.mkVersions cargolock;
          directDependencies = lib.filter
            (v:
              lib.elem v.name (builtins.attrNames cargotoml.dependencies) ||
              (builtins.hasAttr "dev-dependencies" cargotoml &&
                lib.elem v.name (builtins.attrNames cargotoml.dev-dependencies)
              )
            )
            (libb.mkVersions cargolock);
        };
      buildPackage = src: attrs:
        with (commonAttrs src attrs);
        import ./build.nix src
          ( defaultBuildAttrs //
            { name = "foo";  # TODO: infer from toml
              inherit cratePaths crateDependencies;
            } //
            attrs
          );

      buildPackageIncremental = src: attrs:
        with (commonAttrs src attrs);
        with
          { buildDepsScript = writeText "prebuild-script"
              ''
                cat ${builtinz.writeJSON "crates" directDependencies} |\
                  jq -r \
                    --arg cbp $CARGO_BUILD_PROFILE \
                    --arg nbc $NIX_BUILD_CORES \
                    '.[] | "cargo build --\($cbp) -j \($nbc) -p \(.name):\(.version)"' |\
                    while IFS= read -r c
                    do
                      echo "Running build command $c"
                      $c
                    done
              '';
          };
        buildPackage src
          (attrs //
          { builtDependencies = [
              (
                buildPackage libb.dummySrc
                  (attrs //
                  { cargoBuild = "source ${buildDepsScript}";
                    doCheck = false;
                    cargolockPath = builtinz.writeTOML cargolock;
                    cargotomlPath = builtinz.writeTOML
                      (
                      { package = { name = "dummy"; version = "0.0.0"; };
                        dependencies = cargotoml.dependencies;
                      } //
                        (lib.optionalAttrs
                          (builtins.hasAttr "dev-dependencies" cargotoml)
                            { inherit (cargotoml) dev-dependencies; }
                        )
                      )
                      ;
                  })
              )
              ];
          });
  };

{ inherit buildPackage buildPackageIncremental crates;
}
