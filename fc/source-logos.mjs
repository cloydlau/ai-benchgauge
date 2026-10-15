import { parse, serializeOuter } from 'parse5';

export const arenaSourcePages = Object.freeze({
  arenaText: 'https://arena.ai/leaderboard/text',
  codeArenaWebDev: 'https://arena.ai/leaderboard/code/webdev',
  arenaTextToImage: 'https://arena.ai/leaderboard/text-to-image',
  arenaTextToVideo: 'https://arena.ai/leaderboard/text-to-video',
});
export const maximumInlineLogoBytes = 64 * 1024;
const attribute = (node, name) => node.attrs?.find(item => item.name === name)?.value;
function standaloneSVG(mark) {
  // Arena applies some monochrome ink through page CSS (even over fill="none").
  // Materialize those presentation classes before rasterizing outside the page.
  for (const node of descendants(mark)) {
    const classes = (attribute(node, 'class') ?? '').split(/\s+/);
    for (const property of ['fill', 'stroke']) {
      const ink = classes.includes(`${property}-black`) ? '#303030'
        : classes.includes(`${property}-white`) ? '#FFFFFF'
          : classes.includes(`${property}-current`) ? 'currentColor' : null;
      if (!ink) continue;
      const existing = node.attrs.find(item => item.name === property);
      if (existing) existing.value = ink;
      else node.attrs.push({ name: property, value: ink });
    }
  }
  return serializeOuter(mark);
}
function* descendants(node) {
  const stack = [node];
  while (stack.length) {
    const current = stack.pop(); yield current;
    for (let i = (current.childNodes?.length ?? 0) - 1; i >= 0; i--) stack.push(current.childNodes[i]);
  }
}

// Read only the mark beside an exact model name in its table cell. Other SVGs
// in the row are rank ranges, links, badges and controls, not brand assets.
export function arenaRowLogos(html, names) {
  const logos = new Map(), ambiguous = new Set();
  if (!html.includes('<table')) return logos;
  const document = parse(html);
  for (const node of descendants(document)) {
    const name = attribute(node, 'title');
    if (!names.has(name)) continue;
    let cell = node.parentNode;
    while (cell && !['td', 'tr'].includes(cell.tagName)) cell = cell.parentNode;
    if (cell?.tagName !== 'td') continue;
    // The mark is in a preceding sibling of an ancestor of the model label.
    let branch = node, mark;
    while (branch.parentNode && branch.parentNode !== cell && !mark) {
      const siblings = branch.parentNode.childNodes ?? [];
      for (const sibling of siblings.slice(0, siblings.indexOf(branch))) {
        mark = [...descendants(sibling)].find(candidate => ['svg', 'img'].includes(candidate.tagName));
        if (mark) break;
      }
      branch = branch.parentNode;
    }
    if (!mark) continue;
    const logo = mark.tagName === 'svg' ? { svg: standaloneSVG(mark) } : { url: attribute(mark, 'src') };
    if (logo.svg && Buffer.byteLength(logo.svg) > maximumInlineLogoBytes || !logo.svg && !logo.url) continue;
    if (logos.has(name) && JSON.stringify(logos.get(name)) !== JSON.stringify(logo)) ambiguous.add(name);
    else logos.set(name, logo);
  }
  for (const name of ambiguous) logos.delete(name);
  return logos;
}
