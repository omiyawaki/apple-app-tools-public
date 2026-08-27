import AppKit
import Foundation

public struct IconComposerBuilder {
    private let options: BuildOptions
    private let fileManager = FileManager.default

    public init(options: BuildOptions) {
        self.options = options
    }

    public func run() throws {
        try validateInputs()

        let ictool = try ToolLocator.resolveICTool(explicit: options.ictool)
        let actool = try ToolLocator.resolveXcrunTool("actool")
        let iconutil = URL(fileURLWithPath: "/usr/bin/iconutil")
        let actoolOutput = options.work.appendingPathComponent("actool", isDirectory: true)
        let iconset = options.work.appendingPathComponent("\(options.name).iconset", isDirectory: true)
        let reviewIconset = options.work.appendingPathComponent("\(options.name)-review.iconset", isDirectory: true)

        try resetDirectory(options.work)
        try fileManager.createDirectory(at: options.out, withIntermediateDirectories: true)

        if let review = options.review {
            try resetDirectory(review)
            try exportRenditions(ictool: ictool, review: review)
        }

        try runActool(actool: actool, output: actoolOutput)
        try copyCompiledAssets(from: actoolOutput)
        try exportDefaultPNG(ictool: ictool)
        try exportIconset(ictool: ictool, iconutil: iconutil, actoolOutput: actoolOutput, iconset: iconset)

        if let reviewSheet = options.reviewSheet {
            try exportRenderedIconset(ictool: ictool, iconset: reviewIconset)
            try ReviewSheetWriter.write(iconset: reviewIconset, output: reviewSheet)
        }

        if let plist = options.verifyPlist {
            try PlistVerifier.verify(plist: plist, iconName: options.name)
        }

        print("Wrote \(options.out.appendingPathComponent("\(options.name).png").path)")
        if options.writesICNS && fileManager.fileExists(atPath: options.out.appendingPathComponent("\(options.name).icns").path) {
            print("Wrote \(options.out.appendingPathComponent("\(options.name).icns").path)")
        }
        if options.writesAssetsCar && fileManager.fileExists(atPath: options.out.appendingPathComponent("Assets.car").path) {
            print("Wrote \(options.out.appendingPathComponent("Assets.car").path)")
        }
        if let review = options.review {
            print("Wrote \(review.appendingPathComponent("rendition-*.png").path)")
        }
        if let reviewSheet = options.reviewSheet {
            print("Wrote \(reviewSheet.path)")
        }
    }

    private func validateInputs() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: options.icon.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BuildError("Missing Icon Composer document: \(options.icon.path)")
        }

        if options.reviewSheet != nil && options.review == nil {
            throw BuildError("--review-sheet requires --review.")
        }
    }

    private func resetDirectory(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func exportRenditions(ictool: URL, review: URL) throws {
        for rendition in options.renditions {
            let output = review.appendingPathComponent("rendition-\(rendition).png")
            try run(ictool, withDesignGeneration([
                    options.icon.path,
                    "--export-image",
                    "--output-file", output.path,
                    "--platform", options.platform.rawValue,
                    "--rendition", rendition,
                    "--width", String(options.renditionSize),
                    "--height", String(options.renditionSize),
                    "--scale", "1"
            ]))
        }
    }

    private func runActool(actool: URL, output: URL) throws {
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        let partialPlist = output.appendingPathComponent("partial.plist")

        try run(
            actool,
            [
                "--compile", output.path,
                "--app-icon", options.name,
                "--platform", options.actoolPlatform ?? options.platform.actoolPlatform,
                "--minimum-deployment-target", options.minimumDeploymentTarget,
                "--standalone-icon-behavior", "all",
                "--output-partial-info-plist", partialPlist.path,
                options.icon.path
            ]
        )
    }

    private func copyCompiledAssets(from actoolOutput: URL) throws {
        if options.writesAssetsCar {
            let source = actoolOutput.appendingPathComponent("Assets.car")
            if fileManager.fileExists(atPath: source.path) {
                try copyReplacing(source, to: options.out.appendingPathComponent("Assets.car"))
            }
        }

        if options.writesICNS {
            let source = actoolOutput.appendingPathComponent("\(options.name).icns")
            if fileManager.fileExists(atPath: source.path) {
                try copyReplacing(source, to: options.out.appendingPathComponent("\(options.name).icns"))
            }
        }
    }

    private func exportDefaultPNG(ictool: URL) throws {
        guard options.writesPNG else {
            return
        }

        try run(ictool, withDesignGeneration([
                options.icon.path,
                "--export-image",
                "--output-file", options.out.appendingPathComponent("\(options.name).png").path,
                "--platform", options.platform.rawValue,
                "--rendition", "Default",
                "--width", String(options.renditionSize),
                "--height", String(options.renditionSize),
                "--scale", "1"
        ]))
    }

    private func exportIconset(ictool: URL, iconutil: URL, actoolOutput: URL, iconset: URL) throws {
        if options.platform == .macOS {
            let icns = actoolOutput.appendingPathComponent("\(options.name).icns")
            if fileManager.fileExists(atPath: icns.path) {
                try run(iconutil, ["-c", "iconset", icns.path, "-o", iconset.path])
                return
            }
        }

        try exportRenderedIconset(ictool: ictool, iconset: iconset)
    }

    private func exportRenderedIconset(ictool: URL, iconset: URL) throws {
        try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
        let exports: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (pixels, file) in exports {
            try run(ictool, withDesignGeneration([
                    options.icon.path,
                    "--export-image",
                    "--output-file", iconset.appendingPathComponent(file).path,
                    "--platform", options.platform.rawValue,
                    "--rendition", "Default",
                    "--width", String(pixels),
                    "--height", String(pixels),
                    "--scale", "1"
            ]))
        }
    }

    private func withDesignGeneration(_ arguments: [String]) -> [String] {
        guard let designGeneration = options.designGeneration else {
            return arguments
        }
        return arguments + ["--design-generation", String(designGeneration)]
    }

    private func copyReplacing(_ source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw BuildError("\(executable.lastPathComponent) failed with status \(process.terminationStatus): \(output)")
        }
    }
}
