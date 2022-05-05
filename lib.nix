{ lib, writeText, runCommandLocal, remarshal }:
let
  builtinz =
    builtins // import ./builtins
      { inherit lib writeText remarshal runCommandLocal; };
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

  # Gets all git dependencies in Cargo.lock as a list.
  # [
  #   {
  #     name = "rand";
  #     url = "https://github.com/...";
  #     checkout = "/nix/store/checkout"
  #   }
  # ]
  findGitDependencies =
    { cargolock, gitAllRefs, gitSubmodules }:
    let
      query = p: (lib.substring 0 4 (p.source or "")) == "git+";

      extractRevision = source: lib.last (lib.splitString "#" source);
      extractPart = part: source: if lib.hasInfix part source then lib.last (lib.splitString part (lib.head (lib.splitString "#" source))) else null;
      extractRepoUrl = source:
        let
          splitted = lib.head (lib.splitString "?" source);
          split = lib.substring 4 (lib.stringLength splitted) splitted;
        in lib.head (lib.splitString "#" split);

      parseLock = lock:
      let
        source = lock.source;
        rev = extractPart "?rev=" source;
        tag = extractPart "?tag=" source;
        branch = extractPart "?branch=" source;
      in
      {
        inherit (lock) name;
        revision = extractRevision source;
        url = extractRepoUrl source;
      } // (lib.optionalAttrs (! isNull branch) { inherit branch; })
        // (lib.optionalAttrs (! isNull tag) { inherit tag; })
        // (lib.optionalAttrs (! isNull rev) { inherit rev; });
      packageLocks = builtins.map parseLock (lib.filter query cargolock.package);

      mkFetch = lock: {
        key = lock.rev or lock.tag or lock.branch or lock.revision
          or (throw "No 'rev', 'tag' or 'branch' available to specify key, nor a git revision was found in Cargo.lock");
        checkout = builtins.fetchGit ({
          url = lock.url;
          rev = lock.revision;
        } // lib.optionalAttrs (lock ? branch) {
          ref = lock.branch;
        } // lib.optionalAttrs (lock ? tag) {
          ref = lock.tag;
        } // lib.optionalAttrs gitAllRefs {
          allRefs = true;
        } // lib.optionalAttrs gitSubmodules {
          submodules = true;
        });
      } // lock;
    in builtins.map mkFetch packageLocks;

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
        runCommandLocal "dummy-src"
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
