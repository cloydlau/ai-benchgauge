import Foundation

public struct PurchaseLink: Identifiable, Hashable, Sendable {
    public let label: String
    public let url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }

    public var id: String { "\(label)|\(url.absoluteString)" }
}

public struct PurchaseLinks: Hashable, Sendable {
    public let codingPlan: [PurchaseLink]
    public let payAsYouGo: [PurchaseLink]

    public init(codingPlan: [PurchaseLink] = [], payAsYouGo: [PurchaseLink] = []) {
        self.codingPlan = codingPlan
        self.payAsYouGo = payAsYouGo
    }

    public var isEmpty: Bool {
        codingPlan.isEmpty && payAsYouGo.isEmpty
    }
}

public enum PurchaseLinkCatalog {
    /// Resolves purchase pages for a leaderboard row.
    /// `modelName` is only used when the source omits `organization` (Devin).
    public static func links(forOrganization organization: String?, modelName: String? = nil) -> PurchaseLinks {
        links(forKey: resolvedKey(organization: organization, modelName: modelName))
    }

    private static func resolvedKey(organization: String?, modelName: String?) -> String {
        let organizationKey = normalizedOrganization(organization ?? "")
        if !organizationKey.isEmpty {
            return organizationKey
        }
        return inferredKey(from: modelName ?? "")
    }

    /// Devin rows on the coding-agent board have no organization.
    private static func inferredKey(from modelName: String) -> String {
        let normalized = normalizedOrganization(modelName)
        if normalized.hasPrefix("devin") {
            return "devin"
        }
        return ""
    }

