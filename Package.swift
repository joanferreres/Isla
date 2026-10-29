// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Isla", platforms: [.macOS(.v15)], products: [.executable(name: "Isla", targets: ["Isla"])], targets: [.target(name: "IslandCore"), .target(name: "LidEffects", dependencies: ["IslandCore"], swiftSettings: [.swiftLanguageMode(.v5)]), .executableTarget(name: "Isla", dependencies: ["IslandCore", "LidEffects"]), .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]), .testTarget(name: "IslaTests", dependencies: ["Isla"])])
