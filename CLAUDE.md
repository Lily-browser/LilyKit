# LilyKit — Claude Rules

Platform-neutral Swift package shared by Lily-macos and Lily-ios (macOS 14+, iOS 18+). No AppKit, UIKit, SwiftUI or windowing here; no Electron/web wrappers. Priorities: correctness on both platforms, low CPU/RAM, small binary, security.

## Token discipline (user is token-constrained)
- Work inline; at most one `builder` per task, only for large multi-file work. Run the gates yourself.
- Read only what you need (Grep, then ranged Read). No unrequested refactors; short reports.
- After a PR is opened, or once a session gets long, end with: "`/compact` now (or `/clear` before an unrelated task)".

## What belongs here
- Logic with no UI that both apps use: storage, models, IPC schemas/routing, migration readers, ad-block conversion, extension manifest/package/audit, assistant client, URL/privacy helpers.
- Not here: anything importing AppKit/UIKit/SwiftUI, `Tab`/window types, the WebKit extension runtime, code signing/DMG, injected JS (still in Lily-macos until iOS needs it).
- Platform differences are `#if os(macOS)` fences inside the file, never duplicated files. Every change must build for **both** macOS and the iOS Simulator (`xcodebuild -scheme LilyKit -destination 'generic/platform=iOS Simulator' build`).

## API rules
- Declarations the apps use are `public`, structs get an explicit `public init` (the synthesized one is internal), public structs that cross actors declare `Sendable`.
- Breaking API changes bump the minor version (0.x) and need the apps' PRs; apps pin by `exact:` tag (or `revision:` before the first tag).

## Code rules (enforced by `scripts/security-lint.sh`, which CI runs)
- Concurrency: `async/await`, `actor`, `@MainActor` only; Swift 6 mode, strict concurrency complete.
- Logging: `os.Logger` with `privacy: .sensitive` on dynamic values; no `print`/`NSLog`.
- Secrets in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never UserDefaults or files.
- No `Process()` / shell, no unsafe pointers, no `evaluateJavaScript`/`callAsyncJavaScript`/nil `baseURL` (web views belong to the apps). XPC validates the peer's code signature.
- No package dependencies unless pinned (`exact:`/`revision:`). Scripts: `set -euo pipefail`, fixed `PATH`, quoted expansions, `umask 077` + `mktemp -d`.
- Migration readers open SQLite `SQLITE_OPEN_READONLY`; URLs are deduplicated.

## Gates before a PR
`bash scripts/security-lint.sh`, `swift test`, and the iOS Simulator build above.

## Git
On `main`, branch first (`feature/…`, `fix/…`). Conventional, atomic, signed commits. When done: push and open the PR to `main` automatically. Release (only when asked): `git tag -a vX.Y.Z`, push tags, `gh release create`. Then the apps bump their pin.
