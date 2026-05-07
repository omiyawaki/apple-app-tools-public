import Foundation

public enum PlistVerifier {
    public static func verify(plist: URL, iconName: String) throws {
        let data = try Data(contentsOf: plist)
        guard let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw BuildError("Could not read plist as a dictionary: \(plist.path)")
        }

        guard object["CFBundleIconName"] as? String == iconName else {
            throw BuildError("\(plist.path) must set CFBundleIconName to \(iconName).")
        }

        if object["CFBundleIconFile"] != nil {
            throw BuildError("\(plist.path) must not set CFBundleIconFile because it can bypass adaptive Icon Composer assets.")
        }
    }
}
