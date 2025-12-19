set quiet

scheme := "Trufflehound"
build_dir := "build"

# List available commands
default:
    @just --list

# Build debug configuration
build:
    xcodebuild -scheme {{scheme}} -configuration Debug build

# Build release configuration
release:
    xcodebuild -scheme {{scheme}} \
        -configuration Release \
        -derivedDataPath {{build_dir}} \
        -archivePath {{build_dir}}/{{scheme}}.xcarchive \
        archive \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

# Clean build artifacts
clean:
    xcodebuild -scheme {{scheme}} clean
    rm -rf {{build_dir}}

# Open project in Xcode
open:
    open {{scheme}}.xcodeproj

# Run the app (debug build)
run: build
    open {{build_dir}}/Debug/{{scheme}}.app || open ~/Library/Developer/Xcode/DerivedData/{{scheme}}-*/Build/Products/Debug/{{scheme}}.app

# Create DMG from release build
dmg: release
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{build_dir}}
    mkdir -p export
    cp -R {{scheme}}.xcarchive/Products/Applications/{{scheme}}.app export/
    cd export
    mkdir -p dmg_contents
    cp -R {{scheme}}.app dmg_contents/
    ln -s /Applications dmg_contents/Applications
    hdiutil create -volname "{{scheme}}" \
        -srcfolder dmg_contents \
        -ov -format UDZO \
        {{scheme}}.dmg
    rm -rf dmg_contents
    echo "Created: {{build_dir}}/export/{{scheme}}.dmg"

# Create ZIP from release build
zip: release
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{build_dir}}
    mkdir -p export
    cp -R {{scheme}}.xcarchive/Products/Applications/{{scheme}}.app export/
    cd export
    ditto -c -k --keepParent {{scheme}}.app {{scheme}}.zip
    echo "Created: {{build_dir}}/export/{{scheme}}.zip"

# Build all release artifacts (DMG and ZIP)
dist: dmg zip
    @echo "Release artifacts created in {{build_dir}}/export/"
