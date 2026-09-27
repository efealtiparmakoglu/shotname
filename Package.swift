// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "shotname",
    targets: [
        .executableTarget(name: "shotname", path: "Sources/shotname"),
        .testTarget(name: "shotnameTests", dependencies: ["shotname"], path: "Tests"),
    ]
)
