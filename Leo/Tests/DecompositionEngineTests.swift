import Testing
@testable import Leo

@Suite("DecompositionEngine Tests")
struct DecompositionEngineTests {

    private let engine: DecompositionEngine = {
        let e = DecompositionEngine.shared
        e.load()
        return e
    }()

    // MARK: - Decomposition

    @Test("学 decomposes to components including 子")
    func xueDecomposesIncludesZi() {
        let components = engine.decompose("学")

        #expect(components != nil)
        let flat = components!.joined()
        #expect(flat.contains("子"), "Expected 子 in components of 学, got: \(components!)")
    }

    @Test("好 decomposes to 女 and 子")
    func haoDecomposesToNuZi() {
        let components = engine.decompose("好")

        #expect(components != nil)
        #expect(components!.contains("女"), "Expected 女 in components of 好, got: \(components!)")
        #expect(components!.contains("子"), "Expected 子 in components of 好, got: \(components!)")
    }

    @Test("的 decomposes to 白 and 勺")
    func deDecomposesToBaiShao() {
        let components = engine.decompose("的")

        #expect(components != nil)
        #expect(components!.contains("白"), "Expected 白 in components of 的, got: \(components!)")
        #expect(components!.contains("勺"), "Expected 勺 in components of 的, got: \(components!)")
    }

    @Test("ASCII characters return nil")
    func asciiReturnsNil() {
        #expect(engine.decompose("A") == nil)
        #expect(engine.decompose("z") == nil)
        #expect(engine.decompose("1") == nil)
    }

    @Test("Empty-style input: space character returns nil")
    func spaceCharacterReturnsNil() {
        #expect(engine.decompose(" ") == nil)
    }

    @Test("一 decomposes to its stroke component ㇐")
    func primitiveCharacter() {
        // 一 (yī) decomposes to the CJK stroke ㇐ (horizontal stroke)
        // The dataset models 一 as me(㇐) — modified equivalent of the horizontal stroke
        let result = engine.decompose("一")
        #expect(result != nil, "Expected decomposition for 一")
        #expect(result!.contains("㇐"), "Expected stroke ㇐ in components of 一, got: \(result as Any)")
    }

    // MARK: - Recursive decomposition

    @Test("学 recursive decomposition resolves to stroke-level components")
    func xueRecursiveDecomposition() {
        // Fully recursive decomposition bottoms out at CJK strokes (㇒, ㇏, ㇑, etc.)
        // 学 → d(37044, 子) → 37044: d(⺍,冖) → strokes; 子 → lock(了,㇐) → strokes
        let leaves = engine.decomposeRecursive("学")

        #expect(leaves != nil, "Expected recursive decomposition for 学")
        #expect(!leaves!.isEmpty, "Expected non-empty recursive leaves for 学")
        // All leaves should be CJK stroke or radical characters (non-ASCII, non-numeric IDs)
        let allNonNumeric = leaves!.allSatisfy { $0.count <= 2 && !$0.allSatisfy(\.isNumber) }
        #expect(allNonNumeric, "All recursive leaves should be Unicode chars, got: \(leaves!)")
    }

    @Test("ASCII returns nil for recursive decomposition")
    func asciiRecursiveReturnsNil() {
        #expect(engine.decomposeRecursive("A") == nil)
    }

    // MARK: - Radical lookup

    @Test("好 has radical 女 (radical 38)")
    func haoRadical() {
        let radical = engine.radicalOf("好")
        #expect(radical == "女", "Expected radical 女 for 好, got: \(radical as Any)")
    }

    @Test("学 has radical 子 (radical 39)")
    func xueRadical() {
        let radical = engine.radicalOf("学")
        #expect(radical == "子", "Expected radical 子 for 学, got: \(radical as Any)")
    }

    @Test("女 has radical 女 (radical 38, is itself a radical)")
    func nuRadical() {
        let radical = engine.radicalOf("女")
        #expect(radical == "女", "Expected radical 女 for 女, got: \(radical as Any)")
    }

    @Test("ASCII returns nil for radical lookup")
    func asciiRadicalReturnsNil() {
        #expect(engine.radicalOf("A") == nil)
        #expect(engine.radicalOf("!") == nil)
    }

    @Test("Space returns nil for radical lookup")
    func spaceRadicalReturnsNil() {
        #expect(engine.radicalOf(" ") == nil)
    }
}
