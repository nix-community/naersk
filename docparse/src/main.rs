use std::{env, fs};

use rnix::{types::*, NodeOrToken, SyntaxKind::*, SyntaxNode};

fn main() {
    let file = match env::args().skip(1).next() {
        Some(file) => file,
        None => {
            panic!("No file given");
        }
    };
    let content = fs::read_to_string(&file).expect("Couldn't read content");
    let ast = rnix::parse(&content).as_result().expect("Couldn't parse");

    let lambda = ast
        .root()
        .inner()
        .and_then(Lambda::cast)
        .ok_or("root isn't a lambda")
        .expect("Something bad happened");
    let args = lambda.body().and_then(LetIn::cast).unwrap();

    for kv in args.entries() {
        if let Some(key) = kv.key() {
            if format!("{}", key.path().next().unwrap()) == "mkAttrs" {
                if let Some(val) = kv.value() {
                    print_mk_attrs(val);
                }
            }
        }
    }
}

fn print_mk_attrs(mk_attrs: SyntaxNode) {
    let body = Lambda::cast(mk_attrs)
        .unwrap()
        .body()
        .and_then(AttrSet::cast)
        .expect("Not a pattern");
    for e in body.entries() {
        let k = e.key().expect("No key").path().next().unwrap();
        let mshown = e
            .value()
            .and_then(OrDefault::cast)
            .expect("Is not OrDefault")
            .default().and_then(|def|
        {
            let shown = format!("{}", def);
            if shown != "null" {
                Some(shown)
            } else {
                None
            }
        });
        let e = e.node().clone();
        let c = find_comment(e).expect("No comment");
        println!("### {} \n", k);
        println!("{}", c);
        if let Some(shown) = mshown {
            println!("");
            println!("_default value:_");
            println!("``` nix");
            println!("{}", shown);
            println!("```");
        }
        println!("");
    }
}

fn find_comment(node: SyntaxNode) -> Option<String> {
    let mut node = NodeOrToken::Node(node);
    let mut comments = Vec::new();
    loop {
        loop {
            if let Some(new) = node.prev_sibling_or_token() {
                node = new;
                break;
            } else {
                node = NodeOrToken::Node(node.parent()?);
            }
        }

        match node.kind() {
            TOKEN_COMMENT => match &node {
                NodeOrToken::Token(token) => comments.push(token.text().clone()),
                NodeOrToken::Node(_) => unreachable!(),
            },
            t if t.is_trivia() => (),
            _ => break,
        }
    }
    let doc = comments
        .iter()
        .map(|it| it.trim_start_matches('#').trim())
        .collect::<Vec<_>>()
        .join("\n        ");
    return Some(doc).filter(|it| !it.is_empty());
}
