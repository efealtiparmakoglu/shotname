// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "shotname",
    platforms: [
        .macOS(.v10_15)
    ],
    targets: [
        .executableTarget(name: "shotname", path: "Sources/shotname"),
        .testTarget(name: "shotnameTests", dependencies: ["shotname"], path: "Tests"),
    ]
)
