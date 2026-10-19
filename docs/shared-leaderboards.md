# 共享排行榜

FC 提供所有平台共用的 HTTPS 接口；OSS 为每张榜单保存一个 `latest.json`，新快照覆盖旧快照。不使用数据库，不保存排行榜历史，不设置快照过期时间。即使几个月无人成功更新，也返回最后一份完整快照。FC 实例回收、扩容和重启不会丢失共享数据。

## Arena 官方数据集（2026-10-19）

四张 Arena 榜单已改为服务端读取[官方 CC BY 4.0 数据集](https://huggingface.co/datasets/lmarena-ai/leaderboard-dataset)。文本使用 `text_style_control`，其余使用 `webdev`、`text_to_image`、`text_to_video`，均只取 `latest/overall`。保留分数、排名、发布日期、修订 SHA 和署名说明；各端来源说明及图片导出保留许可信息。具体口径、实测日期与上线验证见[迁移记录](arena-dataset-migration.md)。

Arena 的刷新请求由 FC 直接读取固定修订的 Parquet 文件并写入 OSS，不向客户端发放官网抓取资格，拒绝旧客户端的 HTML 贡献。各榜独立限频 30 分钟；失败保留已迁移的数据集快照，不回退官网。旧官网缓存仍保存在存储中直至替换，但不作为已许可的数据集快照对外返回。数据集刷新协调日志位于 `benchgauge/arena-dataset/{kind}/coordination.log`。

数据集的发布时间只有日期粒度，各端按 UTC 日期展示，不把它称为投票截止时刻。每张榜的发布日期可能不同；上游未承诺固定更新频率。本服务按用户刷新检查更新，无访问时不会自行轮询。下面的客户端 HTML 贡献流程适用于其他来源。

## 客户端流程

1. `POST /v1/boards/{kind}/refresh` 返回共享快照及可选的更新资格。
2. 没有更新资格时，直接显示共享快照，禁止向原站发起请求。首次快照尚未产生时，只短暂轮询共享读取接口。
3. 拿到资格的客户端先显示 FC 返回的缓存，再在后台请求该榜单固定的原站地址、校验并上传 HTML。贡献流程总时限为 30 秒（原站请求 20 秒、上传请求 10 秒，受总时限约束）；资格仍有 90 秒有效期。服务端重新解析数据；客户端不直接上传分数表或更新时间。
4. 上传成功后，原位更新为服务端确认的快照。原站被屏蔽、解析失败、上传失败或贡献超时时，继续显示共享旧快照；共享服务不可用时，保留本地缓存。刷新期间不清空表格、不遮挡交互；手机保留榜单标题右上角的小提示。

`GET /v1/boards/{kind}` 只读共享快照，永远不会触发原站请求。Windows 的 `cachedBoards` 引擎命令先执行这一只读阶段，呈现结果后再执行后台刷新；Apple 两端通过同一 fetcher 的缓存回调立即呈现并保存，独立来源完成后也立即更新，避免等待另一张慢榜单。

更新资格在所有用户、所有 FC 实例之间共享；每张榜单（每个原站 URL）独立限频。资格有效期结束后，再等待 30 分钟才允许下一次更新，因此实际资格间隔为 31 分 30 秒。失败也占用这一轮，手动刷新不能绕过限制。被拒绝的请求不延长等待期。

原站提供的 `sourceUpdatedAt` 与成功拉取时间 `fetchedAt` 分别保留；读取缓存不修改任何时间。本地数据比共享快照更新时，也不会被共享旧数据覆盖。现有相对时间、原站更新时间提示直接使用这些字段。

## 模型开放状态

快照条目可选携带 `openness`（`open` / `closed`）。Apple 本地解析器与 FC 解析器采用相同规则：Artificial Analysis 的 `isOpenWeights` 布尔值或媒体榜 `openWeightsUrl`；Arena 的 `license`。`Proprietary` 为闭源，已识别的公开权重许可证为开源；受限社区、研究或非商业许可证也按源站的公开权重分类，并不代表无使用限制或 OSI 认证。未识别的许可证、缺字段、旧缓存，以及公司聚合行保持未提供状态，界面显示 `—`。当前 Artificial Analysis 编程智能体榜没有这些字段，不能仅凭厂商名称判断。

编程榜缺少开放状态时，共享服务在读取时复用现存文本榜及 Arena 编程榜中同一模型的明确分类。只匹配完整模型 ID 或去除推理设置后的完整模型名称；代理名称不参与模型匹配，参数规模、日期和版本保持区分。已有明确分类优先，匹配不到或证据冲突时仍显示 `—`。不按厂商猜测，也不将开源代理工具等同于开源模型。

状态随正常榜单刷新或贡献自动更新并保存到 OSS；编程榜的补齐只影响返回数据，不写回推断结果，也不改动分数、排名、更新时间或全局刷新限频，不额外请求原站。旧快照也可立即使用已保存的模型资料。中文列名为「源码」，英文为 `Source`；值为「开源 / 闭源」或 `Open / Closed`。

## 存储和并发

每张榜单使用两个私有对象：

- `benchgauge/{kind}/latest.json`：唯一一份排行榜快照，原子覆盖。
- `benchgauge/{kind}/coordination.log`：更新资格的少量协调元数据，不保存 HTML 或排行榜历史。

协调对象使用 OSS `AppendObject` 的位置前置条件：并发实例只有一个能在同一位置追加成功。读操作只读取日志末尾 2 KB；资格只保存令牌的 SHA-256 摘要。上传先原子消费资格，重放或并发上传只有一个能发布。无数据库、进程内锁或固定单实例假设。

协调日志会增长，每次成功发放或消费资格追加一行。它不能随意删除或设置自动过期，否则可能重置限频窗口。若以后需要整理，先暂停发放资格并等待至少 31 分 30 秒，再重置协调对象；排行榜快照保持不动。

必须使用未开启过版本控制的 Bucket，并保证生命周期规则不会删除 `benchgauge/` 下的任何对象。对象保持私有；用户通过 FC 读取，不能直接访问或写入 OSS。

参考：[FC 实例生命周期](https://www.alibabacloud.com/help/en/functioncompute/overview-of-instance-isolation)、[OSS 追加位置校验](https://www.alibabacloud.com/help/en/oss/developer-reference/appendobject)、[覆盖同名对象](https://www.alibabacloud.com/help/en/oss/developer-reference/putobject)。

## 自动模型资料

共享服务已接入 models.dev 定时同步，校验后保存私有 OSS catalog；各榜新增模型在读取时自动匹配并返回上下文、开放权重、模型许可和分供应商报价。各端保留同一份补全及来源，榜单分数和时间保持原值。身份不确定或上游缺项时保持未知。来源口径、MIT 声明、触发器、失败保留及线上覆盖情况见 [models.dev 自动补全](models-dev-sync.md)。

## 自动品牌资料

国家归属统一遵循 `fc/leaderboard-policy.json` 的 `countryOverrides`：港澳台代码（`HK`、`MO`、`TW`，含三字代码及常见中英文名称）归一为中国 `CN`，展示中国国旗及中国名称。该规则覆盖上游字段解析、自动总部查询、共享缓存读取、小程序旧快照、模型/公司筛选和分享链接；Swift 使用生成的同一份规则，Windows 也从该文件读取规则以迁移旧筛选设置。原始排名、分数和榜单时间不受影响。

每次榜单刷新和新快照贡献都会按厂商识别缺失资料；普通读取只使用缓存。厂商名先去除格式差异并合并已有别名，已知厂商的新模型和不同榜单复用同一份资料。编码代理榜缺失厂商时，可从明确的 `Harness - Model` 家族识别归属；未知归属不猜测，也不继承另一家代理工具的图标。

优先使用原站的厂商图标。共享服务接受 Artificial Analysis 自有 `/img/logos/` HTTPS 图片，逐跳校验重定向和体积，拒绝 SVG 外部引用及活动内容。Sharp 在服务端转换为 64×64 的透明 PNG（最多 16 KiB），纯白透明图标转深色墨迹以适应白色图标底板，空白图片不缓存。服务持久保存图片和厂商资料，通过榜单 JSON 的 `entry.brand` 返回 PNG 的 Base64 数据；Apple 的离线快照、公司聚合及导出，以及 Windows 引擎响应均保留图片。这避免客户端等待远程 SVG 或导出时丢失图标。客户端优先共享 PNG，再用打包图标，最终显示首字母。

2026-10-15 补齐 Arena 原网页图标提取。`fc/source-logos.mjs` 用 HTML 解析器将模型名称与同一表格单元格中、名称之前的图标对应，排除排名、外链和提示按钮；同名模型出现不同图片时不猜。四类 Arena 榜单均支持内嵌 SVG 和源站 `/images/models/` 图片，无需新增厂商名单。SVG 中依赖 `fill-black` 等网页样式的墨迹会先转为独立呈现属性，再按既有规则校验并转换 PNG；单张 SVG 上限 64 KiB。厂商 SVG 在快照的 `organizationLogoSVGs` 中去重保留，失败时可在后续刷新重试；没有厂商资料的行使用独立模型图片缓存。已有官方模型专属图标继续优先于源站厂商标志。源图片下载仍逐跳限制域名、路径和大小。

保存的真实原网页验证覆盖文本 414 行、WebDev 142 行、文生图 82 行和文生视频 48 行，分别提取并成功转换 27、20、19、15 个厂商 SVG；视频榜另有 Kandinsky 源图片。验证记录在忽略目录 `work/source-metadata-audit/`。国家资料仍读取原站明确的开发商 ISO 字段，缺失时沿用已核实资料和自动 Wikidata 查询。

同日已部署共享函数，并使用留存的原网页仅填充品牌缓存；本次 Arena 直接抓取返回 403，未用旧网页替换排名快照。没有厂商字段的 Arena 行按来源种类及原站模型 ID 缓存模型图片，旧快照也能在普通读取时取得已获取的源图标。线上四榜共享 PNG 覆盖分别由 316/415、134/143、77/82、41/48 提升至 415/415、143/143、82/82、48/48，合计补齐 120 行。八榜公开接口均验证通过，排名、分数、国家字段及两种时间与填充前一致。52 项服务端、部署边界及跨端规则测试通过；报告为 `work/source-metadata-audit/online-verification.json`。

背景色优先使用已有品牌色，否则提取图标主色；单色图标使用中性灰。无法取得图片时，使用按规范厂商名计算的稳定备用色。现有主题和同厂商型号明暗变化仍在客户端应用。已经安装支持此字段的版本后，新品牌资料随榜单更新获取，无需再为补图标发布应用。

OSS 新增 `benchgauge/brands/{key}.json`、`benchgauge/brand-assets/{sha256}.png`，以及 `benchgauge/brand-state/{key}/coordination.log`。品牌获取也使用追加位置校验，避免不同 FC 实例重复下载；失败或缺少源地址的厂商在至少 30 分钟后的下一次刷新重试，新出现的源地址可以立即尝试。单次处理有时间、并发和图片大小限制；品牌服务失败保留有效排名及已有图片，不改变排行榜时间或绕过原站刷新资格。

`brand.status` 区分 `ready`、`failed`、`missing`、`pending`、`unknown`。`failed` 会自动重试，`pending` 在后续刷新继续获取；缺少源图标的 `missing` 和厂商无法识别的 `unknown` 才需要检查来源资料。已有打包图标的厂商即使共享状态为 `missing` 也仍正常显示。品牌元数据中的来源、获取时间和下次重试时间保存在私有 OSS，便于人工排查。

2026-10-13 的真实接口验证：两张视频榜各 20 行都获得共享 PNG，其中此前缺失的 Utopai Studios、Skywork AI、Sapiens AI 已自动取得图标和提取色。Arena 视频榜复用另一张榜的厂商缓存。无厂商名的编码代理榜也已复用 18 行已识别模型家族的图片，另外两行 Devin 使用现有打包图标。验证记录保存在忽略目录 `work/brand-discovery/`。

## 模型图标与公司图标

2026-10-13 排查确认：AA 视频榜给 Wan 的 `creator.logo` 是 `alibaba.svg`，并非 Wan 的独立图标。现在优先使用榜单明确标注的 `modelLogoURL`，其次使用已核实的官方模型家族图标，最后才用厂商图标。模型缓存使用独立的 `model-*` 命名空间；同厂商的 Wan、Qwen、HappyHorse 不再共享模型图标，厂商的旧 PNG 也不能阻止模型图标升级。名称中的空格、连字符及版本号均兼容两个榜单的命名。

已经核实并纳入官方图标的家族是 Wan、Dreamina Seedance / Seedream、SkyReels、Grok、Gemini、Gemini Omni、Veo。来源及 64×64 PNG 保存在 `fc/brand-catalog.json`，均来自对应官网或 Google DeepMind 官网的模型导航，未使用搜索网站或第三方生成图标。服务优先下载已核实的原图；这些官方 PNG 同时随共享服务保留，区域网络失败时仍显示正确的模型标志。其他新家族只有榜单提供独立模型图标时才自动获取；缺少模型资料不能当作“已经证实该模型没有 logo”，仍需要核实官方归属和图标来源。

`entry.brand` 表示当前模型使用的图片，独立的 `entry.organizationBrand` 保留厂商图片。公司排行取后者；旧快照缺失此字段时兼容原行为。各端既有共享 PNG 支持可以直接获得新模型图标，离线缓存也保留这两种图片。新版共享 Kit 对模型图片使用其提取色，避免套用同公司的另一条产品线颜色。

真实接口验证保存在忽略目录 `work/model-logos/`：Wan 3.0 和 Wan2.7 复用 `model-wan`，公司资料仍单独保留；两张视频榜还核对了 Dreamina 的连字符名称、Gemini Omni、Grok 与 Veo 家族。模型查询失败、旧厂商缓存、无厂商的独立模型图片、冷读、离线保存和公司聚合均有回归测试。

## 部署

运行 `npm ci --prefix fc --include=optional --ignore-scripts` 安装部署依赖。在被 Git 忽略的 `.benchgauge-cloud.local.json` 中配置：

```json
{
  "region": "cn-shenzhen",
  "functionName": "ai-benchgauge",
  "arenaCollector": true,
  "bucket": "ai-benchgauge",
  "runtimeCredentialsFunction": "weaveo",
  "runtimeIdentityName": "limphase-runtime",
  "credentialsFile": "/absolute/path/to/private-cloud.env"
}
```

也可从进程环境变量读取 `ALIBABA_CLOUD_ACCESS_KEY_ID`、`ALIBABA_CLOUD_ACCESS_KEY_SECRET`。配置必须包含已有专用 `bucket`，以及以下一种已有运行身份：

- `runtimeCredentialsFunction` 加 `runtimeIdentityName`：从本账号指定 FC 函数的运行环境复用云凭证，在内存中校验 STS 身份后传给新函数；只转移阿里云凭证，不复制其他供应商密钥。服务端明确使用环境凭证，忽略公共请求中的凭证头。
- `roleArn`：指定已准备好的 FC 执行角色，使用 FC 注入的临时凭证。

`proxy` 可指定本机 HTTP 代理。本机部署凭据从 weaveo 复用至被忽略、权限为 `0600` 的 `.env.local`；这些是部署用户凭据，与运行用户区分。不要提交本机配置或把密钥填入客户端。

当前本机配置使用用户创建的 `ai-benchgauge` 桶、`runtimeCredentialsFunction: "weaveo"`、`runtimeIdentityName: "limphase-runtime"`。STS 已确认 `limphase-runtime` 是本账号的 RAM 用户，Weaveo 使用它的运行凭证。部署脚本不创建 Bucket、RAM 角色或权限策略，也不要求 RAM 管理权限。运行身份需要读取桶配置，并具有快照读取、覆盖写入和协调对象追加权限。

```sh
node Scripts/deploy-shared-leaderboards.mjs --plan
node Scripts/deploy-shared-leaderboards.mjs --package
node Scripts/deploy-shared-leaderboards.mjs
```

部署使用 `custom.debian10` 的 Node.js 20，512 MB / 0.25 vCPU、512 MB 临时磁盘，实例并发 8、请求超时 30 秒，按需启动。临时磁盘只供运行程序，不存放共享快照。函数通过深圳 OSS 内网地址访问存储。部署脚本先运行服务端测试，再打包生产依赖；不会覆盖无关函数。部署回执保存在被忽略的 `work/shared-leaderboards/deployment.json`。ZIP、应用和接口响应均不包含云密钥；运行凭证仅存放在 FC 的运行配置中。

`arenaCollector: true` 同时部署新加坡的专用 Arena 采集函数，解决深圳直连 Hugging Face 超时。它没有 OSS/云凭据，仅接受四个固定路径且必须携带专用随机令牌。令牌保存在被忽略的 `work/shared-leaderboards/arena-collector-token`（0600）及运行环境，重部署复用；丢失后重新生成并同时更新两端。部署后验证未认证访问为 403、四榜完整链路及原共享读取地址。

部署后先验证读取接口；Arena 通过刷新接口读取官方数据集，其他来源使用更新资格从原站填充。确认读写链路可用后，设置 `Sources/LeaderboardKit/SharedLeaderboardConfiguration.swift` 的 `bundledEndpoint`，再构建应用。iOS、macOS、Windows 引用同一个 Swift 配置。开发调试也可设置 `BENCHGAUGE_SHARED_ENDPOINT`；配置了共享服务后，服务失败不能回退到无资格的原站请求。

### 当前部署状态

2026-10-14 将主函数名统一为项目英文名 `ai-benchgauge`，HTTPS 地址为 `https://ai-benchgauge-qrwtdokchx.cn-shenzhen.fcapp.run`。FC 更新接口没有改名字段，因此使用新名称创建函数并切换所有客户端的共用地址。迁移时新旧函数使用同一个 `ai-benchgauge` 桶；八张榜单在两端逐项校验一致，已有快照、国家与品牌资料、贡献协调日志沿用。2026-10-15 按用户要求删除旧函数 `benchgauge-shared-leaderboards` 及其 HTTP 触发器；FC 已返回旧函数不存在，新函数配置未变，八张榜单读取均正常，共用 OSS 数据保留。主部署配置只指向新函数，微信小程序后台的 request 合法域名也需使用新地址。部署、迁移与删除校验记录保存在忽略目录 `work/fc-rename/`，删除回执为 `deletion.json`。

独立函数 `ai-benchgauge` 已接通深圳的 `ai-benchgauge` 私有桶，客户端共享配置按用户选择直接使用 FC HTTPS 内置域名。八类榜单均已使用真实原站数据完成首次填充，HTTP 读取与缓存内容、抓取时间一致。五类通过匿名贡献资格完成上传；三类 Arena 榜单在初始化脚本遇到 301 后，通过可信部署身份跟随跳转并填充首次快照，未重置协调日志或刷新等待期。

实际验证覆盖快照写入、共享读回、立即重复刷新拒绝新资格，以及贡献令牌重放拒绝。初始化和验证记录保存在被忽略的 `work/shared-leaderboards/live/`；其中 `verification.json` 保留第一次脚本的 301 失败记录，`bootstrap-verification.json` 记录补齐过程。函数已配置环境运行凭证，部署用户不需要额外 RAM 管理权限。

当前 JSON API 已通过 FC 内置域名验证，不以购买域名为接通前提。阿里云文档将内置域名定位为测试用途，并提示稳定性限制；用户选择先直接使用该地址，后续如需自定义域名再替换共用配置。[HTTP 触发器说明](https://help.aliyun.com/zh/functioncompute/http-triggers-overview)。

## 客户端贡献的边界

Arena 已停止客户端贡献，以下边界适用于仍使用贡献流程的来源。公开接口的贡献资格不等于原站来源证明。服务端校验来源类型、完整记录数量、字段和数值范围、原站时间不倒退、令牌有效期及一次性使用，并过滤任意外部图片地址；但无法仅凭客户端上传的 HTML，证明它确实来自原站的 HTTPS 响应。恶意客户端仍可能伪造符合结构的 HTML。若需要防范这种行为，后续必须加入可信贡献者认证、设备证明或独立来源验证，不能把格式校验描述为原站真实性校验。

## 验证

`Scripts/brand-discovery.test.mjs` 覆盖并发厂商复用、失败限频与修复、图片规范化、安全下载、时间预算和颜色目录一致性。`Scripts/shared-leaderboards.test.mjs` 覆盖多实例竞争、贡献重放、长期旧快照、原站/存储失败、旧时间拒绝、八类解析、HTTP 读写和 OSS 位置冲突。Swift 测试覆盖不绕过更新资格、网络失败回退、上传流程、缓存时间保留及不覆盖较新的本地快照。`node Scripts/test.mjs` 会运行完整检查，并把 FC 源码纳入测试结果签名。

## 动态厂商国家资料

每次共享榜单刷新（包括源站刷新尚在限流期间）和新榜单提交时，按统一厂商 key 识别缺少国家资料的厂商。已知厂商的新型号复用同一份资料；国家指模型开发商总部，编码代理跟随主模型厂商，公司榜继承该厂商资料。

优先使用已核验的服务端资料和源站开发商 ISO 国家字段，再使用共享 OSS 国家缓存。未知厂商通过 Wikidata 固定公共 API 自动检索：精确匹配厂商名称/别名，源站有官网时核对官网域名，再解析当前总部地点、所在国家和 ISO 国家码。同名实体、多个国家的总部、缺少总部资料等情况保留未知，30 分钟后的刷新再试。不会依据域名后缀、图标、模型语言或母公司位置猜国家，也不会自动抓取任意贡献者提供的网址。

国家元数据和来源链接随榜单传给各端，随本地快照保存，离线展示和国家筛选使用同一份资料；支持新增 ISO 国家码，Windows 筛选选项和译名由共享引擎提供。Windows 原有六国继续显示绘制的旗帜，其他国家先显示 ISO 两字母码。已缓存的有效国家不会因查询服务或 OSS 暂时故障消失。

`fc/country-catalog.json` 用于核验过的资料及原有名单，`fc/countries.mjs` 管理自动发现和重试。新厂商未收录于公开结构化资料、同名且无法核验或无法确认开发者时，仍可能需要人工核实；自动发现不等于所有新厂商都立即有资料。当前视频榜的 Utopai Studios 按官网总部标记美国；Skywork AI 按官方公司/隐私资料标记新加坡；Sapiens AI（Agnes）按其公司发布的总部资料标记新加坡，不采用同名保险软件公司的国家。

2026-10-13 修复 MAGI 的国家缺失：真实 AA 视频榜中的 `MAGI-2 Preview (0912)` 属于 `Sand.ai`，共享 `sandai` 国家记录此前为查询失败，且本地没有兜底映射。根据 [Sand.ai 官方模型归属](https://sand.ai/about-us)及[网宿科技对 Sand.ai 的正式披露](https://static.cninfo.com.cn/finalpage/2026-09-29/1225587991.PDF)中的中国研发/运营主体资料，补充 `CN`；境外控股或服务法人不用于替代模型开发者地区。共享资料目录和 Swift 本地映射同时覆盖 `Sand.ai` / `Sand AI` / `SANDAI`。未知厂商的类似模型名仍保持未知。

线上只修复私有 OSS 中的 `benchgauge/countries/sandai.json`，不需要重新发布整个 FC 函数。读取接口已验证该 MAGI 行返回 `ready` / `CN`，排名、模型名、分数、厂商及榜单抓取时间均与修复前一致；现有客户端刷新共享榜单即可取得。29 项服务端测试及 6 项 Swift 国家测试通过，覆盖失败记录纠正、缓存保存、公司聚合和国家筛选。公开响应与核对记录保存在忽略目录 `work/magi-country/`。

2026-10-16 修复 ERNIE 的国家缺失：Arena 文本榜中 4 个 ERNIE 条目的厂商均为 `Baidu`，共享 `baidu` 国家资料此前为查询失败。根据[百度官方地址资料](https://home.baidu.com/contact.html)补充 `CN`，同步加入服务端目录和 Swift 本地兜底。线上仅修正私有 OSS 的 `benchgauge/countries/baidu.json`，公开读取接口已验证这 4 条均返回 `ready` / `CN`，各条目除国家资料外的字段及榜单更新时间保持不变；客户端刷新即可取得，无需重新部署整个函数。13 项服务端国家测试和 4 项 Swift 国家测试通过，备份和线上核对结果保存在忽略目录 `work/ernie-country/`。

2026-10-16 修复 Inkling 的国家缺失：Arena 文本榜将 `inkling` 和 `Inkling Small` 的厂商标为 `Thinky`，共享国家记录此前查询失败；原目录只识别 `Thinking Machines`。按[官方模型卡](https://thinkingmachines.ai/model-card/inkling/)核实开发者，并依据[官方隐私说明](https://thinkingmachines.ai/legal/privacy/)的美国所在地资料，将 `Thinky` / `Thinking Machines Lab` 合并为 `thinkingmachines`，共用 `US` 国家资料。Swift 策略由目录重新生成。线上仅备份并修正私有 OSS 的 `benchgauge/countries/thinky.json`，兼容尚未部署别名规则的服务；公开接口中两条目均已验证为 `ready` / `US`，模型名、厂商、排名、分数等条目字段保持不变。备份及核对结果位于忽略目录 `work/inkling-country/`。33 项服务端/共享规则测试、88 项小程序测试及 5 项 Swift 国家测试通过，小程序构建完成。

2026-10-16 修复 Amazon Nova 的国家缺失：Arena 文本榜中 10 个 Nova 条目的厂商均为 `Amazon`，共享国家记录此前查询失败且无目录兜底。依据 [Amazon 官方总部资料](https://www.aboutamazon.com/workplace/facilities)补充 `amazon` → `US`，同步加入 Swift 本地映射。线上备份并修正私有 OSS 的 `benchgauge/countries/amazon.json`，公开接口已验证这 10 条均为 `ready` / `US`；除国家资料外的条目字段及榜单时间均保持不变，刷新即可生效，无需重新部署整个函数。15 项服务端国家测试及 6 项 Swift 国家测试通过，备份和核对结果位于忽略目录 `work/nova-country/`。

2026-10-16 修复 LongCat 的国家缺失：Arena 文本榜中的 `longcat-flash-chat-2602-exp` 和 `longcat-flash-chat` 均属 `Meituan`，共享国家记录此前查询失败且无目录兜底。按[美团官方模型发布](https://tech.meituan.com/2025/09/01/LongCat-Flash-Chat.html)核实归属，并依据[美团 2025 年报](https://www1.hkexnews.hk/listedco/listconews/sehk/2026/0424/2026042400179.pdf)所列中国北京总部，补充 `meituan` → `CN`，同步加入 Swift 本地映射。线上备份并修正私有 OSS 的 `benchgauge/countries/meituan.json`，公开接口已验证两个条目均为 `ready` / `CN`；其余条目字段及榜单时间保持不变，刷新即可生效。16 项服务端国家测试及 7 项 Swift 国家测试通过，备份及核对结果位于忽略目录 `work/longcat-country/`。

2026-10-16 修复 Solar 的国家缺失：`solar-pro4` 的 `Upstage` 共享国家查询失败，`solar-10.7b-instruct-v1.0` 的源数据还缺少厂商。按 [Upstage 官网](https://www.upstage.ai/)列出的韩国开发主体 Upstage Co., Ltd. 及首尔地址补充 `upstage` → `KR`；美国办公室不替代该模型开发主体的归属。旧版归属由[官方模型卡](https://huggingface.co/upstage/SOLAR-10.7B-Instruct-v1.0)核实，以完整型号精确匹配，仅补充缺失的厂商，不覆盖已有厂商、不匹配微调版或名称前缀。目录中的 `modelDevelopers` 同步生成 Swift 策略，共享服务读取时补齐厂商并复用国家资料。

已备份并修正私有 OSS 的 `benchgauge/countries/upstage.json`；为兼容已有客户端，从当前线上代码包构建仅改动五个国家/身份规则文件的更新，保留其余代码、函数配置和排行榜快照。公开接口已验证两个 Solar 条目均为 `Upstage` / `ready` / `KR`，排名、分数、模型 ID 及榜单时间保持不变。57 项服务端测试、8 项 Swift 国家测试、89 项小程序测试及小程序构建通过，备份、发布包和核对结果位于忽略目录 `work/solar-country/`。

2026-10-16 修复 Trinity 的国家缺失：Arena 文本榜的 `trinity-large-preview` 与 `trinity-large-thinking` 均缺少厂商，国家状态为 `missing`。依据[两个型号的官方模型卡](https://huggingface.co/arcee-ai/Trinity-Large-Preview)及其 [Thinking 版模型卡](https://huggingface.co/arcee-ai/Trinity-Large-Thinking)核实开发者，并按 [Arcee AI 官方简介](https://www.arcee.ai/about)所述美国模型实验室，补充精确型号 → `arceeai`、公司名 `Arcee AI` 和国家 `US`；不推断其他前缀或微调版、不覆盖已有开发者。Swift 策略同步生成并补齐国家兜底。

从当前线上包构建仅修改三份 JSON 目录的更新，发布前逐项确认仅增加上述映射，其余代码及函数配置保留。公开接口已核验两个条目均为 `Arcee AI` / `ready` / `US`；厂商品牌标识随归属补为 `arceeai`，排名、分数、模型 ID、模型标识、其他条目及榜单时间保持不变。59 项服务端测试、9 项 Swift 国家测试、89 项小程序测试及小程序构建通过。备份、发布包和核对结果位于忽略目录 `work/trinity-country/`。

2026-10-16 全量排查八类共享榜单的 895 条记录，将国家覆盖从 759 条提升到 890 条，补齐 131 条；其余 5 条个人/跨机构开源型号保留未知，并列明核实资料。新增 41 个开发主体的国家资料、49 个精确型号归属，修正三种厂商别名的输出名称，兼容旧客户端的国家身份校验。Swift 国家兜底改由共享目录生成，并提供只读快照覆盖排查脚本。仅更新四个国家/身份规则文件，未写排行榜快照或修改函数配置；线上真实响应已通过新旧身份校验、小程序归一化、国旗及模型/公司国家筛选检查。61 项服务端测试、10 项 Swift 国家测试、95 项小程序测试和小程序构建通过。来源、逐榜结果及保留未知的依据见[国家资料覆盖排查](country-coverage-audit.md)，备份及核对结果位于忽略目录 `work/country-audit/`。

## 微信小程序客户端

`apps/weapp` 从同一服务只读 `GET /v1/boards/{kind}`，不申请更新资格，不访问原站，不上传 HTML。八类真实共享榜单已使用该客户端的归一化、公司聚合与国家筛选代码验证，各来源均有 20 条完整记录；原站日期缺失与已提供日期保持独立。验证记录在忽略目录 `work/weapp/live-verification.json`。

服务地址在构建时从 Swift 共用配置读取，或由 `VITE_BENCHGAUGE_SHARED_ENDPOINT` 覆盖。小程序本地缓存保留源日期与抓取日期，网络失败仍显示已保存数据；时间倒退或丢失已有源日期的快照不能覆盖旧缓存。图片使用响应中的 PNG 数据，不发起任意源站图片请求。正式 AppID 仍需配置微信 request 合法域名。

### 完整榜单（2026-10-14）

共享解析器与原生兜底解析器保留来源中所有有效条目，公司汇总也不再截取二十家。Mac 保持原有表格高度，Windows 保持原有面板尺寸；多出的条目在表格内滚动，各端支持返回顶部。iPhone、iPad 和小程序沿用原有滚动容器。客户端的共享响应大小上限调整为 16 MB，以容纳完整榜单携带的共享图标。

部署兼容线上旧版 `ai-benchgauge` 标识时，仍同时校验专用函数名称、运行时及已验证的 OSS 桶；无关函数继续被拒绝。部署后依照原有贡献资格刷新，AA 综合、编程、图片、视频分别返回 32、39、102、33 条。Arena 来源此次返回 HTTP 403，旧缓存保留，后续通过正常刷新补全；未重置资格或缩短刷新间隔。
