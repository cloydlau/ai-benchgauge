# Vercel AI Gateway 用量占比

“用量”分类同时提供 OpenRouter 与 Vercel AI Gateway；保留综合默认选择和既有偏好键。Vercel 使用公开数据导出，不配置 Key，也不调用收费模型推理 API。

官方资料：
- https://vercel.com/docs/ai-gateway/leaderboards
- https://vercel.com/changelog/open-data-and-shareable-charts-for-ai-gateway-leaderboards
- https://vercel.com/ai-gateway/leaderboards/about

固定 GET 数据接口为 `https://vercel.com/api/ai/leaderboard-export?dataset=models&modality=text`。只取 `group=model, modality=text, metric=tokens` 的最近完整 UTC 日，保留真实统计日，排除当日尚未结束的数据。各端显示 UTC 统计日，不把日期零点伪装为官方发布时刻，也不随用户时区移到前一天。官方缓存 24 小时，全应用通过 OSS 原子协调每天采集一次；失败保留旧快照，十分钟后可重新尝试。深圳主函数通过现有新加坡采集器的认证固定路由 `/v1/vercel-usage` 获取数据，客户端只访问共享函数。GET 和 POST refresh 都可初始化共享快照，禁止客户端贡献 HTML 或自行填写数值。

数据是全平台文本 token 用量百分比，包括输入、输出、推理及缓存 token；不提供绝对 token 或请求数，不能与 OpenRouter 输入/输出 token 绝对量直接互比。仅展示官方公布的模型桶，不将 Other 当作模型，不把可见模型重新归一到 100%，不累计不同日期百分比。公司占比只汇总当前榜内模型；国家/源码分布仍按模型数量统计。

模型名称仅通过公开 `https://ai-gateway.vercel.sh/v1/models` 目录中唯一、完全相同的名称连接完整供应商/model ID，再连接 models.dev 的 vercel offer。保留版本和日期；重名冲突、不同供应商、缺失目录都保持未知，不用 K3 子串或去版本推断。可选资料失败不丢弃有效占比数据。

官方公开数据采用 CC BY 4.0，允许商业使用与修改，要求来源署名、许可链接及注明修改。后端保留官方信用行、来源 URL、统计日和筛选/舍入/公司汇总说明；正常列表不常显英文原始声明，关于页按需打开完整声明与本地化完整许可，截图导出保留署名。

官方要求的信用行：

> © 2026 Vercel. "AI Gateway Leaderboard Data" is licensed under CC BY 4.0. To view a copy of this license, visit https://creativecommons.org/licenses/by/4.0/

2026-10-23 实测公开导出：最近完整日 2026-10-22，10 个公开模型桶，模型占比总和 78.3011%，Other 为21.6988%。全部10个模型可用官方完整 ID 精确关联 models.dev，绝对 token 字段不生成。忽略目录 `work/vercel-usage/` 保留真实响应、部署日志、测试日志和本地视觉证据。模型数量及份额来自实际快照，不是产品固定值。
