# 新增榜单国家、开发者及图标核验

2026-10-31 对全部 29 张可读共享榜快照进行审计，共 2,617 条记录，包含 Epoch 数学、网络安全、软件工程，以及新增 Arena、Artificial Analysis 语音、图像、视频子榜。读取使用 client-first 缓存协议，没有请求原站刷新、重置限频或改写共享榜单。独立 OpenRouter 价格端点未返回榜单快照，不计入 29 张。

| 缺项 | 修改前 | 补全后 |
| --- | ---: | ---: |
| 国家（逐条记录） | 291 | 16 |
| 模型行图标（逐条记录） | 158 | 10 |
| 已识别开发者的公司行图标（跨榜计数） | 76 | 0 |

原始响应、前后审计、字段不变断言、图标联系表和定向检查记录保存在忽略目录 work/metadata-coverage-20261031/。已核对排名、分数、模型 ID、票数、涨跌及所有榜单时间不变；开发者显示名允许核实后的同义写法归一化。

## 共用来源与生效方式

国家依据写入 fc/country-catalog.json；开发者名称、精确模型名与别名写入 fc/brand-catalog.json、fc/leaderboard-policy.json。补齐 44 个厂商的国家，统一 Kling、Alibaba Cloud、Amazon Bedrock、Microsoft Azure、fal.ai、Genmo、Shengshu 的既有开发者键；对 Arena 新展示名称补充精确匹配。新增展示别名遇到不同、未核实的显式模型 ID 时不抢占归属，也不覆盖原站明确提供的其他开发者。

原生品牌色、国家、别名与精确开发者通过 Scripts/generate-leaderboard-policy.mjs 生成，OrganizationLogoCatalog 不再维护另一份手写颜色表。小程序使用相同的共享规则，并继续排除服务端图像数据以控制客户端包体；iPhone、iPad、Mac、Windows 及所有端的图片导出从共享快照获得内嵌 PNG。Windows 沿用 Swift 共享引擎，不复制一份国家表。

19 份新增图标的唯一源文件、哈希和来源保存在 assets/brand/partners/leaderboard-providers/。Scripts/sync-provider-logos.mjs 离线生成 64×64 PNG 与品牌色；--check 可检查生成文件和来源哈希。Alibaba 公司图标单列 companyLogos.qwen，不替换 Qwen 模型图标。旧缓存中空开发者键留下的失败公司图标，也会在确定开发者后同步修复。

共享服务读缓存时即补元数据，不需要重新拉取排名或修改刷新日期。新增国家与图标依赖本轮服务自动发布后在应用刷新读取；本地检查通过不能代替线上发布回执。

## 国家依据

采用服务提供者的官方法律/联系页、公司维护的资料页、官方登记或原论文机构信息；避免用创始人姓名、图标风格、域名或第三方托管商所在地猜国家。国家规则继续将香港、澳门、台湾归一为中国。Noiz 与 VUI Labs 的官方公司资料列出香港，故记为 CN。MetaVoice 的当前官方资料更名为 Familiar 且总部在美国；不沿用过时英国归属。Smallest.ai 采用公司明确列出的美国总部，而非印度支持地址；Deepgram 不因新增亚洲办公室改成新加坡。

