PRODUCT = JrnlBar
BUILD_DIR = .build
APP_BUNDLE = $(PRODUCT).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
INSTALL_DIR = /Applications
LAUNCH_AGENT_DIR = $(HOME)/Library/LaunchAgents
LAUNCH_AGENT_LABEL = com.local.JrnlBar
DMG_NAME = $(PRODUCT).dmg

.PHONY: build app install dmg uninstall clean run test

build:
	@echo "Building $(PRODUCT)..."
	@swift build -c release

app: build
	@echo "Assembling $(APP_BUNDLE)..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(MACOS)"
	@cp "$(BUILD_DIR)/release/$(PRODUCT)" "$(MACOS)/$(PRODUCT)"
	@cp "Resources/Info.plist" "$(CONTENTS)/Info.plist"
	@echo "Code signing..."
	@codesign --force --sign - "$(APP_BUNDLE)"

install: app
	@echo "Installing to $(INSTALL_DIR)..."
	@rm -rf "$(INSTALL_DIR)/$(APP_BUNDLE)"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_BUNDLE)"
	@echo "Installing launch agent..."
	@mkdir -p "$(LAUNCH_AGENT_DIR)"
	@sed "s|__APP_PATH__|$(INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/$(PRODUCT)|g" \
		"Resources/$(LAUNCH_AGENT_LABEL).plist" > "$(LAUNCH_AGENT_DIR)/$(LAUNCH_AGENT_LABEL).plist"
	@launchctl bootout "gui/$$(id -u)/$(LAUNCH_AGENT_LABEL)" 2>/dev/null || true
	@launchctl bootstrap "gui/$$(id -u)" "$(LAUNCH_AGENT_DIR)/$(LAUNCH_AGENT_LABEL).plist"
	@echo "Done. $(PRODUCT) installed and set to launch at login."

dmg: app
	@echo "Creating $(DMG_NAME)..."
	@rm -rf dmg_staging "$(DMG_NAME)"
	@mkdir -p dmg_staging
	@cp -R "$(APP_BUNDLE)" dmg_staging/
	@ln -s /Applications dmg_staging/Applications
	@hdiutil create -volname "$(PRODUCT)" -srcfolder dmg_staging \
		-ov -format UDZO "$(DMG_NAME)" >/dev/null
	@rm -rf dmg_staging
	@echo "Created $(DMG_NAME)"

uninstall:
	@echo "Uninstalling $(PRODUCT)..."
	@launchctl bootout "gui/$$(id -u)/$(LAUNCH_AGENT_LABEL)" 2>/dev/null || true
	@rm -f "$(LAUNCH_AGENT_DIR)/$(LAUNCH_AGENT_LABEL).plist"
	@rm -rf "$(INSTALL_DIR)/$(APP_BUNDLE)"
	@echo "Done."

clean:
	@echo "Cleaning..."
	@rm -rf "$(BUILD_DIR)" "$(APP_BUNDLE)" "$(DMG_NAME)" dmg_staging
	@echo "Done."

test:
	@echo "Running tests..."
	@swift run JrnlBarTests

run: app
	@pkill -9 -f "$(PRODUCT)" 2>/dev/null || true
	@sleep 0.5
	@open "$(APP_BUNDLE)"
