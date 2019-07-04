# some extra "builtins"
{ writeText, runCommand, remarshal }:

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
}
