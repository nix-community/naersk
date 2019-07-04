src:
{ #| What command to run during the build phase
  cargoBuild ?  "cargo build --$CARGO_BUILD_PROFILE -j $NIX_BUILD_CORES"
, #| What command to run during the test phase
  cargoTest ? "cargo test --$CARGO_BUILD_PROFILE"
, doCheck ? true
, name
, rustc
, cargo
, override ? null
, buildInputs ? []
, nativeBuildInputs ? []
, builtDependencies ? []
, cargolockPath ? null
, cargotomlPath ? null
, release ? true
, stdenv
, lib
, llvmPackages
, rsync
, jq
, darwin
, writeText
, symlinkJoin
, runCommand
, remarshal
, crateDependencies
, cratePaths
}:

with
  { builtinz =
      builtins //
      import ./builtins.nix
        { inherit writeText remarshal runCommand ; };
  };

with rec
  {
    drv = stdenv.mkDerivation
      { inherit
          src
          doCheck
          nativeBuildInputs
          cargolockPath
          cargotomlPath
          cratePaths
          name;

        CARGO_BUILD_PROFILE = if release then "release" else "debug";

        # Otherwise specifying CMake as a dep breaks the build
        dontUseCmakeConfigure = true;

        buildInputs =
          [ cargo

            # needed for "dsymutil"
            llvmPackages.stdenv.cc.bintools

            # needed for "cc"
            llvmPackages.stdenv.cc

            # needed at various steps in the build
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

            if [ -n "$cargolockPath" ]
            then
              echo "Setting Cargo.lock"
              if [ -f "Cargo.lock" ]
              then
                echo "WARNING: replacing existing Cargo.lock"
              fi
              cp --no-preserve mode "$cargolockPath" Cargo.lock
            fi

            if [ -n "$cargotomlPath" ]
            then
              echo "Setting Cargo.toml"
              if [ -f "Cargo.toml" ]
              then
                echo "WARNING: replacing existing Cargo.toml"
              fi
              cp "$cargotomlPath" Cargo.toml
            fi

            mkdir -p target

            cat ${builtinz.writeJSON "deps" builtDependencies} |\
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

            # cargo install defaults to "release", but it doesn't have a
            # "--release" flag, only "--debug", so we can't just pass
            # "--$CARGO_BUILD_PROFILE" like we do with "cargo build" and "cargo
            # test"
            install_arg=""
            if [ "$CARGO_BUILD_PROFILE" == "debug" ]
            then
              install_arg="--debug"
            fi

            mkdir -p $out/bin
            for p in "$cratePaths"; do
              # XXX: we don't quote install_arg to avoid passing an empty arg
              # to cargo
              cargo install \
                --path $p \
                $install_arg \
                --bins \
                --root $out ||\
                echo "WARNING: Member wasn't installed: $p"
            done

            mkdir -p $out/lib

            cp -vr target/$CARGO_BUILD_PROFILE/deps/* $out/lib ||\
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

    cargoconfig = builtinz.writeTOML
      { source =
          { crates-io = { replace-with = "nix-sources"; } ;
            nix-sources =
              { directory = symlinkJoin
                  { name = "crates-io";
                    paths = map (v: unpackCrate v.name v.version v.sha256)
                      crateDependencies;
                  };
              };
          };
      };
  };
if isNull override then drv else drv.overrideAttrs override
