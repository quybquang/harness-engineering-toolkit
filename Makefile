.PHONY: test lint install clean help

help:
	@echo "Harness Engineering Toolkit — Makefile"
	@echo ""
	@echo "  make test      Run the full test suite"
	@echo "  make lint      Run shellcheck on all shell scripts"
	@echo "  make install   Run the installer"
	@echo "  make clean     Remove temporary artifacts"
	@echo "  make help      Show this help message"

test:
	@sh tests/run-tests.sh

lint:
	@shellcheck bin/harness install.sh uninstall.sh lib/*.sh tests/run-tests.sh tests/unit/*.sh scripts/*.sh 2>/dev/null || echo "shellcheck not installed — skipping"

install:
	@./install.sh

clean:
	@find . -name "*.log" -delete 2>/dev/null || true
	@rm -rf tests/tmp/* tests/output/* 2>/dev/null || true
	@echo "Cleaned temporary artifacts"
