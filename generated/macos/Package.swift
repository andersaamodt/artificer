// Generated from app-blueprint/app.ir.yaml. Regenerate with scripts/render-native-desktop.sh.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "artificer-native",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "artificer-native", targets: ["App"])
  ],
  targets: [
    .executableTarget(
      name: "App",
      path: "Sources/App"
    )
  ]
)
