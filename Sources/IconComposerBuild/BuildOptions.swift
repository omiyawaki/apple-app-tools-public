import Foundation

public struct BuildOptions: Equatable {
    public var icon: URL
    public var name: String
    public var out: URL
    public var work: URL
    public var review: URL?
    public var reviewSheet: URL?
    public var platform: ApplePlatform
    public var actoolPlatform: String?
    public var minimumDeploymentTarget: String
    public var ictool: URL?
    public var verifyPlist: URL?
    public var renditionSize: Int
    public var renditions: [String]
    public var designGeneration: Int?
    public var writesPNG: Bool
    public var writesICNS: Bool
    public var writesAssetsCar: Bool

    public init(
        icon: URL,
        name: String = "AppIcon",
        out: URL,
        work: URL = URL(fileURLWithPath: ".build/icon-composer-build"),
        review: URL? = nil,
        reviewSheet: URL? = nil,
        platform: ApplePlatform = .macOS,
        actoolPlatform: String? = nil,
        minimumDeploymentTarget: String = "26.0",
        ictool: URL? = nil,
        verifyPlist: URL? = nil,
        renditionSize: Int = 1024,
        renditions: [String] = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"],
        designGeneration: Int? = nil,
        writesPNG: Bool = true,
        writesICNS: Bool = true,
        writesAssetsCar: Bool = true
    ) {
        self.icon = icon
        self.name = name
        self.out = out
        self.work = work
        self.review = review
        self.reviewSheet = reviewSheet
        self.platform = platform
        self.actoolPlatform = actoolPlatform
        self.minimumDeploymentTarget = minimumDeploymentTarget
        self.ictool = ictool
        self.verifyPlist = verifyPlist
        self.renditionSize = renditionSize
        self.renditions = renditions
        self.designGeneration = designGeneration
        self.writesPNG = writesPNG
        self.writesICNS = writesICNS
        self.writesAssetsCar = writesAssetsCar
    }

    public static func parse(_ rawArguments: [String]) throws -> BuildOptions {
        var arguments = rawArguments
        if arguments.first == "build" {
            arguments.removeFirst()
        }

        var values: [String: String] = [:]
        var flags = Set<String>()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--no-png", "--no-icns", "--no-assets-car":
                flags.insert(argument)
                index += 1
            case "--icon", "--name", "--out", "--work", "--review", "--review-sheet",
                 "--platform", "--actool-platform", "--minimum-deployment-target",
                 "--ictool", "--verify-plist", "--rendition-size", "--renditions",
                 "--design-generation":
                guard index + 1 < arguments.count else {
                    throw BuildError("Missing value for \(argument).")
                }
                values[argument] = arguments[index + 1]
                index += 2
            default:
                throw BuildError("Unknown argument: \(argument).")
            }
        }

        guard let iconPath = values["--icon"] else {
            throw BuildError("Missing required --icon PATH.")
        }
        guard let outPath = values["--out"] else {
            throw BuildError("Missing required --out DIR.")
        }

        let platformName = values["--platform"] ?? ApplePlatform.macOS.rawValue
        guard let platform = ApplePlatform(rawValue: platformName) else {
            throw BuildError("Unsupported platform \(platformName).")
        }

        let size = try parsePositiveInt(values["--rendition-size"] ?? "1024", option: "--rendition-size")
        let renditions = (values["--renditions"] ?? "Default,Dark,ClearLight,ClearDark,TintedLight,TintedDark")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if renditions.isEmpty {
            throw BuildError("--renditions must contain at least one rendition.")
        }

        let designGeneration: Int?
        if let rawDesignGeneration = values["--design-generation"] {
            guard let value = Int(rawDesignGeneration), [26, 27].contains(value) else {
                throw BuildError("--design-generation must be 26 or 27.")
            }
            designGeneration = value
        } else {
            designGeneration = nil
        }

        return BuildOptions(
            icon: URL(fileURLWithPath: iconPath),
            name: values["--name"] ?? "AppIcon",
            out: URL(fileURLWithPath: outPath),
            work: URL(fileURLWithPath: values["--work"] ?? ".build/icon-composer-build"),
            review: values["--review"].map { URL(fileURLWithPath: $0) },
            reviewSheet: values["--review-sheet"].map { URL(fileURLWithPath: $0) },
            platform: platform,
            actoolPlatform: values["--actool-platform"],
            minimumDeploymentTarget: values["--minimum-deployment-target"] ?? "26.0",
            ictool: values["--ictool"].map { URL(fileURLWithPath: $0) },
            verifyPlist: values["--verify-plist"].map { URL(fileURLWithPath: $0) },
            renditionSize: size,
            renditions: renditions,
            designGeneration: designGeneration,
            writesPNG: !flags.contains("--no-png"),
            writesICNS: !flags.contains("--no-icns"),
            writesAssetsCar: !flags.contains("--no-assets-car")
        )
    }

    private static func parsePositiveInt(_ raw: String, option: String) throws -> Int {
        guard let value = Int(raw), value > 0 else {
            throw BuildError("\(option) must be a positive integer.")
        }
        return value
    }
}

public enum ApplePlatform: String, Equatable {
    case macOS
    case iOS
    case iPadOS
    case visionOS
    case watchOS
    case tvOS

    public var actoolPlatform: String {
        switch self {
        case .macOS:
            return "macosx"
        case .iOS, .iPadOS:
            return "iphoneos"
        case .visionOS:
            return "xros"
        case .watchOS:
            return "watchos"
        case .tvOS:
            return "appletvos"
        }
    }
}
