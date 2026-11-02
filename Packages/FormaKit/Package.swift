// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FormaKit",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        "FormaGeometry", "FormaDomain", "FormaApplication", "FormaCanvasEngine",
        "FormaDesignSystem", "FormaWorkspaceFeature", "FormaDocumentIO",
        "FormaInterchange", "FormaCatalogInfrastructure", "FormaLocalization"
    ].map { .library(name: $0, targets: [$0]) },
    targets: [
        .target(name: "FormaLocalization", resources:[.process("Resources")]),
        .target(name: "FormaGeometry"),
        .target(name: "FormaDomain", dependencies: ["FormaGeometry"]),
        .target(name: "FormaApplication", dependencies: ["FormaDomain", "FormaGeometry", "FormaLocalization"]),
        .target(name: "FormaCanvasEngine", dependencies: ["FormaDomain", "FormaGeometry"]),
        .target(name: "FormaDesignSystem", dependencies:["FormaLocalization"]),
        .target(name: "FormaWorkspaceFeature", dependencies: ["FormaApplication", "FormaDomain", "FormaGeometry", "FormaCanvasEngine", "FormaDesignSystem", "FormaLocalization"]),
        .target(name: "FormaDocumentIO", dependencies: ["FormaApplication", "FormaDomain", "FormaGeometry"]),
        .target(name: "FormaInterchange", dependencies: ["FormaApplication", "FormaDomain", "FormaGeometry", "FormaCanvasEngine"]),
        .target(name: "FormaCatalogInfrastructure", dependencies: ["FormaApplication", "FormaDomain", "FormaGeometry", "FormaLocalization"]),
        .testTarget(name: "FormaCoreTests", dependencies: ["FormaDomain", "FormaApplication", "FormaGeometry", "FormaDocumentIO", "FormaCanvasEngine", "FormaCatalogInfrastructure", "FormaInterchange", "FormaLocalization"])
    ],
    swiftLanguageModes: [.v6]
)
