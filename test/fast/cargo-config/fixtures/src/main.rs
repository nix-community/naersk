fn main() {
    println!("{}", env!("ENV_HELLO_WORLD"));
}

#[cfg(test)]
mod tests {
    #[test]
    fn test() {
        assert_eq!("Hello, World!", env!("ENV_HELLO_WORLD"));
    }
}
