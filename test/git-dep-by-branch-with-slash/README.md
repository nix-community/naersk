# Abstract

This test ensures that we correctly handle dependencies with slashes in their
names (as it requires some extra care around unpacking them).

# Test

`app` depends on `dep`, for which our Nix test-runner dynamically creates a Git
repository with a branch called `with/slash`; naersk then builds `app`, and if
the compilation succeeds, then everything must be working correctly.

For this test to exist, we rely on one trick though:

- Cargo doesn't support relative Git paths (such as `dep = { git = "file:../dep" }`),
  but it does support _absolute_ paths - that's why `app`'s `Cargo.toml` and
  `Cargo.lock` refer to `dep` via `$depPath` and `$depRev`; those variables are
  substituted through Nix code.

A bit unfortunately, that trick also means that this test cannot be run locally
as it is - you'd have to open `app/Cargo.toml` and adjust `$depPath` to be an 
actual, absolute path to `dep` on your machine.
