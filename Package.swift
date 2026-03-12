// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "spectra-reader-base",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "spectra-reader-base", targets: ["SpectraReaderBase"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-testing.git", exact: "6.2.4")
  ],
  targets: [
    .executableTarget(
      name: "SpectraReaderBase",
      path: "Sources/SpectraReaderBase",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Vision"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("ApplicationServices")
      ]
    ),
    .testTarget(
      name: "SpectraReaderBaseTests",
      dependencies: [
        "SpectraReaderBase",
        .product(name: "Testing", package: "swift-testing")
      ],
      path: "Tests/SpectraReaderBaseTests"
    )
  ]
)
