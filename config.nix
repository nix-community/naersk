{ lib, libb, builtinz, arg }:
let
  mkAttrs = attrs0:
    { # foo bar< baz
      # baz? foooo
      # one
      # two
      # three
      # four
      root = attrs0.root or null;
      # hello src
      # hello world
      src = attrs0.src or null;
      # hello src
      usePureFromTOML = attrs0.usePureFromTOML or true;
      # hello src
      compressTarget = attrs0.compressTarget or true;
      # hello src
      doCheck = attrs0.doCheck or true;
      # hello src
      buildInputs = attrs0.buildInputs or [];
      # hello src
      removeReferencesToSrcFromDocs = attrs0.removeReferencesToSrcFromDocs or true;
      # hello src
      doDoc = attrs0.doDoc or true;
      # hello src
      doDocFail = attrs0.doDocFail or false;
      # hello src
      release = attrs0.release or true;
      # hello src
      override = attrs0.override or (x: x);
      # hello src
      cargoBuild = attrs0.cargoBuild or
          ''cargo build "''${cargo_release}" -j $NIX_BUILD_CORES -Z unstable-options --out-dir out'';
      # hello src
      singleStep = attrs0.singleStep or false;
      # hello src
      targets =  attrs0.targets or null;
      # hello src
      name = attrs0.name or null;
      # hello src
      version = attrs0.version or null;
      # hello src
      cargoTestCommands = attrs0.cargoTestCommands or
          [ ''cargo test "''${cargo_release}" -j $NIX_BUILD_CORES'' ];
      # hello src
      copyTarget = attrs0.copyTarget or false;
      # hello src
      copyBins = attrs0.copyBins or true;
      # hello src
      copyDocsToSeparateOutput =  attrs0.copyDocsToSeparateOutput or true;
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
    isSingleStep = attrs.singleStep or false;

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
