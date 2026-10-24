# 腾讯 CloudBase 用量占比

## Current status: restored (2026-10-24)

At the user's explicit request, Tencent is restored in all active Usage and
About/source catalogs, and shared data acquisition is enabled again. Native
clients use the shared service; GET and refresh can initialize the same snapshot.
OSS atomic coordination permits one acquisition per day across all clients,
retains the last successful snapshot on failure, and allows a retry after ten
minutes. Client contributions remain disabled. Existing source selections and
cached data are retained. Tencent's own source notice remains distinct from CC BY.

The official page was rechecked on 2026-10-24: its cumulative token legend still
parses as nine published model families, with 99.8% listed share and 0.2% Other.
The public legend still omits full sample dates. This source shows “抽样统计”
rather than inventing a publication date. Its selected tab and source text use
Tencent Cloud's official blues; the shared palette is used by every client.

Official contacts verified on 2026-10-23:

- CloudBase contact page: https://cloud.tencent.com/document/product/876/59902
- Written support: https://cloud.tencent.com/online-service ; request referral
  to the CloudBase product team or data-use authorization owner and an explicit
  written human response.
- Official community: https://cnb.cool/tencent/cloud/cloudbase/community/-/issues
  (directly linked by the CloudBase contact page).
- Customer support: 4009100100 (24/7); sales extension 1 (weekdays 09:00-18:00).
  No public email specifically responsible for this leaderboard's data-use
  authorization was found. Unrelated business or historical personal addresses
  are not presented as authorization contacts.

Suggested inquiry: AI BenchGauge would display model names, rankings and token
shares from the official public page in a third-party application, fetching once
daily, caching on its server and attributing/linking to the source without
copying the chart or prose. Ask whether automated fetching, caching, public
display, image exports and commercial use are allowed, and what attribution,
frequency, license or other conditions apply. Request referral if the recipient
does not own those rights. The source notice does not assert an open-data license.

## Design before suspension

“用量”增加第三个独立来源 Tencent CloudBase。综合默认选择及原有偏好键不变，各端共享同一服务端快照。无需腾讯账号或 Key，不调用模型推理接口。

官方来源：https://docs.cloudbase.net/ai/announcement/model-token-volume

仅提取官方公开 HTML 中 Token 图表默认图例的累计占比事实，不执行来源 JavaScript，不复制图表、布局或整段说明。固定地址、有界响应、结构/口径/唯一性/数值/总和校验；页面结构不兼容时保留上次成功快照。服务端通过 OSS 原子协调每天抓取一次，失败十分钟后允许重试，客户端不能贡献数值。与 Vercel 不同，国内主函数直接访问腾讯文档，无需海外采集器。

口径为北京时间抽样统计日的文本输入与输出 Token 之和，包含缓存命中；来源已按模型系列汇总。默认图例的累计占比不等于各日占比的算术平均，也不等于最新一天。保留页面公开的一位小数，不把可见条目重新归一到 100%，Other 不作为模型展示；公司只汇总当前榜内系列。没有绝对 Token 量或总请求数，不生成 totalTokens。

当前公开页面显示 7 个统计日，未在面向用户的图例中给出完整统计日期。即使静态组件的内部数据带月日，也不能据此猜年份或认作最新数据。榜头显示“抽样统计”，不生成 sourceUpdatedAt，不把本次抓取时间伪装为发布时刻。来源不定期更新；即使本地抓取成功，也不能据此推断数据新鲜度。

模型身份只使用此来源作用域内的明确完整系列标签映射供应商及规范系列 ID，例如官方 Kimi-K3 对应 Moonshot AI 的 Kimi K3；K3、含 K3 的其他名称和不同版本不继承该映射。models.dev 仅匹配唯一、完全相同的规范完整 ID，不使用名称或日期移除来猜版本；未明确匹配时保留未知。开发者的国家信息继续遵循统一国家策略。

许可核查：2026-10-23 官方页面未声明开放数据许可证，文档站版权为腾讯所有，不能将 SDK 的 MIT/Apache 许可证或其他来源的 CC BY 4.0 套用于此数据。应用只作带原始来源链接的汇总事实展示，不声称获得腾讯开放数据授权或认可。关于页提供独立“来源说明”，不标为 CC BY 4.0、不附带 CC 全文；导出保留来源说明。扩大转载范围前需另行确认腾讯的适用授权条件。

忽略目录 work/tencent-usage/ 保存此次公开响应、解析结果、部署日志、回归和原生截图证据。当前快照为 9 个模型系列，占比 99.8%，Other 为 0.2%；这些数字不写死在业务中。
