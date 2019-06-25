src:
{ cargoBuildCommands ? [ "cargo build --frozen --release" ]
, cargoTestCommands ? [ "cargo test --release" ]
, doCheck ? true
, patchCrate ? (_: _: x: x)
, name ? null
, rustc ? rustPackages
, cargo ? rustPackages
, override ? null
, buildInputs ? []
, nativeBuildInputs ? []
, rustPackages
, stdenv
, lib
, llvmPackages
, jq
, darwin
, writeText
, symlinkJoin
, runCommand
}:

with
  { libb = import ./lib.nix { inherit lib; }; };

with rec
  {
    drv = stdenv.mkDerivation
      { inherit src doCheck nativeBuildInputs cratePaths;

        # Otherwise specifying CMake as a dep breaks the build
        dontUseCmakeConfigure = true;

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

            # needed for "cc"
            jq
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

        configurePhase =
          ''
            runHook preConfigure
            cat ${writeText "deps" (builtins.toJSON dependencies)} |\
              jq -r '.[]' |\
              while IFS= read -r dep
              do
                echo dep $dep
              done

            export CARGO_HOME=''${CARGO_HOME:-$PWD/.cargo-home}
            mkdir -p $CARGO_HOME

            cp --no-preserve mode ${cargoconfig} $CARGO_HOME/config

            export CARGO_TARGET_DIR="$out/target"

            runHook postConfigure
          '';

        buildPhase =
          ''
            runHook preBuild

            ## Build commands
            ## TODO: -j $NIX_BUILD_CORES
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
          ''
            runHook preInstall

            mkdir -p $out/bin
            # XXX: should have --debug if mode is "debug"
            for p in "$cratePaths"; do
              cargo install --path $p --bins --root $out ||\
                echo "WARNING: Member wasn't installed: $p"
            done

            mkdir -p $out/lib

            # TODO: .../debug if debug
            cp -vr $CARGO_TARGET_DIR/release/deps/* $out/lib ||\
              echo "WARNING: couldn't copy libs"

            runHook postInstall
          '';
      };

    # List of built crates this crate depends on
    dependencies = [];

    # XXX: the actual crate format is not documented but in practice is a
    # gzipped tar; we simply unpack it and introduce a ".cargo-checksum.json"
    # file that cargo itself uses to double check the sha256
    unpackCrate = name: version: sha256:
      with
      { crate = builtins.fetchurl
          { url = "https://crates.io/api/v1/crates/${name}/${version}/download";
            inherit sha256;
          };
      };
      runCommand "unpack-${name}-${version}" {}
      ''
        mkdir -p $out
        tar -xvzf ${crate} -C $out
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
              (libb.mkVersions packageName cargolock);
        };

    readTOML = f: builtins.fromTOML (builtins.readFile f);
    cargolock = readTOML "${src}/Cargo.lock";

    # The top-level Cargo.toml
    cargotoml = readTOML "${src}/Cargo.toml";

    cratePaths =
      with rec
        { workspaceMembers = cargotoml.workspace.members or null;
        };

      if isNull workspaceMembers then "." else lib.concatStringsSep "\n" workspaceMembers;

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

    cargoconfig = writeText "cargo-config"
      ''
        [source.crates-io]
        replace-with = 'nix-sources'

        [source.nix-sources]
        directory = '${mkSnapshotForest patchCrate (lib.head crateNames) cargolock}'
      '';
  };
if isNull override then drv else drv.overrideAttrs override
