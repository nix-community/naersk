# multiple-binaries

This example shows a multi-crate setup with two crates, `bar` and `foo`, that
provide separate binaries within a single workspace:

``` shell
$ nix run .#bar
Hello, Bar!

$ nix run .#foo
Hello, Foo!
```