    private static func links(forKey key: String) -> PurchaseLinks {
        switch key {
        case "anthropic":
            return PurchaseLinks(
                codingPlan: [link("Claude", "https://claude.com/pricing")],
                payAsYouGo: [link("Anthropic API", "https://platform.claude.com/settings/billing")]
            )
        case "openai":
            return PurchaseLinks(
                codingPlan: [link("ChatGPT / Codex", "https://chatgpt.com/pricing")],
                payAsYouGo: [link("OpenAI API", "https://platform.openai.com/settings/organization/billing/overview")]
            )
        case "alibaba":
            return PurchaseLinks(
                codingPlan: [
                    link("中国大陆", "https://www.qianwenai.com/benefits/tokenplan"),
                    link("国际站", "https://www.qwencloud.com/pricing/token-plan")
                ],
                payAsYouGo: [
                    link("中国大陆", "https://help.aliyun.com/zh/model-studio/model-pricing"),
                    link("国际站", "https://www.alibabacloud.com/en/product/modelstudio")
                ]
            )
        case "zai":
            return PurchaseLinks(
                codingPlan: [
                    link("中国大陆", "https://bigmodel.cn/glm-coding"),
                    link("国际站", "https://z.ai/subscribe")
                ],
                payAsYouGo: [
                    link("中国大陆", "https://open.bigmodel.cn/pricing"),
                    link("国际站", "https://z.ai/pricing")
                ]
            )
        case "meta":
            return PurchaseLinks(
                codingPlan: [link("Muse Code", "https://ai.meta.com/muse/")],
                payAsYouGo: [link("Meta API", "https://dev.meta.ai/pricing")]
            )
        case "spacexai":
            return PurchaseLinks(
                codingPlan: [link("Grok", "https://grok.com/plans")],
                payAsYouGo: [link("xAI API", "https://console.x.ai/team/billing")]
            )
        case "stepfun":
            return PurchaseLinks(
                codingPlan: [link("Step Plan", "https://platform.stepfun.ai/step-plan")],
                payAsYouGo: [link("StepFun API", "https://platform.stepfun.ai/interface-key")]
            )
        case "kimi":
            return PurchaseLinks(
                codingPlan: [link("Kimi Code", "https://www.kimi.com/code")],
                payAsYouGo: [link("Kimi API", "https://platform.kimi.com/console/pay")]
            )
        case "google":
            return PurchaseLinks(
                codingPlan: [link("Gemini Code Assist", "https://codeassist.google/")],
                payAsYouGo: [link("Gemini API", "https://ai.google.dev/gemini-api/docs/pricing")]
            )
        case "deepseek":
            return PurchaseLinks(
                payAsYouGo: [link("DeepSeek API", "https://platform.deepseek.com/top_up")]
            )
        case "tencent":
            return PurchaseLinks(
                codingPlan: [
                    link("中国大陆 · 混元", "https://console.cloud.tencent.com/tokenhub/tokenplan/hy"),
                    link("中国大陆 · 通用", "https://console.cloud.tencent.com/tokenhub/tokenplan/common"),
                    link("国际站", "https://console.tencentcloud.com/tokenhub/tokenplan/common")
                ],
                payAsYouGo: [
                    link("中国大陆", "https://cloud.tencent.com/product/tclm"),
                    link("国际站", "https://www.tencentcloud.com/products/hunyuan")
                ]
            )
        case "minimax":
            return PurchaseLinks(
                codingPlan: [
                    link("中国大陆", "https://hailuoai.com/subscribe"),
                    link("国际站", "https://hailuoai.video/subscribe")
                ],
                payAsYouGo: [
                    link("中国大陆", "https://platform.minimaxi.com/docs/guides/pricing"),
                    link("国际站", "https://platform.minimax.io/docs/guides/pricing")
                ]
            )
        case "klingai":
            return PurchaseLinks(
                codingPlan: [
                    link("中国大陆", "https://klingai.com/app/membership/membership-plan"),
                    link("国际站", "https://app.klingai.com/global/membership/membership-plan")
                ],
                payAsYouGo: [
                    link("中国大陆", "https://klingai.com/dev/pricing"),
                    link("国际站", "https://klingai.com/global/dev/pricing")
                ]
            )
        case "bytedance":
            return PurchaseLinks(
                codingPlan: [
                    link("中国大陆", "https://jimeng.jianying.com/ai-tool/home"),
                    link("国际站", "https://dreamina.capcut.com/pricing/dreamina-price")
                ],
                payAsYouGo: [
                    link("中国大陆", "https://www.volcengine.com/docs/82379/1544106"),
                    link("国际站", "https://docs.byteplus.com/en/docs/modelark/1544106")
                ]
            )
        case "xiaomi":
            return PurchaseLinks(
                codingPlan: [
                    link("中国大陆", "https://mimo.mi.com/docs/zh-CN/price/token-plan"),
                    link("国际站", "https://mimo.mi.com/docs/en-US/price/token-plan")
                ],
                payAsYouGo: [
                    link("中国大陆", "https://mimo.mi.com/docs/zh-CN/price/pay-as-you-go"),
                    link("国际站", "https://mimo.mi.com/docs/en-US/price/pay-as-you-go")
                ]
            )
        case "krea":
            return PurchaseLinks(
                codingPlan: [link("Krea", "https://www.krea.ai/pricing")],
                payAsYouGo: [link("Krea API", "https://www.krea.ai/app/api/pricing")]
            )
        case "ideogram":
            return PurchaseLinks(
                codingPlan: [link("Ideogram", "https://ideogram.ai/pricing/")],
                payAsYouGo: [link("Ideogram API", "https://ideogram.ai/features/api-pricing")]
            )
        case "runway":
            return PurchaseLinks(
                codingPlan: [link("Runway", "https://runway.com/pricing")],
                payAsYouGo: [link("Runway API", "https://docs.dev.runwayml.com/guides/pricing")]
            )
        case "luma":
            return PurchaseLinks(
                codingPlan: [link("Luma", "https://lumalabs.ai/pricing")],
                payAsYouGo: [link("Luma API", "https://docs.agents.lumalabs.ai/guides/pricing/")]
            )
        case "blackforestlabs":
            return PurchaseLinks(
                payAsYouGo: [link("BFL API", "https://bfl.ai/pricing")]
            )
        case "fal":
            return PurchaseLinks(
                payAsYouGo: [link("fal API", "https://fal.ai/pricing")]
            )
        case "pixverse":
            return PurchaseLinks(
                codingPlan: [link("PixVerse", "https://app.pixverse.ai/subscribe")],
                payAsYouGo: [link("PixVerse API", "https://platform.pixverse.ai/billing")]
            )
        case "devin":
            return PurchaseLinks(
                codingPlan: [link("Devin", "https://devin.ai/pricing")],
                payAsYouGo: [link("Devin API", "https://app.devin.ai/settings/plans")]
            )
        case "opencode":
            return PurchaseLinks(
                payAsYouGo: [link("OpenCode Zen", "https://opencode.ai/zen")]
            )
        case "microsoftai":
            return PurchaseLinks(
                payAsYouGo: [link("Azure AI Foundry", "https://azure.microsoft.com/en-us/pricing/details/ai-foundry-models/microsoft/")]
            )
        default:
            // Reve stopped selling. Bach (Video Rebirth) has a membership, but no stable public pricing URL.
            return PurchaseLinks()
        }
    }

    private static func link(_ label: String, _ urlString: String) -> PurchaseLink {
        guard let url = URL(string: urlString), urlString.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            preconditionFailure("Invalid static purchase URL: \(urlString)")
        }
        return PurchaseLink(label: label, url: url)
    }

    private static func normalizedOrganization(_ organization: String) -> String {
        let words = organization
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()

        switch words {
        case "moonshot", "moonshotai":
            return "kimi"
        case "xai":
            return "spacexai"
        case "bytedanceseed":
            return "bytedance"
        case "lumaai", "lumalabs":
            return "luma"
        case "alibabaath", "qwen":
            return "alibaba"
        case "zai":
            return "zai"
        default:
            return words
        }
    }
}
