# some extra "builtins"
{ lib, writeText, runCommand, remarshal }:

{
    # Nix < 2.3 cannot parse all TOML files
    # https://github.com/NixOS/nix/issues/2901
    # can then be replaced with:
    #   readTOML = f: builtins.fromTOML (builtins.readFile f);
    readTOML = f: builtins.fromJSON (builtins.readFile (runCommand "read-toml"
      { buildInputs = [ remarshal ]; }
      ''
        remarshal \
          -if toml \
          -i ${f} \
          -of json \
          -o $out
      ''));

    writeTOML = attrs: runCommand "write-toml"
      { buildInputs = [ remarshal ]; }
      ''
        remarshal \
          -if json \
          -i ${writeText "toml-json" (builtins.toJSON attrs)} \
          -of toml \
          -o $out
      '';

    writeJSON = name: attrs: writeText name
      (builtins.toJSON attrs);

    # Returns `true` if `path` exists.
    # TODO: use `builtins.pathExists` once
    # https://github.com/NixOS/nix/pull/3012 has landed and is generally
    # available
    pathExists = path:
      let
        all = lib.all (x: x);
        isOk = part:
          let
            dir = builtins.dirOf part;
            basename = builtins.unsafeDiscardStringContext (builtins.baseNameOf part);
            dirContent = builtins.readDir dir;
          in
          builtins.hasAttr basename dirContent &&
          # XXX: this may not work if the directory is a symlink
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
