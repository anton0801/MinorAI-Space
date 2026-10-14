import React from 'react';
import {AbsoluteFill, Img, staticFile, useCurrentFrame} from 'remotion';
import {C} from './fonts';
import {FPS, Lang, W, ease, kf} from './timeline';

const SPIN: [number, number, ((x: number) => number)?][] = [
	[0, -585],
	[2.25, 0, ease.out],
];

// The map turns into its real slides: they spin out of the screen on a vertical wheel, like an
// iOS picker, and settle on the cover; the wheel keeps drifting behind the deck when it arrives.
export const SlideRing: React.FC<{lang: Lang; start: number; end: number}> = ({lang, start, end}) => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	if (t < start - 0.1 || t > end + 0.1) return null;
	const local = t - start;
	const fade = kf(t, [[end - 0.9, 1], [end, 0, ease.inOut]]);
	const spin = kf(local, SPIN) - Math.max(0, local - 2.25) * 14;
	const speed = Math.abs(kf(local + 0.02, SPIN) - kf(local, SPIN)) / 0.02; // deg/s
	const radius = kf(local, [[0, 40], [0.75, 560, ease.out]]);
	const grow = kf(local, [[0, 0.25], [0.75, 1, ease.out]]);
	const cy = 1190;
	const sw = 690;
	const sh = (sw * 9) / 16;
	const slides = Array.from({length: 8})
		.map((_, i) => {
			const a = ((spin + i * 45) * Math.PI) / 180;
			return {i, a, depth: Math.cos(a)};
		})
		.filter((s) => s.depth > -0.35)
		.sort((a, b) => a.depth - b.depth);
	return (
		<AbsoluteFill style={{perspective: 1300, perspectiveOrigin: `50% ${cy}px`, opacity: fade}}>
			<div
				style={{
					position: 'absolute',
					left: W / 2 - 560,
					top: cy - 420,
					width: 1120,
					height: 840,
					borderRadius: '50%',
					background: `radial-gradient(ellipse, rgba(61,245,180,0.38), rgba(34,199,232,0.12) 45%, transparent 70%)`,
					opacity: kf(local, [[0, 0], [0.5, 1]]),
				}}
			/>
			{slides.map(({i, a, depth}) => {
				const y = Math.sin(a) * radius;
				const z = (depth - 1) * radius;
				const x = Math.sin(a) * 110;
				const light = 0.4 + 0.6 * Math.max(0, depth);
				const front = Math.max(0, (depth - 0.85) / 0.15);
				return (
					<div
						key={i}
						style={{
							position: 'absolute',
							left: W / 2 - sw / 2,
							top: cy - sh / 2,
							width: sw,
							height: sh,
							transform: `translate3d(${x}px, ${y}px, ${z}px) rotateX(${(-a * 180) / Math.PI}deg) rotateZ(${Math.sin(a) * -6}deg) scale(${grow})`,
							opacity: Math.min(1, (depth + 0.35) / 0.5) * Math.min(1, local / 0.25),
							borderRadius: 20,
							overflow: 'hidden',
							boxShadow: `0 40px 100px rgba(0,0,0,0.65), 0 0 ${80 * front}px rgba(61,245,180,${0.55 * front})`,
							border: `2px solid rgba(255,255,255,${0.14 + 0.3 * front})`,
							filter: `brightness(${light}) blur(${Math.min(7, speed / 140)}px)`,
						}}
					>
						<Img src={staticFile(`slides/${lang}/slide${i + 1}.png`)} style={{width: sw, height: sh}} />
						<AbsoluteFill
							style={{
								background: `linear-gradient(180deg, rgba(255,255,255,${0.1 + 0.12 * Math.abs(Math.sin(a))}) 0%, transparent 40%, transparent 70%, rgba(0,0,0,0.25) 100%)`,
							}}
						/>
					</div>
				);
			})}
			{/* A flare where the screen collapses into the wheel. */}
			<div
				style={{
					position: 'absolute',
					left: W / 2 - 6,
					top: cy - 6,
					width: 12,
					height: 12,
					borderRadius: 6,
					backgroundColor: '#fff',
					boxShadow: `0 0 120px 60px ${C.mint}, 0 0 40px 20px #fff`,
					opacity: kf(local, [[0, 0], [0.2, 1, ease.out], [0.7, 0, ease.out]]),
				}}
			/>
		</AbsoluteFill>
	);
};
