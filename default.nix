with rec
  { sources = import ./nix/sources.nix;
    _pkgs = import sources.nixpkgs {};
  };

{ lib ? _pkgs.lib
, runCommand ? _pkgs.runCommand
, symlinkJoin ? _pkgs.symlinkJoin
, stdenv ? _pkgs.stdenv
, writeText ? _pkgs.writeText
, llvmPackages ? _pkgs.llvmPackages
, darwin ? _pkgs.darwin
, rustPackages ?
    with sources;
    (_pkgs.callPackage rust-nightly {}).rust {inherit (rust-nightly) date; }
}:

# Crate building
with rec
  { # creates an attrset from package name to package version + sha256
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
      runCommand "unpack-${name}-${version}" {}
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
    # TODO: this should most likely take more than one packageName
    mkSnapshotForest = patchCrate: packageName: cargolock:
      symlinkJoin
        { name = "crates-io";
          paths =
            map
              (v: patchCrate v.name v (unpackCrate v.name v.version v.sha256))
              (mkVersions packageName cargolock);
        };

    buildPackage =
      src:
      { cargoBuildCommands ? [ "cargo build --release" ]
      , cargoTestCommands ? [ "cargo test" ]
      , patchCrate ? (_: _: x: x)
      , name ? null
      , rustc ? rustPackages
      , cargo ? rustPackages
      , override ? null
      , buildInputs ? []
      }:

      with rec
        {
          readTOML = f: builtins.fromTOML (builtins.readFile f);
          cargolock = readTOML "${src}/Cargo.lock";

          # The top-level Cargo.toml
          cargotoml = readTOML "${src}/Cargo.toml";

          # All the Cargo.tomls, including the top-level one
          cargotomls =
            with rec
              { workspaceMembers = cargotoml.workspace.members or [];
              };

            [cargotoml] ++ (
              map (member: (builtins.fromTOML (builtins.readFile
                "${src}/${member}/Cargo.toml")))
              workspaceMembers);

          crateNames = builtins.filter (pname: ! isNull pname) (
              map (ctoml: ctoml.package.name or null) cargotomls);

          # The list of potential binaries
          # TODO: is this even worth it or shall we simply copy all the
          # executables to bin/?
          bins = crateNames ++
              map (bin: bin.name) (
              lib.concatMap (ctoml: ctoml.bin or []) cargotomls);

          cargoconfig = writeText "cargo-config"
            ''
              [source.crates-io]
              replace-with = 'nix-sources'

              [source.nix-sources]
              directory = '${mkSnapshotForest patchCrate (lib.head crateNames) cargolock}'
            '';
          drv = stdenv.mkDerivation
            { inherit src;
              name =
                if ! isNull name then
                  name
                else if lib.length crateNames == 0 then
                  abort "No crate names"
                else if lib.length crateNames == 1 then
                  lib.head crateNames
                else
                  lib.head crateNames + "-et-al";
              buildInputs =
                [ cargo

                  # needed for "dsymutil"
                  llvmPackages.stdenv.cc.bintools

                  # needed for "cc"
                  llvmPackages.stdenv.cc

                ] ++ (stdenv.lib.optionals stdenv.isDarwin
                [ darwin.Security
                  darwin.apple_sdk.frameworks.CoreServices
                  darwin.cf-private
                ]) ++ buildInputs;
              LIBCLANG_PATH="${llvmPackages.libclang.lib}/lib";
              CXX="clang++";
              RUSTC="${rustc}/bin/rustc";

              cargoBuildCommands = lib.concatStringsSep "\n" cargoBuildCommands;
              cargoTestCommands = lib.concatStringsSep "\n" cargoTestCommands;
              crateNames = lib.concatStringsSep "\n" crateNames;
              bins = lib.concatStringsSep "\n" bins;
              buildPhase =
                ''
                  runHook preBuild

                  ## registry setup
                  export CARGO_HOME="$PWD/.cargo-home"
                  mkdir -p $CARGO_HOME
                  mkdir -p .cargo
                  cp ${cargoconfig} .cargo/config

                  ## Build commands
                  echo "$cargoBuildCommands" | \
                    while IFS= read -r c
                    do
                      echo "Running cargo command: $c"
                      $c
                    done

                  runHook postBuild
                '';

              checkPhase =
                ''
                  runHook preCheck

                  ## test commands
                  echo "$cargoTestCommands" | \
                    while IFS= read -r c
                    do
                      echo "Running cargo (test) command: $c"
                      $c
                    done

                  runHook postCheck
                '';

              installPhase =
                # TODO: this should also copy <foo> for every src/bin/<foo.rs>
                ''
                  runHook preInstall
                  mkdir -p $out/bin
                  echo "$bins" | \
                    while IFS= read -r c
                    do
                      echo "Installing executable: $c"
                      cp "target/release/$c" $out/bin \
                        || echo "No executable $c to install"
                    done

                  runHook postInstall
                '';
            };
          };
      if isNull override then drv else drv.overrideAttrs override;
  };

# lib-like helpers
# These come in handy when cargo manifests must be patched
with rec
  { # Enables the cargo feature "edition" in the cargo manifest
    fixupEdition = name: v: src: fixupFeatures name v src ["edition"];

    # Generates a sed expression that enables the given features
    fixupFeaturesSed = feats:
      with
        { features = ''["'' + lib.concatStringsSep ''","'' feats + ''"]'';
        };
      ''/\[package\]/i cargo-features = ${features}'';

    # Patches the cargo manifest to enable the list of features
    fixupFeatures = name: v: src: feats:
      runCommand "fixup-editions-${name}" {}
        ''
          mkdir -p $out
          cp -r --no-preserve=mode ${src}/* $out
          sed -i '${fixupFeaturesSed feats}' \
            $out/${name}-${v.version}/Cargo.toml
        '';
  };

with
  { crates =
      { lorri = buildPackage sources.lorri
          { override = _oldAttrs:
              { BUILD_REV_COUNT = 1;
                RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
              };
          };

        ripgrep-all = buildPackage sources.ripgrep-all {};

        rustfmt = buildPackage sources.rustfmt {};
      };
  };

{ inherit buildPackage fixupEdition fixupFeatures fixupFeaturesSed crates;

  test_lorri = runCommand "lorri" { buildInputs = [ crates.lorri ]; }
    "lorri --help && touch $out";

  test_talent-plan-1 = buildPackage "${sources.talent-plan}/rust/projects/project-1" {};
  test_talent-plan-2 = buildPackage "${sources.talent-plan}/rust/projects/project-2" {};
  test_talent-plan-3 = buildPackage "${sources.talent-plan}/rust/projects/project-3" {};

  # TODO: support for git deps
  #test_talent-plan-4 = buildPackage "${sources.talent-plan}/rust/projects/project-4" {};
  #test_talent-plan-5 = buildPackage "${sources.talent-plan}/rust/projects/project-5" {};

  # TODO: figure out executables from src/bin/*.rs
  test_ripgrep-all = runCommand "ripgrep-all"
    { buildInputs = [ crates.ripgrep-all ]; }
    "touch $out";

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

  # TODO: walk through bins
  test_rustfmt = runCommand "rust-fmt"
    { buildInputs = [ crates.rustfmt ]; }
    ''
      rustfmt --help
      cargo-fmt --help
      touch $out
    '';
}
