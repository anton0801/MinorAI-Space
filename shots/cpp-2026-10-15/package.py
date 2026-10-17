"""Package verified App Store PNGs, provenance, editable layouts and metadata."""
from pathlib import Path
import json, shutil, hashlib, zipfile
from PIL import Image
ROOT=Path(__file__).resolve().parent
DATA=json.loads((ROOT/'campaign.json').read_text())
assert json.loads((ROOT/'qa-report.json').read_text())['pass']
META=ROOT/'metadata';META.mkdir(exist_ok=True)
metadata={
 'cpp-mind-maps':{'keywords_to_verify':['brainstorm','outline'],'search_intent_hypotheses':['ai mind map','mind mapping','brainstorming','visual notes'],'promotional_text':'Turn ideas, PDFs, links and videos into editable mind maps. Refine them with AI, then build slides or turn your next steps into tasks.'},
 'cpp-study':{'keywords_to_verify':['study','flashcards','lecture','quiz'],'search_intent_hypotheses':['flashcards','study notes','ai study assistant','exam preparation'],'promotional_text':'Turn your material into mind maps, review with flashcards and spaced repetition, and check your understanding with AI-generated quizzes.'},
 'cpp-slides':{'keywords_to_verify':[],'requires_approved_keyword_update':['presentation','deck'],'search_intent_hypotheses':['ai presentation maker','slide maker','presentation creator'],'promotional_text':"Turn a mind map into a presentation. Customize your slides, add speaker notes and export to PowerPoint when you're ready to share."},
 'cpp-tasks':{'keywords_to_verify':['planner','tasks','organizer'],'search_intent_hypotheses':['task planner','project planner','daily planner','task organizer'],'promotional_text':'Turn ideas into tasks with due dates. See what needs attention in Today and return to the map behind each task.'}
}
for key,item in metadata.items():
 assert len(item['promotional_text'])<=170
 item.update({'locale':'en-US','status':'proposed_not_applied','note':'Verify against latest approved version in App Store Connect. Search volume not validated.'})
 (META/f'{key}.json').write_text(json.dumps(item,ensure_ascii=False,indent=2)+'\n')
 (META/f'{key}-promotional-text.txt').write_text(item['promotional_text']+'\n')
keywords='presentation,study,flashcards,planner,tasks,notes,pdf,outline,brainstorm,lecture,quiz,deck,summary'
assert len(keywords)<=100
(META/'proposed-next-version-keywords.txt').write_text(keywords+'\n')
(META/'README_RU.md').write_text('Ключи не применены. Сверьте последнюю одобренную версию в Connect. Новый список добавляет presentation/deck и убирает voice/organizer; organizer для Tasks доступен только пока он присутствует в одобренном наборе. Slides уже есть в локальном подзаголовке. Частотность не проверена. Promotional Text ≤ 170 символов.\n')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={'app_version':'3.0.1','locale':'en-US','capture_date':'2026-10-15','export_date':'2026-10-16','git_base':'681b515','code_state':'local DEBUG fixtures; see build-final.log','pixel_size':[1320,2868],'color':'RGB','publication_status':'not_published','test_status':'not_launched','simulators_created_for_task':['0728F6FC-8CCE-4F3A-9C5E-0CF8F403297D','8A78051D-EF64-49A8-9D95-E143C5A849DD'],'simulator_cleanup':'Both UUIDs absent from simctl list on 2026-10-16','captures':[],'files':[]}
for p in sorted((ROOT/'raw').glob('*.png')):
 with Image.open(p) as im:size=list(im.size)
 source={'map':'shots/appstore-en-3.0.1/raw/map-travel.png','task':'shots/appstore-en-3.0.1/raw/task.png'}.get(p.stem,'dedicated simulator capture; capture.py scene '+p.stem)
 manifest['captures'].append({'file':str(p.relative_to(ROOT)),'source':source,'size':size,'sha256':sha(p)})
for setkey,group in DATA['sets'].items():
 folder=ROOT/'upload/en-US'/setkey;folder.mkdir(parents=True,exist_ok=True)
 for n,key in enumerate(group['cards'],1):
  src=ROOT/'artwork'/f'{key}.png';dst=folder/f'{n:02}-{key}.png'
  with Image.open(src) as im:assert im.size==(1320,2868) and im.mode=='RGB'
  shutil.copy2(src,dst)
  manifest['files'].append({'file':str(dst.relative_to(ROOT)),'card':key,'scene':DATA['cards'][key]['scene'],'sha256':sha(dst)})
assert len(manifest['files'])==36
for a,b in zip(DATA['sets']['default-a']['cards'][1:],DATA['sets']['default-b']['cards'][1:]):assert a==b
(ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
archive=ROOT/'Minor-AI-CPP-EN-US-2026-10-15.zip'
paths=[]
for folder in ['upload','metadata','artwork','layouts','raw']:
 paths.extend((ROOT/folder).rglob('*'))
paths += [ROOT/n for n in ['README.md','STRATEGY_RU.md','campaign.json','manifest.json','qa-report.json','index.html','capture.py','preview.py','render_previews.py','qa_layouts.py','package.py','capture-manifest.json']]
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(paths):
  if p.is_file() and p.name!='.DS_Store':z.write(p,p.relative_to(ROOT))
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 assert len([n for n in z.namelist() if n.startswith('upload/') and n.endswith('.png')])==36
print(f'Packaged {len(manifest["files"])} PNG placements / {len(DATA["cards"])} unique cards; ZIP {archive.stat().st_size/1048576:.1f} MiB; proposed keywords {len(keywords)} characters.')
