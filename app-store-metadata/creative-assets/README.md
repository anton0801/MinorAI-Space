# Minor AI — App Store creative assets

Final direction: **H2 / Glass Canvas + S1 / Duet**, selected by the user on 6 October 2026.

The header pairs the real Minor mark with a glass map canvas, mint light, a fine dot grid and sparse colored branches. The search image uses a short headline and large crops of the real assistant and slide editor. EN and RU use identical artwork, panel positions, crops and scaling; headlines and captured interface text are localized.

## Upload files

| Locale | Product page header | Search results |
| --- | --- | --- |
| English | `en-US/header.png` — 3840 × 1646 | `en-US/search.jpg` — 3840 × 2560 |
| Russian | `ru/header.png` — 3840 × 1646 | `ru/search.jpg` — 3840 × 2560 |

All exports are RGB, contain an embedded sRGB IEC61966-2.1 profile, and have no alpha channel. Requested `header.jpg` files are also included. Use **header.png** for upload: Apple's current creative-assets specification lists PNG for the product page header. Search supports JPEG and PNG.

Official references checked 6 October 2026:
- [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
- [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/)

## Preview and safety geometry

- `preview/final-contact-sheet.jpg`: all four final compositions, EN and RU.
- `preview/header-concepts.jpg`: three proposed header directions.
- `preview/search-concepts.jpg`: two proposed search directions.
- `preview/*-overlay.jpg`: composition guides, never upload these.
- `preview/*-header-iphone.jpg`: supplied iPhone crop, x330–3530.
- `preview/*-search-phone-size.jpg`: full 3:2 search image at 390 px width.

The header's mark, headline and crisp hero branches fit within the supplied key-art area x1097–2743, y493–1154. Background light and glass continue outside it as atmosphere. Orange lines show the supplied horizontal iPhone crop; navigation circles are approximate obstruction reminders. The search inset is explicitly a **design margin, not an official Apple safe-area template**; no additional search crop was assumed.

## Source integrity

- Real mark: `Minor Ai/Assets.xcassets/logo.imageset/minor_plus-3.png`. Only transparent outer padding was cropped. The mark was uniformly scaled and composited, with no redrawing, recoloring, rotation or distortion.
- English screenshots: `shots/raw/en/03-assistant.png`, `04-slides.png`.
- Russian screenshots: `shots/raw/ru/03-assistant.png`, `04-slides.png`.
- Assistant crop: `(0, 350, 1320, 1760)`; slide crop: `(0, 165, 1320, 1240)`, in source pixels.
- The pricing map was not used. The slide crop excludes lower thumbnails containing a QR code. No interface text was fabricated or retouched. Rounded presentation masks and framing sit outside the source interface content.
- Background plates in `sources/` were generated with the built-in image generation tool, without text, branding or UI. Prompts are retained in `sources/prompts.json`. Final logo, typography and screenshot composition were added locally.
- Font: native SF Pro Heavy, `/System/Library/Fonts/SFNS.ttf`. Header size 150 px (106 px cap height); search size 200 px. Tracking −0.025 em.
- Original logo and screenshot files remain unchanged.

## Verification and reproducibility

`verification.json` records `sips` dimensions, alpha and profile checks, hashes, safe-area checks and localization consistency. `layout-manifest.json` records element bounds, source crops and scale factors. `ocr-report.json` retains Apple Vision's recognized text for every final export. OCR can confuse uppercase I with lowercase l; the actual rendered headline is “AI mind maps & slides”.

Visually checked the final contact sheet, localized composition previews and phone-size previews. No prices, URLs, copyright marks, awards, other-platform logos or age-inappropriate content are visible. Russian text has no clipped headline or awkward forced line breaks. The assistant panel includes the full final response card in both languages. Validation covers the exported files; they have not been uploaded to App Store Connect.

From the repository root, on macOS with Pillow and NumPy installed:

```bash
python3 app-store-metadata/creative-assets/scripts/compose.py --concepts
python3 app-store-metadata/creative-assets/scripts/compose.py --header glass --search duet
swiftc -module-cache-path /tmp/minor-creative-module-cache app-store-metadata/creative-assets/scripts/ocr.swift -o /tmp/minor-creative-ocr
/tmp/minor-creative-ocr app-store-metadata/creative-assets
python3 app-store-metadata/creative-assets/scripts/verify.py
```

Apple Vision may require execution outside a restricted sandbox. The compositor does not call an image model again; it uses the saved plates. No video is included in this still-image delivery.
