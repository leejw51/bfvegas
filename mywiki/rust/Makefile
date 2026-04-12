.PHONY: all build copy clean

LIB_NAME := mywiki_ai
DEST     := ../libmywiki_ai.so

all: build copy

build:
	cargo build --release

copy:
	@if [ "$$(uname)" = "Darwin" ]; then \
		cp target/release/lib$(LIB_NAME).dylib $(DEST); \
	elif [ "$$(uname)" = "Linux" ]; then \
		cp target/release/lib$(LIB_NAME).so $(DEST); \
	else \
		cp target/release/$(LIB_NAME).dll ../$(LIB_NAME).dll; \
	fi
	@ls -lh $(DEST) 2>/dev/null || true

clean:
	cargo clean
	rm -f $(DEST)
