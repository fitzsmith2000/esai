#!/bin/zsh
set -euo pipefail
project_root="${0:A:h}"
app_bundle="$project_root/build/esai 定时关闭.app"
sparkle_runtime=$(zsh "$project_root/Scripts/fetch-sparkle.sh")
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
swiftc -swift-version 5 -target arm64-apple-macos13.0 -O -framework AppKit -framework SwiftUI -framework ServiceManagement -F "$sparkle_runtime" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks "$project_root/Sources/Updates.swift" "$project_root/Sources/Schedule.swift" "$project_root/Sources/Accent.swift" "$project_root/Sources/Localization.swift" "$project_root/Sources/PopoverLayout.swift" "$project_root/Sources/Termination.swift" "$project_root/Sources/Applications.swift" "$project_root/Sources/PanelHost.swift" "$project_root/Sources/PanelComponents.swift" "$project_root/Sources/GlassControls.swift" "$project_root/Sources/Panel.swift" "$project_root/Sources/App.swift" -o "$app_bundle/Contents/MacOS/EsaiWeChatTimer"
cp "$project_root/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_bundle/Contents/Resources/AppIcon.icns"
cp "$project_root/Resources/EsaiStatusTemplate.pdf" "$app_bundle/Contents/Resources/EsaiStatusTemplate.pdf"
mkdir -p "$app_bundle/Contents/Resources/Licenses"
cp "$project_root/Resources/Licenses/CodexRunway-AGPL-3.0.txt" "$app_bundle/Contents/Resources/Licenses/"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$app_bundle/Contents/Resources/"
mkdir -p "$app_bundle/Contents/Frameworks"
ditto "$sparkle_runtime/Sparkle.framework" "$app_bundle/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_runtime/LICENSE" "$app_bundle/Contents/Resources/Licenses/Sparkle.txt"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
print -r -- "$app_bundle"
