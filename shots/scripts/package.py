#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
import json, hashlib, zipfile, html
from capture import SCENES, DEVICE
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'manifest.json').read_text())
ocr=json.loads((ROOT/'ocr-raw.json').read_text())
ocr_by_file={str(Path(x['file']).relative_to(ROOT)):x for x in ocr}
checks=[]
for item in manifest:
    slug=Path(item['file']).stem
    item['launch_flags']=['-didOnboard','YES','-auditSignedOut','-demoPro','-appLanguage',item['language'],*dict(SCENES)[slug]]
    for kind in ['file','source']:
        p=ROOT/item[kind]
        with Image.open(p) as image:
            assert image.size==(1320,2868)
            assert image.mode=='RGB' and 'transparency' not in image.info
        assert p.read_bytes()[25]==2, 'PNG must be truecolor RGB without alpha'
        item[kind+'_sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
    text='\n'.join(x['text'] for x in ocr_by_file[item['source']]['text'])
    assert '09:41' in text or '9:41' in text,item['source']
    for bad in ['Get Minor Plus','Получить Plus','Allow AI in Settings','Разрешите ИИ','DEBUG']:
        assert bad.lower() not in text.lower(),(item['source'],bad)
    if slug=='01-map':
        assert '$12.99' in text and '$24.99' in text
    checks.append({'file':item['file'],'size':True,'opaque_rgb_png':True,'status_time_941':True,'no_upgrade_or_debug_notice':True})
assert len(manifest)==16
assert all(sum(x['language']==lang for x in manifest)==8 for lang in ['en','ru'])
(ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(ROOT/'qa.json').write_text(json.dumps({'device':'iPhone 16 Pro Max','simulator':DEVICE,'runtime':'iOS 18.5','images_checked':32,'screens_per_language':8,'visual_review':'All 16 final compositions and all source screens reviewed. Horizontal scroll controls retain their native partially visible trailing items.','checks':checks},ensure_ascii=False,indent=2)+'\n')
page='''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Minor AI — App Store screenshots</title><style>*{box-sizing:border-box}body{margin:0;background:#121212;color:#eee;font:16px -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1600px;margin:auto;padding:44px 28px}h1{font-size:38px;letter-spacing:-1px;margin:12px 0}p{color:#a9aaa9;line-height:1.6}a{color:#2fff9e}nav{display:flex;gap:24px;margin:28px 0 48px}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:22px}figure{margin:0}img{display:block;width:100%;border-radius:18px;border:1px solid #303330}figcaption{padding:12px 0 28px;color:#a9aaa9;font-size:14px}section{margin:50px 0}h2{font-size:26px}small{display:block;margin-top:8px}@media(max-width:900px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:450px){.grid{grid-template-columns:1fr}}</style><main><p style="color:#2fff9e">MINOR AI · APP STORE</p><h1>Два языка. Восемь экранов.</h1><p>Реальные снимки Debug-приложения · iPhone 16 Pro Max · 1320 × 2868 · PNG без прозрачности.<br>Нажмите на изображение, чтобы открыть полный размер. Кадр 8 — презентация с заметками вместо голосового режима.</p><nav><a href="#en">English</a><a href="#ru">Русский</a><a href="Minor-AI-App-Store-EN-RU.zip" download>Скачать набор</a><a href="README.md">Инструкция</a></nav>'''
for lang,title in [('en','English'),('ru','Русский')]:
    page+=f'<section id="{lang}"><h2>{title}</h2><div class="grid">'
    for item in [x for x in manifest if x['language']==lang]:
        caption=html.escape(item['caption']);src=item['file']
        page+=f'<figure><a href="{src}"><img src="{src}" alt="{caption}" loading="lazy"></a><figcaption>{Path(src).stem} · {caption}<small><a href="{src}" download>PNG с подписью</a> · <a href="{item["source"]}" download>Исходный экран</a></small></figcaption></figure>'
    page+='</div></section>'
page+='</main></html>'
(ROOT/'index.html').write_text(page)
with zipfile.ZipFile(ROOT/'Minor-AI-App-Store-EN-RU.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for p in sorted((ROOT/'app-store').rglob('*.png')):archive.write(p,p.relative_to(ROOT/'app-store'))
    for name in ['README.md','manifest.json','qa.json','contact-sheet-en.jpg','contact-sheet-ru.jpg']:
        archive.write(ROOT/name,name)
print('PASS: 16 framed + 16 raw, 1320×2868, RGB PNG, 09:41, prices, manifest and ZIP')
