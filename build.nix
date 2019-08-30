src:
{ #| What command to run during the build phase
  cargoBuild
, #| What command to run during the test phase
  cargoTest
  #| Whether or not to forward build artifacts to $out
, copyBuildArtifacts ? false
, doCheck ? true
, doDoc ? true
  #| Whether or not the rustdoc can fail the build
, doDocFail ? false
, copyDocsToSeparateOutput ? true
  #| Whether to remove references to source code from the generated cargo docs
  #  to reduce Nix closure size. By default cargo doc includes snippets like the
  #  following in the generated highlighted source code in files like: src/rand/lib.rs.html:
  #
  #    <meta name="description" content="Source to the Rust file `/nix/store/mdwpqciww926xayfasl85i4wvvpbgb9a-crates-io/rand-0.7.0/src/lib.rs`.">
  #
  #  The reference to /nix/store/...-crates-io/... causes a run-time dependency
  #  to the complete source code blowing up the Nix closure size for no good
  #  reason. If this argument is set to true (which is the default) the latter
  #  will be replaced by:
  #
  #    <meta name="description" content="Source to the Rust file removed to reduce Nix closure size.">
  #
  #  Which drops the run-time dependency on the crates-io source thereby
  #  significantly reducing the Nix closure size.
, removeReferencesToSrcFromDocs ? true
, name
, version
, rustc
, cargo
, override ? null
, buildInputs ? []
, nativeBuildInputs ? []
, builtDependencies ? []
, replaceToml ? true
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
# TODO: rename to "members"
, cratePaths
}:

with
  { builtinz =
      builtins //
      import ./builtins
        { inherit lib writeText remarshal runCommand ; };
  };

with rec
  {
    drv = stdenv.mkDerivation (
      { inherit
          src
          doCheck
          nativeBuildInputs
          cratePaths
          name
          version;

        cargoconfig = builtinz.toTOML
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

        outputs = [ "out" ] ++ lib.optional (doDoc && copyDocsToSeparateOutput) "doc";
        preInstallPhases = lib.optional doDoc [ "docPhase" ];

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

            mkdir -p target

            cat ${builtinz.writeJSON "dependencies-json" builtDependencies} |\
              jq -r '.[]' |\
              while IFS= read -r dep
              do
                echo pre-installing dep $dep
                rsync -rl \
                  --no-perms \
                  --no-owner \
                  --no-group \
                  --chmod=+w \
                  --executability $dep/target/ target
                chmod +w -R target
              done

            export CARGO_HOME=''${CARGO_HOME:-$PWD/.cargo-home}
            mkdir -p $CARGO_HOME

            echo "$cargoconfig" > $CARGO_HOME/config

            # TODO: figure out why "1" works whereas "0" doesn't
            find . -type f -exec touch --date=@1 {} +

            runHook postConfigure
          '';

        buildPhase =
          ''
            runHook preBuild

            echo "Building..."
            ${cargoBuild}

            runHook postBuild
          '';

        checkPhase =
          ''
            runHook preCheck

            echo "Testing..."
            ${cargoTest}

            runHook postCheck
          '';


        docPhase = lib.optionalString doDoc ''
          runHook preDoc

          # cargo doc defaults to "debug", but it doesn't have a
          # "--debug" flag, only "--release", so we can't just pass
          # "--$CARGO_BUILD_PROFILE" like we do with "cargo build" and "cargo
          # test"
          doc_arg=""
          if [ "$CARGO_BUILD_PROFILE" == "release" ]
          then
            doc_arg="--release"
          fi

          for p in $cratePaths; do
            pushd "$p"
            echo "Documenting $p"
            cargo doc --offline $doc_arg || ${if doDocFail then "false" else "true" }
            popd
          done

          ${lib.optionalString removeReferencesToSrcFromDocs ''
          # Remove references to the source derivation to reduce closure size
                match='<meta name="description" content="Source to the Rust file `${builtins.storeDir}[^`]*`.">'
          replacement='<meta name="description" content="Source to the Rust file removed to reduce Nix closure size.">'
          find target/doc -name "*\.rs\.html" -exec sed -i "s|$match|$replacement|" {} +
          ''}

          runHook postDoc
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
            for p in $cratePaths; do
              pushd "$p"
              echo "Installing $p"
              # XXX: we don't quote install_arg to avoid passing an empty arg
              # to cargo
              cargo install \
                --path . \
                $install_arg \
                --bins \
                --root $out ||\
                echo "WARNING: Member wasn't installed: $p"
              popd
            done

            mkdir -p $out
            mkdir -p $out/lib

            ${lib.optionalString copyBuildArtifacts ''
            cp -r target $out
            ''}

            ${lib.optionalString (doDoc && copyDocsToSeparateOutput) ''
            cp -r target/doc $doc
            ''}

            runHook postInstall
          '';
      }
      )
      ;

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
  };
if isNull override then drv else drv.overrideAttrs override
