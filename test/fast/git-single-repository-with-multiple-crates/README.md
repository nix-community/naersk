# Test

This test ensures that we correctly locate `Cargo.toml`-s when we're given a Git
dependency that points into a workspace-less repository with multiple crates
inside of it.

# Caveats

- This test relies on a [dynamically-built Git repository](../../README.md#caveats).
