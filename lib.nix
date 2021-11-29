{ lib, writeText, runCommand, remarshal }:
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
        # This returns all the git dependencies of a particular Cargo.toml.
        # tomlDependencies : Cargo.toml ->
        #   [
        #     {
        #       checkout = { rev = "abcd"; shortRev = "abcd"; outPath = ...; ... };
        #       key = "abcd";
        #       name = "rand";
        #       url = "https://github.com/...";
        #     }
        #     ...
        #   ]
        #
        # NOTE: this is terribly inefficient _and_ confusing:
        # * the lockfile is read once for every cargo toml entry (n^2)
        # * 'fromLockfile' is odd, instead of returning the first matched
        # revision it'll return a pseudo lockfile entry
      tomlDependencies = cargotoml:
        lib.filter (x: ! isNull x) (
          lib.mapAttrsToList
            (entryName: v: # The dependecy name + the entry from the cargo toml
              if ! (lib.isAttrs v && builtins.hasAttr "git" v)
              then null
              else
                let
                  # Use the 'package' attribute if it exists, which means this is a renamed dependency
                  # https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#renaming-dependencies-in-cargotoml
                  depName = v.package or entryName;
                  # predicate that holds if the given lockfile entry is the
                  # Cargo.toml dependency being looked at (depName)
                  pred = entry: entry.name == depName && (lib.substring 0 (4 + lib.stringLength v.git) entry.source) == "git+${v.git}";

                  # extract the revision from a Cargo.lock "package.source"
                  # entry
                  #   git+https://gi.../rand?rev=703452...#703452
                  #                                        ^^^^^^
                  extractRevision = url: lib.last (lib.splitString "#" url);

                  # parse a lockfile entry:
                  #     { name = "rand";
                  #       version = ...;
                  #       source = "git+https://...rev=703452...#703452";
                  #     } ->
                  #     { name = "rand";
                  #       source = "git+https://...rev=703452...#703452";
                  #       revision = "703452";
                  #     }
                  parseLockfileEntry = entry: rec { inherit (entry) name source; revision = extractRevision source; };

                  # List of all entries: [ { name, source, revision } ]
                  packageLocks = builtins.map parseLockfileEntry (lib.filter pred cargolock.package);

                  # Find the first revision from the lockfile that:
                  #   * has the same name as the cargo toml entry _if_ the cargo toml does not specify a revision, or
                  #   * has the same name and revision as the cargo toml entry
                  fromLockfile = lib.findFirst (p: p.name == depName && ((! v?rev) || v.rev == p.revision)) null packageLocks;

                  # Cargo.lock revision is prioritized, because in Cargo.toml short revisions are allowed
                  val = v // { rev = fromLockfile.revision or v.rev or null; };
                in
                lib.filterAttrs (n: _: n == "rev" || n == "tag" || n == "branch") val //
                {
                  name = depName;
                  url = val.git;
                  key = val.rev or val.tag or val.branch or
                    (throw "No 'rev', 'tag' or 'branch' available to specify key, nor a git revision was found in Cargo.lock");
                  checkout = builtins.fetchGit ({
                    url = val.git;
                  } // lib.optionalAttrs (val ? rev) {
                    rev = val.rev;
                    allRefs = true;
                  } // lib.optionalAttrs (val ? branch) {
                    ref = val.branch;
                  } // lib.optionalAttrs (val ? tag) {
                    ref = "refs/tags/${val.tag}";
                  });
                }
            ) cargotoml.dependencies or { });
      in
        lib.mapAttrs (_: x: tomlDependencies x) cargotomls;

  # A very minimal 'src' which makes cargo happy nonetheless
  dummySrc =
    { cargoconfig   # string
    , cargotomls   # attrset
    , cargolock   # attrset
    , copySources # list of paths that should be copied to the output
    , copySourcesFrom # path from which to copy ${copySources}
    }:
      let
        config = writeText "config" cargoconfig;
        cargolock' = builtinz.writeTOML "Cargo.lock" cargolock;
        fixupCargoToml = cargotoml:
          let
            attrs =
              # Since we pretend everything is a lib, we remove any mentions
              # of binaries
              removeAttrs cargotoml [ "bin" "example" "lib" "test" "bench" "default-run" ]
                // lib.optionalAttrs (builtins.hasAttr "package" cargotoml) ({ package = removeAttrs cargotoml.package [ "default-run" ] ; })
                ;
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
          { inherit copySources copySourcesFrom cargotomlss; }
          ''
            mkdir -p $out/.cargo
            ${lib.optionalString (! isNull cargoconfig) "cp ${config} $out/.cargo/config"}
            cp ${cargolock'} $out/Cargo.lock

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
                # Avoid accidentally pulling `std` for no-std crates.
                echo '#![no_std]' >src/lib.rs
                # pretend there's a `build.rs`, otherwise cargo doesn't build
                # the `[build-dependencies]`. Custom locations of build scripts
                # aren't an issue because we strip the `build` field in
                # `fixupCargoToml`; so cargo always thinks there's a build
                # script which is `./build.rs`.
                echo 'fn main(){}' > build.rs
                popd > /dev/null
            done

            # Copy all the "patched" sources which are used by dependencies.
            # This needs to be done after the creation of the dummy to make
            # sure the dummy source files do not tramp on the patch
            # dependencies.
            for p in $copySources; do
              echo "Copying patched source $p to $out..."
              mkdir -p "$out/$p"

              chmod -R +w "$out/$p"
              echo copying "$copySourcesFrom/$p"/ to "$out/$p"

              cp --no-preserve=mode -R "$copySourcesFrom/$p"/* "$out/$p"
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
