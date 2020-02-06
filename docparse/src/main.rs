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

    println!("| Attribute | Description |");
    println!("| - | - |");
    for e in body.entries() {
        let k = e.key().expect("No key").path().next().unwrap();
        let v = e.value();
        let mshown = if let Some(x) = v.clone().and_then(OrDefault::cast) {
            x.default().and_then(|def| {
                let shown = format!("{}", def);
                if shown != "null" {
                    Some(shown)
                } else {
                    None
                }
            })
        } else if let Some(x) = v.clone().and_then(Apply::cast) {
            let inner = x.lambda().expect("lamdba is not there");
            let after = Apply::cast(inner)
                .expect("Not an inner apply")
                .lambda()
                .expect("No inner lambda");
            let inner2 = Apply::cast(after)
                .expect("Not an inner apply")
                .lambda()
                .expect("No inner lambda");
            if inner2.to_string() == "allowFun" {
                Some(format!("{}", x.value().unwrap()))
            } else {
                None
            }
        } else if let Some(x) = v.clone().and_then(Lambda::cast) {
            Some("lambda".to_string())
        } else {
            None
        };
        let e = e.node().clone();
        let c = find_comment(e).expect("No comment");
        let mut lines = vec![];
        for l in c.lines() {
            lines.push(l);
        }

        let sss;
        if let Some(shown) = mshown {
            lines.push("Default:");
            sss = format!("`{}`", shown);
            lines.push(&sss);
        }
        let descr = lines.join(" ");
        println!("| `{}` | {} |", k, descr);
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
    comments.reverse();
    let doc = comments
        .iter()
        .map(|it| it.trim_start_matches('#').trim())
        .collect::<Vec<_>>()
        .join("\n");
    return Some(doc).filter(|it| !it.is_empty());
}
