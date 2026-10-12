# Build:   make build   (Debug, for development)
# Install: make install (Release, copied to ~/Applications, starts at login)
XCODEBUILD := xcodebuild -project DevDock.xcodeproj -scheme DevDock -derivedDataPath build -quiet
DEBUG_APP := build/Build/Products/Debug/DevDock.app
RELEASE_APP := build/Build/Products/Release/DevDock.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: gen build test run install uninstall open-panel clean

gen:
	xcodegen generate --quiet

build: gen
	$(XCODEBUILD) -configuration Debug build

test: gen
	$(XCODEBUILD) -configuration Debug test

run: build
	-pkill -x DevDock
	open $(DEBUG_APP)

# Launch at login points at this copy, so always run the installed app day to day.
install: gen
	$(XCODEBUILD) -configuration Release build
	-pkill -x DevDock
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/DevDock.app
	cp -R $(RELEASE_APP) $(INSTALL_DIR)/DevDock.app
	open $(INSTALL_DIR)/DevDock.app
	@echo "DevDock installed to $(INSTALL_DIR)/DevDock.app"

uninstall:
	-pkill -x DevDock
	rm -rf $(INSTALL_DIR)/DevDock.app
	@echo "Removed the app. Settings and cached usage stay in ~/Library/Application Support/DevDock;"
	@echo "delete that folder and run 'defaults delete local.personal.DevDock' to remove them too."

# Debug: launch with the panel already open (useful for screenshots).
open-panel: build
	-pkill -x DevDock
	open $(DEBUG_APP) --args --open-panel

clean:
	rm -rf build DevDock.xcodeproj
