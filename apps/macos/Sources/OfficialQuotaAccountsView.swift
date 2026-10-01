import SwiftUI
import LeaderboardCore

@MainActor
private final class OfficialAccountsForm: ObservableObject {
    @Published var providerID = "kimi"
    @Published var apiKey = ""
    @Published var busy = false
    @Published var failed = false
    @Published var accounts: [OfficialQuotaAccount] = []
}

struct OfficialQuotaAccountsView: View {
    @ObservedObject var state: AppState
    #if DEBUG
    var usesVisualFixture = false
    #endif
    @StateObject private var form = OfficialAccountsForm()
    @Environment(\.dismiss) private var dismiss
    private var language: AppLanguage { state.selectedLanguage }
    private func tr(_ en: String, _ zh: String) -> String { language.text(en, zh) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Add model", "添加模型")).font(.headline)
            Text(tr("CC Switch accounts appear automatically. You can also add an official API or plan key here.",
                    "CC Switch 中的账号会自动显示，也可以在这里添加官方 API 或套餐 Key。"))
                .font(.callout).foregroundStyle(.secondary)
            Picker(tr("Provider", "供应商"), selection: $form.providerID) {
                ForEach(LeaderboardQuotaProviders.keyProviders) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .disabled(form.busy)
            if let provider = LeaderboardQuotaProviders.keyProviders.first(where: { $0.id == form.providerID }) {
                Text(description(provider)).font(.caption).foregroundStyle(.secondary)
            }
            SecureField(tr("Official API / plan key", "官方 API / 套餐 Key"), text: $form.apiKey)
                .disabled(form.busy)
            if form.failed {
                Text(tr("Could not verify or save this account. Check the key, region and connection.",
                        "账号验证或保存失败，请检查 Key、地区和网络连接。"))
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button(form.busy ? tr("Checking…", "验证中…") : tr("Verify and add", "验证并添加")) {
                    form.busy = true; form.failed = false
                    Task {
                        let success = await state.addOfficialAccount(providerID: form.providerID,
                            label: "", apiKey: form.apiKey)
                        form.busy = false; form.failed = !success
                        if success {
                            form.apiKey = ""; form.accounts = state.officialAccounts()
                        }
                    }
                }
                .disabled(form.busy || form.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button(tr("Done", "完成")) { dismiss() }.disabled(form.busy)
            }
            if !form.accounts.isEmpty {
                Divider()
                Text(tr("Added accounts", "已添加的账号")).font(.subheadline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(form.accounts) { account in
                            HStack {
                                Text(account.target?.shortName ?? account.providerID)
                                Spacer()
                                Button(tr("Remove", "移除")) {
                                    form.failed = !state.removeOfficialAccount(id: account.id)
                                    form.accounts = state.officialAccounts()
                                }.disabled(form.busy)
                            }
                        }
                    }
                }.frame(maxHeight: 130)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Coverage and inclusion", "收录原则与范围")).fontWeight(.semibold)
                Text(tr("We prioritize official providers in the General, Coding, Image and Video Top 20 lists from Artificial Analysis and Arena.",
                        "优先接入 Artificial Analysis 与 Arena 的综合、编程、图片、视频 Top 20 榜单涉及的官方供应商。"))
                Text(tr("The menu offers supported official API balance, credits and plan quota queries. Products, plans and regions may have separate quotas; see the selected provider's description.",
                        "下拉列表仅提供已支持的官方 API 余额、Credits 和套餐额度查询。不同产品、套餐和地区可能有独立额度，请查看所选供应商的说明。"))
                Text(tr("Existing OpenAI, Claude, Gemini and Kimi official logins are detected locally. Accounts stay available when a provider leaves the rankings.",
                        "已有 OpenAI、Claude、Gemini、Kimi 官方登录会从本地配置自动识别；供应商跌出榜单不会移除已有账号。"))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(22).frame(width: 480)
        .onAppear {
            #if DEBUG
            if usesVisualFixture { form.accounts = []; return }
            #endif
            form.accounts = state.officialAccounts()
        }
    }

    private func description(_ provider: OfficialQuotaProvider) -> String {
        switch provider.kind {
        case .minimax: tr("Coding Plan quota; Hailuo video credits are separate.", "查询 Coding Plan 套餐额度；海螺视频额度另行计算。")
        case .luma: tr("Luma API balance; Dream Machine subscriptions are separate.", "查询 Luma API 余额；Dream Machine 网页订阅另行计算。")
        case .blackForestLabs: tr("Official API credits.", "查询官方 API Credits。")
        case .deepseek, .stepfun: tr("Official API account balance.", "查询官方 API 账户余额。")
        default: tr("Use the official Coding Plan key.", "请使用官方 Coding Plan 套餐 Key。")
        }
    }
}
