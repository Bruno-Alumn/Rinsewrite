APP := Rinsewrite
NAME := Rinsewrite
BUILD := .build/release
BUNDLE := dist/$(NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ZIP := dist/$(NAME)-$(VERSION).zip
DMG := dist/$(NAME)-$(VERSION).dmg
ENGINE_FILES := engine/main.py engine/engine.py engine/prompts.py engine/requirements.txt engine/words_en.tsv engine/words_es.tsv engine/words_fr.tsv
SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)
VENV := $(HOME)/Library/Application Support/Rinsewrite/venv/bin/python
# How builds are signed (see docs/RELEASING.md): the maintainer's Developer
# ID when this Mac has it, so the Accessibility grant survives rebuilds;
# ad-hoc otherwise (CI, contributors' Macs), where each rebuild needs a new
# grant. Override with CODESIGN_ID="<identity>".
DEVELOPER_ID := Developer ID Application: Bruno Cassina (22R95V8NA5)
CODESIGN_ID ?= $(if $(shell security find-identity -v -p codesigning 2>/dev/null | grep -F '"$(DEVELOPER_ID)"'),$(DEVELOPER_ID),-)

.PHONY: all build bundle engine install run test eval train icon screenshots zip dmg release clean

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources/engine
	cp $(BUILD)/$(APP) $(BUNDLE)/Contents/MacOS/
	# Local symbols are only for debugging; dropping them halves the binary.
	strip -x $(BUNDLE)/Contents/MacOS/$(APP)
	# SwiftPM records the deployment target (13.0) as the SDK version, and
	# macOS gives an app the current design (Liquid Glass window controls
	# and title bars) only when it was built against the macOS 26 SDK or
	# later. Record the SDK it was really built with.
	xcrun vtool -set-build-version macos 13.0 $(SDK_VERSION) -replace \
		-output $(BUNDLE)/Contents/MacOS/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	cp $(ENGINE_FILES) $(BUNDLE)/Contents/Resources/engine/
	@if [ -f engine/adapter/adapters.safetensors ]; then cp -R engine/adapter $(BUNDLE)/Contents/Resources/engine/; fi
	cp CHANGELOG.md $(BUNDLE)/Contents/Resources/
	scripts/sign_app.sh $(BUNDLE) "$(CODESIGN_ID)"
	@du -sh $(BUNDLE)
	@if [ "$(CODESIGN_ID)" = "-" ]; then \
		echo "note: ad-hoc signed; every rebuild needs the Accessibility grant again."; \
	fi

# One-time setup: Python with MLX, and the model (about 1 GB).
engine:
	scripts/setup_engine.sh

# Build, then replace the copy in /Applications and open it.
install: bundle
	-pkill -x $(APP)
	rm -rf /Applications/$(NAME).app
	ditto $(BUNDLE) /Applications/$(NAME).app
	open /Applications/$(NAME).app

run: bundle
	open $(BUNDLE)

# Unit tests, then a check that the launched app settles down.
test: bundle
	swift test
	scripts/launch_check.sh $(BUNDLE)

# Quality checks against the real model (needs `make engine`): typos,
# language, meaning drift and the held-out fine-tuning set.
eval:
	"$(VENV)" engine/tests/test_typos.py 0.5
	"$(VENV)" engine/tests/test_language.py
	"$(VENV)" engine/tests/test_drift.py

# Fine-tune the LoRA adapter (about 75 minutes on an M1 Max); see finetune/.
train:
	"$(VENV)" finetune/build_dataset.py
	"$(VENV)" finetune/train.py --epochs 2

# Rebuild Resources/AppIcon.icns and docs/logo.png.
icon:
	swift scripts/make_icon.swift Resources/AppIcon.icns docs/logo.png

# Render the settings window for the README, light and dark.
screenshots: bundle
	$(BUNDLE)/Contents/MacOS/$(APP) --snapshot docs/screenshots

# A zip of the app that's ready to send or attach (keeps the signature).
zip: bundle
	rm -f $(ZIP)
	ditto -c -k --keepParent --sequesterRsrc $(BUNDLE) $(ZIP)
	@echo "$(ZIP)"

# The disk image people download: the app next to an Applications link.
dmg: bundle
	@if [ "$(CODESIGN_ID)" = "$(DEVELOPER_ID)" ]; then scripts/notarize.sh $(BUNDLE); fi
	scripts/make_dmg.sh $(BUNDLE) $(DMG) "$(CODESIGN_ID)"
	@if [ "$(CODESIGN_ID)" = "$(DEVELOPER_ID)" ]; then scripts/notarize.sh $(DMG); fi

# Publish the disk image as GitHub release v<version>.
release: dmg
	@if [ "$(CODESIGN_ID)" = "-" ]; then echo "refusing to release an ad-hoc build; the Developer ID isn't in this Mac's keychain (docs/RELEASING.md)"; exit 1; fi
	gh release create v$(VERSION) $(DMG) --title "Rinsewrite $(VERSION)" --notes-file dist/notes.md

clean:
	rm -rf .build dist/$(NAME).app dist/$(NAME)-*.zip dist/$(NAME)-*.dmg
