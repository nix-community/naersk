# Tests

This directory contains a handful of naersk's tests; you can run them locally
with:

```
# First, you have to be in the naersk's top-level directory:
$ cd ..

# Then:
$ ./script/test --fast
```

# Caveats

## Dynamically-built Git repositories

Some tests (their READMEs will tell you which ones) utilize dynamically-built
Git repositories (i.e. repositories built _ad hoc_ during the testing through
`pkgs.runCommand`).

Those tests' `Cargo.toml` and `Cargo.lock` contain variables (e.g. `$depPath`,
`$depRev` etc.) that are substituted through our Nix code before the test is
run.

Because of that, it's not possible to execute those tests via `cargo test` (for
whatever the reason you'd like to).
