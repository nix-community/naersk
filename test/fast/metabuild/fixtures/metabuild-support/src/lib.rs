pub fn metabuild() {
    println!("cargo:rustc-env=METABUILD_RAN=1");
}
