# LilyKit

Platform-neutral core shared by [Lily-macos](https://github.com/Lily-browser/Lily-macos) and
[Lily-ios](https://github.com/Lily-browser/Lily-ios): ad-block rule conversion, sealed storage and the
Keychain key store, history/bookmarks/site settings models, page IPC schemas and routing, migration
readers, the assistant client, extension manifest/package/audit logic and URL/privacy helpers.

No AppKit, UIKit or SwiftUI here. UI, windowing, the WebKit extension runtime and signing stay in the apps.
Platform differences inside the kit are `#if os(macOS)` fences, never separate copies.

## Layout

| Folder (`Sources/LilyKit/`) | Files | What |
|---|---|---|
| `AdBlock/` | 5 | Filter-list download and conversion to WebKit content rules, cosmetic/procedural filters |
| `Agent/` | 5 | Local assistant: Ollama client, prompts, context store |
| `Browser/` | 3 | HTTPS-first upgrades, URL resolution, web inspector hook, script bridge helpers |
| `Extensions/` | 10 | Extension manifest, package/CRX3 reading, audit, compatibility shims, Chrome Web Store client, storage |
| `Handlers/` | 1 | Page IPC payload schemas and limits |
| `IPC/` | 3 | Versioned wire envelopes, router, script-message bridge with source checks |
| `Migration/` | 4 | Read-only importers for Chrome, Safari, Arc, Dia, Zen |
| `Scripts/` | 2 | Injection manifest and script registry |
| `Session/` | 1 | Typed-text recovery (form drafts) |
| `Support/` | 14 | Sealed storage + Keychain key store, history, bookmarks, site settings, address completion, link tracking, sanitizers, certificate pinning, paths, logging |

## Using it

```swift
.package(url: "https://github.com/Lily-browser/LilyKit.git", exact: "0.1.0")   // revision: "<sha>" until the first tag
```

- Platforms: macOS 14+, iOS 18+. Swift 6 language mode, no package dependencies.
- Declarations are `public`; the host app supplies anything environment-specific (for example the user agent for `SearchSuggestionClient`).
- Platform-only code is fenced with `#if os(macOS)` (the legacy-keychain ACLs in `KeychainKeyStore`, `Sanitize.resolvedAddresses`).
- Apps pin an exact tag, so a kit change reaches an app only through a reviewed version bump.

## Development

```sh
bash scripts/security-lint.sh                                                     # the same rules as the apps
swift test                                                                        # macOS
xcodebuild -scheme LilyKit -destination 'generic/platform=iOS Simulator' build    # iOS
```

CI runs all three on every PR. Rules and what belongs here: [`CLAUDE.md`](CLAUDE.md); contribution flow: [`CONTRIBUTING.md`](CONTRIBUTING.md); security reports: [`SECURITY.md`](SECURITY.md).

Licensed under GPL-3.0-only (see `LICENSE`).
