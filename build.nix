src:
{ cargoBuild ?  "cargo build --frozen --release -j $NIX_BUILD_CORES"
, cargoTest ?  "cargo test --release"
, doCheck ? true
, name ? null
, rustc ? rustPackages
, cargo ? rustPackages
, override ? null
, buildInputs ? []
, nativeBuildInputs ? []
, builtDependencies ? []
, rustPackages
, stdenv
, lib
, llvmPackages
, rsync
, jq
, darwin
, writeText
, symlinkJoin
, runCommand
}:

with
  { libb = import ./lib.nix { inherit lib; };
    readTOML = f: builtins.fromTOML (builtins.readFile f);
  };

with rec
  {
    drv = stdenv.mkDerivation
      { inherit src doCheck nativeBuildInputs;

        # The list of paths to Cargo.tomls. If this is a workspace, the paths
        # are the members. Otherwise, there is a single path, ".".
        cratePaths =
          with rec
            { workspaceMembers = cargotoml.workspace.members or null;
            };

          if isNull workspaceMembers then "." else lib.concatStringsSep "\n" workspaceMembers;

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

            rsync
          ] ++ (stdenv.lib.optionals stdenv.isDarwin
          [ darwin.Security
            darwin.apple_sdk.frameworks.CoreServices
            darwin.cf-private
          ]) ++ buildInputs;

        LIBCLANG_PATH="${llvmPackages.libclang.lib}/lib";
        CXX="clang++";
        RUSTC="${rustc}/bin/rustc";

        configurePhase =
          ''
            runHook preConfigure

            mkdir -p target

            cat ${writeText "deps" (builtins.toJSON builtDependencies)} |\
              jq -r '.[]' |\
              while IFS= read -r dep
              do
                echo pre-installing dep $dep
                rsync -rl --executability $dep/target/ target
                chmod +w -R target
              done

            export CARGO_HOME=''${CARGO_HOME:-$PWD/.cargo-home}
            mkdir -p $CARGO_HOME

            cp --no-preserve mode ${cargoconfig} $CARGO_HOME/config

            # TODO: figure out why "1" works whereas "0" doesn't
            find . -type f -exec touch --date=@1 {} +

            runHook postConfigure
          '';

        buildPhase =
          ''
            runHook preBuild

            echo "Running build command:"
            echo '  ${cargoBuild}'
            ${cargoBuild}

            runHook postBuild
          '';

        checkPhase =
          ''
            runHook preCheck

            echo "Running test command:"
            echo '  ${cargoTest}'
            ${cargoTest}

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
            cp -vr target/release/deps/* $out/lib ||\
              echo "WARNING: couldn't copy libs"

            mkdir -p $out
            cp -r target $out

            runHook postInstall
          '';
      };

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
    mkSnapshotForest = packageName: cargolock:
      symlinkJoin
        { name = "crates-io";
          paths = map (v: unpackCrate v.name v.version v.sha256)
            (libb.mkVersions packageName cargolock);
        };

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

    cargoconfig = writeText "cargo-config"
      ''
        [source.crates-io]
        replace-with = 'nix-sources'

        [source.nix-sources]
        directory = '${mkSnapshotForest (lib.head crateNames) cargolock}'
      '';
  };
if isNull override then drv else drv.overrideAttrs override
