import Testing
import LeaderboardKit

@Test func everySelectableVariantExplainsItsWholeFamilyInAllLanguages() {
    for language in AppLanguage.allCases {
        for kind in LeaderboardKind.allCases {
            let help = LeaderboardVariantHelp.text(kind, language: language)
            if kind.mediaVariants.isEmpty {
                #expect(help.isEmpty)
            } else {
                #expect(LeaderboardPresentation.sourceHelp(kind, language: language, board: nil).contains(help + "\n\n"))
                #expect(help == LeaderboardVariantHelp.text(kind.mediaVariants[0], language: language))
                for option in kind.mediaVariants {
                    #expect(help.contains(option.mediaVariantTitle(language: language)))
                }
            }
        }
    }
}

@Test func speechOptionHelpDistinguishesVoicesDialogueAndTranscription() {
    let help = LeaderboardVariantHelp.text(.artificialAnalysisSpeechControlledVoice, language: .chinese)
    for phrase in ["各厂商提供", "克隆同一组参考声音", "不是情绪或语气控制能力", "实时语音交谈", "按批次", "边接收音频边返回", "不是按响应延迟排名"] {
        #expect(help.contains(phrase))
    }
    #expect(LeaderboardVariantHelp.text(.arenaMultiImageEditing, language: .chinese).contains("不是一次生成多张结果"))
}
