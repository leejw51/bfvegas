.PHONY: menu help build test run package fuse assets bot bg clean

# Default target shows the menu
.DEFAULT_GOAL := menu

LIB       := libmywiki_ai.so
RUST_DIR  := rust
TEST_BIN  := tests/test_ffi
LOVE_NAME := mywiki.love
LOVE_BIN  := love
DIST_DIR  := dist
PKG_NAME  := mywiki-package.tar.gz
LOVE_APP  := /Applications/love.app
APP_NAME  := MyWiki.app
APP_ZIP   := MyWiki-macos.zip

menu help:
	@echo ""
	@echo "  MyWiki  -  visual AI knowledge mindmap"
	@echo "  ============================================"
	@echo ""
	@echo "  make build    - build Rust cdylib (libmywiki_ai)"
	@echo "  make test     - cargo test + headless FFI smoke test"
	@echo "  make run      - build then launch LOVE2D (love .)"
	@echo "  make package  - bundle $(LOVE_NAME) + native lib into $(PKG_NAME)"
	@echo "  make fuse     - build a fused macOS $(APP_NAME) (love + .love + dylib)"
	@echo "  make assets   - regenerate UI/asset images via Grok (Python)"
	@echo "  make clean    - remove build artifacts"
	@echo ""
	@echo "  Requires: rustc/cargo, cc, love"
	@echo "  AI features need GROK_API_KEY in env"
	@echo ""

build:
	@$(MAKE) -C $(RUST_DIR) all
	@ls -lh $(LIB)

test: build $(TEST_BIN)
	@echo ""
	@echo "==> cargo test"
	cd $(RUST_DIR) && cargo test --release
	@echo ""
	@echo "==> headless FFI smoke test"
	./$(TEST_BIN)
	@echo ""
	@echo "All tests passed."

$(TEST_BIN): tests/test_ffi.c
	cc tests/test_ffi.c -o $(TEST_BIN)

run: build
	@if [ -z "$$GROK_API_KEY" ]; then \
		echo "warning: GROK_API_KEY not set - AI button will be disabled"; \
	fi
	$(LOVE_BIN) .

package: build
	@rm -rf $(DIST_DIR) $(LOVE_NAME) $(PKG_NAME)
	@mkdir -p $(DIST_DIR)
	@echo "==> packing $(LOVE_NAME)"
	zip -9 -r $(LOVE_NAME) \
		main.lua conf.lua \
		ai.lua aiui.lua bot.lua editor.lua easing.lua export.lua \
		graph.lua json.lua mindmap.lua nativelib.lua render.lua ui.lua settings.lua \
		assets data \
		-x 'assets/raw/*' '*.DS_Store'
	@echo "==> staging $(DIST_DIR)/"
	@cp $(LOVE_NAME) $(DIST_DIR)/
	@cp $(LIB) $(DIST_DIR)/
	@printf '#!/bin/sh\ncd "$$(dirname "$$0")" && exec love ./$(LOVE_NAME) "$$@"\n' > $(DIST_DIR)/run.sh
	@chmod +x $(DIST_DIR)/run.sh
	@tar -czf $(PKG_NAME) $(DIST_DIR)
	@ls -lh $(LOVE_NAME) $(PKG_NAME)
	@echo ""
	@echo "Run with:  ./$(DIST_DIR)/run.sh"
	@echo "Distribute: $(PKG_NAME)  (LuaJIT FFI requires $(LIB) next to the .love file)"

fuse: package
	@if [ ! -d "$(LOVE_APP)" ]; then \
		echo "error: $(LOVE_APP) not found - install LÖVE from https://love2d.org"; exit 1; \
	fi
	@rm -rf "$(DIST_DIR)/$(APP_NAME)" "$(APP_ZIP)"
	@echo "==> cloning $(LOVE_APP) -> $(DIST_DIR)/$(APP_NAME)"
	@cp -R "$(LOVE_APP)" "$(DIST_DIR)/$(APP_NAME)"
	@echo "==> fusing $(LOVE_NAME) into love binary"
	@cat "$(DIST_DIR)/$(APP_NAME)/Contents/MacOS/love" $(LOVE_NAME) \
		> "$(DIST_DIR)/$(APP_NAME)/Contents/MacOS/love.fused"
	@mv "$(DIST_DIR)/$(APP_NAME)/Contents/MacOS/love.fused" \
		"$(DIST_DIR)/$(APP_NAME)/Contents/MacOS/love"
	@chmod +x "$(DIST_DIR)/$(APP_NAME)/Contents/MacOS/love"
	@echo "==> installing $(LIB) into Contents/Frameworks"
	@cp $(LIB) "$(DIST_DIR)/$(APP_NAME)/Contents/Frameworks/libmywiki_ai.dylib"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleName MyWiki" \
		"$(DIST_DIR)/$(APP_NAME)/Contents/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.mywiki.app" \
		"$(DIST_DIR)/$(APP_NAME)/Contents/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" \
		"$(DIST_DIR)/$(APP_NAME)/Contents/Info.plist" 2>/dev/null || true
	@codesign --force --deep --sign - "$(DIST_DIR)/$(APP_NAME)" 2>/dev/null || true
	@find "$(DIST_DIR)/$(APP_NAME)" -exec xattr -c {} \; 2>/dev/null || true
	@( cd $(DIST_DIR) && zip -9 -qry ../$(APP_ZIP) $(APP_NAME) )
	@ls -lh "$(DIST_DIR)/$(APP_NAME)/Contents/MacOS/love" $(APP_ZIP)
	@echo ""
	@echo "Run with:  open $(DIST_DIR)/$(APP_NAME)"
	@echo "Distribute: $(APP_ZIP)"

assets:
	python scripts/generate_assets.py all

bot:
	python scripts/generate_assets.py bot

bg:
	python scripts/generate_assets.py bg

clean:
	$(MAKE) -C $(RUST_DIR) clean
	rm -rf $(TEST_BIN) $(LOVE_NAME) $(LIB) $(DIST_DIR) $(PKG_NAME) $(APP_ZIP)
