import Foundation

/// Character decomposition engine powered by the CJK Decomposition Data File.
///
/// Data source: amake/cjk-decomp (fork of Gavin Grover's original dataset)
/// License: MIT — https://github.com/amake/cjk-decomp
///
/// Format of cjk-decomp.txt:
///   character:type(component1,component2,...)
///   Intermediate decompositions use 5-digit numeric IDs (not in Unicode).
///
/// Kangxi radical data source: Unicode Unihan Database kRSUnicode field
/// License: https://www.unicode.org/terms_of_use.html
final class DecompositionEngine: @unchecked Sendable {
    static let shared = DecompositionEngine()

    // MARK: - Storage

    /// Maps a character (or 5-digit numeric ID string) to its raw component strings.
    /// Components may themselves be Unicode chars or 5-digit numeric IDs.
    private var rawComponents: [String: [String]] = [:]

    /// Maps a Unicode codepoint (hex string like "5B66") to its Kangxi radical index.
    private var radicalIndex: [String: Int] = [:]

    /// The 214 canonical Kangxi radical characters, indexed by radical number (1-based).
    /// Source: Unicode kRSUnicode .0 entries — verified correct for Unicode 17.0.
    private static let kangxiRadicals: [Int: Character] = [
        1: "一", 2: "丨", 3: "丶", 4: "丿", 5: "乙", 6: "亅",
        7: "二", 8: "亠", 9: "人", 10: "儿", 11: "入", 12: "八",
        13: "冂", 14: "冖", 15: "冫", 16: "几", 17: "凵", 18: "刀",
        19: "力", 20: "勹", 21: "匕", 22: "匚", 23: "匸", 24: "十",
        25: "卜", 26: "卩", 27: "厂", 28: "厶", 29: "又", 30: "口",
        31: "囗", 32: "土", 33: "士", 34: "夂", 35: "夊", 36: "夕",
        37: "大", 38: "女", 39: "子", 40: "宀", 41: "寸", 42: "小",
        43: "尢", 44: "尸", 45: "屮", 46: "山", 47: "巛", 48: "工",
        49: "己", 50: "巾", 51: "干", 52: "幺", 53: "广", 54: "廴",
        55: "廾", 56: "弋", 57: "弓", 58: "彐", 59: "彡", 60: "彳",
        61: "心", 62: "戈", 63: "戶", 64: "手", 65: "支", 66: "攴",
        67: "文", 68: "斗", 69: "斤", 70: "方", 71: "无", 72: "日",
        73: "曰", 74: "月", 75: "木", 76: "欠", 77: "止", 78: "歹",
        79: "殳", 80: "毋", 81: "比", 82: "毛", 83: "氏", 84: "气",
        85: "水", 86: "火", 87: "爪", 88: "父", 89: "爻", 90: "爿",
        91: "片", 92: "牙", 93: "牛", 94: "犬", 95: "玄", 96: "玉",
        97: "瓜", 98: "瓦", 99: "甘", 100: "生", 101: "用", 102: "田",
        103: "疋", 104: "疒", 105: "癶", 106: "白", 107: "皮", 108: "皿",
        109: "目", 110: "矛", 111: "矢", 112: "石", 113: "示", 114: "禸",
        115: "禾", 116: "穴", 117: "立", 118: "竹", 119: "米", 120: "糸",
        121: "缶", 122: "网", 123: "羊", 124: "羽", 125: "老", 126: "而",
        127: "耒", 128: "耳", 129: "聿", 130: "肉", 131: "臣", 132: "自",
        133: "至", 134: "臼", 135: "舌", 136: "舛", 137: "舟", 138: "艮",
        139: "色", 140: "艸", 141: "虍", 142: "虫", 143: "血", 144: "行",
        145: "衣", 146: "襾", 147: "見", 148: "角", 149: "言", 150: "谷",
        151: "豆", 152: "豕", 153: "豸", 154: "貝", 155: "赤", 156: "走",
        157: "足", 158: "身", 159: "車", 160: "辛", 161: "辰", 162: "辵",
        163: "邑", 164: "酉", 165: "釆", 166: "里", 167: "金", 168: "長",
        169: "門", 170: "阜", 171: "隶", 172: "隹", 173: "雨", 174: "靑",
        175: "非", 176: "面", 177: "革", 178: "韋", 179: "韭", 180: "音",
        181: "頁", 182: "風", 183: "飛", 184: "食", 185: "首", 186: "香",
        187: "馬", 188: "骨", 189: "高", 190: "髟", 191: "鬥", 192: "鬯",
        193: "鬲", 194: "鬼", 195: "魚", 196: "鳥", 197: "鹵", 198: "鹿",
        199: "麥", 200: "麻", 201: "黃", 202: "黍", 203: "黑", 204: "黹",
        205: "黽", 206: "鼎", 207: "鼓", 208: "鼠", 209: "鼻", 210: "齊",
        211: "齒", 212: "龍", 213: "龜", 214: "龠",
    ]

