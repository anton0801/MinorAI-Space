"""Read-only layout geometry and output validation for campaign documents."""
from pathlib import Path
import json, subprocess, re, html
from PIL import Image
from render_previews import CHROME, render
ROOT=Path(__file__).resolve().parent
data=json.loads((ROOT/'campaign.json').read_text())
frames=''.join(f'<iframe id="{key}" src="layouts/{key}.html" width="1320" height="2868"></iframe>' for key in data['cards'])
script='''<script>setTimeout(()=>{let checks=[...document.querySelectorAll('iframe')].map(f=>{let d=f.contentDocument, errors=[]; for(let s of d.querySelectorAll('h1 span,.eyebrow,.detail')){let r=d.createRange();r.selectNodeContents(s);let b=r.getBoundingClientRect();if(b.right>1255||b.left<60)errors.push('Text exceeds safe margin: '+s.textContent);if(s.matches('h1 span')&&b.bottom>552)errors.push('Headline overlaps detail');if(s.matches('.detail')&&b.bottom>660)errors.push('Detail overlaps screen')}let im=d.querySelector('img');if(!im.complete||im.naturalWidth===0)errors.push('Missing image');return {card:f.id,errors}});document.getElementById('result').textContent=JSON.stringify(checks)},2500)</script>'''
path=ROOT/'qa-layouts.html'; path.write_text('<html><body><pre id="result"></pre>'+frames+script+'</body></html>')
r=subprocess.run([str(CHROME),'--no-sandbox','--disable-gpu','--allow-file-access-from-files','--user-data-dir=/tmp/minor-cpp-qa','--virtual-time-budget=4000','--dump-dom',path.as_uri()],capture_output=True,text=True,check=True)
m=re.search(r'<pre id="result">(.*?)</pre>',r.stdout,re.S)
assert m and m[1],r.stderr
geometry=json.loads(html.unescape(m[1]))
files=[]
for key in data['cards']:
 p=ROOT/'artwork'/f'{key}.png'
 with Image.open(p) as im:
  files.append({'card':key,'size':list(im.size),'mode':im.mode})
  assert im.size==(1320,2868) and im.mode=='RGB',(key,im.size,im.mode)
report={'geometry':geometry,'files':files,'pass':all(not x['errors'] for x in geometry)}
(ROOT/'qa-report.json').write_text(json.dumps(report,indent=2))
for x in geometry:
 if x['errors']:print(x)
assert report['pass'],'Layout errors'
print(f'PASS: {len(files)} RGB images, exact dimensions, all text within safe margins')
for n in range(2):
 keys=list(data['cards'])[n*12:(n+1)*12]
 board='<html><style>body{margin:0;padding:24px;background:#eee;font:18px sans-serif}.grid{display:grid;grid-template-columns:repeat(4,330px);gap:20px}img{display:block;width:330px}p{margin:8px 0}</style><div class="grid">'
 for key in keys:board+=f'<div><img src="artwork/{key}.png"><p>{key}</p></div>'
 board+='</div></html>'
 p=ROOT/f'qa-board-{n+1}.html';p.write_text(board)
 render(p,ROOT/f'qa-board-{n+1}.png',1428,2350)
