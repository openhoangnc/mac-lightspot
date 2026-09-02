.PHONY: build run install uninstall clean icon

build:
	@./build.sh

run:
	@./run.sh

install:
	@./install.sh

uninstall:
	@./uninstall.sh

clean:
	@rm -rf build .build
	@echo "✅ Cleaned"

icon:
	@./scripts/generate_icon.sh
