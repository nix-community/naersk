src:
{ preBuild
  #| What command to run during the build phase
, cargoBuild
, #| What command to run during the test phase
  cargoTestCommands
, copyTarget
  #| Whether or not to compress the target when copying it
, compressTarget
  #| Whether or not to copy binaries to $out/bin
, copyBins
, doCheck
, doDoc
, doDocFail
, copyDocsToSeparateOutput
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
, removeReferencesToSrcFromDocs
, pname
, version
, rustc
, cargo
, override
, buildInputs
, builtDependencies
, release
, stdenv
, lib
, rsync
, jq
, darwin
, writeText
, symlinkJoin
, runCommand
, remarshal
, crateDependencies
, zstd
}:

with
  { builtinz =
      builtins //
      import ./builtins
        { inherit lib writeText remarshal runCommand ; };
  };

let
  drv = stdenv.mkDerivation (
    { name = "${pname}-${version}";
      inherit
        src
        doCheck
        version
        preBuild;

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

      # Otherwise specifying CMake as a dep breaks the build
      dontUseCmakeConfigure = true;

      nativeBuildInputs =
        [ cargo
          # needed at various steps in the build
          jq
          rsync
        ] ;

      buildInputs =
        stdenv.lib.optionals stdenv.isDarwin
        [ darwin.Security
        darwin.apple_sdk.frameworks.CoreServices
        darwin.cf-private
        ] ++ buildInputs;

      # iff not in a shell
      inherit builtDependencies;

      RUSTC="${rustc}/bin/rustc";

      configurePhase =
        ''
          cargo_release=( ${lib.optionalString release "--release" } )

          runHook preConfigure

          logRun() {
            echo "$@"
            eval "$@"
          }

          mkdir -p target

          for dep in $builtDependencies; do
              echo pre-installing dep $dep
              if [ -d "$dep/target" ]; then
                rsync -rl \
                  --no-perms \
                  --no-owner \
                  --no-group \
                  --chmod=+w \
                  --executability $dep/target/ target
              fi
              if [ -f "$dep/target.tar.zst" ]; then
                ${zstd}/bin/zstd -d "$dep/target.tar.zst" --stdout | tar -x
              fi

              if [ -d "$dep/target" ]; then
                chmod +w -R target
              fi
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

          logRun ${cargoBuild}

          runHook postBuild
        '';

      checkPhase =
        ''
          runHook preCheck

          ${lib.concatMapStringsSep "\n" (cmd: "logRun ${cmd}") cargoTestCommands}

          runHook postCheck
        '';


      docPhase = lib.optionalString doDoc ''
        runHook preDoc

        logRun cargo doc --offline "''${cargo_release[*]}" || ${if doDocFail then "false" else "true" }

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

          ${lib.optionalString copyBins ''
          if [ -d out ]; then
            mkdir -p $out/bin
            find out -type f -executable -exec cp {} $out/bin \;
          fi
          ''}

          ${lib.optionalString copyTarget ''
          mkdir -p $out
          ${if compressTarget then
          ''
          tar -c target | ${zstd}/bin/zstd -o $out/target.tar.zst
          '' else
          ''
          cp -r target $out
          ''}
          ''}

          ${lib.optionalString (doDoc && copyDocsToSeparateOutput) ''
          cp -r target/doc $doc
          ''}

          runHook postInstall
        '';
      passthru = {
        # Handy for debugging
        inherit builtDependencies;
      };
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
      tar -xzf ${crate} -C $out
      echo '{"package":"${sha256}","files":{}}' > $out/${name}-${version}/.cargo-checksum.json
    '';
in
drv.overrideAttrs override
