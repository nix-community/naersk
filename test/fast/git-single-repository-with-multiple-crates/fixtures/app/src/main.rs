fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod test {
    #[test]
    fn test() {
        assert_eq!("dep-a", dep_a::id());
        assert_eq!("dep-b", dep_b::id());
        assert_eq!("dep-c", dep_c::id());
    }
}
