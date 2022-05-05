{ naersk, pkgs, ... }:
let
  dep = pkgs.runCommand "dep" {
    buildInputs = [ pkgs.git ];
  } ''
    mkdir $out
    cd $out
    cp -ar ${./fixtures/dep}/* .

    git init
    git add .
    git config user.email 'someone'
    git config user.name 'someone'
    git commit -am 'Initial commit'
  '';

  app = pkgs.runCommand "app" {
    buildInputs = [ pkgs.git ];
  } ''
    mkdir $out
    cd $out
    cp -ar ${./fixtures/app}/* .

    depPath="${dep}"
    depRev=$(cd ${dep} && git rev-parse HEAD)

    sed "s:\$depPath:$depPath:" -is Cargo.*
    sed "s:\$depRev:$depRev:" -is Cargo.*
  '';

in
naersk.buildPackage {
  src = app;
  doCheck = true;
  cargoOptions = (opts: opts ++ [ "--locked" ]);
}
