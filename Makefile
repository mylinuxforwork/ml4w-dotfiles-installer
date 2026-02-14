# Variables
BIN_DIR = $(HOME)/.local/bin
LIB_DIR = $(HOME)/.local/share/ml4w-dotfiles-installer

.PHONY: install uninstall test

install:
	@echo "Installing ml4w-dotfiles-installer..."
	mkdir -p $(BIN_DIR)
	mkdir -p $(LIB_DIR)
	
	# Install binary (executable)
	install -m 755 bin/ml4w-dotfiles-installer $(BIN_DIR)/
	
	# Install libraries (read-only)
	install -m 644 lib/*.sh $(LIB_DIR)/
	@echo "Done! Make sure $(BIN_DIR) is in your PATH."

uninstall:
	rm -f $(BIN_DIR)/ml4w-dotfiles-installer
	rm -rf $(LIB_DIR)
	@echo "Removed ml4w-dotfiles-installer."

test:
	bats tests/