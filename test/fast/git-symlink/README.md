# Test

This test ensures that we resolve ("copy", "follow", etc.) symlinks during Git
dependency unpacking.

(see: https://github.com/nix-community/naersk/issues/230)

# Setup

In this test, crate `app` depends on crate `dep`, which is located in
`./dep-workspace/dep`.

`./dep-workspace/dep/src/lib.rs` contains an `include_str!()` that loads a
symlinked file called `../symlink.txt`, which points _outside_ of
`./dep-workspace/dep`, at `./dep-workspace/original.txt`.

Because that symlink points outside of `./dep-workspace/dep`, had we not
resolved symlinks during dependency unpacking, the symlink would have become
broken during the dependency unpacking, making the test fail with:

```
error: couldn't read /nix/store/...-crates-io/dep/src/../symlink.txt: No such file or directory (os error 2)
 --> /sources/.../src/lib.rs:2:5
  |
  |     include_str!("../symlink.txt")
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

# Caveats

- This test relies on a [dynamically-built Git repository](../../README.md#caveats).
