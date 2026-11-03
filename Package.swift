// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenPMTools",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "pmt", targets: ["pmt"]),
        .executable(name: "OpenPMTools", targets: ["OpenPMTools"]),
    ],
    dependencies: [.package(path: "../frequent-finder")],
    targets: [
        .target(name: "PMTCore", dependencies: [.product(name: "FFCore", package: "frequent-finder")]),
        .executableTarget(name: "pmt", dependencies: ["PMTCore"]),
        .executableTarget(name: "OpenPMTools",
                          dependencies: ["PMTCore", .product(name: "FFCore", package: "frequent-finder")],
                          path: "Sources/OpenPMToolsApp"),
        .testTarget(name: "PMTCoreTests", dependencies: [
            "PMTCore", .product(name: "FFCore", package: "frequent-finder")]),
    ],
    swiftLanguageModes: [.v5]
)
