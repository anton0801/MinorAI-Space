from pathlib import Path
import json, html, re
O=Path(__file__).resolve().parents[1]; S=O/'screens'
def ico(n): return f'<i class="mn-ico" data-i="{n}" aria-hidden="true"></i>'
def btn(n,label,href='',cls='mn-iconbtn',extra=''):
    return f'<a class="{cls}" href="{href}.html" aria-label="{label}" {extra}>{ico(n)}</a>' if href else f'<button class="{cls}" aria-label="{label}" {extra}>{ico(n)}</button>'
def chip(label,n,href='',extra=''):
    return f'<a class="mn-chip" href="{href}.html" {extra}>{ico(n)}{label}</a>' if href else f'<button class="mn-chip" {extra}>{ico(n)}{label}</button>'
logo='../../assets/Logos/minor-mark@3x.png'
def top(home=False):
    return f'<header class="top mn-topbar"><a class="mn-menu-btn" href="07-your-maps.html" aria-label="Your Maps"><img src="../../assets/Icons/menu.png" alt=""></a><a class="mn-pill" href="09-paywall.html"><img src="{logo}" alt="">Minor Plus</a>'+ ('<button class="mn-model" aria-expanded="false">GPT-5.5 '+ico('chevron.right')+'</button>' if home else '<span></span>')+'</header>'
def composer(ph='Ask or change this map',value='',active=False):
    return f'<form class="mn-composer" data-composer><input class="field" aria-label="{ph}" placeholder="{ph}" value="{value}"><button class="mn-send" aria-label="Send" {"" if active else "disabled"}>{ico("arrow.up")}</button></form>'
def thumb(building=False):
    if building:return '<svg class="thumb" viewBox="0 0 64 48" aria-hidden="true"><rect class="f-root" x="6" y="19" width="14" height="10" rx="3"/><path class="mn-link ghost" d="M20 24 C32 24 32 14 52 14"/></svg>'
    return '<svg class="thumb" viewBox="0 0 64 48" aria-hidden="true">'+''.join(f'<path class="mn-link l2 s-{c}" d="M20 24 C27 24 27 {y} 34 {y}"/><rect class="f-{c}" x="34" y="{y-3}" width="22" height="6" rx="3"/>' for c,y in [('mint',10),('sky',24),('lilac',38)])+'<rect class="f-root" x="6" y="19" width="14" height="10" rx="3"/></svg>'
def card(title='Launch plan',meta='23 nodes · Today',pin=False,building=False):
    return f'<a class="mn-mapcard {"is-generating" if building else ""}" href="{"03-generating" if building else "04-editor"}.html">{thumb(building)}<span class="t"><span class="title">{title}</span><span class="meta">{meta}</span></span><span class="side">{ico("pin" if pin else "chevron.right") if not building else ""}</span></a>'
def usage(full=False):
    return f'<div class="mn-usage"><div class="row"><span>Free Maps</span><b>{"3" if full else "2"} of 3 this month</b></div><div class="bar"><i style="width:{"100" if full else "66.6667"}%"></i></div><span class="hint">Resets on Nov 1. Minor Plus removes the limit.</span></div>'
SCREENS=[]
def screen(name,title,body,cls='',group='',chrome=True):
    SCREENS.append(dict(file=name,title=title,group=group))
    text=f'''<!doctype html>
<html lang="en" data-theme="classic"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} · Minor</title><link rel="stylesheet" href="../../tokens.css"><link rel="stylesheet" href="../../components/bundle.css"><link rel="stylesheet" href="../screens.css"><script src="../../components/bundle.js" defer></script><script src="../screens.js" defer></script></head>
<body><main class="mn-phone {cls}" aria-label="{title}"><div class="mn-status" aria-hidden="true"><span>9:41</span><span class="sys"><i></i></span></div><div class="mn-island" aria-hidden="true"></div>{body}<div class="mn-home-ind" aria-hidden="true"></div></main></body></html>'''
    if not chrome:
        text=re.sub(r'<div class="mn-status".*?<div class="mn-island" aria-hidden="true"></div>', '', text)
        text=text.replace('<div class="mn-home-ind" aria-hidden="true"></div>', '')
    (S/(name+'.html')).write_text(text)
