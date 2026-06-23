# workspace-meta

Tests that metadata can be read from the workspace via the workspace's `[package]`:

```toml
[workspace.package]
version = "0.0.1"
...

[package]
version = { workspace = true }
...
```
