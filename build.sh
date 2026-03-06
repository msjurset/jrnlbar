#!/bin/bash
set -euo pipefail

PRODUCT="JrnlBar"
BUILD_DIR=".build"
APP_BUNDLE="${PRODUCT}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
INSTALL_DIR="/Applications"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_LABEL="com.local.JrnlBar"

echo "Building ${PRODUCT}..."
swift build -c release

echo "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"

cp "${BUILD_DIR}/release/${PRODUCT}" "${MACOS}/${PRODUCT}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"

echo "Code signing..."
codesign --force --sign - "${APP_BUNDLE}"

# Install to /Applications
echo "Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_BUNDLE}"
cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/${APP_BUNDLE}"

# Install launch agent for login startup
echo "Installing launch agent..."
mkdir -p "${LAUNCH_AGENT_DIR}"
EXECUTABLE="${INSTALL_DIR}/${APP_BUNDLE}/Contents/MacOS/${PRODUCT}"
sed "s|__APP_PATH__|${EXECUTABLE}|g" "Resources/${LAUNCH_AGENT_LABEL}.plist" > "${LAUNCH_AGENT_DIR}/${LAUNCH_AGENT_LABEL}.plist"

# Load the agent (unload first if already loaded)
launchctl bootout "gui/$(id -u)/${LAUNCH_AGENT_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENT_DIR}/${LAUNCH_AGENT_LABEL}.plist"

echo "Done. ${PRODUCT} installed to ${INSTALL_DIR} and set to launch at login."
echo "Run now with: open ${INSTALL_DIR}/${APP_BUNDLE}"
