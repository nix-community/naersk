{ lib, libb, builtinz, arg }:
let
  mkAttrs = attrs0:
  {   # The name of the derivation.
      name = attrs0.name or null;
      # The version of the derivation.
      version = attrs0.version or null;
      # Used by `naersk` as source input to the derivation. When `root` is not
      # set, `src` is also used to discover the `Cargo.toml` and `Cargo.lock`.
      src = attrs0.src or null;
      # Used by `naersk` to read the `Cargo.toml` and `Cargo.lock` files. May
      # be different from `src`. When `src` is not set, `root` is (indirectly)
      # used as `src`.
      root = attrs0.root or null;
      # The command to use for the build.
      cargoBuild = attrs0.cargoBuild or
          ''cargo "''${cargo_options[@]}" build "''${cargo_release[@]}" -j $NIX_BUILD_CORES -Z unstable-options --out-dir out'';
      # When true, `checkPhase` is run.
      doCheck = attrs0.doCheck or true;
      # The commands to run in the `checkPhase`.
      cargoTestCommands = attrs0.cargoTestCommands or
          [ ''cargo "''${cargo_options[@]}" test "''${cargo_release[@]}" -j $NIX_BUILD_CORES'' ];
      # Extra `buildInputs` to all derivations.
      buildInputs = attrs0.buildInputs or [];
      # Options passed to cargo before the command (cargo OPTIONS <cmd>)
      cargoOptions = attrs0.cargoOptions or [];
      # When true, `cargo doc` is run and a new output `doc` is generated.
      doDoc = attrs0.doDoc or true;
      # When true, all cargo builds are run with `--release`.
      release = attrs0.release or true;
      # An override for all derivations involved in the build.
      override = attrs0.override or (x: x);
      # When true, no intermediary (dependency-only) build is run. Enabling
      # `singleStep` greatly reduces the incrementality of the builds.
      singleStep = attrs0.singleStep or false;
      # The targets to build if the `Cargo.toml` is a virtual manifest.
      targets =  attrs0.targets or null;
      # When true, the resulting binaries are copied to `$out/bin`.
      copyBins = attrs0.copyBins or true;
      # When true, the documentation is generated in a different output, `doc`.
      copyDocsToSeparateOutput =  attrs0.copyDocsToSeparateOutput or true;
      # When true, the build fails if the documentation step fails; otherwise
      # the failure is ignored.
      doDocFail = attrs0.doDocFail or false;
      # When true, references to the nix store are removed from the generated
      # documentation.
      removeReferencesToSrcFromDocs = attrs0.removeReferencesToSrcFromDocs or true;
      # When true, the build output of intermediary builds is compressed with
      # [`Zstandard`](https://facebook.github.io/zstd/). This reduces the size
      # of closures.
      compressTarget = attrs0.compressTarget or true;
      # When true, the `target/` directory is copied to `$out`.
      copyTarget = attrs0.copyTarget or false;
      # Whether to use the `fromTOML` built-in or not. When set to `false` the
      # python package `remarshal` is used instead (in a derivation) and the
      # JSON output is read with `builtins.fromJSON`.
      # This is a workaround for old versions of Nix. May be used safely from
      # Nix 2.3 onwards where all bugs in `builtins.fromTOML` seem to have been
      # fixed.
      usePureFromTOML = attrs0.usePureFromTOML or true;

      # Prefetch git dependencies with `builtins.fetchGit` and add `[patch.*]`
      # sections to the `Cargo.toml`. This also removes all references to git
      # links in the `Cargo.lock`. **Highly experimental.**
      allowGitDependencies = attrs0.allowGitDependencies or false;
    };

  argIsAttrs =
    if lib.isDerivation arg then false
    else if lib.isString arg then false
    else if builtins.typeOf arg == "path" then false
    else if builtins.hasAttr "outPath" arg then false
    else true;

  # if the argument is not an attribute set, then assume it's the 'root'.

  attrs =
    if argIsAttrs
    then mkAttrs arg
    else mkAttrs { root = arg; };

  # we differentiate 'src' and 'root'. 'src' is used as source for the build;
  # 'root' is used to find files like 'Cargo.toml'. As often as possible 'root'
  # should be a "path" to avoid reading values from the nix-store.
  # Below we try to come up with some good values for src and root if they're
  # not defined.
  sr =
    let
      hasRoot = ! isNull attrs.root;
      hasSrc = ! isNull attrs.src;
      isPath = x: builtins.typeOf x == "path";
      root = attrs.root;
      src = attrs.src;
    in
    # src: yes, root: no
    if hasSrc && ! hasRoot then
      if isPath src then
        { src = lib.cleanSource src; root = src; }
      else { inherit src; root = src; }
    # src: yes, root: yes
    else if hasRoot && hasSrc then
      { inherit src root; }
    # src: no, root: yes
    else if hasRoot && ! hasSrc then
      if isPath root then
        { inherit root; src = lib.cleanSource root; }
      else
        { inherit root; src = root; }
    # src: no, root: yes
    else throw "please specify either 'src' or 'root'";

  usePureFromTOML = attrs.usePureFromTOML;
  readTOML = builtinz.readTOML usePureFromTOML;

  # config used during build the prebuild and the final build
  buildConfig = {
    compressTarget = attrs.compressTarget;
    doCheck = attrs.doCheck;
    cargoOptions = attrs.cargoOptions;
    buildInputs = attrs.buildInputs;
    removeReferencesToSrcFromDocs = attrs.removeReferencesToSrcFromDocs;
    doDoc = attrs.doDoc;
    #| Whether or not the rustdoc can fail the build
    doDocFail = attrs.doDocFail;

    release = attrs.release or true;

    override = attrs.override or (x: x);

    cargoBuild = attrs.cargoBuild or ''
      cargo build "''${cargo_release}" -j $NIX_BUILD_CORES -Z unstable-options --out-dir out
    '';

    # The list of _all_ crates (incl. transitive dependencies) with name,
    # version and sha256 of the crate
    # Example:
    #   [ { name = "wabt", version = "2.0.6", sha256 = "..." } ]
    crateDependencies = libb.mkVersions buildPlanConfig.cargolock;
  };

  # config used when planning the builds
  buildPlanConfig = rec {
    inherit (sr) src root;
    # Whether we skip pre-building the deps
    isSingleStep = attrs.singleStep;

    patchGitDeps = attrs.allowGitDependencies;

    # The members we want to build
    # (list of directory names)
    wantedMembers =
      lib.mapAttrsToList (member: _cargotoml: member) wantedMemberCargotomls;

    # Member path to cargotoml
    # (attrset from directory name to Nix object)
    wantedMemberCargotomls =
      let
        pred =
          if ! isWorkspace
          then (_member: _cargotoml: true)
          else
            if ! isNull attrs.targets
            then (_member: cargotoml: lib.elem cargotoml.package.name attrs.targets)
            else (member: _cargotoml: member != ".");
      in
        lib.filterAttrs pred cargotomls;

    # All cargotomls, from path to nix object
    # (attrset from directory name to Nix object)
    cargotomls =
      let
        readTOML = builtinz.readTOML usePureFromTOML;
      in
        { "." = toplevelCargotoml; } // lib.optionalAttrs isWorkspace
          (
            lib.listToAttrs
              (
                map
                  (
                    member:
                      {
                        name = member;
                        value = readTOML (root + "/${member}/Cargo.toml");
                      }
                  )
                  (toplevelCargotoml.workspace.members or [])
              )
          );

    patchedSources =
      let
        mkRelative = po:
          if lib.hasPrefix "/" po.path
          then throw "'${toString src}/Cargo.toml' contains the absolute path '${toString po.path}' which is not allowed under a [patch] section by naersk. Please make it relative to '${toString src}'"
          else src + "/" + po.path;
      in
        lib.optionals (builtins.hasAttr "patch" toplevelCargotoml)
          (
            map mkRelative
              (
                lib.collect (as: lib.isAttrs as && builtins.hasAttr "path" as)
                  toplevelCargotoml.patch
              )
          );

    # Are we building a workspace (or is this a simple crate) ?
    isWorkspace = builtins.hasAttr "workspace" toplevelCargotoml;

    # The top level Cargo.toml, either a workspace or package
    toplevelCargotoml = readTOML (root + "/Cargo.toml");

    # The cargo lock
    cargolock = readTOML (root + "/Cargo.lock");

    packageName =
      if ! isNull attrs.name
      then attrs.name
      else toplevelCargotoml.package.name or
        (if isWorkspace then "rust-workspace" else "rust-package");

    packageVersion =
      if ! isNull attrs.version
      then attrs.version
      else toplevelCargotoml.package.version or "unknown";

    cargoTestCommands = attrs.cargoTestCommands;

    #| Whether or not to forward intermediate build artifacts to $out
    copyTarget = attrs.copyTarget or false;

    copyBins = attrs.copyBins or true;

    copyDocsToSeparateOutput = attrs.copyDocsToSeparateOutput or true;
  };
in
buildPlanConfig // { inherit buildConfig; }
