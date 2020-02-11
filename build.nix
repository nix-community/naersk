{ src
, preBuild
  #| What command to run during the build phase
, cargoBuild
, cargoBuildOptions
, #| What command to run during the test phase
  cargoTestCommands
, cargoTestOptions
, copyTarget
  #| Whether or not to compress the target when copying it
, compressTarget
  #| Whether or not to copy binaries to $out/bin
, copyBins
, copyBinsFilter
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
, gitDependencies
, pname
, version
, rustc
, cargo
, override
, buildInputs
, builtDependencies
, release
, cargoOptions
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
, fetchurl
}:

let
  builtinz =
    builtins // import ./builtins
      { inherit lib writeText remarshal runCommand; };

  # All the git dependencies, as a list
  gitDependenciesList =
    lib.concatLists (lib.mapAttrsToList (_: ds: ds) gitDependencies);

  # This unpacks all git dependencies:
  #   $out/rand
  #   $out/rand/Cargo.toml
  #   $out/rand_core
  #   ...
  # It does so by discovering all the `Cargo.toml`s and creating a directory in
  # $out for each one.
  # NOTE:
  #   Only non-virtual manifests are taken into account. That is, only cargo
  #   tomls that have a [package] sections with a `name = ...`. The
  #   implementation is a bit tricky and basically akin to parsing TOML with
  #   bash. The reason is that there is no lightweight jq-equivalent available
  #   in nixpkgs (rq fails to build).
  #   We discover the name (in any) in three steps:
  #     * grab anything that comes after `[package]`
  #     * grab the first line that contains `name = ...`
  #     * grab whatever is surrounded with `"`s.
  #   The last step is very, very slow.
  unpackedGitDependencies = runCommand "git-deps"
    { nativeBuildInputs = [ jq ]; }
    ''
      log() {
        >&2 echo "[naersk]" "$@"
      }

      mkdir -p $out

      while read -r dep; do
        checkout=$(echo "$dep" | jq -cMr '.checkout')
        url=$(echo "$dep" | jq -cMr '.url')
        tomls=$(find $checkout -name Cargo.toml)
        rev=$(echo "$dep" | jq -cMr '.rev')
        while read -r toml; do
          name=$(cat $toml \
            | sed -n -e '/\[package\]/,$p' \
            | grep -m 1 "^name\W" \
            | grep -oP '(?<=").+(?=")' \
            || true)
          if [ -n "$name" ]; then
            key="$name-$rev"
            log "$url Found crate '$name' ($rev)"
            if [ -d "$out/$key" ]; then
              log "Crate was already unpacked at $out/$key"
            else
              cp -r $(dirname $toml) $out/$key
              chmod +w "$out/$key"
              echo '{"package":null,"files":{}}' > $out/$key/.cargo-checksum.json
              log "Crate unpacked at $out/$key"
            fi
          fi
        done <<< "$tomls"
      done < <(cat ${
    builtins.toFile "git-deps-json" (builtins.toJSON gitDependenciesList)
    } | jq -cMr '.[]')
    '';

  drv = stdenv.mkDerivation {
    name = "${pname}-${version}";
    inherit
      src
      doCheck
      version
      preBuild
      ;

    # The cargo config with source replacement. Replaces both crates.io crates
    # and git dependencies.
    cargoconfig = builtinz.toTOML {
      source = {
        crates-io = { replace-with = "nix-sources"; };
        nix-sources = {
          directory = symlinkJoin {
            name = "crates-io";
            paths = map (v: unpackCrate v.name v.version v.sha256)
              crateDependencies ++ [ unpackedGitDependencies ];
          };
        };
      } // lib.listToAttrs (
        map
          (
            e:
              {
                name = "${e.url}?rev=${e.rev}";
                value =
                  {
                    git = e.url;
                    rev = e.rev;
                    replace-with = "nix-sources";
                  };
              }
          )
          gitDependenciesList
      );
    };

    outputs = [ "out" ] ++ lib.optional (doDoc && copyDocsToSeparateOutput) "doc";
    preInstallPhases = lib.optional doDoc [ "docPhase" ];

    # Otherwise specifying CMake as a dep breaks the build
    dontUseCmakeConfigure = true;

    nativeBuildInputs = [
      cargo
      # needed at various steps in the build
      jq
      rsync
    ];

    buildInputs = stdenv.lib.optionals stdenv.isDarwin [
      darwin.Security
      darwin.apple_sdk.frameworks.CoreServices
      darwin.cf-private
    ] ++ buildInputs;

    inherit builtDependencies;

    # some environment variables
    RUSTC = "${rustc}/bin/rustc";
    cargo_release = lib.optionalString release "--release";
    cargo_options = cargoOptions;
    cargo_build_options = cargoBuildOptions;
    cargo_test_options = cargoTestOptions;
    cargo_bins_jq_filter = copyBinsFilter;

    configurePhase = ''
      runHook preConfigure

      logRun() {
        >&2 echo "$@"
        eval "$@"
      }

      log() {
        >&2 echo "[naersk]" "$@"
      }

      cargo_build_output_json=$(mktemp)

      log "cargo_release: $cargo_release"
      log "cargo_options: $cargo_options"
      log "cargo_build_options: $cargo_build_options"
      log "cargo_test_options: $cargo_test_options"
      log "cargo_bins_jq_filter: $cargo_bins_jq_filter"
      log "cargo_build_output_json (created): $cargo_build_output_json"

      mkdir -p target

      # make sure that all source files are tagged as "recent" (since we write
      # some stubs here and there)
      find . -type f -exec touch {} +

      for dep in $builtDependencies; do
          log "pre-installing dep $dep"
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

      runHook postConfigure
    '';

    buildPhase =

      ''
        runHook preBuild

        cargo_ec=0
        logRun ${cargoBuild} || cargo_ec="$?"

        if [ "$cargo_ec" -ne "0" ]
        then
          cat $cargo_build_output_json | jq -cMr 'select(.message.rendered != null) | .message.rendered'
          log "cargo returned with exit code $cargo_ec, exiting"
          exit "$cargo_ec"
        fi

        runHook postBuild
      '';

    checkPhase = ''
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
        if [ -f "$cargo_build_output_json" ]
        then
          log "Using file $cargo_build_output_json to retrieve build products"
          while IFS= read -r to_copy; do
            bin_path=$(jq -cMr '.executable' <<<"$to_copy")
            bin_name=$(jq -cMr '.target.name' <<<"$to_copy")
            log "found executable $bin_name -> $out/bin/$bin_name"
            cp "$bin_path" "$out/bin/$bin_name"
          done < <(jq -cMr "$cargo_bins_jq_filter" <"$cargo_build_output_json")
        else
          log "$cargo_build_output_json: file wasn't written, using less reliable copying method"
          find out -type f -executable \
            -not -name '*.so' -a -not -name '*.dylib' \
            -exec cp {} $out/bin \;
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
  };

  # XXX: the actual crate format is not documented but in practice is a
  # gzipped tar; we simply unpack it and introduce a ".cargo-checksum.json"
  # file that cargo itself uses to double check the sha256
  unpackCrate = name: version: sha256:
    let
      crate = fetchurl {
        url = "https://crates.io/api/v1/crates/${name}/${version}/download";
        inherit sha256;
        name = "download-${name}-${version}";
      };
    in
      runCommand "unpack-${name}-${version}" {}
        ''
          mkdir -p $out
          tar -xzf ${crate} -C $out
          echo '{"package":"${sha256}","files":{}}' > $out/${name}-${version}/.cargo-checksum.json
        '';
in
drv.overrideAttrs override
