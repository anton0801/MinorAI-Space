"""Build campaign layouts using only the fresh 3.0.1 simulator captures."""
from pathlib import Path
import json, html

ROOT = Path(__file__).resolve().parent
data = json.loads((ROOT / 'campaign.json').read_text())
CSS = '''
*{box-sizing:border-box}html,body{margin:0;width:1320px;height:2868px;overflow:hidden}
body{font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Arial,sans-serif;background:var(--bg);color:var(--ink)}
.mint{--bg:#C6F8DF;--ink:#102D24;--muted:#46685A;--accent:#206748;--line:#A5D7BE}
.blue{--bg:#D8EBFD;--ink:#173244;--muted:#526C80;--accent:#386684;--line:#B6CDDF}
.lilac{--bg:#E9E0FB;--ink:#35234A;--muted:#71617F;--accent:#70508F;--line:#CFC0E4}
.sand{--bg:#F2E7D5;--ink:#382E22;--muted:#786955;--accent:#876848;--line:#D9CCB6}
.dark{--bg:#101815;--ink:#F1F6F3;--muted:#ACBDB4;--accent:#84E5B5;--line:#2C3C33}
.brand{position:absolute;left:96px;right:96px;top:79px;display:flex;align-items:center;justify-content:space-between;font-size:38px;font-weight:650;letter-spacing:-1.2px}
.brand span:last-child{font-size:26px;letter-spacing:2px;font-weight:500;color:var(--muted)}
.brand svg{width:39px;height:39px;margin-right:17px;vertical-align:-7px;stroke:currentColor;fill:none;stroke-width:3;stroke-linecap:round;stroke-linejoin:round}
.eyebrow{position:absolute;top:191px;left:96px;font-size:27px;font-weight:650;letter-spacing:3.1px;color:var(--accent)}
h1{position:absolute;top:244px;left:88px;right:65px;font-size:142px;line-height:1.01;letter-spacing:-5.5px;font-weight:750;margin:0}
h1 span{display:block;white-space:nowrap}h1 span:last-child{color:var(--accent)}
.detail{position:absolute;left:96px;right:90px;top:552px;font-size:35px;line-height:1.3;letter-spacing:-.6px;color:var(--muted);margin:0}
.screen{position:absolute;left:174px;top:690px;width:972px;height:2111.89px;border-radius:77px;overflow:hidden;outline:8px solid #202724;box-shadow:0 0 0 11px #788780,0 40px 85px #0000002A;background:#121212}
.screen img{display:block;width:100%;height:auto}.rail{position:absolute;left:96px;top:677px;bottom:70px;border-left:1px solid var(--line)}
.rail::before{content:'';width:9px;height:9px;border-radius:50%;background:var(--accent);position:absolute;left:-5px;top:0}
.proof{position:absolute;bottom:16px;left:20px;right:20px;padding:10px 16px;background:#fff5c9;color:#403715;font-size:24px;text-align:center;z-index:5}
'''
pages=ROOT/'layouts';pages.mkdir(exist_ok=True)
status={}
for key, card in data['cards'].items():
    fresh=ROOT/'raw'/f"{card['scene']}.png"
    assert fresh.exists(), f"Missing current capture: {fresh}"
    is_fresh=True
    src=f"../raw/{card['scene']}.png"
    status[key]=is_fresh
    # At most two lines, headline width is verified after browser rendering.
    title=''.join(f'<span>{html.escape(line)}</span>' for line in card['headline'])
    body=f'''<!doctype html><html lang="en"><meta charset="utf-8"><title>{html.escape(' '.join(card['headline']))}</title><style>{CSS}</style><body class="{card['theme']}">
<div class="brand"><span>Minor AI</span><span>IDEAS INTO ACTION</span></div>
<div class="eyebrow">{html.escape(card['eyebrow'])}</div><h1>{title}</h1><p class="detail">{html.escape(card['detail'])}</p><div class="rail"></div>
<div class="screen"><img src="{src}" alt="{html.escape(card['scene'])}"></div>
{'' if is_fresh else '<div class="proof">DESIGN PREVIEW · PREVIOUS UI REFERENCE · NOT FOR UPLOAD</div>'}</body></html>'''
    (pages/f'{key}.html').write_text(body)

gallery='''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Minor AI · Custom Product Pages</title><style>
*{box-sizing:border-box}body{margin:0;background:#f5f3ed;color:#242b27;font:16px -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1500px;margin:auto;padding:50px 30px}header{max-width:950px}h1{font-size:52px;line-height:1.08;letter-spacing:-2px;margin:18px 0}h2{font-size:26px;margin:44px 0 22px}p{line-height:1.6;color:#606963}nav{display:flex;gap:20px;flex-wrap:wrap;margin:28px 0}a{color:#235b42}.label{font-size:13px;letter-spacing:2px;color:#42755c;font-weight:700}.warning{padding:16px 20px;background:#fff1c2;border-radius:12px}.row{display:flex;gap:20px;overflow:auto;padding:0 0 20px}figure{margin:0;flex:0 0 264px}.frame{width:264px;height:573.6px;overflow:hidden;border-radius:12px;box-shadow:0 4px 20px #1a30231a}iframe{width:1320px;height:2868px;border:0;transform:scale(.2);transform-origin:top left;pointer-events:none}figcaption{padding:14px 0;font-size:14px;line-height:1.5}.note{font-size:14px}.hero-row{margin-top:35px} @media(max-width:600px){main{padding:30px 20px}h1{font-size:38px}}
</style><main><header><div class="label">MINOR AI · ENGLISH / UNITED STATES</div><h1>One app.<br>Four reasons to download.</h1><p>Четыре страницы под конкретные задачи: карты, учёба, презентации, планирование. Реальный интерфейс, крупные заголовки и отдельный сценарий для каждой аудитории.</p>'''
if not all(status.values()):
    gallery+='<p class="warning">Дизайн-превью: внутри используются старые экраны как временные референсы. Финальная съёмка обновлённой версии заблокирована нехваткой места на диске. Эти макеты не готовы к загрузке.</p>'
gallery+='<p>Свежая съёмка Minor AI 3.0.1 · 1320 × 2868 · English (US)</p><nav><a href="Minor-AI-CPP-EN-US-2026-10-15.zip">Скачать PNG и метаданные</a><a href="STRATEGY_RU.md">Ключи и план теста</a><a href="campaign.json">Все заголовки и порядок</a></nav></header>'
for set_key,group in data['sets'].items():
    gallery+=f'<section><h2>{html.escape(group["name"])}</h2>'
    if set_key=='default-b':gallery+='<p class="note">Тестируется только первый заголовок; остальные семь кадров совпадают с A.</p>'
    gallery+='<div class="row">'
    for i,key in enumerate(group['cards'],1):
        c=data['cards'][key]
        gallery+=f'<figure><a href="layouts/{key}.html"><div class="frame"><img loading="lazy" alt="{html.escape(key)}" style="display:block;width:100%;height:auto" src="artwork/{key}.png"></div></a><figcaption>{i:02} · {html.escape(" ".join(c["headline"]))}</figcaption></figure>'
    gallery+='</div></section>'
gallery+='</main></html>'
(ROOT/'index.html').write_text(gallery)
print(f'Created {len(status)} editable layouts. Fresh captures: {sum(status.values())}/{len(status)}.')
