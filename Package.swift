// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Spelunkr",
    platforms: [.macOS(.v13), .tvOS(.v17)],
    products: [
        .library(name: "SpelunkrCore", targets: ["SpelunkrCore"]),
        .executable(name: "spelunkr-probe", targets: ["SpelunkrProbe"])
    ],
    targets: [
        .target(name: "SpelunkrCore", resources: [.process("Resources")]),
        .executableTarget(name: "SpelunkrProbe", dependencies: ["SpelunkrCore"], path: "Tools/SpelunkrProbe"),
        .testTarget(name: "SpelunkrCoreTests", dependencies: ["SpelunkrCore"], resources: [.process("Fixtures")])
    ]
)
