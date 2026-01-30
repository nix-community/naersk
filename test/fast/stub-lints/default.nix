{ naersk, ... }:

naersk.buildPackage {
  src = ./fixtures;
  doCheck = true;

  # we instruct cargo to error out if the 'missing-docs' lint is triggered. At the time of writing
  # (30-01-2026) this is the only documentation lint that rustc looks for:
  #
  # > Note that, except for missing_docs, these lints are only available when running rustdoc, not rustc.
  # > [https://doc.rust-lang.org/rustdoc/lints.html#lints]
  CARGO_BUILD_RUSTFLAGS = "-D missing-docs"; # error out if 'missing-docs' is triggered
}
