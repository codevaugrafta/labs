import Testing
import SwiftData
@testable import Leo

@Suite("FamiliarityTracker Tests")
struct FamiliarityTrackerTests {

    @MainActor
    private func makeTracker() throws -> (FamiliarityTracker, ModelContext) {
        let schema = Schema([VocabularyEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let tracker = FamiliarityTracker(modelContext: context)
        return (tracker, context)
    }

    @Test("Unknown words start as .unknown")
    @MainActor
    func unknownByDefault() throws {
        let (tracker, _) = try makeTracker()
        #expect(tracker.state(for: "你好") == .unknown)
    }

    @Test("First encounter transitions Unknown → Seen")
    @MainActor
    func encounterPromotes() throws {
        let (tracker, _) = try makeTracker()
        tracker.recordEncounter("你好")
        #expect(tracker.state(for: "你好") == .seen)
    }

    @Test("Multiple encounters don't promote past Seen")
    @MainActor
    func encountersCapped() throws {
        let (tracker, _) = try makeTracker()
        for _ in 0..<20 {
            tracker.recordEncounter("你好")
        }
        #expect(tracker.state(for: "你好") == .seen)
    }

    @Test("Mark as known jumps to .known from any state")
    @MainActor
    func markAsKnown() throws {
        let (tracker, _) = try makeTracker()
        tracker.recordEncounter("你好") // Now .seen
        tracker.markAsKnown("你好")
        #expect(tracker.state(for: "你好") == .known)
    }

    @Test("Mark as known works from .unknown")
    @MainActor
    func markAsKnownFromUnknown() throws {
        let (tracker, _) = try makeTracker()
        tracker.markAsKnown("你好")
        #expect(tracker.state(for: "你好") == .known)
    }

    @Test("Mark as learning promotes correctly")
    @MainActor
    func markAsLearning() throws {
        let (tracker, _) = try makeTracker()
        tracker.recordEncounter("你好") // .seen
        tracker.markAsLearning("你好")
        #expect(tracker.state(for: "你好") == .learning)
    }

    @Test("Learning doesn't demote known")
    @MainActor
    func learningDoesntDemote() throws {
        let (tracker, _) = try makeTracker()
        tracker.markAsKnown("你好")
        tracker.markAsLearning("你好") // Should NOT demote from .known
        #expect(tracker.state(for: "你好") == .known)
    }

    @Test("States are monotonically increasing (no backward movement)")
    @MainActor
    func monotonic() throws {
        let (tracker, _) = try makeTracker()
        tracker.recordEncounter("学生")           // .seen
        tracker.markAsLearning("学生")            // .learning
        tracker.promoteToFamiliar("学生")         // .familiar
        tracker.promoteToKnown("学生")            // .known

        // Now try to go backward via encounters — should stay at .known
        tracker.recordEncounter("学生")
        #expect(tracker.state(for: "学生") == .known)
    }

    @Test("Explicit reset can move state backward")
    @MainActor
    func explicitReset() throws {
        let (tracker, _) = try makeTracker()
        tracker.markAsKnown("学生")
        tracker.resetState("学生", to: .unknown)
        #expect(tracker.state(for: "学生") == .unknown)
    }

    @Test("Batch states lookup")
    @MainActor
    func batchStates() throws {
        let (tracker, _) = try makeTracker()
        tracker.recordEncounter("你好")
        tracker.markAsKnown("世界")

        let states = tracker.states(for: ["你好", "世界", "未知"])
        #expect(states["你好"] == .seen)
        #expect(states["世界"] == .known)
        #expect(states["未知"] == .unknown)
    }

    @Test("Comprehension score calculation")
    @MainActor
    func comprehensionScore() throws {
        let (tracker, _) = try makeTracker()
        tracker.markAsKnown("我")
        tracker.markAsKnown("是")
        tracker.promoteToFamiliar("学生") // Need to get to familiar first
        // Actually need to go through states
        tracker.recordEncounter("学生")
        tracker.markAsLearning("学生")
        tracker.promoteToFamiliar("学生")

        // 我(known) + 是(known) + 学生(familiar) = 3 comprehended / 4 total
        let score = tracker.comprehensionScore(for: ["我", "是", "学生", "不知道"])
        #expect(score == 0.75)
    }

    @Test("Comprehension score is 0 for all unknown words")
    @MainActor
    func comprehensionAllUnknown() throws {
        let (tracker, _) = try makeTracker()
        let score = tracker.comprehensionScore(for: ["一", "二", "三"])
        #expect(score == 0.0)
    }

    @Test("Comprehension score is 1 for all known words")
    @MainActor
    func comprehensionAllKnown() throws {
        let (tracker, _) = try makeTracker()
        tracker.markAsKnown("一")
        tracker.markAsKnown("二")
        tracker.markAsKnown("三")
        let score = tracker.comprehensionScore(for: ["一", "二", "三"])
        #expect(score == 1.0)
    }

    @Test("Encounter count increments")
    @MainActor
    func encounterCount() throws {
        let (tracker, context) = try makeTracker()
        tracker.recordEncounter("你好")
        tracker.recordEncounter("你好")
        tracker.recordEncounter("你好")

        let descriptor = FetchDescriptor<VocabularyEntry>()
        let entries = try context.fetch(descriptor)
        let entry = entries.first { $0.text == "你好" }
        #expect(entry?.encounterCount == 3)
    }

    @Test("FamiliarityState ordering is correct")
    func stateOrdering() {
        #expect(FamiliarityState.unknown < .seen)
        #expect(FamiliarityState.seen < .learning)
        #expect(FamiliarityState.learning < .familiar)
        #expect(FamiliarityState.familiar < .known)
    }
}
