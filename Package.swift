// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EC25Helper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EC25Helper", targets: ["EC25Helper"])
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
            name: "EC25Helper",
            dependencies: ["CEC25USB"],
            path: "Sources/EC25Helper",
            linkerSettings: [
                // Let dev runs (.build/release/EC25Helper) find the Homebrew libusb.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"])
            ]
        )
    ]
)
