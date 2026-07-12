import XCTest
@testable import Flotis

final class TranscriptAssemblyTests: XCTestCase {
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
