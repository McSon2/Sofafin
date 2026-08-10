// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JellyfinKit",
    platforms: [.tvOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "JellyfinKit", targets: ["JellyfinKit"])
    ],
    targets: [
        .target(
            name: "JellyfinKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
