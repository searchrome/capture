// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Capture",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Capture", targets: ["Capture"])],
    targets: [
        .executableTarget(
            name: "Capture",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(name: "CaptureTests", dependencies: ["Capture"])
    ],
    swiftLanguageVersions: [.v5]
)
