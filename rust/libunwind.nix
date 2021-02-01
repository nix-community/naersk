# [naersk] this is needed for proper musl builds
# We need libunwind-9.0.0 because earlier versions link c++ symbols we don't
# have to have to link to
{ fetchurl, stdenv, lib, cmake, enableShared ? true }:
let
  version = "9.0.0";
  fetch = sha256: fetchurl {
    url = "https://releases.llvm.org/${version}/libunwind-${version}.src.tar.xz";
    inherit sha256;
  };
in
stdenv.mkDerivation rec {
  pname = "libunwind";
  inherit version;

  src = fetch "1chd1nz4bscrs6qa7p8sqgk5df86ll0frv0f451vhks2w44qsslp";

  nativeBuildInputs = [ cmake ];

  enableParallelBuilding = true;

  cmakeFlags = lib.optional (!enableShared) "-DLIBUNWIND_ENABLE_SHARED=OFF";
}
