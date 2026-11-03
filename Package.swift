// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPower",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacPower",
            path: "Sources/MacPower",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
