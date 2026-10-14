import React from 'react';
import {AbsoluteFill, OffthreadVideo, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {C} from './fonts';
import {CH, CLIPS, CW, FPS, FULL, Lang, REST_Y, TAPS, W, ease, kf} from './timeline';

// Where the floating screen is at time t: one continuous "camera" for the whole film.
export const pose = (t: number) => {
	const scale = kf(t, [
		[0, FULL],
		[2.2, FULL],
		[2.95, 1, ease.out],
		[3.25, 1],
		[4.55, 1.22, ease.inOut],
		[5.25, 1.22],
		[5.65, 1, ease.out],
		[6.86, 0.97, ease.inOut],
		[6.9, 0.9, ease.linear],
		[7.3, 1.01, ease.back],
		[9.3, 1.07, ease.linear],
		[9.7, 1, ease.out],
		[10.9, 1],
		[11.3, 0.3, ease.in],
		[13.35, 0.3],
		[13.36, 1.12, ease.linear],
		[13.95, 1, ease.out],
		[22.7, 1],
		[23.15, 0.38, ease.in],
	]);
	const y =
		kf(t, [
			[0, 960],
			[2.2, 960],
			[2.95, REST_Y, ease.out],
			[3.25, REST_Y],
			[4.55, 1300, ease.inOut],
			[5.25, 1300],
			[5.65, REST_Y, ease.out],
			[10.9, REST_Y],
			[11.3, 1190, ease.in],
			[13.35, 1190],
			[13.36, 2900, ease.linear],
			[13.95, REST_Y, ease.out],
			[22.7, REST_Y],
			[23.15, 1100, ease.in],
		]) + (t > 3 ? Math.sin(t * 1.15) * 7 : 0);
	const x = kf(t, [
		[0, W / 2],
		[17.22, W / 2],
		[17.4, -520, ease.in],
		[17.41, W + 520, ease.linear],
		[17.68, W / 2, ease.out],
	]);
	const rx = kf(t, [
		[0, 0],
		[13.36, 0],
		[13.37, -38, ease.linear],
		[13.95, 0, ease.out],
		[19.72, 0],
		[19.9, -90, ease.in],
		[19.91, 90, ease.linear],
		[20.18, 0, ease.out],
		[22.7, 0],
		[23.15, 28, ease.in],
	]);
	const ry =
		kf(t, [
			[0, 0],
			[14.7, 0],
			[14.9, 90, ease.in],
			[14.91, -90, ease.linear],
			[15.16, 0, ease.out],
		]) + (t > 3.2 ? Math.sin(t * 0.8) * 4.5 : 0);
	const rz = kf(t, [
		[0, 0],
		[17.22, 0],
		[17.4, -9, ease.in],
		[17.41, 9, ease.linear],
		[17.68, 0, ease.out],
		[22.7, 0],
		[23.15, -12, ease.in],
	]);
	const opacity = kf(t, [
		[0, 1],
		[11.15, 1],
		[11.3, 0, ease.linear],
		[13.35, 0],
		[13.36, 1, ease.linear],
		[22.95, 1],
		[23.15, 0, ease.linear],
	]);
	const blur = kf(t, [[17.2, 0], [17.4, 16, ease.in], [17.41, 16], [17.62, 0, ease.out]]);
	const radius = kf(t, [[0, 0], [2.2, 0], [2.8, 94, ease.out]]);
	return {scale, x, y, rx, ry, rz, opacity, blur, radius};
};

// The Apple-Intelligence-like edge glow while the AI works.
const glowAt = (t: number) =>
	kf(t, [
		[5.25, 0],
		[5.5, 1, ease.out],
		[6.86, 1],
		[6.92, 1.8, ease.linear],
		[7.6, 0, ease.out],
	]);

const Ripple: React.FC<{t: number; x: number; y: number}> = ({t, x, y}) => {
	if (t < -0.05 || t > 0.55) return null;
	const p = Math.max(0, t) / 0.55;
	const dot = kf(t, [[-0.05, 0], [0.04, 1, ease.out], [0.35, 0, ease.linear]]);
	const r = 34 + p * 70;
	return (
		<>
			<div
				style={{
					position: 'absolute',
					left: x * CW - 36,
					top: y * CH - 36,
					width: 72,
					height: 72,
					borderRadius: 36,
					background: 'radial-gradient(circle, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.55) 45%, rgba(255,255,255,0) 72%)',
					opacity: dot,
					scale: String(0.75 + dot * 0.25),
				}}
			/>
			<div
				style={{
					position: 'absolute',
					left: x * CW - r,
					top: y * CH - r,
					width: r * 2,
					height: r * 2,
					borderRadius: r,
					border: `${4 * (1 - p) + 1}px solid ${C.mint}`,
					boxShadow: `0 0 24px ${C.mint}`,
					opacity: (1 - p) * (t >= 0 ? 1 : 0),
				}}
			/>
		</>
	);
};

export const Card: React.FC<{lang: Lang}> = ({lang}) => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	const p = pose(t);
	const glow = glowAt(t);
	const flash = kf(t, [[6.88, 0], [6.9, 0.75, ease.linear], [7.35, 0, ease.out]]);
	const angle = (t * 220) % 360;
	if (p.opacity <= 0.001) return null;
	return (
		<AbsoluteFill style={{perspective: 2400, perspectiveOrigin: `50% ${p.y}px`}}>
			<div
				style={{
					position: 'absolute',
					left: p.x - CW / 2,
					top: p.y - CH / 2,
					width: CW,
					height: CH,
					transform: `scale(${p.scale}) rotateX(${p.rx}deg) rotateY(${p.ry}deg) rotateZ(${p.rz}deg)`,
					opacity: p.opacity,
					filter: p.blur > 0.1 ? `blur(${p.blur}px)` : undefined,
				}}
			>
				{/* Soft shadow and an ambient brand glow under the screen. */}
				<div
					style={{
						position: 'absolute',
						inset: 0,
						borderRadius: p.radius,
						boxShadow: `0 60px 140px rgba(0,0,0,0.75), 0 0 ${90 + glow * 60}px rgba(61,245,180,${0.12 + glow * 0.35})`,
					}}
				/>
				{glow > 0.01 ? (
					<>
						<div
							style={{
								position: 'absolute',
								inset: -26,
								borderRadius: p.radius + 26,
								background: `conic-gradient(from ${angle}deg, ${C.lime}, ${C.mint}, ${C.teal}, ${C.violet}, #ff7ad9, ${C.lime})`,
								filter: 'blur(38px)',
								opacity: Math.min(1, glow) * 0.95,
							}}
						/>
						<div
							style={{
								position: 'absolute',
								inset: -5,
								borderRadius: p.radius + 5,
								padding: 5,
								background: `conic-gradient(from ${angle}deg, ${C.lime}, ${C.mint}, ${C.teal}, ${C.violet}, #ff7ad9, ${C.lime})`,
								WebkitMask: 'linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)',
								WebkitMaskComposite: 'xor',
								maskComposite: 'exclude',
								opacity: Math.min(1, glow),
							}}
						/>
					</>
				) : null}
				<div
					style={{
						position: 'absolute',
						inset: 0,
						borderRadius: p.radius,
						overflow: 'hidden',
						backgroundColor: '#000',
					}}
				>
					{CLIPS[lang].map((c, i) => {
						const span = c.dur ?? c.to - c.from;
						const rate = (c.to - c.from) / span;
						return (
							<Sequence key={i} from={Math.round(c.at * FPS)} durationInFrames={Math.round(span * FPS)} premountFor={FPS}>
								{/* OffthreadVideo: the in-browser decoder dropped and half-drew frames of these tall clips. */}
								<OffthreadVideo
									src={staticFile(`${c.src}.mp4`)}
									trimBefore={Math.round(c.from * FPS)}
									playbackRate={rate}
									muted
									style={{position: 'absolute', width: CW, height: CH}}
								/>
							</Sequence>
						);
					})}
					{TAPS[lang].map((tap, i) => (
						<Ripple key={i} t={t - tap.at} x={tap.x} y={tap.y} />
					))}
					{/* Inner AI glow along the edges. */}
					{glow > 0.01 ? (
						<AbsoluteFill
							style={{
								borderRadius: p.radius,
								boxShadow: `inset 0 0 ${50 * Math.min(1.4, glow)}px rgba(61,245,180,${0.55 * Math.min(1, glow)}), inset 0 0 ${120 * Math.min(1.4, glow)}px rgba(125,107,255,${0.35 * Math.min(1, glow)})`,
							}}
						/>
					) : null}
					{/* Glass glare that follows the tilt. */}
					<AbsoluteFill
						style={{
							background: `linear-gradient(${115 + p.ry * 2}deg, transparent 30%, rgba(255,255,255,${0.05 + Math.abs(p.ry) * 0.004}) 46%, transparent 60%)`,
						}}
					/>
					<AbsoluteFill style={{backgroundColor: '#fff', opacity: flash}} />
				</div>
				<div
					style={{
						position: 'absolute',
						inset: 0,
						borderRadius: p.radius,
						border: `2px solid rgba(255,255,255,${p.radius > 10 ? 0.2 : 0})`,
						pointerEvents: 'none',
					}}
				/>
			</div>
		</AbsoluteFill>
	);
};
