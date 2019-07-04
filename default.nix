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
              map
                (member: (builtinz.readTOML "${src}/${member}/Cargo.toml"))
                members;

          # The list of paths to Cargo.tomls. If this is a workspace, the paths
          # are the members. Otherwise, there is a single path, ".".
          cratePaths =
            with rec
              { workspaceMembers = rootCargotoml.workspace.members or null;
              };

            if isNull workspaceMembers then "."
            else lib.concatStringsSep "\n" workspaceMembers;
          crateDependencies = libb.mkVersions cargolock;
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
        with rec
          # FIXME: directDependencies should be built on a per-cargotoml basis.
          # All dependencies are not available in every member.
          # Also, if a dependency is shared between two cargotomls, there's
          # (most of the time) no point recompiling it
          { buildDepsScript = cargotoml: writeText "prebuild-script"
              ''
                cat ${builtinz.writeJSON "crates" ((directDependencies cargotoml))} |\
                  jq -r \
                    --arg cbp $CARGO_BUILD_PROFILE \
                    --arg nbc $NIX_BUILD_CORES \
                    '.[] | "cargo build --\($cbp) -j \($nbc) -p \(.name):\(.version)"' |\
                    while IFS= read -r c
                    do
                      echo "Running build command $c"
                      cat Cargo.toml
                      $c || echo "WARNING: one some dependencies failed to build: $c"
                    done
              '';
            isMember = name:
              lib.elem name (map (ctoml: ctoml.package.name) cargotomls);
            directDependencies = cargotoml: lib.filter
              (v:
                (builtins.hasAttr "dependencies" cargotoml &&
                  lib.elem v.name (builtins.attrNames cargotoml.dependencies) &&
                  ! isMember v.name
                ) ||
                (builtins.hasAttr "dev-dependencies" cargotoml &&
                  lib.elem v.name (builtins.attrNames cargotoml.dev-dependencies) &&
                  ! isMember v.name
                )
              )
              (libb.mkVersions cargolock);
          };
        buildPackage src
          (attrs //
          { builtDependencies = map (cargotoml:
              buildPackage libb.dummySrc
                (attrs //
                { cargoBuild = "source ${buildDepsScript cargotoml}";
                  doCheck = false;
                  cargolockPath = builtinz.writeTOML cargolock;
                  cargotomlPath = builtinz.writeTOML
                    (
                    { package = { name = "dummy"; version = "0.0.0"; }; } //
                      (
                      #lib.filterAttrs (k: v: ! isMember k) (
                      (lib.optionalAttrs
                        (builtins.hasAttr "dependencies" cargotoml)
                          { dependencies = lib.filterAttrs
                              (k: _: ! isMember k)
                              cargotoml.dependencies;
                          }
                      )) //
                      (
                      #lib.filterAttrs (k: v: ! isMember k) (
                      (lib.optionalAttrs
                        (builtins.hasAttr "dev-dependencies" cargotoml)
                          { dev-dependencies = lib.filterAttrs
                              (k: _: ! isMember k)
                              cargotoml.dev-dependencies;
                          }
                          #{ inherit (cargotoml) dev-dependencies; }
                      ))
                    )
                    ;
                  name = "${cargotoml.package.name}-deps";
                })
              ) cargotomls;
          });
  };

{ inherit buildPackage buildPackageIncremental crates;
}
