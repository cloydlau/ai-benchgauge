# WeChat platform icon

Source: [Tabler Icons brand-wechat outline](https://github.com/tabler/tabler-icons/blob/main/icons/outline/brand-wechat.svg), retrieved 2026-10-26.
The source SVG is unchanged. For the shared 18pt / 36rpx platform row, the
exporter reduces the 24-unit SVG's stroke from 2 to 4/3 units, giving a 1pt
display stroke that matches the neighboring platform icons instead of 1.5pt.
Its large rear bubble, small front bubble, opposing tails
and four dots identify WeChat; do not replace it with generic chat symbols.
This is a Tabler rendition, not official Tencent artwork. WeChat is Tencent's
trademark; this icon identifies the WeChat mini-program platform only.

Tabler Icons is MIT licensed, copyright (c) 2020-2026 Paweł Kuna.
The full license is retained in the parent `NOTICE.txt` and packaged with both
clients. Run `node Scripts/source-logos.mjs` to generate the shared 54×54 PNGs
and `node Scripts/source-logos.mjs --check` to check Apple bundle copies.
The mini-program build uses the same renderer. Both themes retain the existing
neutral icon colors. No new icon library is loaded at runtime.
