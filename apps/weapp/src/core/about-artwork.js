import { text } from './catalog.js'

// Shared by the mini-program and the generated iPhone/iPad About content.
export const aboutArtworkFile = 'ai-models-group-portrait.jpg'
export function aboutArtwork(language) {
  return {
    image: `/assets/about/${aboutArtworkFile}`,
    sourceURL: 'https://weibo.com/1401527553/RouFUDfWK',
    width: 1474,
    height: 1067,
    title: text(['Across a century', '跨世纪的同框', '跨世紀的同框'], language),
    alt: text(['AI models as illustrated characters in front of a historic group photograph',
      '历史合影前，DeepSeek、ChatGPT、Claude、Gemini、Grok、Kimi、GLM、Qwen 的拟人插画',
      '歷史合影前，DeepSeek、ChatGPT、Claude、Gemini、Grok、Kimi、GLM、Qwen 的擬人插畫'], language),
    previewLabel: text(['View full image', '查看大图', '查看大圖'], language),
    sourceLabel: text(['Artwork source', '作品出处', '作品出處'], language),
    credits: [
      {
        id: 'adaptation',
        role: text(['Via', '出处', '出處'], language),
        name: 'tombkeeper',
        url: 'https://weibo.com/1401527553/RouFUDfWK',
        detail: '',
        sourceIcon: 'weibo',
      },
      {
        id: 'photograph',
        role: text(['Photo', '原图', '原圖'], language),
        name: 'Benjamin Couprie',
        url: 'https://commons.wikimedia.org/wiki/File:Solvay_conference_1927.jpg',
        detail: text(['Fifth Solvay Conference, 1927', '1927 年第五届索尔维会议', '1927 年第五屆索爾維會議'], language),
        sourceIcon: 'solvay',
      },
    ],
  }
}
