# Test

This test ensures that we correctly handle dependencies with slashes in their
names (as it requires some extra care around unpacking them).

# Setup

In this test, crate `app` depends on crate `dep`, for which our Nix test-runner
dynamically creates a Git repository with a branch called `with/slash`.

Naersk then builds `app`, and if the compilation succeeds, then everything must
be working correctly.

# Caveats

- This test relies on a [dynamically-built Git repository](../../README.md#caveats).
