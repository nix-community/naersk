{ lib, libb, builtinz, src, attrs }:
rec
{ usePureFromTOML = attrs.usePureFromTOML or true;
  readTOML = builtinz.readTOML usePureFromTOML;

  compressTarget = attrs.compressTarget or true;

  # Whether we skip pre-building the deps
  isSingleStep = attrs.singleStep or false;

  # The members we want to build
  # (list of directory names)
  wantedMembers =
    lib.mapAttrsToList (member: _cargotoml: member) wantedMemberCargotomls;

  # Member path to cargotoml
  # (attrset from directory name to Nix object)
  wantedMemberCargotomls =
    let pred =
      if ! isWorkspace
      then (_member: _cargotoml: true)
      else
        if builtins.hasAttr "targets" attrs
        then (_member: cargotoml: lib.elem cargotoml.package.name attrs.targets)
        else (member: _cargotoml: member != "."); in
    lib.filterAttrs pred cargotomls;

  # All cargotomls, from path to nix object
  # (attrset from directory name to Nix object)
  cargotomls =
    let readTOML = builtinz.readTOML usePureFromTOML; in

    { "." = toplevelCargotoml; } //
    lib.optionalAttrs isWorkspace
    (lib.listToAttrs
      (map
        (member:
          { name = member;
            value = readTOML (src + "/${member}/Cargo.toml");
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
    in lib.optionals (builtins.hasAttr "patch" toplevelCargotoml)
        (map mkRelative
          (lib.collect (as: lib.isAttrs as && builtins.hasAttr "path" as)
            toplevelCargotoml.patch));

  # Are we building a workspace (or is this a simple crate) ?
  isWorkspace = builtins.hasAttr "workspace" toplevelCargotoml;

  # The top level Cargo.toml, either a workspace or package
  toplevelCargotoml = readTOML (src + "/Cargo.toml");

  # The cargo lock
  cargolock = readTOML (src + "/Cargo.lock");

  # The list of paths to Cargo.tomls. If this is a workspace, the paths
  # are the members. Otherwise, there is a single path, ".".
  cratePaths = lib.concatStringsSep "\n" wantedMembers;

  packageName = attrs.name or toplevelCargotoml.package.name or
    (if isWorkspace then "rust-workspace" else "rust-package");

  packageVersion = attrs.version or toplevelCargotoml.package.version or
    "unknown";

  # The list of _all_ crates (incl. transitive dependencies) with name,
  # version and sha256 of the crate
  # Example:
  #   [ { name = "wabt", version = "2.0.6", sha256 = "..." } ]
  crateDependencies = libb.mkVersions cargolock;

  preBuild = ''
    # Cargo uses mtime, and we write `src/lib.rs` and `src/main.rs`in
    # the dep build step, so make sure cargo rebuilds stuff
    if [ -f src/lib.rs ] ; then touch src/lib.rs; fi
    if [ -f src/main.rs ] ; then touch src/main.rs; fi
  '';

  cargoBuild = attrs.cargoBuild or ''
    cargo build "''${cargo_release}" -j $NIX_BUILD_CORES -Z unstable-options --out-dir out
  '';
  cargoTestCommands = attrs.cargoTestCommands or [
    ''cargo test "''${cargo_release}" -j $NIX_BUILD_CORES''
  ];
}
