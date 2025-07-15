# Tests

This directory contains a handful of naersk's tests. Run the tests with:

```bash
nix build .#tests
```

You can build a subset of fast tests:

```bash
nix build .#tests.fast
```

You can also build tests individually:

```bash
nix build .#tests.simple-dep
```

For a list of tests see `./test` (and subdirs) or type `nix build .#tests.<TAB>`.


## External Git repositories

Some tests use external Git repositories hosted on
https://github.com/nmattia/naersk-fixtures. This is much simpler than wrestling
with IFD & nested git repos.
