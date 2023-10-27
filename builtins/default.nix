# some extra "builtins"
{
  lib,
  writeText,
  runCommandLocal,
  remarshal,
  formats,
}: rec
{
  # Serializes given attrset into a TOML file.
  #
  # Usage:
  #   writeTOML path attrset
  #
  # On newer nixpkgs, this function invokes `lib.formats.toml` that nowadays
  # handles all TOML documents properly.
  #
  # On older nixpkgs, where that serializer doesn't work correctly¹, we rely on
  # a custom implementation (with its own tiny shortcomings²).
  #
  # TODO remove our custom serializer after nixpkgs v23 becomes more widely
  #      adopted
  #
  # ¹ e.g. cases like `[targets."cfg(\"something\")"]` are translated badly
  # ² https://github.com/nix-community/naersk/issues/263
  writeTOML = let
    our-impl = let
      to-toml = import ./to-toml.nix {
        inherit lib;
      };
    in
      name: value:
        runCommandLocal name {
          value = to-toml value;
          passAsFile = ["value"];
        } ''
          cp "$valuePath" "$out"
          cat "$out"
        '';

    nixpkgs-impl = (formats.toml {}).generate;
  in
    if builtins.compareVersions lib.version "22.11" <= 0
    then our-impl
    else nixpkgs-impl;

  readTOML = usePure: f:
    if usePure
    then
      builtins.fromTOML (
        # Safety: We invoke `unsafeDiscardStringContext` _after_ reading the
        # file, so the derivation either had been already realized or `readFile`
        # just realized it.
        #
        # Abstract: Discarding the context allows for users to provide `src`s
        # that are dynamically generated and contain references to other
        # derivations (e.g. via `pkgs.runCommand`); that's a pretty rare use
        # case, but we need it - if nothing else - for our tests.
        #
        # Had we not discarded the context, and had user passed some string with
        # one, `builtins.fromTOML` would fail with:
        #
        # ```
        # the string '...' is not allowed to refer to a store path
        # ```
        builtins.unsafeDiscardStringContext (
          builtins.readFile f
        )
      )
    else
      builtins.fromJSON (
        builtins.readFile (
          runCommandLocal "from-toml" {
            buildInputs = [remarshal];
          }
          ''
            echo "$from_toml_in" > in.toml
            remarshal \
              -if toml \
              -i ${f} \
              -of json \
              -o $out
          ''
        )
      );

  writeJSON = name: attrs: writeText name (builtins.toJSON attrs);

  # Returns `true` if `path` exists.
  # TODO: use `builtins.pathExists` once
  # https://github.com/NixOS/nix/pull/3012 has landed and is generally
  # available
  pathExists =
    if lib.versionAtLeast builtins.nixVersion "2.3"
    then builtins.pathExists
    else path: let
      all = lib.all (x: x);
      isOk = part: let
        dir = builtins.dirOf part;
        basename = builtins.unsafeDiscardStringContext (builtins.baseNameOf part);
        dirContent = builtins.readDir dir;
      in
        builtins.hasAttr basename dirContent
        && # XXX: this may not work if the directory is a symlink
        (part == path || dirContent.${basename} == "directory");
      parts = let
        # [ "" "nix" "store" "123123" "foo" "bar" ]
        parts = lib.splitString "/" path;
        len = lib.length parts;
      in
        map (n: lib.concatStringsSep "/" (lib.take n parts)) (lib.range 3 len);
    in
      all (map isOk parts);
}
