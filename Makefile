.PHONY: build test clean

# Build the native library for the current platform
build:
	cargo build --release
	@if [ "$$(uname)" = "Darwin" ]; then \
		cp target/release/libtreediff.dylib lib/treediff_native.so; \
	else \
		cp target/release/libtreediff.so lib/treediff_native_linux.so; \
	fi
	@echo "Built native library"

# Run all tests (requires Neovim with tree-sitter parsers installed)
test:
	nvim --headless -u tests/minimal_init.lua -l tests/test_diffview.lua
	nvim --headless -u tests/minimal_init.lua -l tests/test_difft_parity.lua

clean:
	cargo clean
