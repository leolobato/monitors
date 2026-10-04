APP_NAME     := Monitors
PROJECT      := $(APP_NAME).xcodeproj
SCHEME       := $(APP_NAME)
BUILD_DIR    := build
RELEASE_APP  := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR  := /Applications
SIGN_IDENTITY ?= Developer ID Application

.PHONY: all project build install quit uninstall clean

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
	@$(MAKE) --no-print-directory quit
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	ditto "$(RELEASE_APP)" "$(INSTALL_DIR)/$(APP_NAME).app"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

# The app treats SIGTERM as a normal quit, so it re-enables displays before exiting.
quit:
	@pkill -TERM -x $(APP_NAME) || true
	@for i in $$(seq 50); do pgrep -x $(APP_NAME) >/dev/null || exit 0; sleep 0.2; done; \
		echo "$(APP_NAME) did not quit" >&2; exit 1

uninstall: quit
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR)
