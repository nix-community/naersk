{ pkgs }:

{
    openssl-sys = { ... }: {
        nativeBuildInputs = with pkgs; [ pkg-config ];
        buildInputs = with pkgs; [ openssl ];
    };
}
