// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CaptureCodex",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CaptureCodex", targets: ["CaptureCodex"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "CaptureCodex",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "CaptureCodexTests",
            dependencies: ["CaptureCodex"]
        )
    ],
    swiftLanguageModes: [.v5]
)
