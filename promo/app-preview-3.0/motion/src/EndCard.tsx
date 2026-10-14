import React from 'react';
import {AbsoluteFill, Img, staticFile, useCurrentFrame} from 'remotion';
import {C, display, text} from './fonts';
import {END_TEXT, FPS, Lang, W, ease, kf} from './timeline';

const heptagon = (cx: number, cy: number, r: number) =>
	Array.from({length: 7})
		.map((_, i) => {
			const a = -Math.PI / 2 + (i * 2 * Math.PI) / 7;
			return `${cx + r * Math.cos(a)},${cy + r * Math.sin(a)}`;
		})
		.join(' ');

// The logo lands with a burst of its own heptagon rings, then the name, the line and the note.
export const EndCard: React.FC<{lang: Lang; start: number}> = ({lang, start}) => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	if (t < start - 0.05) return null;
	const local = t - start;
	const logo = kf(local, [[0, 0], [0.55, 1, ease.back]]);
	const cx = W / 2;
	const cy = 760;
	const name = 'Minor AI';
	const copy = END_TEXT[lang];
	return (
		<AbsoluteFill>
			<div
				style={{
					position: 'absolute',
					left: cx - 520,
					top: cy - 520,
					width: 1040,
					height: 1040,
					borderRadius: '50%',
					background: `radial-gradient(circle, rgba(61,245,180,${0.38 * logo}) 0%, rgba(34,199,232,${0.14 * logo}) 35%, transparent 65%)`,
					scale: String(0.9 + 0.1 * Math.sin(local * 2)),
				}}
			/>
			<svg width={W} height={1920} style={{position: 'absolute', left: 0, top: 0}}>
				{[0, 0.14, 0.28, 0.42].map((d, i) => {
					const p = Math.max(0, Math.min(1, (local - d) / 1.6));
					const e = 1 - Math.pow(1 - p, 3);
					return (
						<polygon
							key={i}
							points={heptagon(cx, cy, 150 + e * (520 + i * 160))}
							fill="none"
							stroke={i % 2 ? C.lime : C.mint}
							strokeWidth={6 * (1 - e) + 1.2}
							strokeLinejoin="round"
							opacity={p > 0 ? (1 - p) * 0.9 : 0}
							style={{filter: `drop-shadow(0 0 12px ${C.mint})`}}
						/>
					);
				})}
			</svg>
			<Img
				src={staticFile('minor-mark.png')}
				style={{
					position: 'absolute',
					left: cx - 170,
					top: cy - 170,
					width: 340,
					height: 340,
					scale: String(0.3 + 0.7 * logo),
					rotate: `${(1 - logo) * -40}deg`,
					opacity: Math.min(1, logo * 1.5),
					filter: `drop-shadow(0 0 ${30 + 20 * Math.sin(local * 3)}px rgba(61,245,180,0.75))`,
				}}
			/>
			<div
				style={{
					position: 'absolute',
					top: cy + 250,
					left: 0,
					right: 0,
					display: 'flex',
					justifyContent: 'center',
					fontFamily: display,
					fontWeight: 800,
					fontSize: 116,
					letterSpacing: '-0.04em',
					color: '#fff',
				}}
			>
				{name.split('').map((ch, i) => {
					const p = kf(local, [[0.3 + i * 0.045, 0], [0.75 + i * 0.045, 1, ease.out]]);
					return (
						<span
							key={i}
							style={{
								display: 'inline-block',
								whiteSpace: 'pre',
								opacity: p,
								translate: `0px ${(1 - p) * 60}px`,
								filter: `blur(${(1 - p) * 12}px)`,
								color: i >= 6 ? 'transparent' : '#fff',
								backgroundImage: i >= 6 ? `linear-gradient(120deg, ${C.lime}, ${C.mint}, ${C.teal})` : undefined,
								WebkitBackgroundClip: i >= 6 ? 'text' : undefined,
								backgroundClip: i >= 6 ? 'text' : undefined,
							}}
						>
							{ch}
						</span>
					);
				})}
			</div>
			<div
				style={{
					position: 'absolute',
					top: cy + 420,
					left: 60,
					right: 60,
					textAlign: 'center',
					fontFamily: text,
					fontWeight: 600,
					fontSize: 42,
					color: 'rgba(255,255,255,0.82)',
					opacity: kf(local, [[0.8, 0], [1.3, 1, ease.out]]),
					translate: `0px ${kf(local, [[0.8, 24], [1.3, 0, ease.out]])}px`,
				}}
			>
				{copy.tagline}
			</div>
			<div
				style={{
					position: 'absolute',
					bottom: 120,
					left: 60,
					right: 60,
					textAlign: 'center',
					fontFamily: text,
					fontWeight: 500,
					fontSize: 27,
					color: 'rgba(255,255,255,0.55)',
					opacity: kf(local, [[1.1, 0], [1.6, 1, ease.out]]),
				}}
			>
				{copy.note}
			</div>
		</AbsoluteFill>
	);
};