| 开发者 | 国家码 | 来源 |
| --- | --- | --- |
| ElevenLabs | US | [核验来源](https://elevenlabs.io/contact-legal) |
| Cartesia | US | [核验来源](https://www.cartesia.ai/legal/terms) |
| Inworld | US | [核验来源](https://inworld.ai/terms) |
| AssemblyAI | US | [核验来源](https://www.linkedin.com/company/assemblyai/) |
| Smallest.ai | US | [核验来源](https://www.linkedin.com/company/smallest/) |
| Fish Audio | US | [核验来源](https://beta.fish.audio/terms/) |
| SpeechifyAI | US | [核验来源](https://speechify.com/studio-privacy/) |
| Boson AI | US | [核验来源](https://www.boson.ai/about/contact) |
| Soniox | US | [核验来源](https://soniox.com/policies/privacy-policy) |
| Resemble AI | US | [核验来源](https://www.resemble.ai/privacy-policy) |
| Phonic | US | [核验来源](https://phonic.ai/legal/terms-of-service) |
| Deepgram | US | [核验来源](https://static.deepgram.com/business/Business_TOS_Console.pdf) |
| Murf AI | US | [核验来源](https://murf.ai/legal/data-protection-agreement) |
| Async | US | [核验来源](https://async.com/privacy) |
| Hume AI | US | [核验来源](https://www.hume.ai/careers) |
| Rime | US | [核验来源](https://www.rime.ai/company) |
| Bland AI | US | [核验来源](https://www.bland.ai/ai-information) |
| Zyphra | US | [核验来源](https://www.zyphra.com/legal/privacy-policy) |
| Zoom | US | [核验来源](https://www.zoom.com/en/about/media-kit/) |
| Modulate | US | [核验来源](https://www.modulate.ai/privacy-policy) |
| DeepInfra | US | [核验来源](https://deepinfra.com/privacy) |
| Replicate | US | [核验来源](https://replicate.com/privacy/) |
| Groq | US | [核验来源](https://groq.com/privacy-policy) |
| Rev AI | US | [核验来源](https://www.rev.com/legal/privacy) |
| Telnyx | US | [核验来源](https://www.linkedin.com/company/telnyx/) |
| HeyGen | US | [核验来源](https://www.linkedin.com/company/heygen/) |
| Newport AI | US | [核验来源](https://www.linkedin.com/company/new-port-ai/) |
| MetaVoice | US | [核验来源](https://www.linkedin.com/company/familiario/) |
| StyleTTS | US | [核验来源](https://arxiv.org/html/2306.07691) |
| Gradium | FR | [核验来源](https://gradium.ai/Gradium%20-%20press%20release%20EN%20final.pdf) |
| Gladia | FR | [核验来源](https://www.gladia.io/legal-notice) |
| KugelAudio | DE | [核验来源](https://www.kugelaudio.com/en/press) |
| Coqui | DE | [核验来源](https://www.linkedin.com/company/coqui-ai/) |
| Krafton | KR | [核验来源](https://www.krafton.com/wp-content/uploads/2025/08/2024-KRAFTON-ESG-Report-EN.pdf) |
| Speechmatics | GB | [核验来源](https://www.speechmatics.com/company/contact) |
| Neuphonic | GB | [核验来源](https://find-and-update.company-information.service.gov.uk/company/15612532) |
| Reson8 | NL | [核验来源](https://www.reson8.dev/terms) |
| Sarvam | IN | [核验来源](https://www.sarvam.ai/terms-of-service) |
| Maya Research | IN | [核验来源](https://www.linkedin.com/company/mayaresearch/) |
| Alebex | CA | [核验来源](https://www.alebex.ai/) |
| Hithink | CN | [核验来源](https://www.isca-archive.org/interspeech_2024/ye24_interspeech.pdf) |
| VUI Labs | CN | [核验来源](https://hk.linkedin.com/company/vui-labs/) |
| Noiz | CN | [核验来源](https://www.linkedin.com/company/noiz-ai/) |
| Synlan | SG | [核验来源](https://anypin.ai/collections/frontpage) |

Synlan 的身份由 [iFLYTEK 国际平台隐私政策](https://global.xfyun.cn/doc/policy/privacy.html) 明确为 SYNLAN TECHNOLOGY PTE. LTD.，其 [自有 Anypin 页脚](https://anypin.ai/collections/frontpage) 提供新加坡地址。StyleTTS 使用 [作者论文](https://arxiv.org/html/2306.07691) 的 Columbia University 机构信息。Newport AI 的 [公司资料](https://www.linkedin.com/company/new-port-ai/) 明确链接 newportai.com，避免误匹配同名公司。

## 保留未知的记录

剩余 16 处国家缺失来自 9 个独立模型/开发者：OpenChat 3.5、OpenChat 3.5 (0106)、OpenHermes 2.5、Dolphin 2.2.1、RWKV-4 Raven，及 BreezeBlue、OpenVoice、Kokoro、OpenLM Research。前五个旧模型在两张 Arena 文本总榜重复出现，仍有 10 处图标缺失。

这些记录涉及个人/社区项目或跨机构协作，未取得足以确认当前开发主体及单一国家的依据，保留未知。不能将基础模型 Mistral/Meta 的国家赋给微调开发者，不能将 GitHub/Hugging Face 的所在地当作项目国家，也不能因 Kokoro 名称推定为日本。OpenVoice 的研究合作涉及多个国家；BreezeBlue 法律页给出 RESONIA, INC.，尚未核实主体所在地。后续有可核实资料再更新共享目录。

## 验证范围

本轮 64 项后端/共享规则/小程序品牌策略定向回归通过，包含 200 个真实漏项名称向量、失败和不可用缓存、零外部请求、旧失败公司图标修复、未知微调边界、公司/模型图标分离，以及源文件变化拒绝、过期导出离线恢复。19 份图标生成校验、共享 Swift 生成校验、修改文件 Swift 语法解析与 git diff 检查通过；联系表已人工查看。小程序生产构建及全部运行模块校验通过。完整门禁由 Calmmit 执行，不在会话重复。

小程序、iPhone/iPad、Mac、Windows 的相关实现均通过共享来源同步；本轮未进行原生 UI 运行/视觉截图、安装或客户端发布。线上自动发布状态需以与本轮服务源签名匹配的回执及独立读取为准。
