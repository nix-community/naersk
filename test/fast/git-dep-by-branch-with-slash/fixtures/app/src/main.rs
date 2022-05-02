fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
#[test]
fn test() {
    assert_eq!("with/slash", dep::branch());
}
