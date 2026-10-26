# OpenRouter 用量排行

核实日期：2026-10-23。

同日全量核对当前保存的 50 个模型：原有 6 行缺少源码分类，3 行缺少国家。共享规则按完整永久 ID 补充 MiniMax M3.1 Flash 免费版（权重尚未发布，闭源）、Muse Spark 1.3 Contributor（闭源）、Jev 1.13 / 1.14（闭源）、Dots3-Note Preview 免费版（开放权重）和 GPT-6 Luna Pro（闭源）；TypeSafe 国家为美国，Dots Studio 为中国。依据 URL、核实日期和版本说明保存在 `fc/leaderboard-policy.json` 与 `fc/country-catalog.json`。这些规则在缓存读取和新快照保存时生效，不修改排名、用量或统计时间；明确的上游分类优先，未核实的其他版本不套用。核对记录保存在 `work/openrouter-repair/coverage-*.json`。

补充规则已部署并写入线上保存快照。GET / POST 刷新实测 HTTP 200，国家覆盖 50/50，源码分类为开放权重 25、闭源 25，无缺失；小程序归一化与筛选结果一致，原排名及整数用量不变。61 项相关 Node 回归测试通过，生成的原生共享策略与目录一致。

底部“用量”中以 OpenRouter 和 Vercel AI Gateway 切换数据来源；本文描述 OpenRouter，Vercel 的百分比口径见 vercel-usage.md。统计最近一个完整 UTC 日的公开模型输入与输出 token 总量，并非请求次数、用户数、能力评分或整个 AI 市场份额。展示当日前 50 个公开模型；`other` 是榜外模型的聚合量，不作为模型参赛。免费及其他 `:variant` 后缀按来源独立保留。不同供应商的 tokenizer 不同，用量比较仅作规模参考。私有模型、私有端点和零数据留存流量不在数据范围内。

“源码”列沿用现有 models.dev 开放权重分类。用量 Data API 的 `model_permaslug` 与 models.dev 的 OpenRouter 端点 ID 格式不同；采集时另读固定的 [官方模型目录](https://openrouter.ai/docs/api/api-reference/models/get-models)，根据每条明确的 `canonical_slug` / `id` 对应关系保存 `openRouterModelID`，再限定到 models.dev 的 `openrouter` 供应商 offer 匹配。保留榜单完整永久标识、日期、排名及整数用量；目录行未将变体写入 canonical slug 时，仅补回该行 ID 中明确的变体。不同版本、日期和免费/批量等变体不会通过删后缀、名称子串或厂商整体推断关联。动态别名、冲突对应或未收录模型保留未知；目录下载、格式校验失败不影响已经验证的用量榜单。

数据接口为 `GET https://openrouter.ai/api/v1/datasets/rankings-daily`，明确传入相同的 `start_date` 和 `end_date`。不累加每日前 50 名来伪造一周榜单。原始 `total_tokens` 十进制字符串及 `meta` 块保存在共享快照；客户端展示单位 B（十亿 token），并保留完整模型标识，不根据局部名称猜归属。公司用量仅汇总筛选后、榜内模型的用量，不声称是平台上该公司的全部用量。模型数量分布仍按模型数统计。

## 授权核实

[官方 Data API 文档](https://openrouter.ai/docs/cookbook/administration/data-api)明确将这些端点返回的聚合数据以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 授权，允许署名后的复制、再分发、改编和商业使用。该授权不包括个人、客户级用量或未由这些端点发布的数据。应用保留来源指定的引用行 `Source: OpenRouter (openrouter.ai/rankings), as of <meta.as_of>.`、`Licensed under CC BY 4.0.`、许可链接、统计日、变更说明及原始 `meta`。离线快照、帮助及图片导出保留这些信息。

榜单正文只展示简洁的来源入口，不在展开按钮下或表格旁常显英文原始说明。小程序和 iOS 的“关于 → OpenRouter → CC BY 4.0”弹窗展示当前缓存的完整来源署名、统计口径和本地化协议；没有缓存时仍可离线查看来源及完整协议，不伪造统计时间。Mac 在“开源声明”内点击 OpenRouter 协议展开查看。原始说明继续随快照缓存并保留在图片导出中。

官方限定用途为分析、报道及可视化，不应把数据重新托管为竞争性的免费数据 API。本接入仅用于应用榜单展示，不提供原始数据集镜像或任意日期查询服务。[服务条款](https://openrouter.ai/terms)另有自动抓取限制；本功能仅使用明确许可的官方 API，不抓取排行榜 HTML，也不绕过访问限制。

因此，按上述范围、署名与用途要求展示这份官方聚合数据有明确许可依据；不能把它扩大解释为 OpenRouter 站内所有内容均可自由使用。

## 配置和缓存

将 `OPENROUTER_API_KEY` 配置到共享函数的服务端环境变量，再部署包含 `fc/openrouter-usage.mjs` 的后端。也可在运行部署脚本的环境中设置该变量；脚本会保留线上已存在的 Key。不要将 Key 放入客户端、仓库、截图或聊天。没有 Key 时不访问上游、不发放客户端抓取资格，返回 `configurationRequired: true`，应用显示“数据源待配置”。后续有 Key 后刷新即可工作。

深圳 FC 直连 OpenRouter 会超时。生产环境复用现有的新加坡采集函数，经固定的 `/v1/openrouter-usage` 路由访问官方 Data API。主函数校验采集器 HTTPS 地址并携带采集令牌，将 OpenRouter Key 放在该请求的认证头内；采集器仅在请求内存中使用它，不持久化、输出到日志或放入返回值，Key 仍只需配置在主函数。采集器拒绝任意 URL、缺失认证、其他方法及查询参数，按 Key 的摘要和完整 UTC 统计日隔离缓存；主函数重新校验 token 整数、模型标识、日期和原始 meta 并生成许可署名。不配置采集器的部署继续直连官方 API。

官方限额为每 Key 每分钟 30 次、每账号每天 500 次；本应用通过 OSS 原子协调最多每小时尝试一次（每整天约 24 次），所有用户共享。失败保持最后一份有效快照，不清空缓存，不自动高频重试。不记录上游错误正文或认证头。服务端拒绝客户端对该榜单贡献 HTML/自填分数。

自动化测试使用明确的合成 fixture，不会将其发布成真实榜单。2026-10-23 用户配置 Key 后，真实连通性检查确认深圳 FC 超时、新加坡 FC 返回 HTTP 200（51 行含 other，50 个模型）；临时诊断函数均已删除。修复与线上验证记录保存在忽略目录 `work/openrouter-repair/`。

2026-10-23 修复已部署。共享接口实测 HTTP 200、50 个真实模型，重复读取保持相同快照；来源 meta、十进制 token 和 CC BY 署名完整。小程序数据校验器接受全部 50 行；新加坡采集路由未认证访问返回 403。一次性通过追加协调记录解除失败初始化的等待，没有删除历史协调日志或其他榜单。原 Artificial Analysis 读取仍为 HTTP 200。部署前 105 项后端回归通过。
应用使用的 POST 刷新接口也已实测 HTTP 200、50 条模型数据。原生客户端读取检查因项目自动构建占用锁而未执行，未中断现有构建；不据此宣称原生界面已验证。
