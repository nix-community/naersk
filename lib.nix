{ lib }:
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

    # crafts the key used to look up the sha256 in the cargo lock; no
    # robustness guarantee
    mkMetadataKey = name: version:
      "checksum ${name} ${version} (registry+https://github.com/rust-lang/crates.io-index)";
}
