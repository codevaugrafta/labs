import Foundation

extension Bundle {
    /// Library sidebar title, e.g. `LeoComposer2 v.01` when `CFBundleShortVersionString` is `0.01`.
    var leoComposerSidebarTitle: String {
        let name =
            object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "LeoComposer2"
        guard let raw = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return name
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let label: String
        if trimmed.range(of: #"^0\.\d{2}$"#, options: .regularExpression) != nil {
            label = String(trimmed.dropFirst(2))
        } else {
            label = trimmed
        }
        return "\(name) v.\(label)"
    }
}
