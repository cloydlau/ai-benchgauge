import { text } from './catalog.js'

export function contributorsContent(snapshot, language) {
  return {
    title: text(['Contributors', '贡献者', '貢獻者'], language),
    note: text(['Circle area reflects commit count.', '圆面积随提交数变化。', '圓面積隨提交數變化。'], language),
    hint: text(['Tap an avatar to see contributions', '点按头像查看提交次数', '點按頭像查看提交次數'], language),
    expandLabel: text(['View contributors', '查看贡献者', '查看貢獻者'], language),
    closeLabel: text(['Done', '完成', '完成'], language),
    nodes: (snapshot?.nodes || []).map(node => ({
      ...node,
      avatar: node.avatar ? `/${node.avatar}` : '',
      countLabel: text([`${node.count.toLocaleString('en-US')} commits`, `${node.count.toLocaleString('en-US')} 次提交`, `${node.count.toLocaleString('en-US')} 次提交`], language),
      style: `left:${(node.x - node.r) * 100}%;top:${(node.y - node.r) * 100}%;width:${node.r * 200}%;height:${node.r * 200}%;`,
    })),
  }
}
