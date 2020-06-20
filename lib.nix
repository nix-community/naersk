{ lib, writeText, runCommand, remarshal, fetchgit }:
let
  builtinz =
    builtins // import ./builtins
      { inherit lib writeText remarshal runCommand; };
in
rec
{
  # The list of _all_ crates (incl. transitive dependencies) with name,
  # version and sha256 of the crate
  # Example:
  #   [ { name = "wabt", version = "2.0.6", sha256 = "..." } ]
  mkVersions = cargolock:
    if builtins.hasAttr "metadata" cargolock then

      # TODO: this should nub by <pkg-name>-<pkg-version>
      (
        lib.concatMap (
          x:
            let
              mdk = mkMetadataKey x.name x.version;
            in
              (
                lib.optional (builtins.hasAttr mdk cargolock.metadata)
                  {
                    inherit (x) version name;
                    sha256 = cargolock.metadata.${mkMetadataKey x.name x.version};
                  }
              ) ++ (lib.concatMap (parseDependency cargolock) (x.dependencies or []))

        )
          cargolock.package
      )
    else if builtins.hasAttr "package" cargolock then
      map (
        p:
          {
            inherit (p) name version;
            sha256 = p.checksum;
          }
      ) (builtins.filter (builtins.hasAttr "checksum") cargolock.package)
    else [];

  # Turns "lib-name lib-ver (registry+...)" to [ { name = "lib-name", etc } ]
  # iff the package is present in the Cargo.lock (otherwise returns [])
  parseDependency = cargolock: str:
    let
      components = lib.splitString " " str;
      name = lib.elemAt components 0;
      version = lib.elemAt components 1;
      mdk = mkMetadataKey name version;
    in
      lib.optional (builtins.hasAttr mdk cargolock.metadata)
        (
          let
            sha256 = cargolock.metadata.${mkMetadataKey name version};
          in
            { inherit name version sha256; }
        );


  # crafts the key used to look up the sha256 in the cargo lock; no
  # robustness guarantee
  mkMetadataKey = name: version:
    "checksum ${name} ${version} (registry+https://github.com/rust-lang/crates.io-index)";

  # a record:
  #   { "." = # '.' is the directory of the cargotoml
  #     [
  #       {
  #         name = "rand";
  #         url = "https://github.com/...";
  #         checkout = "/nix/store/checkout"
  #       }
  #     ]
  #   }
  findGitDependencies =
    { cargotomls
    , cargolock
    }:
      let
        tomlDependencies = cargotoml:
          lib.filter (x: ! isNull x) (
          lib.mapAttrsToList
            (k: v:
              if ! (lib.isAttrs v && builtins.hasAttr "git" v)
              then null
              else lib.filterAttrs (n: _: n == "rev" || n == "tag" || n == "branch") v //
                { name = k;
                  url = v.git;
                  key = v.rev or v.tag or v.branch or
                        (throw "No 'rev', 'tag' or 'branch' available to specify key");
                  checkout = builtins.fetchGit ({
                    url = v.git;
                  } // lib.optionalAttrs (v ? rev) {
                    rev = let
                            query = p: p.name == k && (lib.substring 0 (4 + lib.stringLength v.git) p.source) == "git+${v.git}";
                            extractRevision = url: lib.last (lib.splitString "#" url);
                            parseLock = lock: rec { inherit (lock) name source; revision = extractRevision source; };
                            packageLocks = builtins.map parseLock (lib.filter query cargolock.package);
                            match = lib.findFirst (p: lib.substring 0 7 p.revision == lib.substring 0 7 v.rev) null packageLocks;
                          in
                            if ! (isNull match) then match.revision else v.rev;
                  } // lib.optionalAttrs (v ? branch) {
                    ref = v.branch;
                  } // lib.optionalAttrs (v ? tag) {
                    ref = v.tag;
                  });
                }
            ) cargotoml.dependencies or {});
      in
        lib.mapAttrs (_: tomlDependencies) cargotomls;

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
          let
            attrs =
              # Since we pretend everything is a lib, we remove any mentions
              # of binaries
              removeAttrs cargotoml [ "bin" "example" "lib" "test" "bench" ];
          in
            attrs // lib.optionalAttrs (lib.hasAttr "package" attrs) {
              package = removeAttrs attrs.package [ "build" ];
            };

        # a list of tuples from member to cargo toml:
        #   "foo-member:/path/to/toml bar:/path/to/other-toml"
        cargotomlss = lib.mapAttrsToList
          (k: v: "${k}:${builtinz.writeTOML "Cargo.toml" (fixupCargoToml v)}")
          cargotomls;

      in
        runCommand "dummy-src"
          { inherit patchedSources cargotomlss; }
          ''
            mkdir -p $out/.cargo
            ${lib.optionalString (! isNull cargoconfig) "cp ${config} $out/.cargo/config"}
            cp ${cargolock'} $out/Cargo.lock

            for p in $patchedSources; do
              echo "Copying patched source $p to $out..."
              cp -R "$p" "$out/"
            done

            for tuple in $cargotomlss; do
                member="''${tuple%%:*}"
                cargotoml="''${tuple##*:}"

                final_dir="$out/$member"
                mkdir -p "$final_dir"
                final_path="$final_dir/Cargo.toml"
                cp $cargotoml "$final_path"

                # make sure cargo is happy
                pushd $out/$member > /dev/null
                mkdir -p src
                touch src/lib.rs
                # pretend there's a `build.rs`, otherwise cargo doesn't build
                # the `[build-dependencies]`. Custom locations of build scripts
                # aren't an issue because we strip the `build` field in
                # `fixupCargoToml`; so cargo always thinks there's a build
                # script which is `./build.rs`.
                echo 'fn main(){}' > build.rs
                popd > /dev/null
            done
          '';

  mkPackages = cargolock:
    lib.foldl' lib.recursiveUpdate {} (
      map (p: { ${p.name} = { ${p.version} = p; }; })
        cargolock.package
    );

  directDependencies = cargolock: name: version:
    let
      packages = mkPackages cargolock;
      package = packages.${name}.${version};
    in
      lib.optionals (builtins.hasAttr "dependencies" package)
        (map parseDependency' package.dependencies);

  transitiveDeps = cargolock: name: version:
    let
      wrap = p:
        {
          key = "${p.name}-${p.version}";
          package = p;
        };
      packages = mkPackages cargolock;
    in
      builtins.genericClosure
        {
          startSet = [ (wrap packages.${name}.${version}) ];
          operator = p: map (dep: wrap (packages.${dep.name}.${dep.version})) (
            (
              lib.optionals (builtins.hasAttr "dependencies" p.package)
                (map parseDependency' p.package.dependencies)
            )
          );
        };

  # turns "<package> <version> ..." into { name = <package>, version = <version>; }
  parseDependency' = str:
    let
      components = lib.splitString " " str;
    in
      { name = lib.elemAt components 0; version = lib.elemAt components 1; };
}
