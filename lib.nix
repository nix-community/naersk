{ lib, writeText, runCommand, remarshal }:
rec
{

    # creates an attrset from package name to package version + sha256
    # (note: this includes the package's dependencies)
    mkVersions = packageName: cargolock:
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
        (builtins.filter (v: v.name != packageName) cargolock.package))
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

    # turns "<package> <version> ..." into { name = <package>, version = <version>; }
    parseDependency' = str:
      with { components = lib.splitString " " str; };
      { name = lib.elemAt components 0; version = lib.elemAt components 1; };


    # crafts the key used to look up the sha256 in the cargo lock; no
    # robustness guarantee
    mkMetadataKey = name: version:
      "checksum ${name} ${version} (registry+https://github.com/rust-lang/crates.io-index)";

    cargolockFor = cargolock: _: _: cargolock;
    cargolockFor' = cargolock: name: version:
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

    transitiveDeps = cargolock: name: version:
      with
        { wrap = p:
            { key = "${p.name}-${p.version}";
              package = p;
            };
          packages = lib.foldl' lib.recursiveUpdate {} (
            map (p: { ${p.name} = { ${p.version} = p; } ; })
              cargolock.package);
        };
      builtins.genericClosure
      { startSet = [ (wrap packages.${name}.${version}) ];
        operator = p: map (dep: wrap (packages.${dep.name}.${dep.version})) (
          (lib.optionals (builtins.hasAttr "dependencies" p.package)
            (map parseDependency' p.package.dependencies)));
      };


    readTOML = f: builtins.fromTOML (builtins.readFile f);
    writeTOML = attrs: runCommand "write-toml"
      { buildInputs = [ remarshal ]; }
      ''
        remarshal \
          -if json \
          -i ${writeText "toml-json" (builtins.toJSON attrs)} \
          -of toml \
          -o $out
      '';
}
