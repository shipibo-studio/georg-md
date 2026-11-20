APP      := GeorgMD
PRODUCT  := Georg md
CONFIG   := Release
DERIVED  := build/DerivedData
APP_PATH := $(DERIVED)/Build/Products/$(CONFIG)/$(PRODUCT).app
DEVTOOL  := build/DerivedData/Build/Products/Debug/GeorgDevTool.app/Contents/MacOS/GeorgDevTool
# Read from project.yml so the number lives in exactly one place.
VERSION  := $(shell awk -F'"' '/^ *MARKETING_VERSION:/ {print $$2; exit}' project.yml)
# The georg-ds release the app icon comes from. Change it, then `make icon`.
GEORG_DS      := 0.13.0
ICON_SRC      := ../georg-ds/src/brand/md-icon-macos-1024.png
ICON_SHA256   := 2b5c43fdea0f60a0946e90fad87c6ff850c600a726000f433d8f4d717bb02c09
ICON_SET      := App/Assets.xcassets/AppIcon.appiconset

# Everyday builds are ad-hoc signed, so anyone (and CI) can build without a certificate.
# `make release` signs with the family's Developer ID and notarizes (scripts/release.sh).
SIGNING := CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

.PHONY: all project build test run install icon release clean

all: build

## Generate the .xcodeproj from project.yml
project:
	xcodegen generate --quiet

## Build the app (ad-hoc signed)
build: project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -quiet $(SIGNING) build
	@echo "→ $(APP_PATH)"

## Run the test suite (renderer, Write mode styler, edit helpers, limits, update check)
test: project
	xcodebuild -project $(APP).xcodeproj -scheme GeorgDevTool -configuration Debug \
		-derivedDataPath $(DERIVED) -quiet $(SIGNING) build
	MDQ_IN=samples/test.md MDQ_OUT=/tmp/georg-md-test MDQ_TASK=test "$(DEVTOOL)"

## Build and open the app
run: build
	open "$(APP_PATH)"

## Install into /Applications
install: build
	rm -rf "/Applications/$(PRODUCT).app"
	cp -R "$(APP_PATH)" /Applications/
	@echo "Installed in /Applications/$(PRODUCT).app"

## Regenerate the app icon from georg-ds (checks the source's SHA-256 first)
icon:
	@echo "$(ICON_SHA256)  $(ICON_SRC)" | shasum -a 256 -c -
	@for s in 16 32 128 256 512; do \
		sips -z $$s $$s "$(ICON_SRC)" --out "$(ICON_SET)/icon_$${s}x$${s}.png" >/dev/null; \
		[ $$s = 512 ] || sips -z $$((s*2)) $$((s*2)) "$(ICON_SRC)" --out "$(ICON_SET)/icon_$${s}x$${s}@2x.png" >/dev/null; \
	done
	cp "$(ICON_SRC)" "$(ICON_SET)/icon_512x512@2x.png"
	@echo "→ $(ICON_SET) from georg-ds $(GEORG_DS)"

## Signed with Developer ID, notarized, stapled .dmg in dist/ (does not publish)
release:
	scripts/release.sh $(VERSION)

clean:
	rm -rf build $(APP).xcodeproj
