# Contributing to LilyKit

LilyKit is licensed under the [GPL-3.0](LICENSE); a pull request is licensed under it too. See the [Lily project](https://github.com/Lily-browser) for the big picture.

- Branch from `main` (`feature/…`, `fix/…`), conventional and signed commits, one PR per change.
- Before opening: `bash scripts/security-lint.sh`, `swift test`, and the iOS Simulator build (see `CLAUDE.md`). CI runs all three.
- No UI imports (AppKit/UIKit/SwiftUI). If it needs a window or a web view, it belongs in an app repo.
- New API the apps use must be `public`. After a kit PR merges and is tagged, the apps ([Lily-macos](https://github.com/Lily-browser/Lily-macos), Lily-ios) bump their pinned version in a PR of their own.
