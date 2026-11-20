// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LilyKit",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "LilyKit", targets: ["LilyKit"])],
    targets: [
        .target(name: "LilyKit"),
        .testTarget(name: "LilyKitTests", dependencies: ["LilyKit"]),
    ],
    swiftLanguageModes: [.v6]
)
