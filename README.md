# Naersk

Nix support for building [cargo] crates.

## Install

Use [niv]:

``` shell
$ niv add nmattia/naersk
```

And then

``` nix
let
    pkgs = import <nixpkgs> {};
    sources = import ./nix/sources.nix;
    naersk = pkgs.callPackage sources.naersk {};
in naersk.buildPackage ./path/to/rust {}
```

_NOTE_: `./path/to/rust/` should contain a `Cargo.lock`.


[cargo]: https://crates.io/
[niv]: https://github.com/nmattia/niv
