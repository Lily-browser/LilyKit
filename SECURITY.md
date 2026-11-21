# Security policy

LilyKit is the shared, UI-free code of Lily for macOS and Lily for iOS: sealed storage, ad-block conversion, extension audit and
packaging, migration readers, URL and privacy helpers.

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Report them privately through GitHub:
**[Security → Report a vulnerability](https://github.com/Lily-browser/LilyKit/security/advisories/new)**.

Include what you found, how to reproduce it, and the LilyKit version (git tag). It is maintained by one person, so replies are best
effort; you'll get an acknowledgement, and a credit in the advisory if you want one.

## Supported versions

Only the latest tag and `main` get security fixes; the apps pin an exact tag and move forward with it.

## Scope

In scope: the package's own code, for example data at rest (`SecureStorage`, sealed files), extension package parsing and audit
(`CRX3`, `ExtensionPackage`), migration readers (hostile browser profiles), filter-list parsing and conversion, URL handling, and the build
scripts. Out of scope: WebKit or OS bugs, and attacks that need an already-compromised device.
