// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "EC25Manager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EC25Manager", targets: ["EC25Manager"])
    ],
    targets: [
        .target(
            name: "CEC25USB",
            path: "Sources/CEC25USB",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("usb-1.0")
            ]
        ),
        .executableTarget(
            name: "EC25Manager",
            dependencies: ["CEC25USB"],
            path: "Sources/EC25Manager",
            linkerSettings: [
                // Let dev runs (.build/release/EC25Manager) find the Homebrew libusb.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"])
            ]
        )
    ]
)
