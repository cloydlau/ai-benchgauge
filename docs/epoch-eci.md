# Epoch ECI

综合分类新增第三个来源 `epochECI`。官方说明：https://epoch.ai/eci；官方 CSV：https://epoch.ai/data/eci_scores.csv。

## 数据约定

- 使用 `Model` 作为稳定 ID、`Display name` 作为名称、`eci` 原始数值作为分数。按分数降序，同分按名称排序。模型与公司视图、筛选、缓存、共享贡献、导出均沿用现有管线。
- 显示两位小数。ECI 是指数，不是正确率，也没有 100 分上限；不展示相对榜首百分比。不同来源分数不能直接横比。
- CSV 的 `date` 是模型发布日期；不写入 `sourceUpdatedAt`，界面沿用抓取时间。
- 解析支持 BOM、CRLF、引号、逗号与多行字段；拒绝缺失列、损坏引号、非有限分数、重复 ID 和异常数据量。国家字段遵循仓库统一的 HK/MO/TW → CN 规则。
- 共享服务仅接受绑定 `epochECI` 官方地址的一次性抓取授权；该来源贡献的 MIME 为 `text/csv`。

## 界面

桌面端保持两列。综合左侧是 Artificial Analysis，右侧在已有控制行选择 Arena / Epoch ECI，选择会保存。iPhone / iPad 与微信小程序的综合分类有三个来源；其他分类仍为两个。切换分类和旧分享链接会限制来源索引到有效范围，立方体滑动每次只到相邻来源。

## 本次验证与限制

2026-10-18 已部署共享解析器，缓存 277 个模型；逐条核对线上缓存的模型 ID、名称、原始分数与官方 CSV 一致，且未冒用模型发布日期。测试覆盖 CSV 边界、授权及重放、来源贡献 MIME、三来源切换与边界、偏好与分享迁移、分数精度。

本机 Mac 原生前后截图使用同一测试数据，覆盖英／简／繁、900／1200 × 720、浅／深色，以及出现／刷新／稳定帧。原图和环境元数据在忽略目录 `work/epoch-eci/{before,after}/macos`；本机记录 macOS 27.0.1 (26A434)、实际 backing scale 1.0。这是本地未提交源码的检查，没有 CI 视觉审核记录。

Windows 交叉编译通过；没有 Windows 原生截图或源版本一致的 CI 视觉比较产物，尚未完成 Windows 视觉验收。微信开发者工具在刷新后报 `app.json is not found in the project root directory`，因此本次未完成小程序运行时视觉验收。小程序构建与自动化单元测试通过。发布仍受 `native-visual-review` 人工审核约束。