    private var loaded = false

    private init() {}

    // MARK: - Loading

    /// Load decomposition and radical data from bundled resource files.
    func load(forceReload: Bool = false) {
        guard !loaded || forceReload else { return }

        loadDecompositionData()
        loadRadicalData()

        loaded = true
    }

    private func loadDecompositionData() {
        guard let path = findResourcePath(name: "cjk-decomp", ext: "txt") else {
            print("[DecompositionEngine] cjk-decomp.txt not found")
            return
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("[DecompositionEngine] Failed to read cjk-decomp.txt")
            return
        }

        var table: [String: [String]] = [:]
        table.reserveCapacity(90_000)

        for line in text.split(separator: "\n") {
            let s = String(line)
            guard !s.hasPrefix("#"), !s.isEmpty else { continue }
            guard let colonIdx = s.firstIndex(of: ":") else { continue }

            let key = String(s[s.startIndex..<colonIdx])
            let rest = String(s[s.index(after: colonIdx)...])

            let components = parseComponents(rest)
            if !components.isEmpty {
                table[key] = components
            }
        }

        rawComponents = table
        print("[DecompositionEngine] Loaded \(table.count) decomposition entries")
    }

    private func loadRadicalData() {
        guard let path = findResourcePath(name: "cjk-radicals", ext: "txt") else {
            print("[DecompositionEngine] cjk-radicals.txt not found")
            return
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("[DecompositionEngine] Failed to read cjk-radicals.txt")
            return
        }

        var table: [String: Int] = [:]
        table.reserveCapacity(20_000)

        for line in text.split(separator: "\n") {
            let s = String(line)
            guard !s.hasPrefix("#"), !s.isEmpty else { continue }
            let parts = s.split(separator: "\t")
            guard parts.count == 2,
                  let radNum = Int(parts[1]) else { continue }
            table[String(parts[0])] = radNum
        }

        radicalIndex = table
        print("[DecompositionEngine] Loaded \(table.count) radical entries")
    }

    // MARK: - Public API

