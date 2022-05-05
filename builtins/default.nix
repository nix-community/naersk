# some extra "builtins"
{ lib
, writeText
, runCommandLocal
, remarshal
}:

rec
{
  toTOML = import ./to-toml.nix { inherit lib; };
  writeTOML = name: attrs: writeText name (toTOML attrs);

  readTOML = usePure: f:
    if usePure then
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
            buildInputs = [ remarshal ];
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
  pathExists = if lib.versionAtLeast builtins.nixVersion "2.3" then builtins.pathExists else path:
    let
      all = lib.all (x: x);
      isOk = part:
        let
          dir = builtins.dirOf part;
          basename = builtins.unsafeDiscardStringContext (builtins.baseNameOf part);
          dirContent = builtins.readDir dir;
        in
          builtins.hasAttr basename dirContent && # XXX: this may not work if the directory is a symlink
          (part == path || dirContent.${basename} == "directory");
      parts =
        let
          # [ "" "nix" "store" "123123" "foo" "bar" ]
          parts = lib.splitString "/" path;
          len = lib.length parts;
        in
          map (n: lib.concatStringsSep "/" (lib.take n parts)) (lib.range 3 len);
    in
      all (map isOk parts);
}