glow='<div class="mn-glow" aria-hidden="true"></div>'
home=top(True)+f'<img class="mn-watermark watermark" src="{logo}" alt="">'+glow+f'''<div class="home-bottom"><div class="onboarding footnote">New: turn any topic into a mind map {ico('arrow.up')}</div><div class="mn-prompt"><input class="field" placeholder="Ask me anything" aria-label="Ask me anything"><div class="tools">{btn('plus','Add',extra='data-action="attachment"',cls='mn-circle')}{chip('Media','photo',extra='data-action="media"')}</div><a class="mn-send" href="06-node-chat.html" aria-label="Send">{ico('arrow.up')}</a></div><a class="mind-entry" href="02-create.html" aria-label="Mind Map"><img src="../../assets/Icons/mind-globe.png" alt=""></a></div>'''
screen('01-home','Home · First Map',home,group='Home')
sources=[('Topic','Type any subject','textformat'),('Document','PDF, DOCX or TXT','doc.text'),('Link','Article or web page','link'),('YouTube','Video transcript','play.rectangle'),('Voice','Talk it through','mic'),('From Chat','Turn a chat into a map','bubble.left')]
for state,suffix,title in [('normal','','Start a Map'),('youtube','-youtube','Start a Map · YouTube'),('voice','-voice','Start a Map · Listening'),('limit','-limit','Start a Map · Free Limit'),('offline','-offline','Start a Map · Offline')]:
    tiles=''
    for label,desc,icon in sources:
        sel=label==({'youtube':'YouTube','voice':'Voice'}.get(state,'Topic'))
        route={'YouTube':'02-create-youtube','Voice':'02-create-voice','Topic':'02-create','From Chat':'06-node-chat','Document':'03-generating','Link':'02-create-youtube'}[label]
        gated=label in ['YouTube','Voice']
        badge=f'<span class="source-access">{ico("lock.fill")}Plus</span>' if gated else ''
        attrs=f'data-paid-source="{route}"' if gated else ''
        route='09-paywall' if gated else route
        tiles+=f'<a {attrs} class="mn-source {"is-active" if sel else ""}" href="{route}.html" aria-current="{str(sel).lower()}">{ico(icon)}<span class="t">{label}</span><span class="s">{desc}</span>{badge}</a>'
    content=top()+ '<div class="mn-haze"></div><section class="create-scroll"><div class="intro"><h1 class="title-2">Start a Map</h1><p class="subhead secondary">Pick a source or just type a topic.</p></div><div class="mn-sources">'+tiles+'</div><section class="recent"><h2 class="mn-overline">RECENT</h2>'+card()+card('Biology: cell structure','41 nodes · Sep 28')+'</section></section>'+glow
    if state=='limit': bottom=usage(True)+'<p class="footnote secondary">You’ve used 3 of 3 free maps this month.</p><a class="primary-button" href="09-paywall.html">Get Minor Plus</a>'
    elif state=='youtube': bottom=f'<div class="mn-composer source-composer"><span class="mn-chip is-active">{ico("play.rectangle")}youtube.com<a class="remove-source" href="02-create.html" aria-label="Remove YouTube">{ico("xmark")}</a></span><a class="mn-send" href="03-generating.html" aria-label="Send">{ico("arrow.up")}</a></div>'
    elif state=='voice': bottom=f'<div class="mn-composer recording"><span class="body-lg">Listening…</span><span class="wave" aria-hidden="true">'+''.join(f'<i style="height:{h}px"></i>' for h in [8,16,24,12,32,20,10,24,16,8])+'</span><a class="mn-send" href="03-generating.html" aria-label="Stop"><span class="stop"></span></a></div>'
    else: bottom=('<div class="mn-error" role="status">You’re offline. Maps need a connection to generate.</div>' if state=='offline' else '')+composer('Map any topic or paste a link')
    content+=f'<footer class="create-bottom {"has-limit" if state=="limit" else ""}">{bottom}<a class="mind-entry" href="01-home.html" aria-label="Home">{ico("house.fill")}</a></footer>'
    screen('02-create'+suffix,title,content,'create '+state,'Create')
