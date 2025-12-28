// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeScan",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PokeScan", targets: ["PokeScan"])
    ],
    targets: [
        .executableTarget(
            name: "PokeScan",
            path: "PokeScan",
            exclude: [
                "PokeScan.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
