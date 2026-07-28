// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "DesktopPetCore",
            path: "Sources/DesktopPetCore"
        ),
        .executableTarget(
            name: "desktoppet",
            dependencies: ["DesktopPetCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/App",
            resources: [.copy("Resources/donate-vietqr.png")]
        ),
        .testTarget(
            name: "DesktopPetCoreTests",
            dependencies: ["DesktopPetCore"],
            path: "Tests/DesktopPetCoreTests"
        ),
        .testTarget(
            name: "DesktopPetAppTests",
            dependencies: ["desktoppet"],
            path: "Tests/DesktopPetAppTests"
        ),
    ]
)
