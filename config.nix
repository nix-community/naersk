{ lib, libb, builtinz, arg }:
let
  argIsAttrs =
    if lib.isDerivation arg then false
    else if lib.isString arg then false
    else if builtins.typeOf arg == "path" then false
    else if builtins.hasAttr "outPath" arg then false
    else true;

  # if the argument is not an attribute set, then assume it's the 'root'.
  attrs = if argIsAttrs then arg else { root = arg; };

  # we differentiate 'src' and 'root'. 'src' is used as source for the build;
  # 'root' is used to find files like 'Cargo.toml'. As often as possible 'root'
  # should be a "path" to avoid reading values from the nix-store.
  # Below we try to come up with some good values for src and root if they're
  # not defined.
  sr =
    let
      hasRoot = builtins.hasAttr "root" attrs;
      hasSrc = builtins.hasAttr "src" attrs;
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

  usePureFromTOML = attrs.usePureFromTOML or true;
  readTOML = builtinz.readTOML usePureFromTOML;

  # config used during build the prebuild and the final build
  buildConfig = {
    compressTarget = attrs.compressTarget or true;
    doCheck = attrs.doCheck or true;
    buildInputs = attrs.buildInputs or [];
    removeReferencesToSrcFromDocs = attrs.removeReferencesToSrcFromDocs or true;
    doDoc = attrs.doDoc or true;
    #| Whether or not the rustdoc can fail the build
    doDocFail = attrs.doDocFail or false;

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
            if builtins.hasAttr "targets" attrs
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

    packageName = attrs.name or toplevelCargotoml.package.name or
      (if isWorkspace then "rust-workspace" else "rust-package");

    packageVersion = attrs.version or toplevelCargotoml.package.version or
      "unknown";

    cargoTestCommands = attrs.cargoTestCommands or [
      ''cargo test "''${cargo_release}" -j $NIX_BUILD_CORES''
    ];

    #| Whether or not to forward intermediate build artifacts to $out
    copyTarget = attrs.copyTarget or false;

    copyBins = attrs.copyBins or true;

    copyDocsToSeparateOutput = attrs.copyDocsToSeparateOutput or true;
  };
in
buildPlanConfig // { inherit buildConfig; }
