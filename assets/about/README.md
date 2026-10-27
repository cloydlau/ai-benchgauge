# 关于页图片

`ai-models-group-portrait.jpg`：用户提供的 AI 模型拟人合影，原文件名为
`53899d01ly1iig29uw7f5j214y0tnkjl.jpg`，保留原始图片字节。

- 改编作者：[tombkeeper](https://weibo.com/u/1401527553)，依用户指定署名；
  [作品原帖](https://weibo.com/1401527553/RouFUDfWK)。作者名链接个人主页，旁边的链接图标指向作品原帖。
- 历史原图：**Benjamin Couprie** 摄，**1927 年第五届索尔维会议合影**，
  Institut International de Physique Solvay，布鲁塞尔。
  [原图及来源记录](https://commons.wikimedia.org/wiki/File:Solvay_conference_1927.jpg)；
  [英国皇家学会馆藏记录 IM/008123](https://catalogues.royalsociety.org/CalmView/Record.aspx?id=IM%2F008123&src=CalmView.Catalog)
  独立列明同一摄影者、年份及会议。

上述署名分别对应改编及历史摄影；不将本仓库的 MIT 许可套用于整张合成作品。

小程序构建从此处源图生成同尺寸、quality 86 的 JPEG（控制主包体积），
iOS 项目直接打包此处源图；不手工维护独立图片副本。
展示文案、图片尺寸与出处共用 `apps/weapp/src/core/about-artwork.js`，
iOS 经 `Scripts/ios-about.mjs` 生成本地化内容。
