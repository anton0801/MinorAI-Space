from pathlib import Path
import json,math
from PIL import Image
import numpy as np
O=Path(__file__).resolve().parents[1];A=O/'assets';manifest=[]
def save(name,w,h,body,desc):
    d=A/(name+'.imageset');d.mkdir(exist_ok=True)
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
    (d/(name+'.svg')).write_text(svg)
    (d/'Contents.json').write_text(json.dumps({'images':[{'filename':name+('' if k==1 else '@'+str(k)+'x')+'.png','idiom':'universal','scale':str(k)+'x'} for k in [1,2,3]],'info':{'author':'xcode','version':1}},indent=2))
    manifest.append(dict(name=name,width=w,height=h,description=desc))
# Preserve the actual high-resolution mark: alpha contour tracing, not a replacement polygon.
im=np.array(Image.open(O.parent/'assets/Logos/minor-mark@3x.png').convert('RGBA'))[:,:,3]>127
edges={}
H,W=im.shape
for y,x in np.argwhere(im):
    x=int(x);y=int(y)
    if y==0 or not im[y-1,x]:edges[(x,y)]=(x+1,y)
    if x==W-1 or not im[y,x+1]:edges[(x+1,y)]=(x+1,y+1)
    if y==H-1 or not im[y+1,x]:edges[(x+1,y+1)]=(x,y+1)
    if x==0 or not im[y,x-1]:edges[(x,y+1)]=(x,y)
def simplify(points,eps=.7):
    if len(points)<3:return points
    a=np.array(points[0]);b=np.array(points[-1]);p=np.array(points);v=b-a
    dist=np.abs(v[0]*(p[:,1]-a[1])-v[1]*(p[:,0]-a[0]))/(np.linalg.norm(v) or 1)
    i=int(np.argmax(dist))
    if dist[i]>eps:return simplify(points[:i+1],eps)[:-1]+simplify(points[i:],eps)
    return [points[0],points[-1]]
paths=[]
while edges:
    start=next(iter(edges));cur=start;pts=[]
    while cur in edges:
        pts.append(cur);cur=edges.pop(cur)
        if cur==start:break
    if len(pts)>10:
        split=len(pts)//2;pts=simplify(pts[:split+1])+simplify(pts[split:]+pts[:1])[1:]
        paths.append('M'+' L'.join(f'{x} {y}' for x,y in pts)+'Z')
mark='<path fill="#FFFFFF" fill-rule="evenodd" d="'+' '.join(paths)+'"/>'
(A/'minor-mark-traced.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">{mark}</svg>')
for name,bg,size,glow in [('app-icon-classic','#121212',1100,False),('app-icon-glow','#121212',1100,True),('app-icon-cosmos','#0E0F17',1250,False)]:
    body=f'<rect width="1024" height="1024" fill="{bg}"/>'
    if glow:body+='<defs><filter id="g" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="50"/></filter></defs><rect x="190" y="620" width="644" height="120" fill="#BBFFDF" fill-opacity="0.15" filter="url(#g)"/>'
    body+=f'<g transform="translate({(1024-size)/2} {(1024-size)/2}) scale({size/W})">{mark}</g>'
    save(name,1024,1024,body,'1024pt app icon, opaque square; original mark traced from alpha')
shapes={
'menu':'<path d="M3 5h18M3 12h18M3 19h18"/>',
'mind-globe':'<circle cx="12" cy="12" r="10"/><ellipse cx="12" cy="12" rx="4.5" ry="10"/><path d="M2 12h20M4 6.5h16M4 17.5h16"/>',
'star':'<path d="m12 2.5 3 6.1 6.8 1-4.9 4.8 1.2 6.7-6.1-3.2-6.1 3.2 1.2-6.7-4.9-4.8 6.8-1Z"/>',
'bulb':'<path d="M8.5 16c0-2.1-3-3-3-6.6a6.5 6.5 0 0 1 13 0c0 3.6-3 4.5-3 6.6v2h-7ZM9 21h6M12 0v1M3.2 2.2l1.4 1.4M20.8 2.2l-1.4 1.4M1 10h1.5M21.5 10H23"/>',
'rocket':'<path d="M8 16V10c0-4 4-8 4-8s4 4 4 8v6ZM8 11c-3 2-4 5-4 8l4-2M16 11c3 2 4 5 4 8l-4-2M10 19l2 3 2-3"/><circle cx="12" cy="10" r="1.5"/>',
'node':'<rect x="6" y="6" width="12" height="12" rx="4"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
'branch':'<rect x="2" y="9" width="5" height="6" rx="2"/><rect x="17" y="3" width="5" height="5" rx="2"/><rect x="17" y="16" width="5" height="5" rx="2"/><path d="M7 12h4c3 0 2-6.5 6-6.5M11 12c3 0 2 6.5 6 6.5"/>',
'spark':'<path d="m12 2 2.6 7.4L22 12l-7.4 2.6L12 22l-2.6-7.4L2 12l7.4-2.6Z"/>'}
for name in ['menu','mind-globe','star','bulb','rocket']:
    for color,hex in [('white','#FFFFFF'),('gray','#959595')]:
        size={'menu':25,'mind-globe':30}.get(name,20 if color=='white' else 15)
        body=f'<g transform="scale({size/24})" fill="none" stroke="{hex}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{shapes[name]}</g>'
        save(name+'-'+color,size,size,body,'Optical line reconstruction of supplied PNG; SF Regular weight')
for name in ['node','branch','spark']:
    for color,hex in [('white','#FFFFFF'),('gray','#959595')]:
        for size in [15,20]:
            body=f'<g transform="scale({size/24})" fill="none" stroke="{hex}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{shapes[name]}</g>'
            save(f'particle-{name}-{color}-{size}',size,size,body,'Paywall mind-map particle')
cols=['#5EF0B0','#7CC4FF','#C9A2FF','#FC86C3','#FFD66B','#FC9886'];body=''
for i,(y,c) in enumerate(zip([18,35,52,69,86,103],cols)):
    body+=f'<g fill="none" stroke="{c}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M53 60 C80 60 76 {y} 102 {y}"/><rect x="102" y="{y-5}" width="{[30,42,34,40,28,35][i]}" height="10" rx="5"/></g>'
body+='<rect x="18" y="47" width="35" height="26" rx="12" fill="none" stroke="#5EF0B0" stroke-width="1.5"/><circle cx="35.5" cy="60" r="3" fill="none" stroke="#5EF0B0" stroke-width="1.5"/>'
save('no-maps-yet',160,120,body,'Six branch colors, transparent background, no text')
(A/'manifest.json').write_text(json.dumps(manifest,indent=2));print('Created',len(manifest),'asset sets')
