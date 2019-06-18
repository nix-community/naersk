with
  { sources = import ./nix/sources.nix; };

{ pkgs ? import sources.nixpkgs {}
, rustPackages ?
    with sources;
    (pkgs.callPackage rust-nightly {}).rust {inherit (rust-nightly) date; }
}:

# Crate building
with rec
  { # creates an attrset from package name to package version + sha256
    # (note: this includes the package's dependencies)
    mkVersions = packageName: cargolock:
      # TODO: this should nub by <pkg-name>-<pkg-version>
      (pkgs.lib.concatMap (x:
        with { mdk = mkMetadataKey x.name x.version; };
        ( pkgs.lib.optional (builtins.hasAttr mdk cargolock.metadata)
            { inherit (x) version name;
              sha256 = cargolock.metadata.${mkMetadataKey x.name x.version};
            }
        ) ++ (pkgs.lib.concatMap (parseDependency cargolock) (x.dependencies or []))

      )
      (builtins.filter (v: v.name != packageName) cargolock.package));

    # Turns "lib-name lib-ver (registry+...)" to [ { name = "lib-name", etc } ]
    # iff the package is present in the Cargo.lock (otherwise returns [])
    parseDependency = cargolock: str:
      with rec
        { components = pkgs.lib.splitString " " str;
          name = pkgs.lib.elemAt components 0;
          version = pkgs.lib.elemAt components 1;
          mdk = mkMetadataKey name version;
        };
      ( pkgs.lib.optional (builtins.hasAttr mdk cargolock.metadata)
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

    # XXX: the actual crate format is not documented but in practice is a
    # gzipped tar; we simply unpack it and introduce a ".cargo-checksum.json"
    # file that cargo itself uses to double check the sha256
    unpackCrate = name: version: sha256:
      with
      { src = builtins.fetchurl
          { url = "https://crates.io/api/v1/crates/${name}/${version}/download";
            inherit sha256;
          };
      };
      pkgs.runCommand "unpack-${name}-${version}" {}
      ''
        mkdir -p $out
        tar -xvzf ${src} -C $out
        echo '{"package":"${sha256}","files":{}}' > $out/${name}-${version}/.cargo-checksum.json
      '';

    # creates a forest of symlinks of all the dependencies XXX: this is very
    # basic and means that we have very little incrementality; e.g. when
    # anything changes all the deps will be rebuilt.  The rustc compiler is
    # pretty fast so this is not too bad. In the future we'll want to pre-build
    # the crates and give cargo a pre-populated ./target directory.
    mkSnapshotForest = patchCrate: packageName: cargolock:
      pkgs.symlinkJoin
        { name = "crates-io";
          paths =
            map
              (v: patchCrate v.name v (unpackCrate v.name v.version v.sha256))
              (mkVersions packageName cargolock);
        };


    buildPackage =
      src:
      { cargoCommands ? [ "cargo build" ]
      , patchCrate ? (_: _: x: x)
      , name ? null
      }:
      with rec
        {
          readTOML = f: builtins.fromTOML (builtins.readFile f);
          cargolock = readTOML "${src}/Cargo.lock";
          cargotoml = readTOML "${src}/Cargo.toml";
          crateNames =
            with rec
              { packageName = cargotoml.package.name or null;
                workspaceMembers = cargotoml.workspace.members or null;
              };

            if isNull packageName && isNull workspaceMembers then
              abort
                ''The cargo manifest has neither
                    - a package.name field, nor
                    - a workspace.members field
                  Cannot continue.
                ''
            else if ! isNull packageName && ! isNull workspaceMembers then
              abort
                ''The cargo manifest has both
                    - a package.name field, and
                    - a workspace.members field
                  Refusing to continue.
                ''
            else if ! isNull packageName then
              [packageName]
            else map
              (member: (builtins.fromTOML (builtins.readFile "${src}/${member}/Cargo.toml")).package.name)
              workspaceMembers;
          cargoconfig = pkgs.writeText "cargo-config"
            ''
              [source.crates-io]
              replace-with = 'nix-sources'

              [source.nix-sources]
              directory = '${mkSnapshotForest patchCrate (pkgs.lib.head crateNames) cargolock}'
            '';
        };
      pkgs.stdenv.mkDerivation
        { inherit src;
          name =
            if ! isNull name then
              name
            else if pkgs.lib.length crateNames == 0 then
              abort "No crate names"
            else if pkgs.lib.length crateNames == 1 then
              pkgs.lib.head crateNames
            else
              pkgs.lib.head crateNames + "-et-al";
          buildInputs =
            [ pkgs.cargo

              # needed for "dsymutil"
              pkgs.llvmPackages.stdenv.cc.bintools

              # needed for "cc"
              pkgs.llvmPackages.stdenv.cc

            ] ++ (pkgs.stdenv.lib.optionals pkgs.stdenv.isDarwin
            [ pkgs.darwin.Security
              pkgs.darwin.apple_sdk.frameworks.CoreServices
              pkgs.darwin.cf-private
            ]);
          LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib";
          CXX="clang++";
          RUSTC="${rustPackages}/bin/rustc";
          BUILD_REV_COUNT = 1;
          RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";

          cargoCommands = pkgs.lib.concatStringsSep "\n" cargoCommands;
          crateNames = pkgs.lib.concatStringsSep "\n" crateNames;
          buildPhase =
            ''
              runHook preBuild

              ## registry setup
              export CARGO_HOME="$PWD/.cargo-home"
              mkdir -p $CARGO_HOME
              mkdir -p .cargo
              cp ${cargoconfig} .cargo/config

              ## Build commands
              echo "$cargoCommands" | \
                while IFS= read -r c
                do
                  echo "Runnig cargo command: $c"
                  $c
                done

              runHook postBuild
            '';

          installPhase =
            ''
              runHook preInstall
              mkdir -p $out/bin
              echo "$crateNames" | \
                while IFS= read -r c
                do
                  echo "Installing executable: $c"
                  cp "target/debug/$c" $out/bin \
                    || echo "No executable $c to install"
                done

              runHook postInstall
            '';
        };
  };

# lib-like helpers
# These come in handy when cargo manifests must be patched
with rec
  { # Enables the cargo feature "edition" in the cargo manifest
    fixupEdition = name: v: src: fixupFeatures name v src ["edition"];

    # Generates a sed expression that enables the given features
    fixupFeaturesSed = feats:
      with
        { features = ''["'' + pkgs.lib.concatStringsSep ''","'' feats + ''"]'';
        };
      ''/\[package\]/i cargo-features = ${features}'';

    # Patches the cargo manifest to enable the list of features
    fixupFeatures = name: v: src: feats:
      pkgs.runCommand "fixup-editions-${name}" {}
        ''
          mkdir -p $out
          cp -r --no-preserve=mode ${src}/* $out
          sed -i '${fixupFeaturesSed feats}' \
            $out/${name}-${v.version}/Cargo.toml
        '';
  };

{ test_lorri = buildPackage sources.lorri {};

  test_talent-plan-1 = buildPackage "${sources.talent-plan}/rust/projects/project-1" {};
  test_talent-plan-2 = buildPackage "${sources.talent-plan}/rust/projects/project-2" {};
  test_talent-plan-3 = buildPackage "${sources.talent-plan}/rust/projects/project-3" {};

  # TODO: support for git deps
  #test_talent-plan-4 = buildPackage "${sources.talent-plan}/rust/projects/project-4" {};
  #test_talent-plan-5 = buildPackage "${sources.talent-plan}/rust/projects/project-5" {};

  # TODO: figure out executables from src/bin/*.rs
  test_ripgrep-all = buildPackage sources.ripgrep-all {};

  # TODO: Nix error:
  # error: while parsing a TOML string at default.nix:80:25:
  #   Bare key 'cfg(all(target_env = "musl", target_pointer_width = "64"))'
  #   cannot contain whitespace at line 64
  # and this is the culprit:
  #  https://github.com/BurntSushi/ripgrep/blob/d1389db2e39802d5e04dc7b902fd2b1f9f615b01/Cargo.toml#L64
  #test_ripgrep = buildPackage sources.ripgrep {};

  # TODO: (workspace)
  # error: while parsing a TOML string at ...:115:25:
  #   Bare key 'cfg(any(all(target_arch = "wasm32", not(target_os = "emscripten")), all(target_vendor = "fortanix", target_env = "sgx")))'
  #   cannot contain whitespace at line 53
  #test_rust = buildPackage sources.rust {};

  # Unable to update https://github.com/...
  #test_noria = buildPackage sources.noria {};

  # No submodules
  #test_lucet = buildPackage sources.lucet {};

  test_rustlings = buildPackage sources.rustlings {};
}
