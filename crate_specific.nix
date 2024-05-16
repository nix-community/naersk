# This file contains crate-specific build inputs.
#
# Each of them is an attribute with name of the crate and value being a function.
# This function gets as arguments:
#  - `crateInfo` with information about the crate, such as sha256 or version
#
# Currently supported fields to return are: `buildInputs`, `nativeBuildInputs`

{ pkgs }:

{
    openssl-sys = { ... }: {
        nativeBuildInputs = with pkgs; [ pkg-config ];
        buildInputs = with pkgs; [ openssl ];
    };
}
