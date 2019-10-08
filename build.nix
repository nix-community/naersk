src:
{ preBuild
  #| What command to run during the build phase
, cargoBuild ? "\ncargo build \"\${cargo_release}\" -j $NIX_BUILD_CORES -Z unstable-options --out-dir out\n"
, #| What command to run during the test phase
  cargoTestCommands
  #| Whether or not to forward intermediate build artifacts to $out
, copyTarget ? false
  #| Whether or not to copy binaries to $out/bin
, copyBins ? true
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
, rustc
, cargo
, buildInputs ? []
, builtDependencies ? []
, release ? true
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
}:

with
  { builtinz =
      builtins //
      import ./builtins
        { inherit lib writeText remarshal runCommand ; };
    libb = import ./lib.nix { inherit lib writeText runCommand remarshal; } ;
  };

stdenv.mkDerivation
{ inherit
    src
    name
    preBuild;

  cargoconfig = builtinz.toTOML
    { source =
        { crates-io = { replace-with = "nix-sources"; } ;
          nix-sources =
            { directory = symlinkJoin
                { name = "crates-io";
                  paths = map (v: libb.unpackCrate v.name v.version v.sha256)
                    crateDependencies;
                };
            };
        };
    };

  outputs = [ "out" ] ++ lib.optional (doDoc && copyDocsToSeparateOutput) "doc";
  preInstallPhases = lib.optional doDoc [ "docPhase" ];

  # Otherwise specifying CMake as a dep breaks the build
  dontUseCmakeConfigure = true;

  buildInputs =
    [ cargo
      # needed at various steps in the build
      jq
      rsync
    ] ++ (stdenv.lib.optionals stdenv.isDarwin
    [ darwin.Security
      darwin.apple_sdk.frameworks.CoreServices
      darwin.cf-private
    ]) ++ buildInputs;

  RUSTC="${rustc}/bin/rustc";

  inherit builtDependencies;

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
      mkdir -p $out/bin
      find out -type f -executable -exec cp {} $out/bin \;
      ''}

      ${lib.optionalString copyTarget ''
      mkdir -p $out
      cp -r target $out
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
