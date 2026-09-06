import ProjectDescription

let project = Project(
    name: "ClaudeLimits",
    organizationName: "it.stefer",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "ClaudeLimits",
            destinations: .macOS,
            product: .app,
            bundleId: "it.stefer.ClaudeLimits",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(
                with: [
                    "LSUIElement": true,
                    "CFBundleShortVersionString": "0.1.0",
                    "CFBundleVersion": "1",
                    "NSHumanReadableCopyright": "Stefano Ferri",
                ]
            ),
            sources: ["ClaudeLimits/Sources/**"],
            resources: ["ClaudeLimits/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "ClaudeLimitsTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "it.stefer.ClaudeLimitsTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["ClaudeLimits/Tests/**"],
            dependencies: [.target(name: "ClaudeLimits")]
        ),
    ]
)
