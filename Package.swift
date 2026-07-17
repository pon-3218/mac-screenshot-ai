// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CaptureCodex",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CaptureCodex", targets: ["CaptureCodex"])
    ],
    targets: [
        .executableTarget(
            name: "CaptureCodex",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
