#!/usr/bin/env python3
"""Frame real simulator captures without changing their UI content."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import json, math
ROOT=Path(__file__).resolve().parents[1]
W,H=1320,2868
BOLD='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
REG='/System/Library/Fonts/Supplemental/Arial.ttf'
COPY={
'en':['Any idea, mapped in seconds','From a topic, link, YouTube, PDF or voice','An AI assistant that knows your maps','Slides from your map, with PowerPoint export','Tasks and reminders from all your maps','Learn with flashcards and quizzes','Edit maps together','Your slides and speaker notes, together'],
'ru':['Любая идея — карта за секунды','Из темы, ссылки, YouTube, PDF или голоса','ИИ-помощник, который знает ваши карты','Презентация из карты с экспортом в PowerPoint','Задачи и напоминания из всех карт','Учитесь по карточкам и тестам','Редактируйте карты вместе','Слайды и заметки для выступления']}
def wrap(text,font,maxwidth):
    words=text.split()
    candidates=[]
    for split in range(1,len(words)):
        lines=[' '.join(words[:split]),' '.join(words[split:])]
        widths=[font.getlength(x) for x in lines]
        if max(widths)<=maxwidth: candidates.append((abs(widths[0]-widths[1]),lines))
    if font.getlength(text)<=maxwidth:return [text]
    if candidates:return min(candidates)[1]
    return None
manifest=[]
for lang,captions in COPY.items():
    dest=ROOT/'app-store'/lang;dest.mkdir(parents=True,exist_ok=True)
    for i,source in enumerate(sorted((ROOT/'raw'/lang).glob('*.png'))):
        caption=captions[i]
        shot=Image.open(source).convert('RGB')
        assert shot.size==(W,H),(source,shot.size)
        # Low-resolution radial light, expanded smoothly; always opaque.
        bg=Image.new('RGB',(330,717))
        pix=bg.load()
        for y in range(717):
            for x in range(330):
                glow=math.exp(-(((x-255)/155)**2+((y-195)/190)**2)*2)*.085
                pix[x,y]=tuple(round(18+(v-18)*glow) for v in (47,255,158))
        canvas=bg.resize((W,H),Image.Resampling.BICUBIC).convert('RGBA')
        draw=ImageDraw.Draw(canvas)
        brand=ImageFont.truetype(BOLD,37)
        draw.text((W/2,78),'MINOR AI',font=brand,fill='#2FFF9E',anchor='mt')
        size=96
        while size>=72:
            font=ImageFont.truetype(BOLD,size)
            lines=wrap(caption,font,1160)
            if lines:break
            size-=2
        assert lines,caption
        lineheight=int(size*1.16)
        for n,line in enumerate(lines):
            draw.text((W/2,176+n*lineheight),line,font=font,fill='#FFFFFF',anchor='mt')
        sw=1056;sh=round(H*sw/W);x=(W-sw)//2;y=446
        mask=Image.new('L',(sw,sh));ImageDraw.Draw(mask).rounded_rectangle((0,0,sw-1,sh-1),radius=68,fill=255)
        shadow=Image.new('RGBA',(W,H));shadow.paste((0,0,0,200),(x,y+24,x+sw,y+sh+24),mask)
        canvas=Image.alpha_composite(canvas,shadow.filter(ImageFilter.GaussianBlur(36)))
        resized=shot.resize((sw,sh),Image.Resampling.LANCZOS)
        canvas.paste(resized,(x,y),mask)
        outline=ImageDraw.Draw(canvas);outline.rounded_rectangle((x,y,x+sw-1,y+sh-1),radius=68,outline=(255,255,255,35),width=2)
        out=dest/source.name
        canvas.convert('RGB').save(out,optimize=True)
        manifest.append({'language':lang,'file':str(out.relative_to(ROOT)),'source':str(source.relative_to(ROOT)),'caption':caption,'font_px':size,'dimensions':[W,H],'mode':'RGB'})
(ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
for lang in COPY:
    paths=sorted((ROOT/'app-store'/lang).glob('*.png'))
    sheet=Image.new('RGB',(4*330,2*740),(25,25,25))
    for i,p in enumerate(paths):
        tile=Image.open(p).resize((330,717),Image.Resampling.LANCZOS)
        sheet.paste(tile,((i%4)*330,(i//4)*740))
        ImageDraw.Draw(sheet).text(((i%4)*330+12,(i//4)*740+720),p.stem,fill='white',font=ImageFont.truetype(REG,13))
    sheet.save(ROOT/f'contact-sheet-{lang}.jpg',quality=92)
print(f'Composed {len(manifest)} images')
