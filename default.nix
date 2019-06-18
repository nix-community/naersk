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
    mkVersions = cargotoml: cargolock: pkgs.lib.listToAttrs
      (map (x:
        { inherit (x) name;
          value =
            { inherit (x) version;
              sha256 = cargolock.metadata.${mkMetadataKey x.name x.version};
            } ;
        }
      )
      (builtins.filter (v: v.name != cargotoml.package.name) cargolock.package));

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
    mkSnapshotForest = patchCrate: cargotoml: cargolock:
      pkgs.symlinkJoin
        { name = "crates-io";
          paths =
            pkgs.lib.mapAttrsToList
              (k: v: patchCrate k v (unpackCrate k v.version v.sha256))
              (mkVersions cargotoml cargolock);
        };


    buildPackage =
      src:
      { cargoCommands ? [ "cargo build" ]
      , patchCrate ? (_: _: x: x) }:
      with rec
        {
          readTOML = f: builtins.fromTOML (builtins.readFile f);
          cargolock = readTOML "${src}/Cargo.lock";
          cargotoml = readTOML "${src}/Cargo.toml";
          versions = mkVersions cargolock;
        };
      pkgs.stdenv.mkDerivation
        { inherit src;
          name = "cargo-package";
          buildInputs =
            [ pkgs.cargo

              # needed for "dsymutil"
              pkgs.llvmPackages.stdenv.cc.bintools

              # needed for "cc"
              pkgs.llvmPackages.stdenv.cc

            ] ++ (pkgs.stdenv.lib.optional
            pkgs.stdenv.isDarwin pkgs.darwin.apple_sdk.frameworks.Security);
          LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib";
          CXX="clang++";
          RUSTC="${rustPackages}/bin/rustc";

          cargoCommands = pkgs.lib.concatStringsSep "\n" cargoCommands;
          buildPhase =
            ''
              runHook preBuild
              ##
              ## registry setup
              ##
              export CARGO_HOME="$PWD/.cargo-home"
              mkdir -p $CARGO_HOME

              mkdir -p .cargo
              echo '[source.crates-io]' > .cargo/config
              echo "replace-with = 'nix-sources'" >> .cargo/config

              echo '[source.nix-sources]' >> .cargo/config
              echo "directory = '${mkSnapshotForest patchCrate cargotoml cargolock}'" >> .cargo/config

              echo "$cargoCommands" | \
                while IFS= read -r c
                do
                  echo "Runnig cargo command: $c"
                  $c
                done

              runHook postBuild
            '';
        };
  };

buildPackage sources.lorri
  { patchCrate = name: v: src:
      if name == "fuchsia-cprng" || name == "proptest" then
        pkgs.runCommand "fuchsia-cprng" {}
          ''
            mkdir -p $out
            cp -r --no-preserve=mode ${src}/* $out

            sed -i '/edition =/c\cargo-features = ["edition"]' $out/${name}-${v.version}/Cargo.toml
            cat $out/${name}-${v.version}/Cargo.toml
            echo $out
          ''
      else src;
  }
