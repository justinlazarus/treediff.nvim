fn main() {
    let home = std::env::var("HOME").unwrap();
    let parser_path = std::path::PathBuf::from(&home)
        .join(".local/share/nvim/site/pack/core/opt/nvim-treesitter/parser/lua.so");

    println!("Parser: {:?} exists: {}", parser_path, parser_path.exists());

    let lib = unsafe { libloading::Library::new(&parser_path).unwrap() };
    let lang = unsafe {
        let func: libloading::Symbol<unsafe extern "C" fn() -> tree_sitter::Language> =
            lib.get(b"tree_sitter_lua").unwrap();
        func()
    };
    std::mem::forget(lib);

    let mut parser = tree_sitter::Parser::new();
    parser.set_language(&lang).unwrap();
    let tree = parser.parse("function hello()\nend\n", None).unwrap();
    println!("Parsed: {}", tree.root_node().to_sexp());
}
