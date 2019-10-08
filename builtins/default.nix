# some extra "builtins"
{ lib
, writeText
, runCommand
, remarshal
}:

rec
{
    toTOML = import ./to-toml.nix { inherit lib; };
    writeTOML = name: attrs: writeText name (toTOML attrs);

    readTOML = usePure: f:
      if usePure then
        builtins.fromTOML (builtins.readFile f)
      else
        builtins.fromJSON (builtins.readFile (
          runCommand "from-toml"
          { buildInputs = [ remarshal ];
            allowSubstitutes = false;
            preferLocalBuild = true;
          }
          ''
            echo "$from_toml_in" > in.toml
            remarshal \
              -if toml \
              -i ${f} \
              -of json \
              -o $out
          ''));

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
            parts = lib.splitString "/" (toString path);
            len = lib.length parts;
          in
          map (n: lib.concatStringsSep "/" (lib.take n parts)) (lib.range 3 len);
      in
      all (map isOk parts);
}
