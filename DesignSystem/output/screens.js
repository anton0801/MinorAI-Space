/* Local design prototype. No networking, AI, microphone, or payment requests. */
(()=>{
 const themes=['classic','vio','aqua','rosa','cosmos','flam'];
 const q=new URLSearchParams(location.search); const theme=q.get('theme');
 if(q.get('width'))document.documentElement.style.setProperty('--frame-width',Math.max(375,Math.min(430,Number(q.get('width'))))+'px');
 if(themes.includes(theme))document.documentElement.dataset.theme=theme;
 if(q.get('height'))document.documentElement.style.setProperty('--frame-height',Math.max(667,Math.min(932,Number(q.get('height'))))+'px');
 window.addEventListener('message',e=>{if(!document.querySelector('.launch-screen')&&e.source===parent&&themes.includes(e.data?.theme))document.documentElement.dataset.theme=e.data.theme});
 const phone=document.querySelector('.mn-phone');
 if(phone.classList.contains('launch-screen'))document.documentElement.dataset.theme='classic';
 const dock=document.querySelector('.create-bottom'),createScroll=document.querySelector('.create-scroll');
 if(dock&&createScroll){const reserve=()=>createScroll.style.bottom=(phone.clientHeight-dock.offsetTop+8)+'px';new ResizeObserver(reserve).observe(dock);reserve();}
 const subscription=q.get('subscription')||((phone.classList.contains('youtube')||phone.classList.contains('voice'))?'plus':'free');
 document.querySelectorAll('[data-paid-source]').forEach(a=>{if(subscription!=='free'){a.href=a.dataset.paidSource+'.html';a.querySelector('.source-access').hidden=true;}else{a.href='09-paywall.html';a.dataset.plan='plus';a.classList.remove('is-active');a.setAttribute('aria-current','false');}});
 if(subscription!=='free'&&phone.classList.contains('create'))document.querySelector('.mn-pill').outerHTML='<span class="headline">Mind Map</span>';

 const go=f=>location.href=f+'.html?theme='+document.documentElement.dataset.theme+(q.get('height')?'&height='+q.get('height'):'')+(q.get('width')?'&width='+q.get('width'):'');
 document.querySelectorAll('a[href$=".html"]').forEach(a=>{a.href+='?theme='+document.documentElement.dataset.theme+(q.get('height')?'&height='+q.get('height'):'')+(q.get('width')?'&width='+q.get('width'):'')});
 const toast=t=>{phone.querySelector('.toast')?.remove();const el=document.createElement('div');el.className='toast';el.setAttribute('role','status');el.textContent=t;phone.append(el);setTimeout(()=>el.remove(),4000)};
 const dialog=(text,ok,yes)=>{const d=document.createElement('dialog');d.innerHTML='<p class="headline"></p><button class="cancel">Cancel</button><button class="confirm"></button>';d.querySelector('p').textContent=text;d.querySelector('.confirm').textContent=ok;d.querySelector('.cancel').onclick=()=>d.remove();d.querySelector('.confirm').onclick=()=>{d.remove();yes()};phone.append(d);d.showModal();};
 const view=document.querySelector('.map-viewport'),world=document.querySelector('.map-world');
 let scale=1,tx=0,ty=0;
 function fit(){if(!view)return;const mode=view.dataset.mode;const w=view.clientWidth,h=view.clientHeight;scale=Math.min((w-32)/Number(world.dataset.width),(h-24)/Number(world.dataset.height),1);if(['zoom','many'].includes(mode))scale=.4;if(mode==='editing'){scale=.7;tx=-116;ty=h/2-282*scale;}else{tx=(w-Number(world.dataset.width)*scale)/2;ty=(h-Number(world.dataset.height)*scale)/2;}paint()}
 function paint(){world.style.transform=`translate(${tx}px,${ty}px) scale(${scale})`;const z=document.querySelector('.zoom-ind');if(z)z.textContent=Math.round(scale*100)+'%'}
 fit();if(view)new ResizeObserver(fit).observe(view);
 let drag;
 view?.addEventListener('pointerdown',e=>{if(e.target.closest('button'))return;drag={x:e.clientX,y:e.clientY,tx,ty};view.setPointerCapture(e.pointerId)});
 view?.addEventListener('pointermove',e=>{if(!drag)return;tx=drag.tx+e.clientX-drag.x;ty=drag.ty+e.clientY-drag.y;paint()});
 view?.addEventListener('pointerup',()=>drag=null);view?.addEventListener('pointercancel',()=>drag=null);view?.addEventListener('dblclick',fit);
 document.querySelectorAll('[data-node]').forEach(n=>{n.onclick=()=>go('04-editor-node-selected');n.ondblclick=()=>go('04-editor-editing')});
 document.querySelectorAll('[data-composer]').forEach(f=>{const i=f.querySelector('input'),b=f.querySelector('button');i.oninput=()=>b.disabled=!i.value.trim();f.onsubmit=e=>{e.preventDefault();if(!i.value.trim())return;if(phone.classList.contains('offline'))return;else if(phone.classList.contains('create'))go('03-generating');else{toast('Map updated · Undo');i.value='';b.disabled=true}}});
 document.querySelectorAll('[data-segment]').forEach(s=>s.querySelectorAll('button').forEach((b,i)=>b.onclick=()=>{s.classList.toggle('is-second',i===1);s.querySelectorAll('button').forEach((x,j)=>x.setAttribute('aria-selected',String(i===j)));const year=document.querySelector('[data-segment="period"]').classList.contains('is-second'),pro=document.querySelector('[data-segment="plan"]').classList.contains('is-second');document.querySelector('.mn-buy').textContent=pro?(year?'$239.90':'$24.99'):(year?'$101.90':'$9.99');const features=pro?['Everything in Plus','Export to Xmind and MindNode','Share links to your maps','The most capable AI model']:['Unlimited mind maps','All sources: YouTube, voice and documents up to 300 pages','Export to PDF','Chat with any node'];document.querySelectorAll('.mn-features .mn-feature span').forEach((x,j)=>x.textContent=features[j]);document.querySelector('[data-plan-title]').textContent=pro?'PRO':'Minor Plus'}));
 const outline='Launch plan\n'+['Audience','Positioning','Pricing','Channels','Timeline','Risks'].map(x=>'  '+x).join('\n');
 document.addEventListener('click',async e=>{const b=e.target.closest('[data-action]');if(!b)return;const a=b.dataset.action;
 if(a==='fit')fit();
 if(a==='settings')go('12-settings');
 if(a==='apple-signin')go('01-home');
 if(a==='confirm-delete-account')go('10-sign-in');
 if(a==='themes'){const sw=document.querySelector('.settings-swatches');sw.hidden=!sw.hidden;b.setAttribute('aria-expanded',String(!sw.hidden));}

 if(a==='stop'){dialog('Stop building this map?','Stop',()=>go('02-create'));document.querySelector('dialog .cancel').textContent='Keep Building';}
 if(a==='delete')dialog('Delete this node and its 4 children?','Delete',()=>go('04-editor'));
 if(a==='add-to-map'){b.innerHTML='<i class=mn-ico>'+Minor.icon('checkmark')+'</i>Added';b.disabled=true;toast('Map updated · Undo')}
 if(a==='remove-context')b.closest('.node-context').remove();
 if(a==='media')b.classList.toggle('is-active');
 if(a==='new-node')go('04-editor-editing');
 if(a==='expand'){go('04-editor-expanding')}
 if(a==='summarize')go('06-node-chat');
 if(a==='copy'){try{await navigator.clipboard.writeText(outline);toast('Copied')}catch{const t=document.createElement('textarea');t.value=outline;phone.append(t);t.select();document.execCommand('copy');t.remove();toast('Copied')}}
 if(a==='outline-export'){const url=URL.createObjectURL(new Blob(['# Launch plan\n\n'+outline],{type:'text/markdown'}));const link=document.createElement('a');link.href=url;link.download='Launch plan.md';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}
 if(a==='menu'){document.querySelector('.popover')?.remove();const m=document.createElement('nav');m.className='popover';[['Rename','04-editor-editing'],['Layout','04-editor-outline'],['Focus','04-editor-focus'],['Pricing','04-editor-search'],['Pin','07-your-maps']].forEach(([label,href])=>{const x=document.createElement('a');x.textContent=label;x.href=href+'.html?theme='+document.documentElement.dataset.theme;m.append(x)});phone.append(m)}
 if(a==='color'){document.querySelector('.color-picker')?.remove();const p=document.createElement('div');p.className='color-picker';['mint','sky','lilac','pink','sun','coral'].forEach(c=>{const x=document.createElement('button');x.style.background='var(--branch-'+c+')';x.setAttribute('aria-label',c);x.onclick=()=>{document.querySelectorAll('.b-lilac').forEach(n=>{n.style.setProperty('--b','var(--branch-'+c+')');n.style.setProperty('--b-tint','var(--branch-'+c+'-tint)');n.style.setProperty('--b-line','var(--branch-'+c+'-line)')});p.remove()};p.append(x)});phone.append(p)}
 if(a==='chats'){b.closest('.mn-seg').classList.add('is-second');b.setAttribute('aria-selected','true');b.previousElementSibling.setAttribute('aria-selected','false');const list=document.querySelector('.library-scroll');if(list){list.dataset.original=list.innerHTML;list.innerHTML='<a class="mn-convo" href="06-node-chat.html"><span class="t"><span class="title">Launch plan</span><span class="date">Today</span></span></a>'}}
 if(a==='maps'){b.closest('.mn-seg').classList.remove('is-second');b.setAttribute('aria-selected','true');b.nextElementSibling.setAttribute('aria-selected','false');const list=document.querySelector('.library-scroll');if(list?.dataset.original)list.innerHTML=list.dataset.original}
 });
 document.querySelector('.search-box input')?.addEventListener('input',e=>{const s=e.target.value.toLowerCase();document.querySelectorAll('.map-node').forEach(n=>n.classList.toggle('is-dim',!!s&&!n.textContent.toLowerCase().includes(s)))});
 if(q.get('plan')==='pro')document.querySelector('[data-segment=plan] button.pro')?.click();
 document.querySelectorAll('.mn-row').forEach(a=>{if(a.tagName==='A'&&a.querySelector('.trail.pro'))a.href+='&plan=pro'});
 document.querySelectorAll('[data-plan=plus]').forEach(a=>a.href+='&plan=plus');
 document.querySelectorAll('.settings-scroll a').forEach(a=>{if(a.textContent.includes('Upgrade to PRO'))a.href+='&plan=pro';});
 const themeButtons=document.querySelectorAll('[data-theme-choice]');
 const applySwatches=()=>themeButtons.forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.themeChoice===document.documentElement.dataset.theme)));
 themeButtons.forEach(b=>b.onclick=()=>{document.documentElement.dataset.theme=b.dataset.themeChoice;applySwatches();});applySwatches();
 if(q.get('subscription')==='pro')document.querySelectorAll('.settings-scroll a').forEach(a=>{if(a.textContent.includes('Upgrade to PRO'))a.hidden=true;});
 Minor.hydrate();
})();
