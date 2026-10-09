// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopGames",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DesktopGames",
            path: "Sources/DesktopGames",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
