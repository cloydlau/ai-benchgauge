import LeaderboardCore
import XCTest

final class ModelMatcherTests: XCTestCase {
    func testMatchesEquivalentModelVariantsAcrossLeaderboards() {
        let pairs = [
            (
                "Claude Fable 5.1 (Adaptive Reasoning, Max Effort, Default Fallback)",
                "claude-fable-5.1-max"
            ),
            (
                "GPT-6 Astra (xhigh)",
                "gpt-6-astra-xhigh"
            ),
            (
                "Muse Spark 1.3 (max)",
                "muse-spark-1.3-max"
            ),
            (
                "Qwen3.8 Max (0902)",
                "qwen3.8-max-0902"
            )
        ]

        for pair in pairs {
            XCTAssertEqual(
                ModelMatcher.canonicalModelID(from: pair.0),
                ModelMatcher.canonicalModelID(from: pair.1)
            )
        }
    }

    func testDoesNotMergeDifferentModelVersionsOrEfforts() {
        XCTAssertNotEqual(
            ModelMatcher.canonicalModelID(from: "Gemini 3.8 Flash (high)"),
            ModelMatcher.canonicalModelID(from: "gemini-3.7-flash-high")
        )
        XCTAssertNotEqual(
            ModelMatcher.canonicalModelID(from: "GPT-6 Astra (max)"),
            ModelMatcher.canonicalModelID(from: "gpt-6-astra-high")
        )
    }
}
