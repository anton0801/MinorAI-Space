import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {C} from './fonts';
import {FPS, H, W, kf, rand} from './timeline';

// The living background: slow aurora blobs, a dot grid, drifting sparks and film grain.
export const Backdrop: React.FC<{energy: number}> = ({energy}) => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	const blobs = [
		{color: C.mint, r: 820, x: 0.2 + 0.18 * Math.sin(t * 0.45), y: 0.18 + 0.08 * Math.cos(t * 0.38), a: 0.42},
		{color: C.lime, r: 700, x: 0.85 + 0.12 * Math.cos(t * 0.33), y: 0.42 + 0.12 * Math.sin(t * 0.41), a: 0.3},
		{color: C.teal, r: 900, x: 0.3 + 0.2 * Math.cos(t * 0.29), y: 0.82 + 0.06 * Math.sin(t * 0.52), a: 0.34},
		{color: C.violet, r: 760, x: 0.9 + 0.1 * Math.sin(t * 0.37), y: 0.95 + 0.05 * Math.cos(t * 0.3), a: 0.3},
	];
	return (
		<AbsoluteFill style={{backgroundColor: C.bg, overflow: 'hidden'}}>
			{blobs.map((b, i) => (
				<div
					key={i}
					style={{
						position: 'absolute',
						left: b.x * W - b.r,
						top: b.y * H - b.r,
						width: b.r * 2,
						height: b.r * 2,
						borderRadius: '50%',
						background: `radial-gradient(circle, ${b.color} 0%, transparent 62%)`,
						opacity: Math.min(1, b.a * energy),
						mixBlendMode: 'screen',
					}}
				/>
			))}
			{/* Dot grid, brighter in the middle. */}
			<AbsoluteFill
				style={{
					backgroundImage: 'radial-gradient(rgba(255,255,255,0.55) 1.3px, transparent 1.6px)',
					backgroundSize: '34px 34px',
					backgroundPosition: `0px ${-t * 14}px`,
					opacity: 0.1 * Math.min(1, energy),
					maskImage: 'radial-gradient(ellipse 70% 55% at 50% 50%, #000 0%, transparent 100%)',
				}}
			/>
			<Sparks />
			<AbsoluteFill style={{background: 'radial-gradient(ellipse 90% 70% at 50% 50%, transparent 40%, rgba(0,0,0,0.75) 100%)'}} />
		</AbsoluteFill>
	);
};

const Sparks: React.FC = () => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	return (
		<>
			{Array.from({length: 46}).map((_, i) => {
				const speed = 30 + rand(i * 3.1) * 70;
				const x = rand(i * 1.7) * W + Math.sin(t * (0.4 + rand(i) * 0.6) + i) * 18;
				const y = (((rand(i * 2.3) * H - t * speed) % H) + H) % H;
				const size = 2 + rand(i * 5.3) * 4;
				const tw = 0.35 + 0.65 * Math.abs(Math.sin(t * (1 + rand(i * 7)) * 2 + i));
				const color = [C.mint, C.lime, '#ffffff', C.teal][i % 4];
				return (
					<div
						key={i}
						style={{
							position: 'absolute',
							left: x,
							top: y,
							width: size,
							height: size,
							borderRadius: '50%',
							backgroundColor: color,
							boxShadow: `0 0 ${size * 4}px ${color}`,
							opacity: 0.55 * tw,
						}}
					/>
				);
			})}
		</>
	);
};

export const Grain: React.FC = () => {
	const frame = useCurrentFrame();
	return (
		<AbsoluteFill style={{mixBlendMode: 'overlay', opacity: 0.16, pointerEvents: 'none'}}>
			<svg width={W} height={H}>
				<filter id="grain">
					<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed={frame % 17} stitchTiles="stitch" />
					<feColorMatrix type="saturate" values="0" />
				</filter>
				<rect width="100%" height="100%" filter="url(#grain)" />
			</svg>
		</AbsoluteFill>
	);
};

// A bright shock ring and sparks bursting from a point, `t` seconds after it fires.
export const Burst: React.FC<{t: number; x: number; y: number; scale?: number; seed?: number; layer?: 'rings' | 'sparks' | 'all'}> = ({t, x, y, scale = 1, seed = 1, layer = 'all'}) => {
	if (t < 0 || t > 1.4) return null;
	const ring = kf(t, [[0, 0], [0.9, 1, (p) => 1 - Math.pow(1 - p, 3)]]);
	return (
		<AbsoluteFill style={{pointerEvents: 'none'}}>
			{layer !== 'sparks' && [0, 0.12].map((delay, k) => {
				const p = Math.max(0, Math.min(1, (t - delay) / 0.9));
				const e = 1 - Math.pow(1 - p, 3);
				const r = (120 + e * 900) * scale;
				return (
					<div
						key={k}
						style={{
							position: 'absolute',
							left: x - r,
							top: y - r,
							width: r * 2,
							height: r * 2,
							borderRadius: '50%',
							border: `${(k ? 2 : 5) * (1 - e) + 1}px solid ${k ? C.lime : C.mint}`,
							boxShadow: `0 0 60px ${C.mint}, inset 0 0 60px ${C.mint}`,
							opacity: (1 - p) * (p > 0 ? 0.9 : 0),
						}}
					/>
				);
			})}
			{layer !== 'rings' && Array.from({length: 34}).map((_, i) => {
				const a = rand(i * 9.1 + seed) * Math.PI * 2;
				const v = (380 + rand(i * 4.7 + seed) * 760) * scale;
				const d = v * (1 - Math.pow(1 - Math.min(1, t / 1.1), 3));
				const size = 3 + rand(i * 2.9 + seed) * 7;
				const color = [C.mint, C.lime, '#fff', C.teal][i % 4];
				return (
					<div
						key={i}
						style={{
							position: 'absolute',
							left: x + Math.cos(a) * d - size / 2,
							top: y + Math.sin(a) * d - size / 2,
							width: size,
							height: size,
							borderRadius: '50%',
							backgroundColor: color,
							boxShadow: `0 0 ${size * 5}px ${color}`,
							opacity: Math.max(0, 1 - t / 1.3) * (ring > 0 ? 1 : 0),
						}}
					/>
				);
			})}
		</AbsoluteFill>
	);
};
