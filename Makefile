APP = build/Beam.app

SPARKLE = .build/artifacts/sparkle/Sparkle

.PHONY: build test app run clean install uninstall dmg release appcast sandbox run-sandbox

test:
	swift test

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Beam $(APP)/Contents/MacOS/Beam
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	# Stamp the git commit (shown in About) so it's clear which build is running.
	/usr/libexec/PlistBuddy -c "Add :BeamCommit string $$(git rev-parse --short HEAD)$$(git diff --quiet HEAD || echo -dirty)" $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources
	find -H .build/release -maxdepth 1 -name '*.bundle' -exec cp -R {} $(APP)/Contents/Resources/ \;
	cp Resources/Beam.icns Resources/menubar-icon.svg THIRD_PARTY_NOTICES.txt $(APP)/Contents/Resources/
	# Sparkle: scripts/release.sh re-signs it with Developer ID, dev builds keep Sparkle's own signature.
	mkdir -p $(APP)/Contents/Frameworks
	cp -R $(SPARKLE)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP)/Contents/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks $(APP)/Contents/MacOS/Beam
	# Pin the designated requirement to the bundle ID so the Accessibility grant
	# survives rebuilds (ad-hoc signing otherwise ties it to the cdhash).
	codesign --force --sign - -r='designated => identifier "com.beam.launcher"' $(APP)

run: app
	open $(APP)

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

dmg: app
	rm -rf build/dmg build/Beam.dmg
	mkdir -p build/dmg
	cp -R $(APP) build/dmg/Beam.app
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname Beam -srcfolder build/dmg -ov -format UDZO build/Beam.dmg
	rm -rf build/dmg

# Developer ID signed, notarized, stapled app and dmg (see docs/testing.md).
release:
	./scripts/release.sh

# Sparkle feed for the release dmg (needs the EdDSA private key in the login Keychain, see docs/testing.md).
# Upload build/appcast/appcast.xml and the dmg yourself. DOWNLOAD_PREFIX is where the dmg will be served.
DOWNLOAD_PREFIX ?= https://downloads.beamlauncher.app/
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
appcast:
	@test -f build/Beam.dmg || { echo "Run make release first."; exit 1; }
	@test ! Resources/Info.plist -nt build/Beam.dmg || { echo "build/Beam.dmg is older than Resources/Info.plist; run make release again."; exit 1; }
	rm -rf build/appcast && mkdir -p build/appcast
	cp build/Beam.dmg build/appcast/Beam-$(VERSION).dmg
	$(SPARKLE)/bin/generate_appcast --download-url-prefix "$(DOWNLOAD_PREFIX)" build/appcast
	@echo "Wrote build/appcast/appcast.xml; upload Beam-$(VERSION).dmg to $(DOWNLOAD_PREFIX)"

# Opt-in App Sandbox build (separate bundle + bundle id so TCC grants don't clash with the normal build).
SANDBOX_APP = build/Beam-Sandbox.app

sandbox: build
	rm -rf $(SANDBOX_APP)
	mkdir -p $(SANDBOX_APP)/Contents/MacOS $(SANDBOX_APP)/Contents/Resources
	cp .build/release/Beam $(SANDBOX_APP)/Contents/MacOS/Beam
	cp Resources/Info.plist $(SANDBOX_APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.beam.launcher.sandbox" $(SANDBOX_APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.utilities" $(SANDBOX_APP)/Contents/Info.plist
	find -H .build/release -maxdepth 1 -name '*.bundle' -exec cp -R {} $(SANDBOX_APP)/Contents/Resources/ \;
	# Linked but never started in this variant (no updater), so it only needs to load.
	mkdir -p $(SANDBOX_APP)/Contents/Frameworks
	cp -R $(SPARKLE)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(SANDBOX_APP)/Contents/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks $(SANDBOX_APP)/Contents/MacOS/Beam
	cp Resources/Beam.icns Resources/menubar-icon.svg THIRD_PARTY_NOTICES.txt $(SANDBOX_APP)/Contents/Resources/
	codesign --force --sign - -r='designated => identifier "com.beam.launcher.sandbox"' --entitlements Resources/Beam-Sandbox.entitlements $(SANDBOX_APP)
	codesign -d --entitlements - $(SANDBOX_APP)

run-sandbox: sandbox
	open $(SANDBOX_APP)

clean:
	rm -rf .build build
