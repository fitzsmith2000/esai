#!/bin/zsh
set -euo pipefail
project_root="${0:A:h}"
zsh "$project_root/build.sh"
app_bundle="$project_root/build/esai 定时关闭.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_bundle/Contents/Info.plist")
stage=$(mktemp -d "${TMPDIR:-/tmp/}esai-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$project_root/dist"
ditto "$app_bundle" "$stage/esai 定时关闭.app"
ln -s /Applications "$stage/Applications"
image_path="$project_root/dist/esai-$version-apple-silicon.dmg"
hdiutil create -ov -volname "esai 定时关闭" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$image_path"
hdiutil verify "$image_path"
(cd "$project_root/dist" && shasum -a 256 "${image_path:t}" > "${image_path:t}.sha256")
print -r -- "$image_path"
