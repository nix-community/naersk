{ lib, libb, builtinz, arg, pkgs }:
let
  allowFun = attrs0: attrName: default:
    if builtins.hasAttr attrName attrs0 then
      if lib.isFunction attrs0.${attrName} then
        attrs0.${attrName} default
      else
        let
          finalTy = builtins.typeOf default;
          actualTy = builtins.typeOf attrs0.${attrName};
        in
          throw "${attrName} should be a function from ${finalTy} to ${finalTy}, but is a ${actualTy}"
    else default;

  mkAttrs = attrs0: rec
  {
    # The name of the derivation.
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

    # Whether to fetch all refs while fetching Git dependencies. Useful if
    # the wanted revision isn't in the default branch. Requires Nix 2.4+.
    gitAllRefs = attrs0.gitAllRefs or false;

    # Whether to fetch submodules while fetching Git dependencies. Requires Nix
    # 2.4+.
    gitSubmodules = attrs0.gitSubmodules or false;

    additionalCargoLock = attrs0.additionalCargoLock or null;

    # Url for downloading crates from an alternative source
    cratesDownloadUrl = attrs0.cratesDownloadUrl or "https://crates.io";

    # The command to use for the build.
    cargoBuild =
      allowFun attrs0 "cargoBuild"
        ''cargo $cargo_options build $cargo_build_options >> $cargo_build_output_json'';

    # Options passed to cargo build, i.e. `cargo build <OPTS>`. These options
    # can be accessed during the build through the environment variable
    # `cargo_build_options`. <br/>
    # Note: naersk relies on the
    # `--out-dir out` option and the `--message-format` option.
    # The `$cargo_message_format` variable is set
    # based on the cargo version.<br/>
    # Note: these values are not (shell) escaped, meaning that you can use
    # environment variables but must be careful when introducing e.g. spaces. <br/>
    cargoBuildOptions =
      allowFun attrs0 "cargoBuildOptions" [ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' "--message-format=$cargo_message_format" ];

    # When `true`, rustc remaps the (`/nix/store`) source paths to `/sources`
    # to reduce the number of dependencies in the closure.
    remapPathPrefix = attrs0.remapPathPrefix or true;

    # The commands to run in the `checkPhase`. Do not forget to set
    # [`doCheck`](https://nixos.org/nixpkgs/manual/#ssec-check-phase).
    cargoTestCommands =
      allowFun attrs0 "cargoTestCommands" [ ''cargo $cargo_options test $cargo_test_options'' ];

    # Options passed to cargo test, i.e. `cargo test <OPTS>`. These options
    # can be accessed during the build through the environment variable
    # `cargo_test_options`. <br/>
    # Note: these values are not (shell) escaped, meaning that you can use
    # environment variables but must be careful when introducing e.g. spaces. <br/>
    cargoTestOptions =
      allowFun attrs0 "cargoTestOptions" [ "$cargo_release" ''-j "$NIX_BUILD_CORES"'' ];

    # Options passed to cargo clippy, i.e. `cargo clippy -- <OPTS>`. These options
    # can be accessed during the build through the environment variable
    # `cargo_clippy_options`. <br />
    # Note: these values are not (shell) escaped, meaning that you can use
    # environment variables but must be careful when introducing e.g. spaces. <br/>
    cargoClippyOptions =
      allowFun attrs0 "cargoClippyOptions" [ "-D warnings" ];

    # Options passed to cargo fmt, i.e. `cargo fmt -- <OPTS>`. These options
    # can be accessed during the build through the environment variable
    # `cargo_fmt_options`. <br />
    # Note: these values are not (shell) escaped, meaning that you can use
    # environment variables but must be careful when introducing e.g. spaces. <br/>
    cargoFmtOptions =
      allowFun attrs0 "cargoFmtOptions" [ "--check" ];

    # Extra `nativeBuildInputs` to all derivations.
    nativeBuildInputs = attrs0.nativeBuildInputs or [];

    # Extra `buildInputs` to all derivations.
    buildInputs = attrs0.buildInputs or [];

    # Options passed to all cargo commands, i.e. `cargo <OPTS> ...`. These
    # options can be accessed during the build through the environment variable
    # `cargo_options`. <br/>
    # Note: these values are not (shell) escaped, meaning that you can use
    # environment variables but must be careful when introducing e.g. spaces. <br/>
    cargoOptions =
      allowFun attrs0 "cargoOptions" [ ];

    # When true, `cargo doc` is run and a new output `doc` is generated.
    doDoc = attrs0.doDoc or false;

    # The commands to run in the `docPhase`. Do not forget to set `doDoc`.
    cargoDocCommands =
      allowFun attrs0 "cargoDocCommands" [ ''cargo $cargo_options doc $cargo_doc_options'' ];

    # Options passed to cargo doc, i.e. `cargo doc <OPTS>`. These options
    # can be accessed during the build through the environment variable
    # `cargo_doc_options`. <br/>
    # Note: these values are not (shell) escaped, meaning that you can use
    # environment variables but must be careful when introducing e.g. spaces. <br/>
    cargoDocOptions =
      allowFun attrs0 "cargoDocOptions" [ "--offline" "$cargo_release" ''-j "$NIX_BUILD_CORES"'' ];

    # When true, all cargo builds are run with `--release`. The environment
    # variable `cargo_release` is set to `--release` iff this option is set.
    release = attrs0.release or true;

    # An override for all derivations involved in the build.
    override = attrs0.override or (x: x);

    # An override for the top-level (last, main) derivation. If both `override`
    # and `overrideMain` are specified, _both_ will be applied to the top-level
    # derivation.
    overrideMain = attrs0.overrideMain or (x: x);

    # When true, no intermediary (dependency-only) build is run. Enabling
    # `singleStep` greatly reduces the incrementality of the builds.
    singleStep = attrs0.singleStep or false;

    # When true, the resulting binaries are copied to `$out/bin`. <br/>
    # Note: this relies on cargo's `--message-format` argument, set in the
    # default `cargoBuildOptions`.
    copyBins = attrs0.copyBins or true;

    # When true, the resulting binaries are copied to `$out/lib`. <br/> Note:
    # this relies on cargo's `--message-format` argument, set in the default
    # `cargoBuildOptions`.
    copyLibs = attrs0.copyLibs or false;

    # A [`jq`](https://stedolan.github.io/jq) filter for selecting which build
    # artifacts to release. This is run on cargo's
    # [`--message-format`](https://doc.rust-lang.org/cargo/reference/external-tools.html#json-messages)
    # JSON output. <br/>
    # The value is written to the `cargo_bins_jq_filter` variable.
    copyBinsFilter = attrs0.copyBinsFilter or
      ''select(.reason == "compiler-artifact" and .executable != null and .profile.test == false)'';

    # A [`jq`](https://stedolan.github.io/jq) filter for selecting which build
    # artifacts to release. This is run on cargo's
    # [`--message-format`](https://doc.rust-lang.org/cargo/reference/external-tools.html#json-messages)
    # JSON output. <br/> The value is written to the `cargo_libs_jq_filter`
    # variable. Default: `''select(.reason == "compiler-artifact" and
    # ((.target.kind | contains(["staticlib"])) or (.target.kind |
    # contains(["cdylib"]))) and .filenames != null and .profile.test ==
    # false)''`
    copyLibsFilter = attrs0.copyLibsFilter or
      ''select(.reason == "compiler-artifact" and ((.target.kind | contains(["staticlib"])) or (.target.kind | contains(["cdylib"]))) and .filenames != null and .profile.test == false)'';

    # When true, the documentation is generated in a different output, `doc`.
    copyDocsToSeparateOutput = attrs0.copyDocsToSeparateOutput or true;

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

    # Optional hook to run after the compilation is done; inside this script,
    # `$out/bin` contains compiled Rust binaries. Useful if your application
    # needs e.g. custom environment variables, in which case you can simply run
    # `wrapProgram $out/bin/your-app-name` in here.
    postInstall = attrs0.postInstall or false;

    # Whether to use the `fromTOML` built-in or not. When set to `false` the
    # python package `remarshal` is used instead (in a derivation) and the
    # JSON output is read with `builtins.fromJSON`.
    # This is a workaround for old versions of Nix. May be used safely from
    # Nix 2.3 onwards where all bugs in `builtins.fromTOML` seem to have been
    # fixed.
    usePureFromTOML = attrs0.usePureFromTOML or true;

    # What to do when building the derivation. Either `build`, `check`, `test`, `fmt` or `clippy`. <br/>
    # When set to something other than `build`, no binaries are generated.
    mode = attrs0.mode or "build";

    # Whether to automatically apply crate-specific overrides, mainly additional
    # `buildInputs` for dependencies. <br />
    # For example, if you use the `openssl` crate, `pkgs.pkg-config` and
    # `pkgs.openssl` are automatically added as buildInputs.
    autoCrateSpecificOverrides = attrs0.autoCrateSpecificOverrides or true;
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

  userAttrs =
    if argIsAttrs
    then removeAttrs arg (builtins.attrNames attrs)
    else {};

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

  cargoCommand = let
      mode = attrs.mode;
    in
      if (mode == "build") then
        attrs.cargoBuild
      else if (mode == "check") then
        ''cargo $cargo_options check $cargo_build_options >> $cargo_build_output_json''
      else if (mode == "test") then
        ''cargo $cargo_options test $cargo_test_options >> $cargo_build_output_json''
      else if (mode == "clippy") then
        ''cargo $cargo_options clippy $cargo_build_options -- $cargo_clippy_options >> $cargo_build_output_json''
      else if (mode == "fmt") then
        ''cargo $cargo_options fmt -- $cargo_fmt_options''
      else throw "Unknown mode ${mode}, allowed modes: build, check, test, clippy";

  # config used during build the prebuild and the final build
  buildConfig = {
    inherit cargoCommand;
    inherit (attrs)
      nativeBuildInputs
      buildInputs
      release
      override
      cargoOptions
      compressTarget
      mode
      cratesDownloadUrl

      cargoBuildOptions
      remapPathPrefix
      copyBins
      copyBinsFilter
      copyLibs
      copyLibsFilter
      copyTarget

      cargoTestCommands
      cargoTestOptions

      cargoClippyOptions
      cargoFmtOptions

      doDoc
      doDocFail
      cargoDocCommands
      cargoDocOptions
      copyDocsToSeparateOutput
      removeReferencesToSrcFromDocs
      autoCrateSpecificOverrides

      postInstall
      ;

    # The list of _all_ crates (incl. transitive dependencies) with name,
    # version and sha256 of the crate
    # Example:
    #   [ { name = "wabt", version = "2.0.6", sha256 = "..." } ]
    cratesIoDependencies = libb.mkVersions buildPlanConfig.cargolock ++ lib.optionals (! isNull buildPlanConfig.additionalcargolock) (libb.mkVersions buildPlanConfig.additionalcargolock);

    crateSpecificOverrides = import ./crate_specific.nix { inherit pkgs; };
  };

  # config used when planning the builds
  buildPlanConfig = rec {
    inherit userAttrs;
    inherit (sr) src root;
    inherit (attrs) overrideMain gitAllRefs gitSubmodules;

    isSingleStep = attrs.singleStep;

    # List of all the Cargo.tomls in the workspace.
    #
    # Note that the simplest thing here would be to read `workspace.members`,
    # but somewhat unfortunately there's no requirement that all workspace
    # crates should be listed there - for instance, some projects¹ do:
    #
    # ```
    # [workspace]
    # members = [ "crates/foo", "crates/bar" ]
    #
    # [dependencies]
    # foo = { path = "crates/foo" }
    # bar = { path = "crates/bar" }
    # zar = { path = "crates/zar" }
    # ```
    #
    # ... which Cargo allows and so should we.
    #
    # ¹ such as Nushell
    cargotomls =
      let
        findCargoTomls = dir:
          lib.mapAttrsToList
            (name: type:
              let
                path = "${root}/${dir}/${name}";

              in
              if name == "Cargo.toml" then
                [{ name = dir; toml = readTOML path; }]
              else if type == "directory" then
                findCargoTomls "${dir}/${name}"
              else
                [])
            (builtins.readDir "${root}/${dir}");

      in
        lib.flatten (findCargoTomls ".");

    # If `copySourcesFrom` is set, then it looks like the benefits brought by
    # two-step caching break, for unclear reasons as of now. As such, do not set
    # `copySourcesFrom` if there is no source to actually copy from.
    copySourcesFrom = if copySources != [] then src else null;

    copySources =
      let
        mkRelative = po:
          if lib.hasPrefix "/" po.path
          then throw "'${toString src}/Cargo.toml' contains the absolute path '${toString po.path}' which is not allowed under a [patch] section by naersk. Please make it relative to '${toString src}'"
          else po.path;
      in
        arg.copySources or []
      ++
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
    cargolock =
      let
        cargolock-file = root + "/Cargo.lock";
      in
      if builtins.pathExists cargolock-file then
        readTOML (cargolock-file)
      else
        throw "Naersk requires Cargo.lock to be available in root. Check that it is not in .gitignore and stage it when using git to filter sources (which flakes does)";

    additionalcargolock =
      if ! isNull attrs.additionalCargoLock then
        readTOML (attrs.additionalCargoLock)
      else
        null;

    packageName =
      if ! isNull attrs.name
      then attrs.name
      else toplevelCargotoml.package.name or
        (if isWorkspace then "rust-workspace" else "rust-package");

    packageVersion =
      if ! isNull attrs.version
      then attrs.version
      else toplevelCargotoml.package.version
        or toplevelCargotoml."workspace.package".version
        or "unknown";
  };
in
buildPlanConfig // { inherit buildConfig; }
