#!/usr/bin/env python3
"""Campaign compositor. Generated plates only; logo, SF Pro type and captured UI are real.
The source screenshots and logo are never edited in place.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageCms, ImageOps
import numpy as np
import json, argparse, hashlib, math
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT.parents[1]
SOURCES=ROOT/'sources'; PREVIEW=ROOT/'preview'
FONT='/System/Library/Fonts/SFNS.ttf'
LOGO=PROJECT/'Minor Ai/Assets.xcassets/logo.imageset/minor_plus-3.png'
HEADER=(3840,1646); SEARCH=(3840,2560)
SAFE=(1097,493,2743,1154); IPHONE=(330,0,3530,1646)
SRGB=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
COLORS=['#5EF0B0','#7CC4FF','#C9A2FF','#FC86C3','#FFD66B','#FC9886']
COPY={
'en-US':{'header':['Give your','thoughts shape.'],'search':['AI mind maps & slides'],'search_split':['AI mind maps','& slides']},
'ru':{'header':['Придайте','мыслям форму.'],'search':['ИИ-карты мыслей и слайды'],'search_split':['ИИ-карты мыслей','и слайды']}}

def font(size,weight='Heavy'):
    f=ImageFont.truetype(FONT,size)
    f.set_variation_by_name(weight)
    return f

def rgb(c):return tuple(bytes.fromhex(c.lstrip('#')))

def srgb(im):
    if im.info.get('icc_profile'):
        try:
            import io
            src=ImageCms.ImageCmsProfile(io.BytesIO(im.info['icc_profile']))
            return ImageCms.profileToProfile(im,src,ImageCms.createProfile('sRGB'),outputMode='RGBA' if im.mode=='RGBA' else 'RGB')
        except Exception: pass
    return im.convert('RGBA' if im.mode=='RGBA' else 'RGB')

def plate(name,size):
    im=srgb(Image.open(SOURCES/(name+'.png'))).convert('RGB')
    return ImageOps.fit(im,size,method=Image.Resampling.LANCZOS).convert('RGBA')

def light(im,center,radii,color,alpha):
    # Render smooth volumetric haze at quarter resolution, then composite.
    w,h=im.size;mw,mh=w//4,h//4
    yy,xx=np.mgrid[0:mh,0:mw]
    opacity=np.exp(-2*(((xx*4-center[0])/radii[0])**2+((yy*4-center[1])/radii[1])**2))*alpha
    layer=Image.new('RGBA',(mw,mh),rgb(color)+(0,))
    layer.putalpha(Image.fromarray(np.uint8(np.clip(opacity,0,255))))
    return Image.alpha_composite(im,layer.resize(im.size,Image.Resampling.BICUBIC))

def shade(im,alpha=30):
    return Image.alpha_composite(im,Image.new('RGBA',im.size,(9,12,12,alpha)))

def logo(im,box,manifest):
    original=srgb(Image.open(LOGO)).convert('RGBA')
    bounds=original.getchannel('A').getbbox()
    mark=original.crop(bounds)
    w,h=box[2:]
    scale=min(w/mark.width,h/mark.height)
    mark=mark.resize((round(mark.width*scale),round(mark.height*scale)),Image.Resampling.LANCZOS)
    x=round(box[0]+(w-mark.width)/2);y=round(box[1]+(h-mark.height)/2)
    im.alpha_composite(mark,(x,y))
    manifest.append({'kind':'logo','source':str(LOGO.relative_to(PROJECT)),'bounds':[x,y,x+mark.width,y+mark.height],'uniform_scale':scale,'source_alpha_bounds':bounds})
    return im

def tracked_width(text,f,tracking):
    return f.getlength(text)+(len(text)-1)*tracking

def text(im,lines,x,top,size,leading=None,align='left',manifest=None,color='#FFFFFF'):
    f=font(size);tracking=-size*.025;leading=leading or size*1.1
    layer=Image.new('RGBA',im.size);d=ImageDraw.Draw(layer)
    cap=f.getbbox('H')[3]-f.getbbox('H')[1]
    for n,line in enumerate(lines):
        width=tracked_width(line,f,tracking)
        lx=x-width/2 if align=='center' else x
        baseline=top+n*leading+cap
        for i,ch in enumerate(line):
            before=f.getlength(line[:i]) if i else 0
            d.text((lx+before+i*tracking,baseline),ch,font=f,fill=color,anchor='ls')
    box=layer.getchannel('A').getbbox()
    im=Image.alpha_composite(im,layer)
    if manifest is not None:manifest.append({'kind':'headline','text':' '.join(lines),'lines':lines,'bounds':box,'font':'SF Pro / SFNS Heavy','font_px':size,'cap_height_px':cap,'tracking_px':tracking})
    return im

def bezier(points,steps=100):
    a,b,c,d=points
    return [tuple((1-t)**3*a[j]+3*(1-t)**2*t*b[j]+3*(1-t)*t*t*c[j]+t**3*d[j] for j in (0,1)) for t in np.linspace(0,1,steps)]

def branches(im,paths):
    core=Image.new('RGBA',im.size);d=ImageDraw.Draw(core)
    for pts,col in paths:
        points=bezier(pts)
        d.line(points,fill=rgb(col)+(190,),width=3,joint='curve')
        x,y=pts[-1];d.rounded_rectangle((x-20,y-8,x+20,y+8),radius=8,fill=rgb(col)+(225,))
    glow=core.filter(ImageFilter.GaussianBlur(14))
    im=Image.alpha_composite(im,glow)
    return Image.alpha_composite(im,core.filter(ImageFilter.GaussianBlur(.45)))

def header(concept,lang):
    meta=[]
    im=plate(concept,HEADER)
    if concept=='confluence':
        im=shade(im,25)
        im=light(im,(1290,806),(380,350),'#BBFFDF',25)
        im=branches(im,[([(1320,794),(1430,520),(1710,550),(1840,550)],COLORS[0]), ([(1360,840),(1530,1100),(2180,1080),(2310,1080)],COLORS[1]), ([(1400,870),(1720,1070),(2490,1040),(2650,1040)],COLORS[2])])
        im=logo(im,(1128,638,320,326),meta)
        im=text(im,COPY[lang]['header'],1540,649,150,174,manifest=meta)
        meta.append({'kind':'hero_branches','bounds':[1280,530,2671,1100]})
    elif concept=='glass':
        im=shade(im,15)
        im=light(im,(2420,790),(480,400),'#2FFF9E',24)
        im=branches(im,[([(2360,800),(2280,510),(1810,550),(1560,550)],COLORS[0]), ([(2470,820),(2300,1068),(1670,1080),(1180,1080)],COLORS[1]), ([(2500,830),(2620,920),(2670,1040),(2670,1100)],COLORS[2])])
        im=logo(im,(2340,650,320,326),meta)
        im=text(im,COPY[lang]['header'],1130,651,150,174,manifest=meta)
        meta.append({'kind':'hero_branches','bounds':[1159,530,2691,1120]})
    else:
        im=shade(im,45)
        im=light(im,(1920,690),(500,310),'#BBFFDF',22)
        im=branches(im,[([(1920,672),(1630,580),(1400,610),(1220,630)],COLORS[0]), ([(1920,680),(2100,530),(2470,560),(2635,555)],COLORS[1]), ([(1880,680),(1610,740),(1430,790),(1250,790)],COLORS[2]), ([(1950,700),(2240,755),(2420,780),(2630,770)],COLORS[3])])
        im=logo(im,(1770,514,300,303),meta)
        im=text(im,COPY[lang]['header'],1920,856,150,164,'center',meta)
        meta.append({'kind':'hero_branches','bounds':[1199,533,2656,810]})
    return im,meta

def screen(im,lang,name,crop,box,meta,glow_color='#BBFFDF'):
    source=PROJECT/'shots/raw'/('en' if lang=='en-US' else 'ru')/(name+'.png')
    source_im=srgb(Image.open(source)).convert('RGB')
    panel=source_im.crop(crop)
    scale=box[2]/panel.width
    size=(box[2],round(panel.height*scale))
    panel=panel.resize(size,Image.Resampling.LANCZOS)
    x,y=box[:2];w,h=size;r=58
    mask=Image.new('L',size);ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,h-1),radius=r,fill=255)
    # Framing is an external crop presentation; no interface elements are redrawn.
    halo=Image.new('RGBA',im.size)
    hd=ImageDraw.Draw(halo);hd.rounded_rectangle((x-4,y-4,x+w+4,y+h+4),radius=r+4,outline=rgb(glow_color)+(90,),width=8)
    im=Image.alpha_composite(im,halo.filter(ImageFilter.GaussianBlur(38)))
    rim=ImageDraw.Draw(im);rim.rounded_rectangle((x-5,y-5,x+w+5,y+h+5),radius=r+5,fill=(50,58,57,255))
    im.paste(panel,(x,y),mask)
    meta.append({'kind':'real_ui_crop','source':str(source.relative_to(PROJECT)),'source_crop':crop,'bounds':[x,y,x+w,y+h],'uniform_scale':scale,'retouching':'none; rectangular crop, uniform resize, outside framing only'})
    return im

def search(concept,lang):
    meta=[]
    im=shade(plate('glass' if concept=='duet' else 'confluence',SEARCH),10)
    im=light(im,(1920,1610),(1500,950),'#2FFF9E',15)
    if concept=='duet':
        im=logo(im,(1840,190,160,160),meta)
        im=text(im,COPY[lang]['search'],1920,453,200,align='center',manifest=meta)
        im=screen(im,lang,'03-assistant',(0,350,1320,1760),(375,790,1450),meta)
        im=screen(im,lang,'04-slides',(0,165,1320,1240),(1985,945,1480),meta,'#7CC4FF')
        im=branches(im,[([(1826,1510),(1860,1510),(1930,1480),(1950,1480)],COLORS[0])])
    else:
        im=logo(im,(397,278,130,130),meta)
        im=text(im,COPY[lang]['search_split'],390,520,200,225,manifest=meta)
        # A closer view: the real edited-map response and the slide editor.
        im=screen(im,lang,'04-slides',(0,165,1320,1240),(1800,900,1710),meta,'#7CC4FF')
        im=screen(im,lang,'03-assistant',(0,350,1320,1760),(620,1040,1300),meta)
    return im,meta

def export(im,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    kwargs={'icc_profile':SRGB}
    if path.suffix.lower() in ['.jpg','.jpeg']:kwargs.update(quality=96,subsampling=0,optimize=True)
    else:kwargs.update(optimize=True)
    im.convert('RGB').save(path,**kwargs)

def preview(im,path,maxw=1440):
    im=im.convert('RGB').resize((maxw,round(im.height*maxw/im.width)),Image.Resampling.LANCZOS)
    export(im,path)

def overlay(im,kind,meta):
    layer=Image.new('RGBA',im.size);d=ImageDraw.Draw(layer)
    lab=font(32,'Semibold')
    if kind=='header':
        # Shaded zones stay in previews only.
        d.rectangle((0,0,330,im.height),fill=(0,0,0,130));d.rectangle((3530,0,3840,im.height),fill=(0,0,0,130))
        d.rectangle(SAFE,outline=(47,255,158,255),width=5)
        for xx in [330,3530]:d.line((xx,0,xx,im.height),fill=(255,193,116,255),width=5)
        d.text((SAFE[0]+16,SAFE[1]-58),'APPLE KEY ART SAFE AREA  /  1097–2743 × 493–1154',font=lab,fill='#2FFF9E')
        d.text((350,55),'iPHONE VISIBLE CROP  /  330–3530',font=lab,fill='#FFC174')
        # Approximate UI obstruction reminders, not exported artwork.
        for xx in [435,3370]:d.ellipse((xx-55,70,xx+55,180),fill=(255,193,116,35),outline=(255,193,116,150),width=3)
    else:
        d.rectangle((240,180,3600,2380),outline=(47,255,158,255),width=5)
        d.rectangle((4,4,3835,2555),outline=(255,193,116,255),width=6)
        d.text((268,196),'COMPOSITION MARGIN · DESIGN GUIDE, NOT AN APPLE SAFE-AREA TEMPLATE',font=lab,fill='#2FFF9E')
        d.text((268,2440),'iPHONE PREVIEW USES THE FULL 3:2 IMAGE · NO EXTRA CROP ASSUMED',font=lab,fill='#FFC174')
    for m in meta:
        if m['kind'] in ['logo','headline']:d.rectangle(m['bounds'],outline=(180,200,255,170),width=2)
    return Image.alpha_composite(im,layer)

def concept_sheets():
    names={'confluence':'H1  /  CONFLUENCE — scattered thoughts become a map','glass':'H2  /  GLASS CANVAS — clarity, light and a tangible surface','constellation':'H3  /  CONSTELLATION — the mark at the center of an idea'}
    entries=[]
    for key in names:
        im,meta=header(key,'en-US')
        preview(im,PREVIEW/f'header-{key}.jpg')
        preview(overlay(im,'header',meta),PREVIEW/f'header-{key}-overlay.jpg')
        entries.append((names[key],PREVIEW/f'header-{key}-overlay.jpg'))
    sheet=Image.new('RGB',(1440,3*690),(18,18,18));d=ImageDraw.Draw(sheet)
    for i,(title,path) in enumerate(entries):
        d.text((26,i*690+18),title,font=font(25,'Semibold'),fill='white')
        sheet.paste(Image.open(path),(0,i*690+63))
    export(sheet,PREVIEW/'header-concepts.jpg')
    entries=[]
    for key,title in [('duet','S1  /  DUET — two real app screens, a single clear headline'),('editorial','S2  /  EDITORIAL — closer crops, overlapping planes')]:
        im,meta=search(key,'en-US')
        preview(im,PREVIEW/f'search-{key}.jpg')
        preview(overlay(im,'search',meta),PREVIEW/f'search-{key}-overlay.jpg')
        entries.append((title,PREVIEW/f'search-{key}-overlay.jpg'))
    sheet=Image.new('RGB',(1440,2*1038),(18,18,18));d=ImageDraw.Draw(sheet)
    for i,(title,path) in enumerate(entries):
        d.text((26,i*1038+18),title,font=font(25,'Semibold'),fill='white')
        sheet.paste(Image.open(path),(0,i*1038+63))
    export(sheet,PREVIEW/'search-concepts.jpg')

def finals(h,s):
    records=[]
    for lang in COPY:
        for kind,fn,concept in [('header',header,h),('search',search,s)]:
            im,meta=fn(concept,lang)
            paths=[ROOT/lang/(kind+'.jpg')]
            if kind=='header':paths.append(ROOT/lang/'header.png')
            for path in paths:
                export(im,path)
                records.append({'file':str(path.relative_to(ROOT)),'placement':kind,'language':lang,'concept':concept,'size':im.size,'elements':meta})
            preview(im,PREVIEW/f'{lang}-{kind}.jpg')
            preview(overlay(im,kind,meta),PREVIEW/f'{lang}-{kind}-overlay.jpg')
            if kind=='header':preview(im.crop(IPHONE),PREVIEW/f'{lang}-header-iphone.jpg',1170)
            else:preview(im,PREVIEW/f'{lang}-search-phone-size.jpg',390)
    (ROOT/'layout-manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    # All four outputs at a useful inspection size.
    sheet=Image.new('RGB',(1920,2*(64+412+64+640)+32),(18,18,18));d=ImageDraw.Draw(sheet)
    for col,lang in enumerate(['en-US','ru']):
        x=col*960
        d.text((x+28,20),lang.upper()+'  /  PRODUCT PAGE HEADER',font=font(24,'Semibold'),fill='white')
        shot=Image.open(ROOT/lang/'header.png').resize((960,412),Image.Resampling.LANCZOS);sheet.paste(shot,(x,64))
        d.text((x+28,500),lang.upper()+'  /  SEARCH RESULTS',font=font(24,'Semibold'),fill='white')
        shot=Image.open(ROOT/lang/'search.jpg').resize((960,640),Image.Resampling.LANCZOS);sheet.paste(shot,(x,540))
    sheet=sheet.crop((0,0,1920,1208))
    export(sheet,PREVIEW/'final-contact-sheet.jpg')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--concepts',action='store_true');p.add_argument('--header',default='confluence',choices=['confluence','glass','constellation']);p.add_argument('--search',default='duet',choices=['duet','editorial']);a=p.parse_args()
    if a.concepts:concept_sheets()
    else:finals(a.header,a.search)
    print('Done:', 'concepts' if a.concepts else (a.header,a.search))
