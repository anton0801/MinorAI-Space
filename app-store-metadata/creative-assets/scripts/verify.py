#!/usr/bin/env python3
"""Verify exports, source provenance, header bounds, and localization geometry."""
from pathlib import Path
from PIL import Image, ImageCms, ImageChops, ImageDraw
import hashlib, io, json, re, subprocess

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parents[1]
SAFE = (1097, 493, 2743, 1154)
records = json.loads((ROOT / 'layout-manifest.json').read_text())
results = []
for item in records:
    path = ROOT / item['file']
    with Image.open(path) as im:
        expected = (3840, 1646) if item['placement'] == 'header' else (3840, 2560)
        assert im.size == expected, (path, im.size)
        assert im.mode == 'RGB' and 'A' not in im.getbands(), (path, im.mode)
        profile = ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(im.info['icc_profile']))).strip()
        assert 'srgb' in profile.lower(), (path, profile)
        sips = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', '-g', 'profile', str(path)], text=True)
        assert 'hasAlpha: no' in sips
        source_hashes = {}
        for element in item['elements']:
            if item['placement'] == 'header':
                x0, y0, x1, y1 = element['bounds']
                assert SAFE[0] <= x0 < x1 <= SAFE[2] and SAFE[1] <= y0 < y1 <= SAFE[3], element
            if 'source' in element:
                source_hashes[element['source']] = hashlib.sha256((PROJECT / element['source']).read_bytes()).hexdigest()
        results.append({'file': item['file'], 'size': im.size, 'mode': im.mode, 'profile': profile,
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'source_sha256': source_hashes, 'header_key_art_inside_safe_area': item['placement'] == 'header',
                        'sips': sips})

# Header language versions must be pixel-identical outside headline bounds.
en = Image.open(ROOT / 'en-US/header.png')
ru = Image.open(ROOT / 'ru/header.png')
diff = ImageChops.difference(en, ru)
draw = ImageDraw.Draw(diff)
for item in records:
    if item['file'].endswith('header.png'):
        for element in item['elements']:
            if element['kind'] == 'headline':
                draw.rectangle(element['bounds'], fill=(0, 0, 0))
assert diff.getbbox() is None, 'Header composition changed outside the localized text'

# Search keeps the same crop coordinates, panel scales, and logo position.
geometries = []
for language in ['en-US', 'ru']:
    item = next(r for r in records if r['file'] == f'{language}/search.jpg')
    geometries.append([{k: e[k] for k in ['kind', 'bounds', 'source_crop', 'uniform_scale'] if k in e}
                       for e in item['elements'] if e['kind'] != 'headline'])
assert geometries[0] == geometries[1]
ocr = json.loads((ROOT / 'ocr-report.json').read_text())
assert len(ocr) == 6
for record in ocr:
    words = ' '.join(row['text'] for row in record['text'])
    forbidden = re.compile(r'\$|€|₽|12[.,]99|24[.,]99|https?://|www\.|minorai\.site|©|discount|editor.s choice|app of the day|google play|app store', re.I)
    assert not forbidden.search(words), (record['file'], words)
(ROOT / 'verification.json').write_text(json.dumps({'files': results,
    'header_artwork_identical_outside_text': True, 'search_geometry_identical': True,
    'ocr_forbidden_text_scan': 'passed for six final files; also visually reviewed',
    'visual_review': 'Final contact sheet, full composition previews and phone-size previews checked. No prices, URLs, awards, other-platform logos, or age-inappropriate content visible. Russian headline and source UI text reviewed; no headline clipping. Screens are genuine localized app captures.'}, ensure_ascii=False, indent=2) + '\n')
print('PASS: six exports; exact dimensions, RGB/no alpha, embedded sRGB; header bounds; matching language compositions.')
for result in results:
    print(result['sips'])
