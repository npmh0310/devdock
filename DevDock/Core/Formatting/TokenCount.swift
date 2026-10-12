import Foundation

enum TokenCount {
    /// "850", "12.4K", "1.24M".
    static func short(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...: String(format: "%.2fM", Double(tokens) / 1_000_000)
        case 1_000...: String(format: "%.1fK", Double(tokens) / 1_000)
        default: "\(tokens)"
        }
    }
}
