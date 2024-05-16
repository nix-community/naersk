# OpenSSL needs `pkg-config` and `openssl` buildInputs. This tests whether we correctly supply them automatically.

{ naersk, ... }:

naersk.buildPackage {
  src = ./fixtures;
  doCheck = true;
}
