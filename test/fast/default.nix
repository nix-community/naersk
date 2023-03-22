args: {
  cargo-wildcard = import ./cargo-wildcard args;
  default-run = import ./default-run args;
  dummyfication = import ./dummyfication args;
  git-dep = import ./git-dep args;
  git-dep-by-branch = import ./git-dep-by-branch args;
  git-dep-by-branch-with-slash = import ./git-dep-by-branch-with-slash args;
  git-dep-by-tag = import ./git-dep-by-tag args;
  git-dep-dup = import ./git-dep-dup args;
  git-single-repository-with-multiple-crates = import ./git-single-repository-with-multiple-crates args;
  git-symlink = import ./git-symlink args;
  post-install-hook = import ./post-install-hook args;
  readme = import ./readme args;
  simple-dep = import ./simple-dep args;
  simple-dep-patched = import ./simple-dep-patched args;
  symlinks = import ./symlinks args;
  workspace = import ./workspace args;
  workspace-build-rs = import ./workspace-build-rs args;
  workspace-patched = import ./workspace-patched args;
}
