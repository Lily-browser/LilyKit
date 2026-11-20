# LilyKit

Platform-neutral core shared by [Lily-macos](https://github.com/Lily-browser/Lily-macos) and
[Lily-ios](https://github.com/Lily-browser/Lily-ios): ad-block rule conversion, sealed storage and the
Keychain key store, history/bookmarks/site settings models, page IPC schemas and routing, migration
readers, the assistant client, extension manifest/package/audit logic and URL/privacy helpers.

No AppKit, UIKit or SwiftUI here. UI, windowing, the WebKit extension runtime and signing stay in the apps.
Platform differences inside the kit are `#if os(macOS)` fences, never separate copies.

- Platforms: macOS 14+, iOS 18+. Swift 6 language mode, no package dependencies.
- Apps pin LilyKit with `exact:` (a tagged release), so a kit change reaches an app only through a reviewed bump.
- CI: `swift test` on macOS and an iOS Simulator build.

Licensed under GPL-3.0-only (see `LICENSE`).
