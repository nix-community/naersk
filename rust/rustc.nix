{ stdenv, removeReferencesTo, pkgsBuildBuild, pkgsBuildHost, pkgsBuildTarget
, lib
, fetchurl, file, python3
, llvm_9, darwin, git, cmake, rust, rustPlatform
, pkgconfig, openssl
, which, libffi
, withBundledLLVM ? false
, enableRustcDev ? true
, version
, sha256
, patches ? []

# [naersk]: extra inputs for musl
, pkgsStatic
, pkgs
, runCommand
, musl
, makeWrapper

}:

# [naersk] We make some assumptions about the platform below, this is just a
# sanity check
assert
  if stdenv.isLinux then
    stdenv.buildPlatform.config == "x86_64-unknown-linux-gnu"
  else
    stdenv.buildPlatform.config == "x86_64-apple-darwin"
  ;

let
  # [naersk]: hard code two targets (musl (on Linux) + wasm32)
  targets =
    [
      "${rust.toRustTarget stdenv.buildPlatform}"
      "wasm32-unknown-unknown"
    ]
    # on Linux we also build the musl target for fully static executables
    ++ lib.optionals stdenv.isLinux [ "x86_64-unknown-linux-musl" ]
    ;
  host = stdenv.buildPlatform.config;
  inherit (stdenv.lib) optionals optional optionalString;
  inherit (darwin.apple_sdk.frameworks) Security;

/* [naersk]: no need for this
  llvmSharedForBuild = pkgsBuildBuild.llvm_9.override { enableSharedLibraries = true; };
  llvmSharedForHost = pkgsBuildHost.llvm_9.override { enableSharedLibraries = true; };
  llvmSharedForTarget = pkgsBuildTarget.llvm_9.override { enableSharedLibraries = true; };
*/

  # For use at runtime
  llvmShared = llvm_9.override { enableSharedLibraries = true; };
