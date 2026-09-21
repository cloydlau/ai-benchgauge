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
    public static func links(forOrganization organization: String?) -> PurchaseLinks {
        switch normalizedOrganization(organization ?? "") {
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
                codingPlan: [],
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
                codingPlan: [],
                payAsYouGo: [link("DeepSeek API", "https://platform.deepseek.com/top_up")]
            )
        case "tencent":
            return PurchaseLinks(
                codingPlan: [],
                payAsYouGo: [
                    link("中国大陆", "https://cloud.tencent.com/product/tclm"),
                    link("国际站", "https://www.tencentcloud.com/products/hunyuan")
                ]
            )
        default:
            return PurchaseLinks()
        }
    }

    private static func link(_ label: String, _ urlString: String) -> PurchaseLink {
        guard let url = URL(string: urlString) else {
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
        case "moonshot":
            return "kimi"
        case "zai":
            return "zai"
        default:
            return words
        }
    }
}
