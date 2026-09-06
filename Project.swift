import ProjectDescription

let project = Project(
    name: "AgentLimits",
    organizationName: "it.stefer",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "AgentLimits",
            destinations: .macOS,
            product: .app,
            bundleId: "it.stefer.AgentLimits",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(
                with: [
                    "LSUIElement": true,
                    "CFBundleShortVersionString": "0.1.0",
                    "CFBundleVersion": "1",
                    "NSHumanReadableCopyright": "Stefano Ferri",
                ]
            ),
            sources: ["AgentLimits/Sources/**"],
            resources: ["AgentLimits/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "AgentLimitsTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "it.stefer.AgentLimitsTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["AgentLimits/Tests/**"],
            dependencies: [.target(name: "AgentLimits")]
        ),
    ]
)
