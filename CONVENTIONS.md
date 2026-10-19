# Campfire Apple apps

Read this file before Git or GitHub operations.

- This repository contains both Apple apps. The sibling `../server` is a separate repository.
- Put reusable models, persistence, validation, HTML rendering, and settings controls in `Shared/`; both Xcode targets compile that folder directly.
- Keep iOS navigation, camera scanning, and UIKit editor interactions in `Campfire/`. Keep macOS windows, commands, local recovery, and AppKit editor interactions in `Mac/`.
- Keep platform checks at native API calls. Do not introduce packages, protocols, or dependencies solely to wrap shared code.
- Preserve existing UserDefaults keys, blog IDs, Keychain accounts, HTML formatting, unsaved text, selection, and undo history during refactors. Appearance preferences and custom blog names are local to each device.
- Verify both Xcode schemes after shared changes. Run `bash Checks/run-mac-ux-checks.sh` for shared logic and Mac recovery checks; assertions require an unoptimized build.
- Build and install through `xcodebuild` and `xcrun devicectl`; screen access is not required. Keep build products outside the source tree.
- Never commit tokens, signing private keys, provisioning profiles, or Xcode user state. Do not create a remote repository or publish without a user request.
