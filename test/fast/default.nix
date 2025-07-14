{ pkgs, naersk, ... }: {
  cargo-config = pkgs.callPackage ./cargo-config { inherit naersk; };
  cargo-wildcard = pkgs.callPackage ./cargo-wildcard { inherit naersk; };
  default-run = pkgs.callPackage ./default-run { inherit naersk; };
  dummyfication = pkgs.callPackage ./dummyfication { inherit naersk; };
  duplicated-cargo-lock-items = pkgs.callPackage ./duplicated-cargo-lock-items { inherit naersk; };
  git-dep = pkgs.callPackage ./git-dep { inherit naersk; };
  git-dep-by-branch = pkgs.callPackage ./git-dep-by-branch { inherit naersk; };
  git-dep-by-branch-with-slash = pkgs.callPackage ./git-dep-by-branch-with-slash { inherit naersk; };
  git-dep-by-tag = pkgs.callPackage ./git-dep-by-tag { inherit naersk; };
  git-dep-dup = pkgs.callPackage ./git-dep-dup { inherit naersk; };
  git-single-repository-with-multiple-crates = pkgs.callPackage ./git-single-repository-with-multiple-crates { inherit naersk; };
  git-symlink = pkgs.callPackage ./git-symlink { inherit naersk; };
  openssl = pkgs.callPackage ./openssl { inherit naersk; };
  post-install-hook = pkgs.callPackage ./post-install-hook { inherit naersk; };
  readme = pkgs.callPackage ./readme { inherit naersk; };
  simple-dep = pkgs.callPackage ./simple-dep { inherit naersk; };
  simple-dep-patched = pkgs.callPackage ./simple-dep-patched { inherit naersk; };
  symlinks = pkgs.callPackage ./symlinks { inherit naersk; };
  unused-patch = pkgs.callPackage ./unused-patch { inherit naersk; };
  workspace = pkgs.callPackage ./workspace { inherit naersk; };
  workspace-build-rs = pkgs.callPackage ./workspace-build-rs { inherit naersk; };
  workspace-patched = pkgs.callPackage ./workspace-patched { inherit naersk; };
}
