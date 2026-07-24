import XCTest
@testable import Flotis

final class TranscriptAssemblyTests: XCTestCase {
    func testAppleAccumulatorKeepsUsefulPartialWhenFinalIsEmpty() {
        var accumulator = AppleTranscriptAccumulator()
        XCTAssertEqual(
            accumulator.apply("你好", startTime: 0.2, endTime: 0.8),
            "你好"
        )
        XCTAssertEqual(
            accumulator.apply("", startTime: nil, endTime: nil),
            "你好"
        )
    }

    func testAppleAccumulatorPreservesSegmentsSeparatedBySilence() {
        var accumulator = AppleTranscriptAccumulator()
        _ = accumulator.apply("hello", startTime: 0.2, endTime: 0.8)
        XCTAssertEqual(
            accumulator.apply("world", startTime: 4.5, endTime: 5.0),
            "hello world"
        )
    }

    func testAppleAccumulatorReplacesOverlappingHypothesisWithoutDuplication() {
        var accumulator = AppleTranscriptAccumulator()
        _ = accumulator.apply("你号", startTime: 0.2, endTime: 0.8)
        XCTAssertEqual(
            accumulator.apply("你好", startTime: 0.2, endTime: 0.9),
            "你好"
        )
    }

    func testAppleAccumulatorKeepsAdjacentTimedSegments() {
        var accumulator = AppleTranscriptAccumulator()
        _ = accumulator.apply("one", startTime: 0.2, endTime: 0.8)
        XCTAssertEqual(
            accumulator.apply("two", startTime: 0.8, endTime: 1.2),
            "one two"
        )
    }

    func testOpenAIAssemblerUsesConversationOrderWhenCompletionsArriveOutOfOrder() {
        var assembler = OpenAITranscriptAssembler()

        assembler.recordItem("item-2", previousItemID: "item-1")
        _ = assembler.applyCompletion(
            itemID: "item-2",
            contentIndex: 0,
            transcript: "第二句。"
        )
        assembler.recordItem("item-1", previousItemID: nil)
        _ = assembler.applyCompletion(
            itemID: "item-1",
            contentIndex: 0,
            transcript: "第一句。"
        )

        XCTAssertEqual(assembler.transcript, "第一句。第二句。")
        XCTAssertEqual(assembler.completedItemIDs, Set(["item-1", "item-2"]))
    }

    func testOpenAIAssemblerReplacesPartialWithFinalPerContentIndex() {
        var assembler = OpenAITranscriptAssembler()
        _ = assembler.applyDelta(itemID: "item-1", contentIndex: 0, delta: "hel")
        _ = assembler.applyDelta(itemID: "item-1", contentIndex: 0, delta: "lo")
        XCTAssertEqual(assembler.transcript, "hello")

        _ = assembler.applyCompletion(
            itemID: "item-1",
            contentIndex: 0,
            transcript: "Hello!"
        )
        XCTAssertEqual(assembler.transcript, "Hello!")
    }

    func testDashScopeAssemblerPreservesLegitimateRepeatedSentence() {
        let once = appendDashScopeSegment("好的。", to: "")
        let twice = appendDashScopeSegment("好的。", to: once)
        XCTAssertEqual(twice, "好的。好的。")
    }

    func testTranscriptSpacingOnlyTargetsASCIIWords() {
        XCTAssertEqual(appendTranscriptSegment("world", to: "hello"), "hello world")
        XCTAssertEqual(appendTranscriptSegment("世界", to: "你好"), "你好世界")
    }
}
