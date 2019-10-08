{ lib, writeText, runCommand, remarshal }:
with
  { builtinz =
      builtins //
      import ./builtins
        { inherit lib writeText remarshal runCommand ; };
  };
rec
{
    # The list of _all_ crates (incl. transitive dependencies) with name,
    # version and sha256 of the crate
    # Example:
    #   [ { name = "wabt", version = "2.0.6", sha256 = "..." } ]
    mkVersions = cargolock:
      if builtins.hasAttr "metadata" cargolock then

        # TODO: this should nub by <pkg-name>-<pkg-version>
        (lib.concatMap (x:
          with { mdk = mkMetadataKey x.name x.version; };
          ( lib.optional (builtins.hasAttr mdk cargolock.metadata)
              { inherit (x) version name;
                sha256 = cargolock.metadata.${mkMetadataKey x.name x.version};
              }
          ) ++ (lib.concatMap (parseDependency cargolock) (x.dependencies or []))

        )
        cargolock.package)
      else [];

    # Turns "lib-name lib-ver (registry+...)" to [ { name = "lib-name", etc } ]
    # iff the package is present in the Cargo.lock (otherwise returns [])
    parseDependency = cargolock: str:
      with rec
        { components = lib.splitString " " str;
          name = lib.elemAt components 0;
          version = lib.elemAt components 1;
          mdk = mkMetadataKey name version;
        };
      ( lib.optional (builtins.hasAttr mdk cargolock.metadata)
      (
      with
        { sha256 = cargolock.metadata.${mkMetadataKey name version};
        };
      { inherit name version sha256; }
      ));


    # crafts the key used to look up the sha256 in the cargo lock; no
    # robustness guarantee
    mkMetadataKey = name: version:
      "checksum ${name} ${version} (registry+https://github.com/rust-lang/crates.io-index)";

    # A cargo lock that only includes the transitive dependencies of the
    # package (and the package itself). This package is Nix-generated and thus
    # only the transitive dependencies contribute to the package's derivation.
    cargolockFor = cargolock: name: version:
      with rec
        { tdeps = transitiveDeps cargolock name version;
          tdepPrefix = dep: "checksum ${dep.name} ${dep.version}";
          isTransitiveDep = p: lib.any
            (d: d.package.name == p.name && d.package.version == p.version)
            tdeps;
          isTransitiveDepChecksumKey = k:
            lib.any (tdep: lib.hasPrefix (tdepPrefix tdep.package) k) tdeps;
        };
      cargolock //
        { package = lib.filter (p:
            (p.name == name && p.version == version) ||
            (isTransitiveDep p))  cargolock.package;

          metadata = lib.filterAttrs (k: _: isTransitiveDepChecksumKey k)
            cargolock.metadata;
        };

    # A stripped down Cargo.toml, similar to cargolockFor
    cargotomlFor = name: version:
      { package =
          { name = "dummy";
            version = "0.1.0";
            edition = "2018";
          };
        dependencies =
          { ${name} = version; };
      };

    # A very minimal 'src' which makes cargo happy nonetheless
    dummySrc =
      { cargoconfig   # string
      , cargotomls   # attrset
      , cargolock   # attrset
      , patchedSources # list of paths that should be copied to the output
      }:
      let
        config = writeText "config" cargoconfig;
        cargolock' = builtinz.writeTOML "Cargo.lock" cargolock;
        fixupCargoToml = cargotoml:
          let attrs =
                # Since we pretend everything is a lib, we remove any mentions
                # of binaries
                removeAttrs cargotoml [ "bin" "example" "lib" "test" "bench" ];
          in attrs // lib.optionalAttrs (lib.hasAttr "package" attrs) {
                        package = removeAttrs attrs.package [ "build" ];
                      };
        cargotomlss = writeText "foo"
          (lib.concatStrings (lib.mapAttrsToList
            (k: v: "${k}\n${builtinz.writeTOML "Cargo.toml" (fixupCargoToml v)}\n")
            cargotomls
          ));

      in
      runCommand "dummy-src" { inherit patchedSources; }
      ''
        mkdir -p $out/.cargo
        ${lib.optionalString (! isNull cargoconfig) "cp ${config} $out/.cargo/config"}
        cp ${cargolock'} $out/Cargo.lock

        for p in $patchedSources; do
          echo "Copying patched source $p to $out..."
          cp -R "$p" "$out/"
        done

        cat ${cargotomlss} | \
          while IFS= read -r member; do
            read -r cargotoml
            final_dir="$out/$member"
            mkdir -p "$final_dir"
            final_path="$final_dir/Cargo.toml"
            cp $cargotoml "$final_path"

            # make sure cargo is happy
            pushd $out/$member > /dev/null
            mkdir -p src
            touch src/lib.rs
            popd > /dev/null
          done
      '';

    mkPackages = cargolock:
      lib.foldl' lib.recursiveUpdate {} (
            map (p: { ${p.name} = { ${p.version} = p; } ; })
              cargolock.package);

    directDependencies = cargolock: name: version:
      with rec
        { packages = mkPackages cargolock;
          package = packages.${name}.${version};
        } ;

      lib.optionals (builtins.hasAttr "dependencies" package)
        (map parseDependency' package.dependencies);

    transitiveDeps = cargolock: name: version:
      with
        { wrap = p:
            { key = "${p.name}-${p.version}";
              package = p;
            };
          packages = mkPackages cargolock;
        };
      builtins.genericClosure
      { startSet = [ (wrap packages.${name}.${version}) ];
        operator = p: map (dep: wrap (packages.${dep.name}.${dep.version})) (
          (lib.optionals (builtins.hasAttr "dependencies" p.package)
            (map parseDependency' p.package.dependencies)));
      };

    # turns "<package> <version> ..." into { name = <package>, version = <version>; }
    parseDependency' = str:
      with { components = lib.splitString " " str; };
      { name = lib.elemAt components 0; version = lib.elemAt components 1; };
}
