// node scripts/stills.mjs <CompId> <outDir> <frame> [frame...] — renders stills from one bundle.
import {bundle} from '@remotion/bundler';
import {renderStill, selectComposition} from '@remotion/renderer';
import path from 'node:path';
const [id, out, ...frames] = process.argv.slice(2);
const serveUrl = await bundle({entryPoint: path.resolve('src/index.ts'), publicDir: path.resolve('public')});
const composition = await selectComposition({serveUrl, id, inputProps: {}, chromeMode: 'chrome-for-testing'});
for (const f of frames) {
	await renderStill({composition, serveUrl, frame: Number(f), output: path.join(out, `${id}-${String(f).padStart(4, '0')}.png`), scale: 0.5, chromiumOptions: {gl: 'angle'}, chromeMode: 'chrome-for-testing'});
	process.stdout.write(f + ' ');
}
console.log('done');
