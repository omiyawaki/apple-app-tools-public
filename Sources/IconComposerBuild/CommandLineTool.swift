import Foundation

public enum CommandLineTool {
    public static func main(arguments: [String]) {
        do {
            if arguments.contains("--help") || arguments.contains("-h") {
                print(Self.usage)
                return
            }

            let options = try BuildOptions.parse(arguments)
            try IconComposerBuilder(options: options).run()
        } catch let error as BuildError {
            FileHandle.standardError.writeLine("error: \(error.message)")
            exit(1)
        } catch {
            FileHandle.standardError.writeLine("error: \(error.localizedDescription)")
            exit(1)
        }
    }

    public static let usage = """
    Usage:
      apple-app-tools icon build --icon PATH --name AppIcon --out DIR [options]

    Options:
      --platform NAME                  Icon Composer platform. Default: macOS.
      --actool-platform NAME           Override the actool platform mapping.
      --minimum-deployment-target VER  Deployment target passed to actool. Default: 26.0.
      --work DIR                       Scratch directory. Default: .build/icon-composer-build.
      --review DIR                     Directory for rendition previews.
      --review-sheet PATH              Contact sheet path. Requires --review.
      --verify-plist PATH              Require CFBundleIconName and reject CFBundleIconFile.
      --ictool PATH                    Icon Composer ictool path.
      --rendition-size PX              Preview rendition size. Default: 1024.
      --renditions A,B,C               Renditions to export.
      --design-generation 26|27        Icon rendering generation passed to ictool.
      --no-png                         Do not write AppIcon.png.
      --no-icns                        Do not copy AppIcon.icns when actool emits one.
      --no-assets-car                  Do not copy Assets.car.
    """
}

private extension FileHandle {
    func writeLine(_ string: String) {
        if let data = "\(string)\n".data(using: .utf8) {
            write(data)
        }
    }
}
