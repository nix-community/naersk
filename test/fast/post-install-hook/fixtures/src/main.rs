fn main() {
    if std::env::var("FAVORITE_SHOW").unwrap() != "The Office" {
        panic!("Something's not right!");
    }
}
