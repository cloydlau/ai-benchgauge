# 榜单数据许可与联系草稿

核对日期：2026-10-19。以下按当前公开条款与实际使用场景整理，不代表已经取得 AA 或 Arena 官网抓取授权。邮件均未发送。

## Epoch ECI

[Epoch 官方 ECI 页面](https://epoch.ai/eci)的 Citations 段落允许在署名后使用、分发与再现数据，链接至 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。署名作者为 Epoch AI，作品为 Epoch Capabilities Index。

应用内以及含 ECI 的图片导出使用同一份离线声明 `Sources/LeaderboardKit/Resources/EpochAttribution.json`：作者、作品、原始链接、许可链接，以及筛选、公司聚合、显示四舍五入和元数据补充/规范化说明。ECI 原始模型分数保留；公司视图属于本应用的派生展示。声明独立应用且无 Epoch AI 背书。数据许可与本软件 MIT 许可分开。

## Artificial Analysis：申请书面许可

优先使用[官方联系表单](https://artificialanalysis.ai/contact)，Topic 填 `Data licensing for a public AI leaderboard aggregation app`。官网明确提供面向用户产品和数据再分发的许可洽谈。也可联系条款所列的 `hello@artificialanalysis.ai`，请其转交数据许可团队。

[Data Platform Terms](https://artificialanalysiscdn.com/legal/ProDataPlatformTerms.pdf) 的 §2.4 涉及向第三方提供原始数据、产品/API 展示及与其他来源合并，§2.5 对以评测、排名、比较或模型选择为主要目的的第三方产品要求事先书面同意。§4.1–4.2 表明具体额外权限须写入 Order Form，Commercial 客户仍受 §2.5 约束。因此不能把购买 Pro、能够调用 API 或单纯标注来源当作本应用已经获准的依据。

首封邮件概括为面向 PC 端和移动端的跨端榜单应用，不枚举具体平台和随时可能变化的产品功能。正文独立询问当前数据使用的许可范围、获取与缓存/分发方式、署名要求及费用，取得书面确认；截图与数据流说明可在对方需要时补充。

末尾单列未来规划的附加问题，分别询问应用代码开源/闭源的要求，以及商业使用适用的要求或许可安排。不将当前数据使用许可与未来商业使用条件捆绑成一次“能否使用”的判断；不把未答复的商业条件视为已经获得授权。

### 英文草稿：AA

Subject: Leaderboard data use inquiry — AI BenchGauge

Hello Artificial Analysis team,

I maintain AI BenchGauge (AI 天梯), an independent cross-platform app for desktop and mobile that brings together AI model leaderboards from multiple sources. The app is currently free.

I would like to include Artificial Analysis leaderboard data, retaining the published model scores and rankings and clearly crediting your work with a link to the source.

Could you advise on the licensing arrangement for this use, including the approved data access channel, caching and delivery of the data through the app, attribution requirements, and any applicable fees? I would appreciate written confirmation of the permitted data-use scope.

Separately, I have two additional questions for future planning:

1. What requirements, if any, apply to whether the app's code is open-source or closed-source?
2. What requirements or licensing terms would apply to future commercial use of an app incorporating your data?

Thank you,
[Your name / legal entity]
[Reply email]
[App / repository link]

## Arena：优先采用官方开放数据集

需要修正此前仅根据网站使用条款得出的概括：[Arena 官方公告](https://arena.ai/blog/arena-leaderboard-dataset)明确发布了[官方 Hugging Face 榜单数据集](https://huggingface.co/datasets/lmarena-ai/leaderboard-dataset)，其数据集声明为 CC BY 4.0。包含 `text`、`text_style_control`、`webdev`、`text_to_image`、`text_to_video` 等子集，并有 `latest` 和 `full` split。

因此本应用将 Arena 四榜的数据获取迁移到该数据集，保留作者、数据集 URL、许可证链接、修改说明和数据集发布时间/修订记录；按 CC BY 4.0 可以用于商业场景。使用开放数据集与继续抓取官网是两种路径，不能把前者的许可自动套到当前官网抓取、官网图片、商标或其他未包含的内容上。2026-10-19 已实现四张 Arena 榜单向该数据集迁移，并在各端来源说明和分享图片中补齐作者、数据集链接、许可链接及处理/无背书说明；线上验证状态见[迁移记录](arena-dataset-migration.md)。该迁移不授予官网图片或商标的额外权限。

已逐项核对类别、style control、分数口径和发布时间；文本采用 `text_style_control/latest/overall`，WebDev、文生图、文生视频采用对应子集的 `latest/overall`。不混用类别补齐一张榜，不承诺日更；实测各榜发布日期不同。若数据集能满足需求，通常不需要另买一份该数据集的数据使用许可；若需要更实时的数据、未公开字段、官网资源或继续原抓取方式，向官方申请额外书面许可。

官方数据集公告建议通过 Arena Discord 或 Hugging Face Community 提问；[榜单政策页面](https://arena.ai/blog/policy)底部也有邮件入口，可请求转交数据许可/合作团队。尚未确认独立的商业授权邮箱，不把隐私邮箱冒称为授权销售邮箱。

### 英文草稿：Arena（数据集范围确认或额外权限）

Subject: Arena leaderboard dataset usage and data access inquiry — AI BenchGauge

Hello Arena team,

I maintain AI BenchGauge (AI 天梯), an independent cross-platform app for desktop and mobile that brings together AI model leaderboards from multiple sources. The app is currently free.

We use your official `lmarena-ai/leaderboard-dataset` on Hugging Face under CC BY 4.0, retaining the published model scores and rankings and providing source and license attribution.

Could you point us to guidance on dataset updates and use of the Arena name and logo alongside the data? If you offer additional data access beyond the published dataset, I would also appreciate information on the available arrangements, including caching, delivery through the app, attribution requirements and fees.

Separately, if additional access involves a separate agreement, I have two questions for future planning:

1. What requirements, if any, would that agreement place on whether the app's code is open-source or closed-source?
2. What requirements or licensing terms would apply to future commercial use under that agreement?

If this is not the right contact, please forward the inquiry to your data licensing or partnerships team.

Thank you,
[Your name / legal entity]
[Reply email]
[App / repository link]

## OpenRouter 使用 AA 的公开证据

[February Release Spotlight](https://openrouter.ai/blog/announcements/february-release-spotlight/)说明其模型页面展示 AA 提供的基准分数；[Exacto 官方文章](https://openrouter.ai/blog/announcements/provider-variance-introducing-exacto/)明确说明与 AA 合作运行 DeepSeek 3.1 评测。

这能确认公开的数据集成及合作关系；没有找到双方公开的授权合同、费用、再分发范围或其适用条款。不能据此断言其一定购买某套餐，也不能把 OpenRouter 的展示或 API 返回当作授予本应用上游数据再分发权。可向 AA 询问与其同类的产品集成授权，是否批准以书面答复或协议为准。
