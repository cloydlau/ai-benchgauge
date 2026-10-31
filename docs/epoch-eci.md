## 领域榜接入核查 — 2026-10-31

## 2026-10-31 上线核验

共享服务已通过完整测试、覆盖率门禁及云端代码包/接口核验并上线，三张领域榜不再返回 Unknown leaderboard。软件工程正常刷新保存 110 条。数学与网络安全首次正常刷新失败后，使用刚下载的官方 CSV、当前同一拟合器及真实文件获取时间，以管理员首次填充补齐 153 / 57 条：只在快照对象不存在时通过 OSS forbid-overwrite 条件创建；写入后独立 GET 逐条核对模型 ID、名次与分数。两张榜的协调日志写入前后哈希一致，未改变冷却时间或其他快照。原始 CSV、来源哈希和回执保存在忽略目录 `work/epoch-domain-live/`。此前安排的冷却后一次刷新已取消，避免额外采集。

小程序实际切换验证：数学、网络安全、软件工程均显示非空榜单（公司视图分别 15、7、13 行）。其他原生客户端共用已上线的快照接口；本轮未安装、发布或逐端运行原生客户端。短重试增强已在同一正常采集内限制最多三次尝试（6 秒超时、200/400 毫秒退避），30 分钟协调限频不变；9 项领域拟合/采集回归通过，增强版本待既有自动发布完成。下方 “尚未部署” 的旧记录由本节替代。

