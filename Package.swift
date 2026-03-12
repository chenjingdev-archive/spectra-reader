// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "spectra-reader-base",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "spectra-reader-base", targets: ["SpectraReaderBase"])
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
    )
  ]
)
