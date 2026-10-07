"""Minor AI / Thought to form — deterministic 10s, 1080×1920, 60fps motion film.

Uses genuine product captures and the original white brand mark. No external
render service. Run `python3 promo/render.py --stills` for the storyboard,
or `python3 promo/render.py` to render the H.264 master.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
from functools import lru_cache
import math, subprocess, sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'promo'
W, H, FPS, DURATION = 1080, 1920, 60, 10
MINT = (47, 255, 158)
WHITE = (245, 248, 247)
MUTED = (151, 164, 159)
BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
REG = '/System/Library/Fonts/Supplemental/Arial.ttf'

def clamp(x): return min(1., max(0., x))
def smooth(x):
    x = clamp(x)
    return x*x*(3-2*x)
def ease(x): return 1-(1-clamp(x))**4
def spring(x):
    x = clamp(x)
    return 1-math.exp(-7*x)*math.cos(9*x) if x < 1 else 1
def lerp(a,b,x): return a+(b-a)*x

@lru_cache(None)
def font(size, bold=True): return ImageFont.truetype(BOLD if bold else REG, size)

def text(im, value, x, y, size=72, color=WHITE, alpha=1, anchor='la', bold=True):
    if alpha <= 0: return
    layer = Image.new('RGBA', im.size)
    ImageDraw.Draw(layer).text((x,y), value, font=font(size,bold), fill=(*color, round(clamp(alpha)*255)), anchor=anchor, stroke_width=0)
    im.alpha_composite(layer)

def paste(im, asset, x, y, scale=1, angle=0, alpha=1):
    if alpha <= 0 or scale <= .005: return
    a = asset
    if abs(scale-1)>.001:
        a=a.resize((max(1,round(a.width*scale)),max(1,round(a.height*scale))),Image.Resampling.LANCZOS)
    if angle:
        a=a.rotate(angle,Image.Resampling.BICUBIC,expand=True)
    if alpha < .999:
        a=a.copy(); a.putalpha(a.getchannel('A').point(lambda v:round(v*clamp(alpha))))
    im.alpha_composite(a,(round(x-a.width/2),round(y-a.height/2)))

def rounded_asset(im, radius, border=True):
    im=im.convert('RGBA')
    mask=Image.new('L',im.size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,im.width-1,im.height-1),radius,fill=255)
    im.putalpha(mask)
    if border:
        ImageDraw.Draw(im).rounded_rectangle((0,0,im.width-1,im.height-1),radius,outline=(164,193,179,130),width=2)
    return im

# A quiet atmospheric field, rendered once. The little dots echo the map canvas.
y,x=np.mgrid[0:H,0:W]
g=np.exp(-(((x-780)/680)**2+((y-1070)/720)**2)*1.6)
g2=np.exp(-(((x-170)/620)**2+((y-1650)/500)**2)*2)
rgb=np.stack([10+g*5+g2*6,13+g*23+g2*8,14+g*16+g2*15],axis=2).astype('uint8')
BG=Image.fromarray(rgb).convert('RGBA')
d=ImageDraw.Draw(BG)
for yy in range(40,H,48):
    for xx in range(36,W,48):
        c=round(23+11*math.exp(-(((xx-540)/700)**2+((yy-1050)/700)**2)))
        d.ellipse((xx,yy,xx+1,yy+1),fill=(c,c+3,c+2))
del x,y,g,g2,rgb

logo=Image.open(ROOT/'DesignSystem/assets/Logos/minor-mark@3x.png').convert('RGBA')
logo=logo.crop(logo.getbbox()).resize((440,440),Image.Resampling.LANCZOS)

def phone(name):
    screen=Image.open(ROOT/'shots/raw/ru'/name).convert('RGBA').resize((564,1225),Image.Resampling.LANCZOS)
    screen=rounded_asset(screen,68,False)
    im=Image.new('RGBA',(600,1261))
    dd=ImageDraw.Draw(im)
    dd.rounded_rectangle((0,0,599,1260),86,fill=(4,6,6),outline=(110,121,116),width=3)
    dd.rounded_rectangle((6,6,593,1254),80,outline=(44,52,48),width=5)
    im.alpha_composite(screen,(18,18))
    dd.rounded_rectangle((17,17,582,1243),68,outline=(194,209,201,100),width=1)
    return im
MAP_PHONE=phone('01-map.png')
SLIDE_PHONE=phone('08-present.png')
source=Image.open(ROOT/'shots/raw/ru/08-present.png')
SLIDE=rounded_asset(source.crop((46,371,1274,1063)).resize((900,507),Image.Resampling.LANCZOS),34)

@lru_cache(None)
def tile(kind):
    im=Image.new('RGBA',(330,166))
    dd=ImageDraw.Draw(im)
    dd.rounded_rectangle((1,1,328,164),30,fill=(25,32,30,255),outline=(74,92,82),width=2)
    dd.rounded_rectangle((24,28,102,106),22,fill=(42,63,52),outline=(71,110,88),width=1)
    if kind=='PDF':
        dd.rounded_rectangle((47,44,79,87),5,outline=MINT,width=3)
        for yy in (58,67,76): dd.line((54,yy,72,yy),fill=MINT,width=2)
        title,sub='Документ','Всё важное'
    elif kind=='VIDEO':
        dd.polygon([(52,47),(52,86),(80,67)],fill=MINT)
        title,sub='Видео','Любая тема'
    elif kind=='VOICE':
        for j,hh in enumerate((13,27,43,30,17)):
            xx=45+j*9; dd.rounded_rectangle((xx,67-hh/2,xx+4,67+hh/2),2,fill=MINT)
        title,sub='Голос','Живая мысль'
    else:
        dd.ellipse((48,45,78,75),outline=MINT,width=3)
        dd.line((55,76,55,84,72,84,72,76),fill=MINT,width=3)
        title,sub='Идея','Твой следующий шаг'
    text(im,title,121,35,29)
    text(im,sub,25,125,21,MUTED,bold=False)
    return im

@lru_cache(None)
def node(label, col):
    ww=round(font(25).getlength(label))+62
    im=Image.new('RGBA',(ww,76));dd=ImageDraw.Draw(im)
    dd.rounded_rectangle((1,1,ww-2,74),23,fill=tuple(round(v*.13+17) for v in col),outline=tuple(round(v*.50) for v in col),width=2)
    text(im,label,ww/2,23,25,col,anchor='ma')
    return im

def header(im,t):
    paste(im,logo,95,140,.095)
    text(im,'minor ai',132,119,32)
    text(im,'МЫСЛИ ОБРЕТАЮТ ФОРМУ',1001,130,17,MUTED,anchor='ra',bold=False)

def line_reveal(im,value,x,y,size,p,color=WHITE):
    p=clamp(p)
    if p<=0:return
    layer=Image.new('RGBA',(W,round(size*1.4)))
    ImageDraw.Draw(layer).text((0,round((1-ease(p))*size*1.1)),value,font=font(size),fill=(*color,255),anchor='lt')
    im.alpha_composite(layer,(round(x),round(y)))

def orbit(im,t,center=(540,1080),opacity=1):
    layer=Image.new('RGBA',(W,H));dd=ImageDraw.Draw(layer)
    cx,cy=center
    for i,rr in enumerate((290,410,555)):
        dd.ellipse((cx-rr,cy-rr,cx+rr,cy+rr),outline=(71,133,99,round(opacity*(23-i*4))),width=2)
        a=t*.20+i*2.1;px=cx+math.cos(a)*rr;py=cy+math.sin(a)*rr
        dd.ellipse((px-3,py-3,px+3,py+3),fill=(*MINT,round(80*opacity)))
    im.alpha_composite(layer)

def footer(im,label):
    text(im,label,540,1778,25,MUTED,anchor='ma',bold=False)

def intro(t):
    im=BG.copy();header(im,t);orbit(im,t)
    line_reveal(im,'Каждая мысль.',80,355,98,t/.55)
    line_reveal(im,'Начало большего.',80,475,88,(t-.12)/.55)
    pull=smooth((t-1.32)/.6)
    positions=[(300,885,-9,'PDF'),(782,948,8,'VIDEO'),(292,1280,6,'VOICE'),(768,1342,-7,'IDEA')]
    for i,(xx,yy,ang,kind) in enumerate(positions):
        ent=spring((t-.08-i*.07)/.55)
        xx=lerp(xx,540,pull); yy=lerp(yy+90*(1-ent),1100,pull)
        scale=(.83+.17*ent)*(1-.78*pull)
        paste(im,tile(kind),xx,yy,scale,ang*(1-pull),1-smooth((pull-.65)/.35))
    dd=ImageDraw.Draw(im)
    r=6+14*ease(t/.5)+25*pull
    dd.ellipse((540-r,1100-r,540+r,1100+r),fill=MINT)
    if t>1.30:
        rr=40+300*pull
        dd.ellipse((540-rr,1100-rr,540+rr,1100+rr),outline=(*MINT,round(255*(1-pull))),width=2)
    footer(im,'Документ. Видео. Голос. Или просто идея.')
    return im

def map_scene(t):
    u=t-1.78;im=BG.copy();header(im,t);orbit(im,t,center=(540,1110))
    line_reveal(im,'Свяжи',80,282,112,u/.5)
    line_reveal(im,'свои идеи.',80,412,112,(u-.09)/.5)
    ent=spring(u/.85)
    exit=smooth((t-3.91)/.47)
    scale=.94+.025*math.sin(clamp(u/2.5)*math.pi)
    paste(im,MAP_PHONE,540-70*exit,1114+560*(1-ent)+30*exit,scale*(1-.12*exit),-4+4*ease(u/1.9)+5*exit)
    # Small orbiting feature chips, timed with the generated node clicks.
    for i,(label,col,xx,yy) in enumerate([
        ('Связи',(110,226,182),848,860),
        ('Структура',(196,162,252),220,1270),
        ('Ясность',(255,211,125),823,1510)]):
        p=spring((u-.55-i*.15)/.55)
        paste(im,node(label,col),xx+(1-p)*(120 if xx>500 else -120),yy,.80+.2*p,0,clamp(p)*(1-exit))
    footer(im,'Интеллект-карты с ИИ')
    return im

def slide_scene(t):
    u=t-4.10;im=BG.copy();header(im,t);orbit(im,t,center=(565,1120))
    line_reveal(im,'Преврати',80,282,108,u/.48)
    line_reveal(im,'в презентацию.',80,412,96,(u-.08)/.50)
    ent=spring(u/.85)
    paste(im,SLIDE_PHONE,700+430*(1-ent),1110,.79,lerp(-12,-6,ease(u/2)))
    # The real slide lifts out of the real screen, then opens into a deck.
    p=spring((u-.35)/.7)
    for i in range(2,-1,-1):
        stack=Image.new('RGBA',(900,507));dd=ImageDraw.Draw(stack)
        dd.rounded_rectangle((0,0,899,506),34,fill=(20+6*i,32+5*i,30+5*i),outline=(55+10*i,100+10*i,80+10*i),width=2)
        paste(im,stack,lerp(704,520,clamp(p))-i*15,lerp(873,1080,clamp(p))+i*36,.57+.40*clamp(p),-6+8*clamp(p)+i*3,clamp(p))
    paste(im,SLIDE,lerp(704,520,clamp(p)),lerp(873,1030,clamp(p)),.57+.40*clamp(p),-6+8*clamp(p),clamp(p))
    p2=ease((u-1.05)/.6)
    badge=node('Готово к выступлению',MINT)
    paste(im,badge,390,1390+75*(1-p2),1.14,0,p2)
    text(im,'Из карты — в слайды.',80,1645,45,alpha=ease((u-.8)/.5))
    footer(im,'Одна идея. Больше возможностей.')
    return im

def end_scene(t):
    u=t-7.0;im=BG.copy()
    orbit(im,t,center=(540,845),opacity=.8)
    p=spring(u/.85)
    # Original brand mark stays upright and white.
    paste(im,logo,540,800+190*(1-p),.82+.18*p,0,ease(u/.4))
    if u<1.15:
        q=clamp(u/1.15);r=210+440*ease(q)
        layer=Image.new('RGBA',(W,H));dd=ImageDraw.Draw(layer)
        dd.ellipse((540-r,800-r,540+r,800+r),outline=(*MINT,round(105*(1-q))),width=2)
        im.alpha_composite(layer)
    text(im,'Minor AI',540,1102+60*(1-ease((u-.13)/.5)),116,alpha=ease((u-.13)/.5),anchor='ma')
    text(im,'Придай мыслям форму.',540,1260+35*(1-ease((u-.38)/.5)),49,alpha=ease((u-.38)/.5),anchor='ma',bold=False)
    text(im,'КАРТЫ  /  СЛАЙДЫ  /  ИИ',540,1435,25,MUTED,alpha=ease((u-.60)/.5),anchor='ma',bold=False)
    pp=ease((u-.82)/.5)
    layer=Image.new('RGBA',(W,H));dd=ImageDraw.Draw(layer)
    dd.rounded_rectangle((352,1619,728,1703),42,fill=(*MINT,round(255*pp)))
    im.alpha_composite(layer)
    text(im,'minorai.site',520,1642,32,(7,30,19),alpha=pp,anchor='ma')
    arrow=Image.new('RGBA',(W,H));ad=ImageDraw.Draw(arrow)
    ad.line((644,1671,663,1652),fill=(7,30,19,round(pp*255)),width=3)
    ad.line((647,1652,663,1652,663,1668),fill=(7,30,19,round(pp*255)),width=3)
    im.alpha_composite(arrow)
    return im

def frame(t):
    if t<1.78:im=intro(t)
    elif t<2.00:im=Image.blend(intro(t),map_scene(t),smooth((t-1.78)/.22))
    elif t<4.1:im=map_scene(t)
    elif t<4.32:im=Image.blend(map_scene(t),slide_scene(t),smooth((t-4.1)/.22))
    elif t<7:im=slide_scene(t)
    elif t<7.24:im=Image.blend(slide_scene(t),end_scene(t),smooth((t-7)/.24))
    else:im=end_scene(t)
    return im.convert('RGB')

def stills():
    times=[.85,1.65,2.5,3.7,4.8,5.85,7.65,9.2]
    sheet=Image.new('RGB',(4*270,2*500),(10,13,14))
    for i,t in enumerate(times):
        im=frame(t);im.save(OUT/'previews'/f'frame-{t:04.2f}.jpg',quality=94)
        sheet.paste(im.resize((270,480),Image.Resampling.LANCZOS),((i%4)*270,(i//4)*500))
        ImageDraw.Draw(sheet).text(((i%4)*270+12,(i//4)*500+481),f'{t:.2f}s',fill='white',font=font(14,False))
    sheet.save(OUT/'storyboard.jpg',quality=92)
    frame(3.1).save(OUT/'poster.jpg',quality=94)
    print('Storyboard and poster ready.',flush=True)

def render():
    cmd=['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/'silent-master.mp4')]
    proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    for n in range(FPS*DURATION):
        proc.stdin.write(frame(n/FPS).tobytes())
        if n%60==0:print(f'Rendering {n//60}/{DURATION}s',flush=True)
    proc.stdin.close()
    if proc.wait():raise RuntimeError('ffmpeg failed')
    print('Video master ready.',flush=True)

if __name__=='__main__':
    stills()
    if '--stills' not in sys.argv:render()
