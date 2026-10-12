import Foundation

/// About this app: version from Info.plist and who made it.
enum AppInfo {
    static let author = "npmh0310"
    static let authorURL = URL(string: "https://github.com/npmh0310")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}
