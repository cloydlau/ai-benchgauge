import Foundation
import LeaderboardCore
import Testing

struct SpeechVariantsTests {
    private func page(_ rows: [[String: Any]]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["results": rows])
        let escaped = try JSONSerialization.data(withJSONObject: [String(decoding: payload, as: UTF8.self)])
        return "<script>self.__next_f.push([1,\(String(decoding: escaped, as: UTF8.self).dropFirst().dropLast())])</script>"
    }
    @Test func selectsOverallSpeechAgentSlice() throws {
        func rows(_ slice: String) -> [[String: Any]] {
            (1...20).map { ["id": "\(slice)-\($0)", "name": "\(slice) \($0)", "stsHostModelId": NSNull(),
                "sliceKey": slice, "rank": $0, "elo": 1200.0 - Double($0), "creatorName": "Maker"] }
        }
        let board = try HTMLLeaderboardParser.artificialAnalysisSpeechAgent(fromHTML: page(rows("agentic") + rows("overall") + rows("non_agentic")))
        #expect(board.kind == .artificialAnalysisSpeechAgent)
        #expect(board.entries.count == 20)
        #expect(board.entries.first?.name == "overall 1")
        #expect(throws: (any Error).self) { try HTMLLeaderboardParser.artificialAnalysisSpeechAgent(fromHTML: page(Array(rows("overall").dropLast()))) }
    }
    @Test func categoryKeepsThreeDistinctSpeechTasks() {
        #expect(LeaderboardCategory.speech.boardKinds == [.artificialAnalysisSpeechProviderVoice])
        #expect(LeaderboardKind.artificialAnalysisSpeechAgent.mediaVariants == [.artificialAnalysisSpeechProviderVoice, .artificialAnalysisSpeechControlledVoice, .artificialAnalysisSpeechAgent, .artificialAnalysisSpeechToText, .artificialAnalysisSpeechToTextStreaming])
        #expect(!LeaderboardKind.artificialAnalysisSpeechProviderVoice.supportsAACost)
    }
    @Test func speechToTextRanksLowerErrorsFirst() throws {
        for (kind, key) in [(LeaderboardKind.artificialAnalysisSpeechToText, "aaWerIndex"), (.artificialAnalysisSpeechToTextStreaming, "aaWerStreamingIndex")] {
            let rows: [[String: Any]] = (1...20).map { rank in
                ["id": "id-\(rank)", "displayName": "Model \(rank)", "host": ["name": rank == 20 ? "Google" : "OpenAI"], "model": ["openWeights": true], key: Double(21 - rank) / 100]
            }
            let board = try HTMLLeaderboardParser.artificialAnalysisSpeechToText(fromHTML: page(rows), kind: kind)
            #expect(board.entries.first?.name == "Model 20")
            #expect(board.entries.first?.score == 1)
            #expect(LeaderboardPresentation.scoreText(1.25, kind: kind) == "1.25%")
            #expect(LeaderboardPresentation.scoreTitle(kind, language: .english) == "WER ↓")
            let companies = LeaderboardPresentation.companies(board, filter: .all)
            #expect(companies.first?.entry.name == "Google")
            #expect(companies.last?.entry.score == 2)
        }
    }
    @Test func providerAndControlledVoicesKeepPrimaryRanking() throws {
        let primary: [[String: Any]] = (1...20).map { rank in
            ["formatted": ["rank": rank], "values": ["id": "id-\(rank)", "name": "Model \(rank)", "elo": Double(1200 - rank)]]
        }
        let later: [[String: Any]] = [["formatted": ["rank": 1], "values": ["id": "other", "name": "Other", "elo": 2000.0]]]
        for kind in [LeaderboardKind.artificialAnalysisSpeechProviderVoice, .artificialAnalysisSpeechControlledVoice] {
            let board = try HTMLLeaderboardParser.artificialAnalysisMediaVariant(fromHTML: page(primary + later), kind: kind)
            #expect(board.entries.count == 20)
            #expect(board.entries.first?.name == "Model 1")
            #expect(board.entries.first?.taskCostUSD == nil)
        }
    }
}