for error in [False,True]:
    steps=''
    for i,t in enumerate(['Reading “Pitch deck.pdf”','Finding the main ideas','Building branches','Adding details']):
        st='done' if i<2 else ('failed' if error else 'now') if i==2 else 'wait'
        steps+=f'<div class="mn-step {st}"><span class="dot">{ico("checkmark") if i<2 else ico("xmark") if error and i==2 else ""}</span><span>{t}</span></div>'
    content=f'<div class="top single">{btn("xmark","Stop building this map?",extra="data-action=stop",cls="mn-close")}</div><section class="generation"><div class="mn-halo {"still" if error else ""}"><img src="{logo}" alt="Minor"></div><h1 class="title-3">Building Your Map</h1><p class="subhead secondary">From “Pitch deck.pdf”.<br>Usually 10–20 seconds.</p><div class="mn-steps">{steps}</div>'
    content+=('<div class="mn-error">Couldn’t build the map. Try again in a moment.</div><a class="primary-button" href="03-generating.html">Try Again</a>' if error else '')+'<a class="footnote secondary leave" href="07-your-maps.html">You can leave this screen. The map will appear in Your Maps.</a></section>'
    screen('03-generating'+('-error' if error else ''),'Building Your Map'+(' · Error' if error else ''),content,group='Generate')
# One coherent 23-node tree. The overview collapses children to keep branch text readable.
colors=['mint','sky','lilac','pink','sun','coral']; names=['Audience','Positioning','Pricing','Channels','Timeline','Risks']
leaves=[['Students','Creators','Small teams'],['AI first','Simple by design'],['Free · 3 maps','Plus · $9.99','PRO · $24.99','Yearly −15%'],['App Store','Communities','Word of mouth'],['Research','Build','Launch'],['Retention']]
def mapdata(many=False):
    children=leaves if not many else [x+[f'{n} {i+1}' for i in range(6-len(x))] for n,x in zip(names,leaves)]
    return children

def map_canvas(mode):
    dense=mode in ['many','zoom']; expanded=mode in ['selected','focus','search','editing','sheet','chat']
    ys=[40,112,260,408,480,552] if expanded else [40,128,216,304,392,480]
    nodes=[];paths=[]
    root=(12,272,138,78)
    nodes.append(f'<button class="mn-node root map-node" style="left:12px;top:272px;width:138px;height:78px" data-node="root">Launch<br>plan</button>')
    ch=mapdata(mode=='many')
    if dense:
        ys=[34+i*152 for i in range(6)]; root=(12,402,138,78);nodes[0]=nodes[0].replace('top:272px','top:402px')
    for idx,(name,col,y,ls) in enumerate(zip(names,colors,ys,ch)):
        selected=idx==2 and expanded
        dim=mode in ['focus','search'] and idx!=2
        w=132; x=206; bh=44
        paths.append(f'<path class="mn-link l1 s-{col} {"dim" if dim else ""}" d="M150 {root[1]+39} C178 {root[1]+39} 178 {y+22} 206 {y+22}"/>')
        nodes.append(f'<button class="mn-node lv1 b-{col} map-node {"is-selected" if selected and mode!="search" else ""} {"is-dim" if dim else ""} {"is-editing" if selected and mode=="editing" else ""}" style="left:{x}px;top:{y}px;width:{w}px;height:{bh}px" data-node="{name}" aria-label="{name}, {len(ls)} items">{name}{"<span class=caret></span>" if selected and mode=="editing" else ""}</button>')
        if dense or selected:
            spacing=22 if dense else 44; start=y+22-(len(ls)-1)*spacing/2
            for j,l in enumerate(ls):
                ly=start+j*spacing
                paths.append(f'<path class="mn-link l2 s-{col}-line" d="M338 {y+22} C366 {y+22} 366 {ly} 394 {ly}"/>')
                if dense: nodes.append(f'<span class="lod-leaf b-{col}" style="left:394px;top:{ly-3}px;width:{[92,120,100,132,80,110][j]}px" aria-label="{l}"></span>')
                else: nodes.append(f'<button class="mn-node leaf b-{col} map-node" style="left:394px;top:{ly-22}px;width:164px;height:44px" data-node="{l}">{l}</button>')
        else: nodes.append(f'<button class="mn-count b-{col} map-count" style="left:346px;top:{y+11}px" aria-label="Expand {name}" data-node="{name}">+{len(ls)}</button>')
    if mode in ['focus','search']: nodes[0]=nodes[0].replace('root map-node','root map-node is-dim')
    return '<div class="map-viewport '+('lod' if dense else '')+'" data-mode="'+mode+'"><div class="map-world" data-width="'+('550' if dense or expanded else '400')+'" data-height="'+('930' if dense else '610')+'"><svg class="mn-links" width="600" height="1000" aria-hidden="true">'+''.join(paths)+'</svg>'+''.join(nodes)+'</div></div>'
