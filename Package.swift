// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FrameShift", platforms: [.macOS(.v14)], products: [.library(name: "ConverterCore", targets: ["ConverterCore"]), .executable(name: "FrameShift", targets: ["LocalVideoConverter"]), .executable(name: "MediaCheck", targets: ["MediaCheck"])], targets: [.target(name: "ConverterCore"), .executableTarget(name: "LocalVideoConverter", dependencies: ["ConverterCore"]), .executableTarget(name: "MediaCheck", dependencies: ["ConverterCore"]), .testTarget(name: "ConverterCoreTests", dependencies: ["ConverterCore"])])
