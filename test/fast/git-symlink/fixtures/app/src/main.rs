fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
#[test]
fn test() {
    assert_eq!("Hello, world!\n", dep::get());
}
