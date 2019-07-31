# some extra "builtins"
{ lib
, writeText
, runCommand
, remarshal
, usePureToTOML ? false
, usePureFromTOML ? false
}:

let
  # Nix < 2.3 cannot parse all TOML files
  # https://github.com/NixOS/nix/issues/2901 so we offer an impure escape hatch
  fromTOML = str: if usePureFromTOML then builtins.fromTOML str else
    builtins.fromJSON (builtins.readFile (
      runCommand "from-toml"
      { buildInputs = [ remarshal ];
        allowSubstitutes = false;
        preferLocalBuild = true;
        from_toml_in = str;
      }
      ''
        echo "$from_toml_in" > in.toml
        remarshal \
          -if toml \
          -i in.toml \
          -of json \
          -o $out
      ''));

    toTOML = obj:
      if usePureToTOML then
        import ./to-toml.nix { inherit lib; }
      else builtins.readFile (runCommand "to-toml"
        { buildInputs = [ remarshal ];
          allowSubstitutes = false;
          preferLocalBuild = true;
          to_toml_in = builtins.toJSON obj;
        }
        ''
          echo "$to_toml_in" > in.json
          remarshal \
            -if json \
            -i in.json \
            -of toml \
            -o $out
        '');

in
{
    readTOML = f: fromTOML (builtins.readFile f);
    writeTOML = attrs:
      writeText "write-toml" (toTOML attrs);

# runCommand "write-toml"
      #{ buildInputs = [ remarshal ];
        #allowSubstitutes = false;
        #preferLocalBuild = true;
      #}
      #''
        #remarshal \
          #-if json \
          #-i ${writeText "toml-json" (builtins.toJSON attrs)} \
          #-of toml \
          #-o $out
      #'';

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
