// Fail compilation if `$METABUILD_RAN` is not set by the build script
const _: &str = env!("METABUILD_RAN");

fn main() {}
