{ pkgs, ...}@args: {
  agent-rs = import ./agent-rs args;
  lorri = import ./lorri args;
  /* nushell doesn't build on Darwin */
  nushell = if pkgs.stdenv.isDarwin then null else import ./nushell args;
  probe-rs = import ./probe-rs args;
  ripgrep-all = import ./ripgrep-all args;
  rustlings = import ./rustlings args;
  talent-plan = import ./talent-plan args;
}
