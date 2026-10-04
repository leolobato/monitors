APP_NAME     := Monitors
PROJECT      := $(APP_NAME).xcodeproj
SCHEME       := $(APP_NAME)
BUILD_DIR    := build
RELEASE_APP  := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR  := /Applications
SIGN_IDENTITY ?= Developer ID Application

.PHONY: all project build install uninstall clean

all: build

project:
	xcodegen generate

# Release build signed with Developer ID (team comes from Configuration/LocalSigning.xcconfig).
build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'platform=macOS' -derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" \
		build
	codesign --verify --strict --verbose=2 $(RELEASE_APP)

# Quitting first lets the running app re-enable any displays it turned off.
install: build
	-osascript -e 'tell application id "$$(defaults read "$(CURDIR)/$(RELEASE_APP)/Contents/Info" CFBundleIdentifier)" to quit' 2>/dev/null
	@while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.2; done
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	ditto "$(RELEASE_APP)" "$(INSTALL_DIR)/$(APP_NAME).app"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	-osascript -e 'tell application "$(APP_NAME)" to quit' 2>/dev/null
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR)
