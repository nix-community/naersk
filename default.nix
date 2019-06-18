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
    mkVersions = cargotoml: cargolock:
      # TODO: this should nub by <pkg-name>-<pkg-version>
      (pkgs.lib.concatMap (x:
        [
            { inherit (x) version name;
              sha256 = cargolock.metadata.${mkMetadataKey x.name x.version};
            }
        ] ++ (map (parseDependency cargolock) (x.dependencies or []))

      )
      (builtins.filter (v: v.name != cargotoml.package.name) cargolock.package));

    # Turns "lib-name lib-ver (registry+...)" to { name = "lib-name", etc }
    parseDependency = cargolock: str:
      with rec
        { components = pkgs.lib.splitString " " str;
          name = pkgs.lib.elemAt components 0;
          version = pkgs.lib.elemAt components 1;
          sha256 = cargolock.metadata.${mkMetadataKey name version};
        };
      { inherit name version sha256;
      };

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
            map
              (v: patchCrate v.name v (unpackCrate v.name v.version v.sha256))
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
          cargoconfig = pkgs.writeText "cargo-config"
            ''
              [source.crates-io]
              replace-with = 'nix-sources'

              [source.nix-sources]
              directory = '${mkSnapshotForest patchCrate cargotoml cargolock}'
            '';
        };
      pkgs.stdenv.mkDerivation
        { inherit src;
          name = cargotoml.package.name;
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
              cp target/debug/${cargotoml.package.name} $out/bin \
                || echo "No executable to install"
              runHook postInstall
            '';
        };
  };

# lib-like helpers
with
  { fixupEditions = name: v: src:
      pkgs.runCommand "fixup-editions-${name}" {}
        ''
          mkdir -p $out
          cp -r --no-preserve=mode ${src}/* $out

          sed -i '/\[package\]/i cargo-features = ["edition"]' $out/${name}-${v.version}/Cargo.toml
          cat $out/${name}-${v.version}/Cargo.toml
          echo $out
        '';
  };

buildPackage sources.lorri
  { patchCrate = name: v: src:
      if name == "fuchsia-cprng" || name == "proptest" then
        fixupEditions name v src
      else src;
  }
