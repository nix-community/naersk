use serde::Serialize;

#[derive(Serialize)]
struct Message {
    msg: String,
}

fn main() {
    let value = serde_json::to_string_pretty(&Message {
        msg: "Hello, world!".into(),
    });
    
    println!("{}", value.unwrap());
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(2 + 2, 4);
    }
}