in stdenv.mkDerivation rec {
  pname = "rustc";
  inherit version;

  src = fetchurl {
    url = "https://static.rust-lang.org/dist/rustc-${version}-src.tar.gz";
    inherit sha256;
  };

  __darwinAllowLocalNetworking = true;

  # rustc complains about modified source files otherwise
  dontUpdateAutotoolsGnuConfigScripts = true;

  # Running the default `strip -S` command on Darwin corrupts the
  # .rlib files in "lib/".
  #
  # See https://github.com/NixOS/nixpkgs/pull/34227
  #
  # Running `strip -S` when cross compiling can harm the cross rlibs.
  # See: https://github.com/NixOS/nixpkgs/pull/56540#issuecomment-471624656
  stripDebugList = [ "bin" ];

  NIX_LDFLAGS = toString (
       # when linking stage1 libstd: cc: undefined reference to `__cxa_begin_catch'
       optional (stdenv.isLinux && !withBundledLLVM) "--push-state --as-needed -lstdc++ --pop-state"
    ++ optional (stdenv.isDarwin && !withBundledLLVM) "-lc++"
    ++ optional stdenv.isDarwin "-rpath ${llvmShared}/lib");

  # Increase codegen units to introduce parallelism within the compiler.
  RUSTFLAGS = "-Ccodegen-units=10";

  # We need rust to build rust. If we don't provide it, configure will try to download it.
  # Reference: https://github.com/rust-lang/rust/blob/master/src/bootstrap/configure.py
  configureFlags = let
    # [naersk]: a bunch of stuff tweaked for the musl target
    # [naersk]: glibc cc
    ccForBuild  = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc";
    cxxForBuild = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}c++";

    # [naersk]: musl-enabled cc
    ccMusl  = "${pkgsStatic.stdenv.cc}/bin/${pkgsStatic.stdenv.cc.targetPrefix}cc";
    cxxMusl = "${pkgsStatic.stdenv.cc}/bin/${pkgsStatic.stdenv.cc.targetPrefix}c++";
    muslRoot =
      # the musl-root requires a libunwind.a, so we provide one from llvm
      let libunwind = pkgsStatic.callPackage ./libunwind.nix
            { enableShared = false; };
      in
      runCommand "musl-root" {}
    ''
      mkdir -p $out
      cp -r ${musl}/* $out
      chmod +w $out/lib
      cp ${libunwind}/lib/libunwind.a $out/lib/libunwind.a
    '';

/*  [naersk]: this is too complicated
    setBuild  = "--set=target.${rust.toRustTarget stdenv.buildPlatform}";
    setHost   = "--set=target.${rust.toRustTarget stdenv.hostPlatform}";
    setTarget = "--set=target.${rust.toRustTarget stdenv.targetPlatform}";
    ccForBuild  = "${pkgsBuildBuild.targetPackages.stdenv.cc}/bin/${pkgsBuildBuild.targetPackages.stdenv.cc.targetPrefix}cc";
    cxxForBuild = "${pkgsBuildBuild.targetPackages.stdenv.cc}/bin/${pkgsBuildBuild.targetPackages.stdenv.cc.targetPrefix}c++";
    ccForHost  = "${pkgsBuildHost.targetPackages.stdenv.cc}/bin/${pkgsBuildHost.targetPackages.stdenv.cc.targetPrefix}cc";
    cxxForHost = "${pkgsBuildHost.targetPackages.stdenv.cc}/bin/${pkgsBuildHost.targetPackages.stdenv.cc.targetPrefix}c++";
    ccForTarget  = "${pkgsBuildTarget.targetPackages.stdenv.cc}/bin/${pkgsBuildTarget.targetPackages.stdenv.cc.targetPrefix}cc";
    cxxForTarget = "${pkgsBuildTarget.targetPackages.stdenv.cc}/bin/${pkgsBuildTarget.targetPackages.stdenv.cc.targetPrefix}c++";
*/
  in [
    "--release-channel=stable"
    "--set=build.rustc=${rustPlatform.rust.rustc}/bin/rustc"
    "--set=build.cargo=${rustPlatform.rust.cargo}/bin/cargo"
    "--enable-rpath"
    "--enable-vendor"
    "--build=${rust.toRustTarget stdenv.buildPlatform}"
    "--host=${rust.toRustTarget stdenv.hostPlatform}"
/*  [naersk]: some more pkgsCross complications
    "--enable-llvm-link-shared"
    "--set=target.${stdenv.buildPlatform.config}.llvm-config=${llvmShared}/bin/llvm-config"
    ] ++ lib.optionals stdenv.isLinux
    [
    "--set=target.x86_64-unknown-linux-gnu.cc=${ccForBuild}"
    "--set=target.x86_64-unknown-linux-gnu.linker=${ccForBuild}"
    "--set=target.x86_64-unknown-linux-gnu.cxx=${cxxForBuild}"

    "--set=target.x86_64-unknown-linux-musl.cc=${ccMusl}"
    "--set=target.x86_64-unknown-linux-musl.linker=${ccMusl}"
    "--set=target.x86_64-unknown-linux-musl.cxx=${cxxMusl}"
    "--set=target.x86_64-unknown-linux-musl.musl-root=${muslRoot}"
*/
    # [naersk]: we replace those with ours
    "--enable-llvm-link-shared"
    "--set=target.${stdenv.buildPlatform.config}.llvm-config=${llvmShared}/bin/llvm-config"
    ] ++ lib.optionals stdenv.isLinux
    [
    "--set=target.x86_64-unknown-linux-gnu.cc=${ccForBuild}"
    "--set=target.x86_64-unknown-linux-gnu.linker=${ccForBuild}"
    "--set=target.x86_64-unknown-linux-gnu.cxx=${cxxForBuild}"

    "--set=target.x86_64-unknown-linux-musl.cc=${ccMusl}"
    "--set=target.x86_64-unknown-linux-musl.linker=${ccMusl}"
    "--set=target.x86_64-unknown-linux-musl.cxx=${cxxMusl}"
    "--set=target.x86_64-unknown-linux-musl.musl-root=${muslRoot}"
/*  [naersk]: we got extra targets, so we replace with our own
    "--target=${rust.toRustTarget stdenv.targetPlatform}"
*/  "--target=${lib.concatStringsSep "," targets}"

/*  [naersk]: extra nixpkgs complicated stuff
    "${setBuild}.cc=${ccForBuild}"
    "${setHost}.cc=${ccForHost}"
    "${setTarget}.cc=${ccForTarget}"

    "${setBuild}.linker=${ccForBuild}"
    "${setHost}.linker=${ccForHost}"
    "${setTarget}.linker=${ccForTarget}"

    "${setBuild}.cxx=${cxxForBuild}"
    "${setHost}.cxx=${cxxForHost}"
    "${setTarget}.cxx=${cxxForTarget}"
  ] ++ optionals (!withBundledLLVM) [
    "--enable-llvm-link-shared"
    "${setBuild}.llvm-config=${llvmSharedForBuild}/bin/llvm-config"
    "${setHost}.llvm-config=${llvmSharedForHost}/bin/llvm-config"
    "${setTarget}.llvm-config=${llvmSharedForTarget}/bin/llvm-config"
  ] ++ optionals stdenv.isLinux [
*/


    "--enable-profiler" # build libprofiler_builtins
    ] ++ lib.optionals stdenv.isDarwin # [naersk]: let's not forget about darwin
    [
    "--set=target.x86_64-apple-darwin.cc=${ccForBuild}"
    "--set=target.x86_64-apple-darwin.linker=${ccForBuild}"
    "--set=target.x86_64-apple-darwin.cxx=${cxxForBuild}"
    ];

  # The bootstrap.py will generated a Makefile that then executes the build.
  # The BOOTSTRAP_ARGS used by this Makefile must include all flags to pass
  # to the bootstrap builder.
  postConfigure = ''
    substituteInPlace Makefile \
      --replace 'BOOTSTRAP_ARGS :=' 'BOOTSTRAP_ARGS := --jobs $(NIX_BUILD_CORES)'
  '';

  # the rust build system complains that nix alters the checksums
  dontFixLibtool = true;

  postPatch = ''
    patchShebangs src/etc

    ${optionalString (!withBundledLLVM) ''rm -rf src/llvm''}

    # Fix the configure script to not require curl as we won't use it
    sed -i configure \
      -e '/probe_need CFG_CURL curl/d'

    # Useful debugging parameter
    # export VERBOSE=1
  '';

  # rustc unfortunately needs cmake to compile llvm-rt but doesn't
  # use it for the normal build. This disables cmake in Nix.
  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    file python3 rustPlatform.rust.rustc git cmake
    which libffi removeReferencesTo pkgconfig
  ];

  buildInputs = [ openssl ]
    ++ optional stdenv.isDarwin Security
    ++ optional (!withBundledLLVM) llvmShared;

  outputs = [ "out" "man" "doc" ];
  setOutputFlags = false;

  postInstall = stdenv.lib.optionalString enableRustcDev ''
    # install rustc-dev components. Necessary to build rls, clippy...
    python x.py dist rustc-dev
    tar xf build/dist/rustc-dev*tar.gz
    cp -r rustc-dev*/rustc-dev*/lib/* $out/lib/

  '' + ''
    # remove references to llvm-config in lib/rustlib/x86_64-unknown-linux-gnu/codegen-backends/librustc_codegen_llvm-llvm.so
    # and thus a transitive dependency on ncurses
    find $out/lib -name "*.so" -type f -exec remove-references-to -t ${llvmShared} '{}' '+'
  '';

  configurePlatforms = [];

  # https://github.com/NixOS/nixpkgs/pull/21742#issuecomment-272305764
  # https://github.com/rust-lang/rust/issues/30181
  # enableParallelBuilding = false;

  setupHooks = ./setup-hook.sh;

  requiredSystemFeatures = [ "big-parallel" ];

  passthru.llvm = llvmShared;

  meta = with stdenv.lib; {
    homepage = "https://www.rust-lang.org/";
    description = "A safe, concurrent, practical language";
    maintainers = with maintainers; [ madjar cstrahan globin havvy ];
    license = [ licenses.mit licenses.asl20 ];
    platforms = platforms.linux ++ platforms.darwin;
  };
}