def editor_top(mode='none'):
    title='<div class="map-title"><span class="headline">Launch plan</span><span class="caption secondary">'+('43' if mode=='many' else '23')+' nodes · Saved</span></div>'
    if mode=='search': title='<label class="search-box">'+ico('magnifyingglass')+'<input aria-label="Search map" value="Pricing"><a href="04-editor.html" aria-label="Cancel">'+ico('xmark')+'</a></label>'
    return '<header class="top editor-top">'+btn('house.fill','Home','01-home')+title+'<div class="header-actions">'+btn('square.and.arrow.up','Export Map','08-export')+btn('ellipsis','More',extra='data-action="menu"')+'</div></header>'
def actions():
    return '<div class="mn-actionbar"><button class="primary" data-action="expand">'+ico('sparkles')+'Expand</button>'+btn('bubble.left','Ask','06-node-chat','tool')+btn('pencil','Edit','04-editor-editing','tool')+btn('circle.lefthalf.filled','Color',cls='tool',extra='data-action="color"')+btn('minus.circle','Collapse','04-editor','tool')+btn('ellipsis','More','05-node-card','tool')+'</div>'
def editor(mode='none',bottom=True):
    content=editor_top(mode)+map_canvas(mode)+glow
    if mode=='focus': content+='<a class="mn-chip focus-chip" href="04-editor.html">'+ico('scope')+'Focus: Pricing '+ico('xmark')+'</a>'
    if mode in ['zoom','many']: content+='<button class="mn-zoom zoom-ind" data-action="fit">40%</button>'
    if bottom:
        if mode=='editing': content+='<div class="edit-dock"><div class="edit-accessory"><a href="04-editor-node-selected.html">Done</a></div>'+composer()+'</div>'+keyboard()
        else: content+='<footer class="editor-bottom">'+(actions() if mode in ['selected','focus'] else '<nav class="mn-chips">'+chip('Node','plus',extra='data-action="new-node"')+chip('Layout','tree','04-editor-outline')+chip('Focus','scope','04-editor-focus')+chip('Export','square.and.arrow.up','08-export')+'</nav>')+composer()+'</footer>'
    return content
def keyboard():
    return '<div class="keyboard" aria-label="Keyboard illustration"><div class="keyboard-rows">'+''.join('<div class="keyrow">'+''.join(f'<span>{c}</span>' for c in row)+'</div>' for row in ['QWERTYUIOP','ASDFGHJKL','↑ZXCVBNM⌫'])+'<div class="keyrow"><span class="key-wide">123</span><span class="key-space">space</span><span class="key-wide">return</span></div></div></div>'
for mode,suffix,title in [('none','','Overview'),('selected','-node-selected','Node Selected'),('editing','-editing','Editing'),('focus','-focus','Focus'),('search','-search','Search'),('zoom','-zoomed-out','40%'),('many','-40-plus-nodes','43 Nodes')]:
    screen('04-editor'+suffix,'Launch plan · '+title,editor(mode),'editor '+mode,'Editor')
outline='<section class="outline-scroll"><h1 class="title-3">Launch plan</h1>'
for n,c,ls in zip(names,colors,leaves):
    outline+=f'<div class="outline-branch b-{c}"><a class="mn-node lv1" href="04-editor-node-selected.html">{n}</a><ul>'+''.join(f'<li><a href="05-node-card.html">{x}</a></li>' for x in ls)+'</ul></div>'
outline+='</section><footer class="editor-bottom">'+chip('Layout','tree','04-editor')+composer()+'</footer>'
screen('04-editor-outline','Launch plan · List',editor_top()+outline,'editor','Editor')
def row(text,icon,trail='',href='',danger=False,extra=''):
    tag='a' if href else 'button';attrs=f'href="{href}.html"' if href else extra
    return f'<{tag} class="mn-row {"danger" if danger else ""}" {attrs}>{ico(icon)}<span class="label">{text}</span>'+ (f'<span class="trail {"pro" if trail=="PRO" else ""}">{trail}</span>' if trail else ico('chevron.right'))+f'</{tag}>'
