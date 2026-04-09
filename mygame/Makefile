.PHONY: run cards cards-grok compose assets-grok cheatsheet-bg assets clean package help

# Default target
help:
	@echo "Texas Hold'em Poker - Makefile"
	@echo "=============================="
	@echo ""
	@echo "  make run          - Run the poker game"
	@echo "  make cards        - Generate cards (Grok art + PIL text compose)"
	@echo "  make cards-grok   - Step 1: Generate raw card art via Grok API"
	@echo "  make compose      - Step 2: Compose final cards with PIL"
	@echo "  make assets-grok  - Generate table/title backgrounds via Grok API"
	@echo "  make cheatsheet-bg - Generate cheatsheet background via Grok API"
	@echo "  make assets       - Generate ALL assets (cards + backgrounds)"
	@echo "  make package      - Package game as .love file"
	@echo "  make clean        - Remove generated assets"
	@echo ""

# Run the game
run:
	/Applications/love.app/Contents/MacOS/love poker/

# Generate cards: Grok art + PIL text composition
cards: cards-grok compose

# Step 1: Generate raw art assets (backgrounds, symbols, portraits) via Grok
cards-grok:
	python3 generate_card_assets.py

# Step 2: Compose final 52 cards + back using PIL
compose:
	python3 compose_cards.py

# Generate table/title backgrounds via Grok API
assets-grok:
	python3 generate_poker_assets.py

# Generate cheatsheet background via Grok API (uses generate_image.py helpers)
cheatsheet-bg:
	python3 generate_cheatsheet_assets.py

# Generate ALL assets
assets: cards assets-grok cheatsheet-bg

# Package as .love file
package:
	cd poker && zip -9 -r ../texasholdem.love . -x "*.DS_Store"
	@echo "Created texasholdem.love"

# Clean generated assets
clean:
	rm -rf poker/assets/cards/*.png
	rm -rf poker/assets/raw/
	rm -f poker/assets/table_bg.png
	rm -f poker/assets/title_bg.png
	rm -f poker/assets/cheatsheet_bg.png
	rm -f poker/assets/chip_*.png
	rm -f texasholdem.love
