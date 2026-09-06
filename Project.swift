import ProjectDescription

let project = Project(
    name: "AgentLimits",
    organizationName: "it.stefer",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
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
            entitlements: .file(path: "AgentLimits/AgentLimits.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "T7H24G7BFW",
                ],
                configurations: [
                    .release(
                        name: .release,
                        settings: [
                            "CODE_SIGN_IDENTITY": "Developer ID Application",
                            "CODE_SIGN_STYLE": "Manual",
                            "OTHER_CODE_SIGN_FLAGS": "--options runtime --timestamp",
                        ]
                    ),
                ]
            )
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
