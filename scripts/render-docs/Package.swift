// swift-tools-version: 5.9
import PackageDescription

// Renders the images in docs/ from the app's real SwiftUI views.
// Run from the repo root: swift run --package-path scripts/render-docs render-docs
let package = Package(
    name: "render-docs",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "render-docs",
            path: "Sources/render-docs",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
