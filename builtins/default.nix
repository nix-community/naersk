# some extra "builtins"
{ lib
, writeText
, runCommandLocal
, remarshal
, formats
}:

rec
{
  # Serializes given attrset into a TOML file.
  #
  # Usage:
  #   writeTOML path attrset
  writeTOML = (formats.toml { }).generate;

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
}