def sheethead(title): return '<div class="handle"></div><header class="mn-sheet-head"><h1 class="mn-sheet-title">'+title+'</h1>'+btn('xmark','Close','04-editor-node-selected','mn-close')+'</header>'
nodebody='<section class="mn-sheet node-sheet" aria-label="Pricing">'+sheethead('<span class="branch-dot"></span>Pricing')+'<div class="sheet-scroll"><textarea class="note body-lg" aria-label="Add a note" placeholder="Add a note"></textarea><div class="mn-group">'+row('Page 4 of Pitch deck.pdf','doc.text',extra='data-action="source"')+'</div><div class="mn-group">'+row('Expand with AI','sparkles','',extra='data-action="expand"')+row('Summarize Branch','text.alignleft',extra='data-action="summarize"')+row('Find Examples','magnifyingglass','',href='06-node-chat')+row('Ask in Chat','bubble.left','',href='06-node-chat')+'</div><div class="mn-group">'+row('Delete Node','trash',danger=True,extra='data-action="delete"')+'</div></div></section>'
screen('05-node-card','Pricing · Node Card',editor('sheet',False)+'<div class="sheet-scrim"></div>'+nodebody,'editor','Details')
chat='<header class="top chat-top"><a class="back-link" href="04-editor-node-selected.html">'+ico('chevron.right')+'<span class="headline">Launch plan</span></a></header><div class="mn-thread chat-thread"><div class="mn-bubble user">Find Examples</div><div class="mn-bubble">Free · 3 maps<br>Plus · $9.99<br>PRO · $24.99</div><div>'+chip('Add to Map','plus',extra='data-action="add-to-map"')+'</div></div>'+glow+'<footer class="editor-bottom"><span class="mn-chip node-context"><span class="branch-dot"></span>Pricing<button aria-label="Remove Pricing" data-action="remove-context">'+ico('xmark')+'</button></span>'+composer('Message')+'</footer>'
screen('06-node-chat','Pricing · Chat',chat,group='Details')
for empty in [False,True]:
    content='<header class="top library-top"><h1 class="title-2">Your Maps</h1>'+btn('square.and.pencil','Start a Map','02-create')+'</header><div class="library-segment mn-seg"><span class="thumb"></span><button aria-selected="true" data-action="maps">Maps</button><button aria-selected="false" data-action="chats">Chats</button></div>'
    content+=('<div class="mn-empty library-empty"><img src="../assets/no-maps-yet.imageset/no-maps-yet.svg" width="160" height="120" alt=""><span class="t">No Maps Yet</span><span class="s">Tap the globe on the home screen to start one.</span><a class="mn-iconbtn" href="02-create.html" aria-label="Mind Map">'+ico('globe')+'</a></div>' if empty else '<section class="library-scroll"><h2 class="mn-overline">PINNED</h2>'+card(pin=True)+'<h2 class="mn-overline">RECENT</h2>'+card('Biology: cell structure','41 nodes · Sep 28')+card('Pitch deck','Building… 60%',building=True)+card('New idea','23 nodes · Yesterday')+'</section>')
    content+='<footer class="library-bottom">'+usage()+btn('gear','Settings',extra='data-action="settings"')+'</footer>'
    screen('07-your-maps'+('-empty' if empty else ''),'Your Maps'+(' · Empty' if empty else ''),content,group='Library')
export='<section class="mn-sheet export-sheet" aria-label="Export Map">'+sheethead('Export Map')+'<section class="section"><h2 class="mn-overline">FILE</h2><div class="mn-group">'+row('Image','photo','PNG',extra='data-action="export"')+row('Document','doc.text','PDF','09-paywall')+row('Xmind, MindNode','tree','PRO','09-paywall')+row('Outline','list.bullet','Markdown',extra='data-action="outline-export"')+'</div></section><section class="section"><h2 class="mn-overline">SHARE</h2><div class="mn-group">'+row('Copy as Text','doc.on.doc',extra='data-action="copy"')+row('Share Link','link','PRO','09-paywall')+'</div></section></section>'
screen('08-export','Export Map',editor('none',False)+'<div class="sheet-scrim"></div>'+export,'editor','Export')
# Additional compositions and revised paywall.
exec((O/'scripts/screens-v2.py').read_text())
(O/'manifest.json').write_text(json.dumps(SCREENS,indent=2))
print(f'Built {len(SCREENS)} screens')
