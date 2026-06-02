APP_NAME := JrnlBar
BUNDLE := $(APP_NAME).app
BUILD_DIR := .build
INSTALL_DIR := /Applications
LAUNCH_AGENT_DIR := $(HOME)/Library/LaunchAgents
LAUNCH_AGENT_LABEL := com.local.JrnlBar
SIGN_IDENTITY := JrnlBar Dev
DMG_NAME := $(APP_NAME).dmg

.PHONY: build rebuild bundle icon deploy dmg uninstall clean run test update-vim cert

build:
	@echo "Building $(APP_NAME)..."
	@swift build -c release

# Force a full from-scratch build by wiping the SwiftPM cache
# first. Use when something looks stale.
rebuild: clean build

update-vim:
	@echo "Updating swift-vim-engine to the latest tagged release..."
	@swift package update swift-vim-engine
	@echo ""
	@echo "Now: review the diff in Package.resolved, build + smoke test, then commit."
	@echo "  git diff Package.resolved"
	@echo "  make run    # smoke test"
	@echo "  git add Package.resolved && git commit -m 'Bump VimEngine to <version>'"

icon:
	@test -f AppIcon.icns || swift scripts/generate-icon.swift

bundle: build icon
	@echo "Assembling $(BUNDLE)..."
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@cp "$(BUILD_DIR)/release/$(APP_NAME)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	@cp "Resources/Info.plist" "$(BUNDLE)/Contents/Info.plist"
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(SIGN_IDENTITY)"; then \
		codesign --force --sign "$(SIGN_IDENTITY)" $(BUNDLE); \
		echo "Signed with $(SIGN_IDENTITY)"; \
	else \
		codesign --force --sign - "$(BUNDLE)"; \
		echo "Ad-hoc signed (no '$(SIGN_IDENTITY)' cert found — run 'make cert' for a stable identity)"; \
	fi

cert:
	@echo "Creating self-signed code-signing certificate '$(SIGN_IDENTITY)'..."
	@printf '[req]\ndistinguished_name=dn\nx509_extensions=cs\nprompt=no\n[dn]\nCN=$(SIGN_IDENTITY)\n[cs]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n' > /tmp/jrnlbar-cert.conf
	@openssl req -x509 -newkey rsa:2048 -noenc -keyout /tmp/jrnlbar-dev.key -out /tmp/jrnlbar-dev.crt -days 3650 -config /tmp/jrnlbar-cert.conf 2>/dev/null
	@openssl pkcs12 -export -legacy -passout pass:jrnlbardev -inkey /tmp/jrnlbar-dev.key -in /tmp/jrnlbar-dev.crt -out /tmp/jrnlbar-dev.p12 2>/dev/null
	@security import /tmp/jrnlbar-dev.p12 -k ~/Library/Keychains/login.keychain-db -P "jrnlbardev" -T /usr/bin/codesign
	@rm -f /tmp/jrnlbar-dev.key /tmp/jrnlbar-dev.crt /tmp/jrnlbar-dev.p12 /tmp/jrnlbar-cert.conf
	@echo "Done. Grant trust: open Keychain Access > '$(SIGN_IDENTITY)' cert > Trust > Always Trust"
	@echo "Then run 'make deploy' — Accessibility permission will persist across rebuilds."

deploy: bundle
	@echo "Stopping $(APP_NAME)..."
	@launchctl bootout "gui/$$(id -u)/$(LAUNCH_AGENT_LABEL)" 2>/dev/null || true
	@pkill -9 -x "$(APP_NAME)" 2>/dev/null || true
	@pkill -9 -f "$(INSTALL_DIR)/$(BUNDLE)" 2>/dev/null || true
	@sleep 1
	@echo "Installing to $(INSTALL_DIR)..."
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE)"
	@ditto "$(BUNDLE)" "$(INSTALL_DIR)/$(BUNDLE)"
	@xattr -dr com.apple.quarantine $(INSTALL_DIR)/$(BUNDLE) 2>/dev/null || true
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(SIGN_IDENTITY)"; then \
		echo "Installed copy retains '$(SIGN_IDENTITY)' signature from bundle step"; \
	else \
		codesign --force --deep --sign - $(INSTALL_DIR)/$(BUNDLE); \
		echo "Ad-hoc signed (no '$(SIGN_IDENTITY)' cert found)"; \
	fi
	@echo "Registering launch agent..."
	@mkdir -p "$(LAUNCH_AGENT_DIR)"
	@sed "s|__APP_PATH__|$(INSTALL_DIR)/$(BUNDLE)/Contents/MacOS/$(APP_NAME)|g" \
		"Resources/$(LAUNCH_AGENT_LABEL).plist" > "$(LAUNCH_AGENT_DIR)/$(LAUNCH_AGENT_LABEL).plist"
	@launchctl bootstrap "gui/$$(id -u)" "$(LAUNCH_AGENT_DIR)/$(LAUNCH_AGENT_LABEL).plist"
	@osascript -e 'use framework "AppKit"' \
		-e 'set iconImage to current application'\''s NSImage'\''s alloc()'\''s initWithContentsOfFile:"$(INSTALL_DIR)/$(BUNDLE)/Contents/Resources/AppIcon.icns"' \
		-e 'current application'\''s NSWorkspace'\''s sharedWorkspace()'\''s setIcon:iconImage forFile:"$(INSTALL_DIR)/$(BUNDLE)" options:0' >/dev/null 2>&1 || true
	@killall Dock 2>/dev/null || true
	@/System/Library/CoreServices/pbs -update 2>/dev/null || true
	@echo "Starting $(APP_NAME)..."
	@sleep 2
	@launchctl kickstart -k "gui/$$(id -u)/$(LAUNCH_AGENT_LABEL)" 2>/dev/null || open "$(INSTALL_DIR)/$(BUNDLE)" || true
	@echo "Deployed to $(INSTALL_DIR)/$(BUNDLE)"

dmg: bundle
	@echo "Creating $(DMG_NAME)..."
	@rm -rf dmg_staging "$(DMG_NAME)"
	@mkdir -p dmg_staging
	@cp -R "$(BUNDLE)" dmg_staging/
	@ln -s /Applications dmg_staging/Applications
	@hdiutil create -volname "$(APP_NAME)" -srcfolder dmg_staging \
		-ov -format UDZO "$(DMG_NAME)" >/dev/null
	@rm -rf dmg_staging
	@echo "Created $(DMG_NAME)"

uninstall:
	@echo "Uninstalling $(APP_NAME)..."
	@launchctl bootout "gui/$$(id -u)/$(LAUNCH_AGENT_LABEL)" 2>/dev/null || true
	@rm -f "$(LAUNCH_AGENT_DIR)/$(LAUNCH_AGENT_LABEL).plist"
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE)"
	@echo "Done."

clean:
	@echo "Cleaning..."
	@rm -rf "$(BUILD_DIR)" "$(BUNDLE)" "$(DMG_NAME)" dmg_staging
	@echo "Done."

test:
	@echo "Running tests..."
	@swift run JrnlBarTests

run: bundle
	@pkill -9 -f "$(APP_NAME)" 2>/dev/null || true
	@sleep 0.5
	@open "$(BUNDLE)"
