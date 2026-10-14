import React from 'react';
import {AbsoluteFill, Img, staticFile, useCurrentFrame} from 'remotion';
import {FPS, Lang, W, ease, kf} from './timeline';

const SCREENS = ['map', 'deck', 'today', 'answer', 'newmap', 'presenter', 'panel', 'study', 'creating', 'deck2', 'home', 'menu'];

// Everything at once: a tilted wall of the app's screens and slides racing past.
export const Wall: React.FC<{lang: Lang; start: number; end: number}> = ({lang, start, end}) => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	if (t < start - 0.05 || t > end + 0.05) return null;
	const local = t - start;
	const fadeIn = kf(local, [[0, 0], [0.3, 1, ease.out]]);
	const out = kf(t, [[end - 0.3, 0], [end, 1, ease.in]]);
	const tw = 250;
	const th = (tw * 2556) / 1180;
	const sh = (tw * 9) / 16;
	const gap = 26;
	const columns = Array.from({length: 5}).map((_, c) => {
		const items: {kind: 'screen' | 'slide'; src: string; h: number}[] = [];
		for (let r = 0; r < 7; r++) {
			const k = c * 7 + r;
			if ((r + c) % 3 === 2) items.push({kind: 'slide', src: `slides/${lang}/slide${(k % 8) + 1}.png`, h: sh});
			else items.push({kind: 'screen', src: `stills/${lang}/${SCREENS[k % SCREENS.length]}.jpg`, h: th});
		}
		return items;
	});
	const plane = columns.length * tw + (columns.length - 1) * gap;
	return (
		<AbsoluteFill style={{perspective: 1700, opacity: fadeIn * (1 - out)}}>
			<div
				style={{
					position: 'absolute',
					left: W / 2 - plane / 2,
					top: -380,
					width: plane,
					height: 2800,
					transform: `rotateX(${kf(local, [[0, 38], [2, 26]])}deg) rotateZ(-16deg) scale(${kf(local, [[0, 1.45], [2, 1.05, ease.out]]) + out * 0.4})`,
					transformOrigin: '50% 45%',
					display: 'flex',
					gap,
				}}
			>
				{columns.map((items, c) => {
					const dir = c % 2 === 0 ? -1 : 1;
					const shift = dir * (local * 210 + c * 40) - (dir > 0 ? 700 : 0);
					return (
						<div key={c} style={{display: 'flex', flexDirection: 'column', gap, translate: `0px ${shift}px`}}>
							{items.map((it, r) => {
								const appear = kf(local, [[0.02 * (c + r), 0], [0.35 + 0.02 * (c + r), 1, ease.out]]);
								return (
									<div
										key={r}
										style={{
											width: tw,
											height: it.h,
											borderRadius: it.kind === 'screen' ? 34 : 14,
											overflow: 'hidden',
											border: '1.5px solid rgba(255,255,255,0.16)',
											boxShadow: '0 24px 60px rgba(0,0,0,0.55)',
											opacity: appear,
											scale: String(0.85 + 0.15 * appear),
										}}
									>
										<Img src={staticFile(it.src)} style={{width: tw, height: it.h, objectFit: 'cover'}} />
									</div>
								);
							})}
						</div>
					);
				})}
			</div>
			<AbsoluteFill style={{background: 'linear-gradient(180deg, rgba(4,6,5,0.92) 0%, rgba(4,6,5,0.55) 22%, transparent 45%, transparent 75%, rgba(4,6,5,0.85) 100%)'}} />
		</AbsoluteFill>
	);
};