    /// Returns the direct (non-recursive) Unicode character components of a character.
    /// Intermediate numeric IDs are resolved one level deep so the returned strings
    /// are all single Unicode scalars or well-known CJK component characters.
    ///
    /// Returns `nil` for non-CJK input or unknown characters.
    func decompose(_ character: Character) -> [String]? {
        guard isCJK(character) else { return nil }
        let key = String(character)
        guard let components = rawComponents[key], !components.isEmpty else { return nil }

        // Resolve any intermediate numeric IDs to their Unicode components
        var result: [String] = []
        for comp in components {
            if isNumericID(comp) {
                // Resolve one level: replace numeric ID with its own components
                if let subComponents = rawComponents[comp] {
                    for sub in subComponents where !isNumericID(sub) {
                        result.append(sub)
                    }
                }
            } else {
                result.append(comp)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Returns all leaf-level Unicode components by fully resolving the decomposition tree.
    /// Useful for finding all atomic radicals of a character.
    func decomposeRecursive(_ character: Character, maxDepth: Int = 8) -> [String]? {
        guard isCJK(character) else { return nil }
        let key = String(character)
        var visited = Set<String>()
        let leaves = resolveLeaves(key: key, depth: 0, maxDepth: maxDepth, visited: &visited)
        return leaves.isEmpty ? nil : leaves
    }

    /// Returns the Kangxi radical character for the given character.
    /// Uses the Unicode Unihan kRSUnicode data for BMP CJK ideographs.
    func radicalOf(_ character: Character) -> String? {
        guard isCJK(character) else { return nil }
        let hexKey = String(format: "%04X", character.unicodeScalars.first!.value)
        guard let radNum = radicalIndex[hexKey],
              let radChar = Self.kangxiRadicals[radNum] else {
            return nil
        }
        return String(radChar)
    }

    // MARK: - Private helpers

    /// Parse the type+components portion of a decomposition line.
    /// Input examples: "a(白,勺)", "d(37044,子)", "c", "lock(了,㇐)"
    private func parseComponents(_ rest: String) -> [String] {
        // Find opening paren
        guard let parenOpen = rest.firstIndex(of: "("),
              let parenClose = rest.lastIndex(of: ")") else {
            // No components (type "c" = component primitive)
            return []
        }

        let inner = String(rest[rest.index(after: parenOpen)..<parenClose])
        // Components are comma-separated; each is either a single Unicode character
        // or a 5-digit intermediate ID number.
        var components: [String] = []
        for part in inner.split(separator: ",") {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                components.append(trimmed)
            }
        }
        return components
    }

    private func resolveLeaves(key: String, depth: Int, maxDepth: Int, visited: inout Set<String>) -> [String] {
        guard depth < maxDepth, !visited.contains(key) else { return [] }
        visited.insert(key)

        guard let components = rawComponents[key], !components.isEmpty else {
            // Leaf: return the key itself if it's a Unicode char (not a numeric ID)
            if !isNumericID(key) {
                return [key]
            }
            return []
        }

        var leaves: [String] = []
        for comp in components {
            leaves.append(contentsOf: resolveLeaves(key: comp, depth: depth + 1, maxDepth: maxDepth, visited: &visited))
        }
        return leaves
    }

    private func isNumericID(_ s: String) -> Bool {
        s.count == 5 && s.allSatisfy(\.isNumber)
    }

    private func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let v = scalar.value
        // CJK Unified Ideographs + Extensions + Radicals + Strokes
        return (v >= 0x4E00 && v <= 0x9FFF)   // CJK Unified Ideographs
            || (v >= 0x3400 && v <= 0x4DBF)   // CJK Extension A
            || (v >= 0x2E80 && v <= 0x2EFF)   // CJK Radicals Supplement
            || (v >= 0x2F00 && v <= 0x2FD5)   // Kangxi Radicals
            || (v >= 0x31C0 && v <= 0x31EF)   // CJK Strokes
            || (v >= 0xF900 && v <= 0xFAFF)   // CJK Compatibility Ideographs
    }

    private func findResourcePath(name: String, ext: String) -> String? {
        let filename = "\(name).\(ext)"

        // SPM bundle resource
        if let url = Bundle.module_safe?.url(forResource: name, withExtension: ext, subdirectory: "Dictionary") {
            return url.path
        }
        // Main bundle
        if let path = Bundle.main.path(forResource: name, ofType: ext) {
            return path
        }

        let execDir = Bundle.main.bundlePath
        let candidates = [
            "\(execDir)/../Resources/Dictionary/\(filename)",
            "\(execDir)/Contents/Resources/Dictionary/\(filename)",
            "\(execDir)/../../Sources/Resources/Dictionary/\(filename)",
            "Sources/Resources/Dictionary/\(filename)",
            "Leo/Sources/Resources/Dictionary/\(filename)",
        ]
        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }
}
