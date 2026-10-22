# Campfire for iOS and macOS

Native SwiftUI apps for a Campfire blog server. One Xcode project, two app targets, and one shared source folder. Requires Xcode with iOS 18 and macOS 15 SDK support or newer.

## Source layout

- `Shared/`: API client, blog storage and Keychain access, connection validation and form fields, setup-code parsing, appearance preferences and controls, HTML parsing and rich-text rendering, editor restyling, and legacy Markdown import.
- `Campfire/`: iOS navigation, settings presentation, camera scanner, and the UIKit rich-text editor and keyboard controls.
- `Mac/`: macOS windows and menus, settings presentation, draft recovery, and the AppKit editor and undo interactions.
- `Checks/`: shared font/HTML and connection checks plus Mac recovery and editing checks.

Both apps use the same themes, System/Light/Dark selector, accent swatches, editor fonts and text sizes, custom blog names, and verified connection fields. Preferences and names stay on the device; they do not change the site's styling or sync between devices. Write tokens stay in Keychain.

Open **Page Editor** from the blog toolbar to edit existing pages such as About and Index with rich text, or templates and CSS as source. Saves publish changes to the selected blog (unless the page is a draft). Source editing keeps quotes and punctuation literal. Closing a file with unsaved edits asks before discarding; failed saves keep the editor open. Templates are validated and applied by the server, and stale saves are rejected rather than overwriting another editor's work. CSS changes may require purging a CDN cache. Page Editor requires the matching server update; it does not create or delete site files.

The server is maintained separately in the sibling `../server` directory. These apps require its HTML API.

## Build

From this directory:

```bash
xcodebuild -project Campfire.xcodeproj -scheme 'Campfire Mac' \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/campfire-mac-build build

xcodebuild -project Campfire.xcodeproj -scheme Campfire \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/campfire-ios-build CODE_SIGNING_ALLOWED=NO build
```

The Mac app is `/tmp/campfire-mac-build/Build/Products/Debug/Campfire.app`. For a physical iPhone, use its destination ID, omit `CODE_SIGNING_ALLOWED=NO`, and pass your `DEVELOPMENT_TEAM` with `-allowProvisioningUpdates`. Install the signed app with `xcrun devicectl device install app --device DEVICE_ID /path/to/Campfire.app`.

## Checks

```bash
bash Checks/run-mac-ux-checks.sh
```

The shared checks exercise real attributed strings and font choices, including italic fallback, lossless restyling, server format compatibility, and connection validation. Mac checks cover local recovery, dirty-state handling, preference migration, light/dark contrast, and filtering. Platform UI behavior still needs hands-on verification.
