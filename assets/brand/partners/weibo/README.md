# Weibo attribution icon

`logo.png` is the 32×32 full-color frame extracted losslessly from Weibo's
[official favicon](https://weibo.com/favicon.ico), retrieved 2026-10-27.

- Original ICO SHA-256: `b86c00f90f8b742d1fb477034fb1916832857b8ac8a77f34a9c2904f3051194a`.
- Canonical PNG SHA-256: `17f4d44f40071a79c5fa08d17a3edffc98df9d55b05766132e5503ef3bb1b55e`.
- Conversion: Pillow `Image.open(ico).ico.getimage((32, 32)).save(png)`;
  original colors, transparency and full canvas retained.

The Weibo mark retains its owner's rights; no repository MIT or Simple Icons
CC0 license is asserted for this official asset. It identifies the original
artwork post, with the icon and tombkeeper's name sharing the same link.

`node Scripts/source-logos.mjs` exports 54×54 PNGs in the original red, yellow,
black and white for both themes and both mobile clients. Display size remains
matched to the attribution text. Runtime images are bundled for offline use.
