use std::path::PathBuf;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let lang_name = args.get(1).map(|s| s.as_str()).unwrap_or("c_sharp");
    let src = args.get(2).map(|s| s.as_str()).unwrap_or(
        "public class Order {\n    public int Id { get; set; }\n    public decimal GetTotal() {\n        decimal total = 0;\n        foreach (var item in Items) {\n            total += item.Price * item.Quantity;\n        }\n        return total;\n    }\n}"
    );
    
    let home = std::env::var("HOME").unwrap();
    let search_dirs = [
        "site/pack/core/opt/nvim-treesitter/parser",
        "lazy/nvim-treesitter/parser",
    ];
    
    let mut parser_path = None;
    for subpath in &search_dirs {
        let p = PathBuf::from(&home).join(".local/share/nvim").join(subpath)
            .join(format!("{}.so", lang_name));
        if p.exists() {
            parser_path = Some(p);
            break;
        }
    }
    let parser_path = parser_path.expect("parser not found");
    
    let lib = unsafe { libloading::Library::new(&parser_path).unwrap() };
    let symbol = format!("tree_sitter_{}", lang_name);
    let lang = unsafe {
        let func: libloading::Symbol<unsafe extern "C" fn() -> tree_sitter::Language> =
            lib.get(symbol.as_bytes()).unwrap();
        func()
    };
    std::mem::forget(lib);
    
    let mut parser = tree_sitter::Parser::new();
    parser.set_language(&lang).unwrap();
    let tree = parser.parse(src, None).unwrap();
    
    fn dump(cursor: &mut tree_sitter::TreeCursor, src: &str, indent: usize) {
        let node = cursor.node();
        let kind = node.kind();
        let text = if node.child_count() == 0 {
            format!(" = {:?}", &src[node.start_byte()..node.end_byte()])
        } else {
            String::new()
        };
        println!("{:>3}:{:<3} {}{}{}", 
            node.start_position().row + 1,
            node.start_position().column,
            "  ".repeat(indent), kind, text);
        
        if cursor.goto_first_child() {
            loop {
                dump(cursor, src, indent + 1);
                if !cursor.goto_next_sibling() { break; }
            }
            cursor.goto_parent();
        }
    }
    
    let mut cursor = tree.walk();
    dump(&mut cursor, src, 0);
}
