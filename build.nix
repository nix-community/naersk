{ src
  #| What command to run during the build phase
, cargoBuild
, cargoBuildOptions
, remapPathPrefix
, #| What command to run during the test phase
  cargoTestCommands
, cargoTestOptions
, copyTarget
  #| Whether or not to compress the target when copying it
, compressTarget
  #| Whether or not to copy binaries to $out/bin
, copyBins
, copyBinsFilter
  #| Whether or not to copy libraries to $out/bin
, copyLibs
, copyLibsFilter
, doDoc
, doDocFail
, cargoDocCommands
, cargoDocOptions
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
, nativeBuildInputs
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
, runCommand
, remarshal
, crateDependencies
, zstd
, fetchurl
, lndir
, userAttrs
}:

let
  builtinz =
    builtins // import ./builtins
      { inherit lib writeText remarshal runCommand; };

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
        key=$(echo "$dep" | jq -cMr '.key')
        while read -r toml; do
          name=$(cat $toml \
            | sed -n -e '/\[package\]/,$p' \
            | grep -m 1 "^name\W" \
            | grep -oP '(?<=").+(?=")' \
            || true)
          version=$(cat $toml \
            | sed -n -e '/\[package\]/,$p' \
            | grep -m 1 "^version\W" \
            | grep -oP '(?<=").+(?=")' \
            || true)
          if [ -n "$name" -a -n "$version" ]; then
            # Most filesystmes have a maximum filename length of 255
            nkey="$(echo "$name-$version-$key" | head -c 255)"
            log "$url Found crate '$name-$version' ($nkey)"
            if [ -d "$out/$nkey" ]; then
              log "Crate was already unpacked at $out/$nkey"
            else
              cp -r $(dirname $toml) $out/$nkey
              chmod +w "$out/$nkey"
              echo '{"package":null,"files":{}}' > $out/$nkey/.cargo-checksum.json
              log "Crate unpacked at $out/$nkey"
            fi
          fi
        done <<< "$tomls"
      done < <(cat ${
    builtins.toFile "git-deps-json" (builtins.toJSON gitDependencies)
    } | jq -cMr '.[]')
    '';

  nixSourcesDir = symlinkJoinPassViaFile {
    name = "crates-io";
    paths = map (v: unpackCrate v.name v.version v.sha256)
      crateDependencies ++ [ unpackedGitDependencies ];
  };

  drvAttrs = {
    name = "${pname}-${version}";
    inherit
      src
      version
      remapPathPrefix
      ;

    crate_sources = nixSourcesDir;

    # The cargo config with source replacement. Replaces both crates.io crates
    # and git dependencies.
    cargoconfig = builtinz.toTOML {
      source = {
        crates-io = { replace-with = "nix-sources"; };
        nix-sources = {
          directory = nixSourcesDir;
        };
      } // lib.listToAttrs (
        map
          (
            e:
              let
                key = if e ? rev    then "?rev=${e.rev}"       else
                      if e ? tag    then "?tag=${e.tag}"       else
                      if e ? branch then "?branch=${e.branch}" else
                      "";
              in
              {
                name = "${e.url}${key}";
                value = lib.filterAttrs (n: _: n == "rev" || n == "tag" || n == "branch") e // {
                  git = e.url;
                  replace-with = "nix-sources";
                };
              }
          )
          gitDependencies
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
    ] ++ nativeBuildInputs;

    buildInputs = lib.optionals stdenv.isDarwin [
      darwin.Security
      darwin.apple_sdk.frameworks.CoreServices
      darwin.cf-private
      darwin.libiconv
    ] ++ buildInputs;

    inherit builtDependencies;

    # some environment variables
    RUSTC = "${rustc}/bin/rustc";
    cargo_release = lib.optionalString release "--release";
    cargo_options = cargoOptions;
    cargo_build_options = cargoBuildOptions;
    cargo_test_options = cargoTestOptions;
    cargo_doc_options = cargoDocOptions;
    cargo_bins_jq_filter = copyBinsFilter;
    cargo_libs_jq_filter = copyLibsFilter;

    configurePhase = ''
      runHook preConfigure
      export SOURCE_DATE_EPOCH=1

      logRun() {
        >&2 echo "$@"
        eval "$@"
      }

      log() {
        >&2 echo "[naersk]" "$@"
      }

      cargo_build_output_json=$(mktemp)
      cargo_version=$(cargo --version | grep -oP 'cargo \K.*')

      # ANSI rendered diagnostics were introduced in 1.38:
      # https://github.com/rust-lang/cargo/blob/master/CHANGELOG.md#cargo-138-2019-09-26
      if ! [[ "$cargo_version" < "1.38" ]]
      then
        cargo_message_format="json-diagnostic-rendered-ansi"
      else
        cargo_message_format="json"
      fi

      # Rust's `libtest` defaults to running tests in parallel and uses as many
      # threads as there are cores. This is often too much parallelism so we
      # reduce it to $NIX_BUILD_CORES if not specified by the caller.
      export RUST_TEST_THREADS="''${RUST_TEST_THREADS:-$NIX_BUILD_CORES}"

      log "cargo_version (read): $cargo_version"
      log "cargo_message_format (set): $cargo_message_format"
      log "cargo_release: $cargo_release"
      log "cargo_options: $cargo_options"
      log "cargo_build_options: $cargo_build_options"
      log "cargo_test_options: $cargo_test_options"
      log "RUST_TEST_THREADS: $RUST_TEST_THREADS"
      log "cargo_bins_jq_filter: $cargo_bins_jq_filter"
      log "cargo_build_output_json (created): $cargo_build_output_json"
      log "crate_sources: $crate_sources"
      log "RUSTFLAGS: $RUSTFLAGS"
      log "CARGO_BUILD_RUSTFLAGS: $CARGO_BUILD_RUSTFLAGS"

      ${lib.optionalString remapPathPrefix ''

      # Remove the source path(s) in Rust
      if [ -n "$RUSTFLAGS" ]; then
        RUSTFLAGS="$RUSTFLAGS --remap-path-prefix $crate_sources=/sources"
        log "RUSTFLAGS (updated): $RUSTFLAGS"
      elif [ -n "$CARGO_BUILD_RUSTFLAGS" ]; then
        CARGO_BUILD_RUSTFLAGS="$CARGO_BUILD_RUSTFLAGS --remap-path-prefix $crate_sources=/sources"
        log "CARGO_BUILD_RUSTFLAGS (updated): $CARGO_BUILD_RUSTFLAGS"
      else
        export CARGO_BUILD_RUSTFLAGS="--remap-path-prefix $crate_sources=/sources"
        log "CARGO_BUILD_RUSTFLAGS (updated): $CARGO_BUILD_RUSTFLAGS"
      fi

      ''}

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
        export SOURCE_DATE_EPOCH=1

        cargo_ec=0
        logRun ${cargoBuild} || cargo_ec="$?"

        if [ "$cargo_ec" -ne "0" ]
        then
          cat "$cargo_build_output_json" | jq -cMr 'select(.message.rendered != null) | .message.rendered'
          log "cargo returned with exit code $cargo_ec, exiting"
          exit "$cargo_ec"
        fi

        runHook postBuild
      '';

    checkPhase = ''
      runHook preCheck
      export SOURCE_DATE_EPOCH=1

      ${lib.concatMapStringsSep "\n" (cmd: "logRun ${cmd}") cargoTestCommands}

      runHook postCheck
    '';


    docPhase = lib.optionalString doDoc ''
      runHook preDoc
      export SOURCE_DATE_EPOCH=1

      ${lib.concatMapStringsSep "\n" (cmd: "logRun ${cmd}  || ${if doDocFail then "false" else "true" }") cargoDocCommands}

      ${lib.optionalString removeReferencesToSrcFromDocs ''
      # Remove references to the source derivation to reduce closure size
            match='<meta name="description" content="Source to the Rust file `${builtins.storeDir}[^`]*`.">'
      replacement='<meta name="description" content="Source to the Rust file removed to reduce Nix closure size.">'
      find target/doc ''${CARGO_BUILD_TARGET:+target/$CARGO_BUILD_TARGET/doc} -name "*\.rs\.html" -exec sed -i "s|$match|$replacement|" {} +
    ''}

      runHook postDoc
    '';

    installPhase =
      ''
        runHook preInstall
        export SOURCE_DATE_EPOCH=1

        ${lib.optionalString copyBins ''
        export SOURCE_DATE_EPOCH=1

        mkdir -p $out/bin
        if [ -f "$cargo_build_output_json" ]
        then
          log "Using file $cargo_build_output_json to retrieve build (executable) products"
          while IFS= read -r to_copy; do
            bin_path=$(jq -cMr '.executable' <<<"$to_copy")
            bin_name="$(basename "$bin_path")"
            log "found executable $bin_name -> $out/bin/$bin_name"
            cp "$bin_path" "$out/bin/$bin_name"
          done < <(jq -cMr "$cargo_bins_jq_filter" <"$cargo_build_output_json")
        else
          log "$cargo_build_output_json: file wasn't written, using less reliable copying method"
          find target -type f -executable \
            -not -name '*.so' -a -not -name '*.dylib' \
            -exec cp {} $out/bin \;
        fi
        ''}
        ${lib.optionalString copyLibs ''
        export SOURCE_DATE_EPOCH=1

        mkdir -p $out/lib
        if [ -f "$cargo_build_output_json" ]
        then
          log "Using file $cargo_build_output_json to retrieve build (library) products"
          while IFS= read -r to_copy; do
            lib_paths=$(jq -cMr '.filenames[]' <<<"$to_copy")
            for lib in $lib_paths; do
              log "found library $lib"
              cp "$lib" "$out/lib/"
            done
          done < <(jq -cMr "$cargo_libs_jq_filter" <"$cargo_build_output_json")
        else
          log "$cargo_build_output_json: file wasn't written, using less reliable copying method"
          find target -type f \
            -name '*.so' -or -name '*.dylib' -or -name '*.a' \
            -exec cp {} $out/lib \;
        fi
        ''}

        ${lib.optionalString copyTarget ''
        export SOURCE_DATE_EPOCH=1

        mkdir -p $out
        ${if compressTarget then
        ''
          # See: https://reproducible-builds.org/docs/archives/
          tar --sort=name \
            --mtime="@''${SOURCE_DATE_EPOCH}" \
            --owner=0 --group=0 --numeric-owner \
            --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
            -c target | ${zstd}/bin/zstd -o $out/target.tar.zst
        '' else
        ''
          cp -r target $out
        ''}
      ''}

        ${lib.optionalString (doDoc && copyDocsToSeparateOutput) ''
        export SOURCE_DATE_EPOCH=1

        cp -r target/doc $doc
        if [[ -n "$CARGO_BUILD_TARGET" && -d "target/$CARGO_BUILD_TARGET/doc" ]]; then
          cp -r target/$CARGO_BUILD_TARGET/doc/. $doc/
        fi
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

  /*
  * A copy of `symlinkJoin` from `nixpkgs` which passes the `paths` argument via a file
  * instead of via an environment variable. This should fix the "Argument list too long"
  * error when `paths` exceeds the limit.
  *
  * Create a forest of symlinks to the files in `paths'.
  *
  * Examples:
  * # adds symlinks of hello to current build.
  * { symlinkJoin, hello }:
  * symlinkJoin { name = "myhello"; paths = [ hello ]; }
  *
  * # adds symlinks of hello to current build and prints "links added"
  * { symlinkJoin, hello }:
  * symlinkJoin { name = "myhello"; paths = [ hello ]; postBuild = "echo links added"; }
  */
  symlinkJoinPassViaFile =
    args_@{ name
         , paths
         , preferLocalBuild ? true
         , allowSubstitutes ? false
         , postBuild ? ""
         , ...
         }:
    let
      args = removeAttrs args_ [ "name" "postBuild" ]
        // { inherit preferLocalBuild allowSubstitutes;
             passAsFile = [ "paths" ];
             nativeBuildInputs = [ lndir ];
           }; # pass the defaults
    in runCommand name args
      ''
        mkdir -p $out

        for i in $(cat $pathsPath); do
          lndir -silent $i $out
        done
        ${postBuild}
      '';
  drv = stdenv.mkDerivation (drvAttrs // userAttrs);
in
drv.overrideAttrs override
