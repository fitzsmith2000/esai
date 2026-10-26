# macOS update publishing

esai uses [Sparkle 2.10.1](https://sparkle-project.org/documentation/) for checking, downloading, verifying, replacing and relaunching the app. Quosparr's former Swift implementation used Sparkle; its current Go implementation uses a Go updater. esai remains a Swift/AppKit application.

## Client behavior

- Stable Apple Silicon feed: `https://raw.githubusercontent.com/fitzsmith2000/esai/main/updates/appcast-arm64.xml`.
- Automatic checks default on, with a 3,600-second interval while running. Manual checks remain available when automatic checks are off.
- Automatic download and installation default off. When enabled, Sparkle can install on normal quit or offer its standard restart prompt. esai does not force a background restart.
- Feed and archive signatures are mandatory. The pinned Ed25519 public key is in `Resources/Info.plist`; an archive must verify before extraction.
- Preferences remain in the existing `com.esai.wechat-timer` domain. Preview mode starts no updater and changes no update preferences.
- Versions before 1.6.0 have no updater and require one manual installation.

The app still uses ad-hoc signing rather than Apple Developer ID/notarization. Ed25519 verifies the publisher's update artifacts; it does not provide Apple notarization.

## Dependency and signing key

`Scripts/fetch-sparkle.sh` downloads the official release archive, verifies its pinned SHA-256, and extracts only the framework and signing tools into ignored `build/dependencies`. The framework's original signatures are retained and verified. Its complete upstream license is bundled.

The release private seed is kept only at `~/.config/esai/updates/ed25519.seed` with mode `600`, outside this repository. Back it up securely. Never commit the seed or put it into app resources. A clone can build the application without the private key; publishing signed updates requires the original key.

`swift Scripts/create-update-key.swift` creates a key only if missing and prints only its public key. **Do not generate a replacement key for an already distributed app.** Restore the original private key instead. The release script verifies an archive against the public key pinned in the app and rejects a mismatched key.

## Release procedure

1. Increment both `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. The build number must increase monotonically. Keep the same bundle ID, feed URL and public key.
2. Run the logic tests and package:

   ```sh
   zsh test.sh
   zsh package.sh
   ```

3. Sign the app-only ZIP and generate the signed feed. For example:

   ```sh
   python3 Scripts/make-appcast.py dist/esai-1.6.0-apple-silicon.zip \
     --notes '新增应用内检查更新、自动检查及可选的自动下载和安装。'
   ```

   The script verifies package identity/version/public key, signs the archive, verifies the signature against the pinned public key, then signs the appcast. It keeps recent releases for supported-OS fallback. Do not modify the ZIP after signing or edit the XML after signing. Re-run signing if the feed changes.

4. Commit the corresponding source and public feed, tag the source with `v<version>`, then create the GitHub Release containing both DMG and ZIP plus their `.sha256` files. The release must be public and the ZIP URL accessible before clients are expected to consume the feed. Keep the previous release assets available.
5. Fetch the published feed and archive and verify their signatures and sizes. Install the downloaded DMG and manually check once on a real Mac.

The repository marks signed XML as `-text` to prevent Git newline normalization from invalidating its signature. The DMG is for manual first installation; Sparkle uses the app-only ZIP.

## Isolated integration tests

```sh
python3 Tests/test-updates.py
```

Requires the local signing key and a macOS desktop session. The fixture uses unique test bundle IDs, disposable signed app bundles and a loopback HTTP server. It never imports esai's scheduler or closes user apps. Checks include finding a newer version, refusing a downgrade/current version, rejecting a modified feed, handling an unavailable feed, and actually downloading/verifying/installing/relaunching a test update. A modified archive must fail verification. Temporary test preferences and caches are removed.
