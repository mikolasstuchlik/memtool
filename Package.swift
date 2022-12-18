// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "memtool",
    products: [
        .library(name: "MemtoolCore", targets: ["MemtoolCore"]),
        .executable(name: "memtool", targets: ["memtool"])
    ],
    targets: [
        .target(name: "Cutils"),
        .target(name: "MemtoolCore", dependencies: ["Cutils"]),
        .executableTarget(name: "memtool", dependencies: ["MemtoolCore"]),


        .testTarget(name: "MemtoolCoreTests", dependencies: ["MemtoolCore"])
    ]
)
