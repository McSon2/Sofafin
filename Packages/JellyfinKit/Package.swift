// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JellyfinKit",
    // Le paquet produit quelques textes destinés à l'écran — libellés de saut,
    // durées, sous-titres de vignettes — et porte donc ses propres traductions.
    defaultLocalization: "fr",
    platforms: [.tvOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "JellyfinKit", targets: ["JellyfinKit"])
    ],
    targets: [
        .target(
            name: "JellyfinKit",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
