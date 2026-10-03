const fs=require('fs'),path=require('path');
const deps='/Users/antondanilov/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));
const root=path.resolve(__dirname,'../assets');
(async()=>{const all=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));for(const a of all){const dir=path.join(root,a.name+'.imageset');for(const scale of [1,2,3]){const source=fs.readFileSync(path.join(dir,a.name+'.svg'));let render=sharp(source,{density:72*scale}).resize(a.width*scale,a.height*scale);if(a.name.startsWith('app-icon'))render=render.removeAlpha();await render.png().toFile(path.join(dir,a.name+(scale===1?'':'@'+scale+'x')+'.png'));}}console.log(`Rendered ${all.length*3} PNGs`);})();