数学和网络安全放在专业分类，软件工程作为编程分类的 Epoch 来源。三者已接入共享服务并完成首次线上填充。Epoch 官方交互页面当前读取 `/data/eci_scores.csv`、`/data/processed_data_for_eci.csv`、`/data/edi_scores.csv` 和模型资料；数学、软件工程按官方预设选取基准，使用固定难度与斜率重新拟合每个模型，默认要求至少两项基准。网络安全使用独立 `/data/cyber/` 下的数据及参数，不能沿用综合参数；其模型也可能不在综合榜中。以上基于 [Epoch 官方方法](https://epoch.ai/data/eci-documentation/domain-specific-eci)和官方页面实际加载路径核查，不能把固定名单当成永久基准。

本机对源站下载间歇超时；现已取得网络安全分数、评测明细和独立难度参数，以及综合评测明细和难度参数。三张榜单已在工作区接入共享服务和各端源码，数学和软件工程使用 2026-10-31 核对的固定领域预设；官方增减基准时需要重新核对并更新，不能假称自动同步。真实数据生成数学 153、软件工程 110、网络安全 57 条，抽查 GPT-6 Astra 的数学和软件工程结果与官方页面展示整数一致；网络安全 57 条与官方分数逐项比对最大差约 0.000000085。共享服务已部署并完成首次填充；客户端原生发布状态按各端独立记录。采集失败时保留缓存，不以综合分数替代领域分数。

# Epoch ECI

综合分类新增第三个来源 `epochECI`。官方说明：https://epoch.ai/eci；官方 CSV：https://epoch.ai/data/eci_scores.csv。

## 数据约定

- 使用 `Model` 作为稳定 ID、`Display name` 作为名称、`eci` 原始数值作为分数。按分数降序，同分按名称排序。模型与公司视图、筛选、缓存、共享贡献、导出均沿用现有管线。
- 显示两位小数。ECI 是指数，不是正确率，也没有 100 分上限；不展示相对榜首百分比。不同来源分数不能直接横比。
- CSV 的 `date` 是模型发布日期；不写入 `sourceUpdatedAt`，界面沿用抓取时间。
- 解析支持 BOM、CRLF、引号、逗号与多行字段；拒绝缺失列、损坏引号、非有限分数、重复 ID 和异常数据量。国家字段遵循仓库统一的 HK/MO/TW → CN 规则。
- 共享服务仅接受绑定 `epochECI` 官方地址的一次性抓取授权；该来源贡献的 MIME 为 `text/csv`。

## 开源／闭源资料核对（2026-10-18）

官方 CSV 当天共 277 个模型，其中 24 项的 `Accessibility group` 是 `Other`；已有精确型号规则覆盖其中 18 项，剩余 6 项在 Epoch 官方模型详情页均明确归类为 `Closed weights`。本次将这 6 项加入共用规则，并记录核对日期与来源：

| 精确型号 | 核实来源 |
| --- | --- |
| Gemini 4 Argon | [Epoch 模型页](https://epoch.ai/models/gemini-4-argon) |
| Qwen 3.6 Max (Preview) | [Epoch 模型页](https://epoch.ai/models/qwen-3-6-max-preview) |
| Mistral Large 4 | [Epoch 模型页](https://epoch.ai/models/mistral-large-4) |
| Qwen 3.5 Plus (hosted 397B-A17B) | [Epoch 模型页](https://epoch.ai/models/qwen-3-5-plus-hosted-397b-a17b) |
| Qwen 3.5 Flash (hosted 35B-A3B) | [Epoch 模型页](https://epoch.ai/models/qwen-3-5-flash-hosted-35b-a3b) |
| Qwen 3.6 Flash | [Epoch 模型页](https://epoch.ai/models/qwen-3-6-flash) |

按完整 `modelID` 匹配；托管版本与公开权重版本分别处理，不按公司、系列或名称子串猜测。上游明确提供的 `open`／`closed` 优先于补全规则，未核实的新变体仍保持未知。Mistral Large 4 当前预览版本尚未发布权重；[官方公告](https://mistral.ai/news/mistral-large-4/)预告后续发布，届时须按实际发布情况复核，不能提前判为开源。

FC 读取已有缓存时应用规则；原生端（含 Windows 桥接）与小程序使用同一份规则及生成结果。回归测试覆盖旧缓存、筛选与标识、托管和公开版本区分、未知变体、明确上游值优先，以及补全前后排名、分数、抓取时间不变。

本次相关 JavaScript 测试 57 项、原生 Swift 测试 11 项通过，小程序构建通过。共享服务以现网代码包为基础，仅更新 `leaderboard-policy.json`；线上复核 277 项分类缺失数由 6 降为 0，排名、分数与榜单抓取时间不变（国家资料读取时动态生成的 `retrievedAt` 不作为榜单更新时间比较）。微信开发者工具真实刷新后，277 项缓存分类均完整，当前渲染的 41 行均有源码标识。核对与部署记录位于忽略目录 `work/epoch-openness/`。

## 界面

桌面端保持两列。综合左侧是 Artificial Analysis，右侧在已有控制行选择 Arena / Epoch ECI，选择会保存。iPhone / iPad 与微信小程序的综合分类有三个来源；其他分类仍为两个。切换分类和旧分享链接会限制来源索引到有效范围，立方体滑动每次只到相邻来源。

## 本次验证与限制

2026-10-18 已部署共享解析器，缓存 277 个模型；逐条核对线上缓存的模型 ID、名称、原始分数与官方 CSV 一致，且未冒用模型发布日期。测试覆盖 CSV 边界、授权及重放、来源贡献 MIME、三来源切换与边界、偏好与分享迁移、分数精度。

本机 Mac 原生前后截图使用同一测试数据，覆盖英／简／繁、900／1200 × 720、浅／深色，以及出现／刷新／稳定帧。原图和环境元数据在忽略目录 `work/epoch-eci/{before,after}/macos`；本机记录 macOS 27.0.1 (26A434)、实际 backing scale 1.0。这是本地未提交源码的检查，没有 CI 视觉审核记录。

Windows 交叉编译通过；没有 Windows 原生截图或源版本一致的 CI 视觉比较产物，尚未完成 Windows 视觉验收。微信开发者工具在刷新后报 `app.json is not found in the project root directory`，因此本次未完成小程序运行时视觉验收。小程序构建与自动化单元测试通过。发布仍受 `native-visual-review` 人工审核约束。

## Cyber fit verification — 2026-10-31

The separate Cyber ECI parameters and results were retrieved. The fitting function in fc/epoch-domain-fit.mjs matched 57 eligible models in the official Cyber scores CSV with a maximum absolute difference below 0.00000009. Three model names present only in benchmark data were excluded. The score CSV contains models below the two-benchmark minimum, so final integration must check benchmark data too. Three fitting tests pass. The function is not yet connected to the service or clients.
