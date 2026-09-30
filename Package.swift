// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WindowMenu",
            path: "Sources/WindowMenu",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
